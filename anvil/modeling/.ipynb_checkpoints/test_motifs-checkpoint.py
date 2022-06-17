import pandas as pd
import numpy as np
from tqdm import tqdm
import h5py
import logging
import math
import os
import sys
import tensorflow as tf
import pysam
import random

from basepairmodels.cli import logger
from basepairmodels.cli.exceptionhandler import NoTracebackException

from genomicsdlarchsandlosses.bpnet.attribution_prior \
    import AttributionPriorModel
from genomicsdlarchsandlosses.bpnet.custommodel \
    import CustomModel
from genomicsdlarchsandlosses.bpnet.losses import \
MultichannelMultinomialNLL, multinomial_nll, CustomMeanSquaredError
from tensorflow.keras.models import load_model
from tensorflow.keras.utils import CustomObjectScope
import tensorflow.keras.backend as kb
from scipy.spatial.distance import jensenshannon
from scipy.ndimage import gaussian_filter1d

import argparse

# need full paths!
parser = argparse.ArgumentParser(description="calculates fold changes in signal with the given motifs over GC shuffled peak regions for the given model. Returns a txt file with fold changes for all the motifs. Return a txt file with fold change for the motif with highest fold change. Also returns these txt files for the motifs in reverse complement.")
parser.add_argument("-p", "--peak", type=str, required=True, help="peaks file")
parser.add_argument("-h5", "--h5model", type=str, required=True, help="model file")
parser.add_argument("--no_control_model", action='store_true', default=False, help='bool to indicate if the model was trained without control tracks')
parser.add_argument("--motifs", type=str, required=True, help="motifs string. Mutiple motifs are seperated by a colon")
parser.add_argument("--reference_genome", type=str,required=True, help="path the genome fasta")
parser.add_argument("-n", "--number_of_backgrounds", type=int,default=1000, help="number of gc maintaining shuffled background regions to test.")
parser.add_argument("-r", "--not_test_reverse_complement", action='store_true', default=False, help="boolean to whether test the motifs in the reverse complement orientation")
parser.add_argument("--input_seq_len", type=int,default=2114, help="length of the sequence input to the model.")
parser.add_argument("--output_len", type=int,default=1000, help="output length from the model")
parser.add_argument("--output_dir", type=str,default='.', help="output length from the model")


args = parser.parse_args()


def random_seq(seqlen):
    return ''.join(random.choices("ACGT", k=seqlen))


def dinuc_shuffle(seq, num_shufs=None, rng=None):
    """
    Creates shuffles of the given sequence, in which dinucleotide frequencies
    are preserved.
    Arguments:
        `seq`: either a string of length L, or an L x D NumPy array of one-hot
            encodings
        `num_shufs`: the number of shuffles to create, N; if unspecified, only
            one shuffle will be created
        `rng`: a NumPy RandomState object, to use for performing shuffles
    If `seq` is a string, returns a list of N strings of length L, each one
    being a shuffled version of `seq`. If `seq` is a 2D NumPy array, then the
    result is an N x L x D NumPy array of shuffled versions of `seq`, also
    one-hot encoded. If `num_shufs` is not specified, then the first dimension
    of N will not be present (i.e. a single string will be returned, or an L x D
    array).
    """
    if type(seq) is str:
        arr = string_to_char_array(seq)
    elif type(seq) is np.ndarray and len(seq.shape) == 2:
        seq_len, one_hot_dim = seq.shape
        arr = one_hot_to_tokens(seq)
    else:
        raise ValueError("Expected string or one-hot encoded array")

    if not rng:
        rng = np.random.RandomState()
   
    # Get the set of all characters, and a mapping of which positions have which
    # characters; use `tokens`, which are integer representations of the
    # original characters
    chars, tokens = np.unique(arr, return_inverse=True)

    # For each token, get a list of indices of all the tokens that come after it
    shuf_next_inds = []
    for t in range(len(chars)):
        mask = tokens[:-1] == t  # Excluding last char
        inds = np.where(mask)[0]
        shuf_next_inds.append(inds + 1)  # Add 1 for next token
 
    if type(seq) is str:
        all_results = []
    else:
        all_results = np.empty(
            (num_shufs if num_shufs else 1, seq_len, one_hot_dim),
            dtype=seq.dtype
        )

    for i in range(num_shufs if num_shufs else 1):
        # Shuffle the next indices
        for t in range(len(chars)):
            inds = np.arange(len(shuf_next_inds[t]))
            inds[:-1] = rng.permutation(len(inds) - 1)  # Keep last index same
            shuf_next_inds[t] = shuf_next_inds[t][inds]

        counters = [0] * len(chars)
       
        # Build the resulting array
        ind = 0
        result = np.empty_like(tokens)
        result[0] = tokens[ind]
        for j in range(1, len(tokens)):
            t = tokens[ind]
            ind = shuf_next_inds[t][counters[t]]
            counters[t] += 1
            result[j] = tokens[ind]

        if type(seq) is str:
            all_results.append(char_array_to_string(chars[result]))
        else:
            all_results[i] = tokens_to_one_hot(chars[result], one_hot_dim)
    return all_results if num_shufs else all_results[0]
def string_to_char_array(seq):
    """
    Converts an ASCII string to a NumPy array of byte-long ASCII codes.
    e.g. "ACGT" becomes [65, 67, 71, 84].
    """
    return np.frombuffer(bytearray(seq, "utf8"), dtype=np.int8)


def char_array_to_string(arr):
    """
    Converts a NumPy array of byte-long ASCII codes into an ASCII string.
    e.g. [65, 67, 71, 84] becomes "ACGT".
    """
    return arr.tostring().decode("ascii")


def one_hot_to_tokens(one_hot):
    """
    Converts an L x D one-hot encoding into an L-vector of integers in the range
    [0, D], where the token D is used when the one-hot encoding is all 0. This
    assumes that the one-hot encoding is well-formed, with at most one 1 in each
    column (and 0s elsewhere).
    """
    tokens = np.tile(one_hot.shape[1], one_hot.shape[0])  # Vector of all D
    seq_inds, dim_inds = np.where(one_hot)
    tokens[seq_inds] = dim_inds
    return tokens


def tokens_to_one_hot(tokens, one_hot_dim):
    """
    Converts an L-vector of integers in the range [0, D] to an L x D one-hot
    encoding. The value `D` must be provided as `one_hot_dim`. A token of D
    means the one-hot encoding is all 0s.
    """
    identity = np.identity(one_hot_dim + 1)[:, :-1]  # Last row is all 0s
    return identity[tokens]

def fix_sequence_length(sequence, length):
    """
        Function to check if length of sequence matches specified
        length and then return a sequence that's either padded or
        truncated to match the given length
        Args:
            sequence (str): the input sequence
            length (int): expected length
        Returns:
            str: string of length 'length'
    """

    # check if the sequence is smaller than expected length
    if len(sequence) < length:
        # pad the sequence with 'N's
        sequence += 'N' * (length - len(sequence))
    # check if the sequence is larger than expected length
    elif len(sequence) > length:
        # truncate to expected length
        sequence = sequence[:length]

    return sequence
def jsd_min_max_bounds(profile):
    """
        Min Max bounds for the jsd metric
        
        Args:
            profile (numpy.ndarray): true profile 
            
        Returns:
            tuple: (min, max) bounds values
    """
    
    # uniform distribution profile
    uniform_profile = np.ones(len(profile)) * (1.0 / len(profile))

    # profile as probabilities
    profile_prob = profile / np.sum(profile)

    # jsd of profile with uniform profile
    max_jsd = jensenshannon(profile_prob, uniform_profile)

    # jsd of profile with itself (upper bound)
    min_jsd = 0.0

    return (min_jsd, max_jsd)

def min_max_normalize(metric_value, min_max_bounds, default=1.0):
    """
        Min Max normalize a metric value
        
        Args:
            metric_value (float): unnormalized metric value
            min_max_bounds (tuple): (min, max) bounds
            default (float): the default value to return in case
                of runtime exceptions
    """
    
    min_bound = min_max_bounds[0]
    max_bound = min_max_bounds[1]
    
    if (max_bound - min_bound) == 0:
        return default
    
    norm_value = (metric_value - min_bound) / (max_bound - min_bound) 
    
    if norm_value < 0:
        return 0
    
    if norm_value > 1:
        return 1
    
    return norm_value

def metrics_update(
    metrics_tracker, example_idx, track_idx, true_profile, true_logcounts,
    pred_profile, pred_logcounts, true_profile_smoothing=[7.0, 81]):
    """
        Update metrics with new true/predicted profile & counts
        
        Args:
            metrics_tracker (dict): dictionary to track & update 
                metrics info 
            example_idx (int): index of the example to be updated
            track_idx (int): index of the ith track to be updated
            true_profile (numpy.ndarray): ground truth profile
            true_counts (float): sum of true profile
            pred_profile (numpy.ndarray): predicted profile output
            pred_counts (float): predicted 
            true_profile_smoothing (list): list of 2 values, sigma &
                window size for gaussuan 1d smoothing
            
    
    """
    
    # Step 1 - smooth true profile
    sigma = true_profile_smoothing[0]
    width = float(true_profile_smoothing[1])
    truncate = (((width - 1)/2)-0.5)/sigma

    # Step 2 - smooth true profile and convert profiles to 
    # probabilities
    if np.sum(true_profile) != 0 and np.sum(pred_profile) != 0:
        # smoothing
        true_profile_smooth = gaussian_filter1d(
            true_profile, sigma=sigma, truncate=truncate)

        # convert to probabilities
        true_profile_smooth_prob = true_profile_smooth / np.sum(
            true_profile_smooth)
        pred_profile_prob = pred_profile / np.sum(pred_profile)
        pred_profile_prob = _fix_sum_to_one(pred_profile_prob)

        # metrics 
        # profile pearson & spearman
        # with pearson we need to check if either of the arrays
        # has zero standard deviation (i.e having all same elements,
        # a zero or any other value). Unfortunately np.std
        # returns a very small non-zero value, so we'll use a 
        # different approach to check if the array has the same value.
        # If true then pearson correlation is undefined 
        if np.unique(true_profile_smooth_prob).size == 1 or \
            np.unique(pred_profile_prob).size == 1:
            metrics_tracker['profile_pearsonrs'][example_idx, track_idx] = 0
            metrics_tracker['profile_spearmanrs'][example_idx, track_idx] = 0
        else:
            metrics_tracker['profile_pearsonrs'][example_idx, track_idx] = \
                pearsonr(true_profile_smooth_prob, pred_profile_prob)[0]

            metrics_tracker['profile_spearmanrs'][example_idx, track_idx] = \
                spearmanr(true_profile_smooth_prob, pred_profile_prob)[0]
            
        # mnll
        _mnll = np.nan_to_num(mnll(true_profile, probs=pred_profile_prob))
        _mnll = min_max_normalize(_mnll, mnll_min_max_bounds(true_profile))
        metrics_tracker['profile_mnlls'][example_idx, track_idx] = _mnll

        # cross entropy
        metrics_tracker['profile_cross_entropys'][example_idx, track_idx] = \
            min_max_normalize(
                profile_cross_entropy(true_profile, probs=pred_profile_prob), 
                cross_entropy_min_max_bounds(true_profile))

        # jsd
        metrics_tracker['profile_jsds'][example_idx, track_idx] = \
            min_max_normalize(
                jensenshannon(true_profile_smooth_prob, pred_profile_prob), 
                jsd_min_max_bounds(true_profile))

        # mse
        metrics_tracker['profile_mses'][example_idx, track_idx] = \
            np.square(np.subtract(true_profile, pred_profile)).mean()
        
    metrics_tracker['all_true_logcounts'][example_idx, track_idx] = \
        true_logcounts
    metrics_tracker['all_pred_logcounts'][example_idx, track_idx] = \
        pred_logcounts
    

def one_hot_encode(sequences, seq_length=2114):
    """
    
       One hot encoding of a list of DNA sequences 
       
       Args:
           sequences (list): python list of strings of equal length
           seq_length (int): expected length of each sequence in the 
               list
           
       Returns:
           numpy.ndarray: 
               3-dimension numpy array with shape 
               (len(sequences), len(list_item), 4)
    """
    
    if len(sequences) == 0:
        logging.error("'sequences' is empty")
        return None
    
    # First, let's make sure all sequences are of equal length
    sequences = list(map(
        fix_sequence_length, sequences, [seq_length] * len(sequences)))

    # Step 1. convert sequence list into a single string
    _sequences = ''.join(sequences)
    
    # Step 2. translate the alphabet to a string of digits
    transtab = str.maketrans('ACGTNYRMSWK', '01234444444')    
    sequences_trans = _sequences.translate(transtab)
    
    # Step 3. convert to list of ints
    int_sequences = list(map(int, sequences_trans))
    
    # Step 4. one hot encode using int_sequences to index 
    # into an 'encoder' array
    encoder = np.vstack([np.eye(4), np.zeros(4)])
    X = encoder[int_sequences]

    # Step 5. reshape 
    return X.reshape(len(sequences), len(sequences[0]), 4)


def get_suffled_peak_sequences(peak_path,fasta_path, input_seq_len = 2114,
                               num_of_simulated_sequences=1000):
    peaks_df = pd.read_csv(peak_path,
                           sep='\t',header=None,
                           names=['chrom', 'start', 'end', 'name', 'score',
                                      'strand', 'signalValue', 'p', 'q', 'summit'])

    peaks_df = peaks_df.sample(frac=1).reset_index(drop=True)
    
    valid_chroms = ['chr2', 'chr11', 'chr6', 'chr19', 'chr5', 'chr18',
       'chrX', 'chr1', 'chr10', 'chr12', 'chr15', 'chr22', 'chr17',
       'chr3', 'chr4', 'chr20', 'chr21', 'chr14', 'chr16', 'chr9', 'chr7',
       'chr8', 'chrM', 'chr13', 'chrY']
    
    peaks_df = peaks_df.loc[peaks_df['chrom'].isin(valid_chroms),:].reset_index(drop=True)

    fasta_ref = pysam.FastaFile(fasta_path)

    sequences = []

    Input_start = peaks_df['start'] + peaks_df['summit'] - (input_seq_len//2)
    Input_start = Input_start.mask(Input_start < 0,0)
    Input_end = peaks_df['start'] + peaks_df['summit'] + (input_seq_len//2)

    if len(peaks_df)<num_of_simulated_sequences:
        num_of_simulated_sequences = len(peaks_df)
    for i in range(num_of_simulated_sequences):
        actual_sequence = fasta_ref.fetch(peaks_df['chrom'][i], Input_start[i] , Input_end[i]).upper()
        padded_sequence = actual_sequence+(random_seq(input_seq_len-len(actual_sequence)))
        shuffled_seq = dinuc_shuffle(padded_sequence)
        sequences.append(shuffled_seq)
    
    return sequences


def predict_logits(model,encoded_inserted_sequences,no_control_model=False,output_seq_len = 1000,number_of_strands = 2):
    
    if no_control_model:
        prediction = model.predict([encoded_inserted_sequences])   
    else:
        prediction = model.predict([encoded_inserted_sequences,
                       np.zeros(output_seq_len*number_of_strands*encoded_inserted_sequences.shape[0]).reshape((encoded_inserted_sequences.shape[0],output_seq_len,number_of_strands)),    
                       np.zeros(encoded_inserted_sequences.shape[0]*number_of_strands).reshape((encoded_inserted_sequences.shape[0],number_of_strands))])
        

    return prediction


def calculate_fold_change_in_predicted_signal(peak_path,
                                                 model,
                                                 motifs,
                                                 reference_genome,
                                                 number_of_backgrounds=1000,
                                                 no_control_model=False,
                                                 output_seq_len=1000,
                                                 input_seq_len=2114,
                                                 not_test_reverse_complement=False):

    background_sequences = get_suffled_peak_sequences(peak_path=peak_path,fasta_path=reference_genome, 
                                                      input_seq_len = input_seq_len,
                                                       num_of_simulated_sequences=number_of_backgrounds)
    one_hot_encoded_background_sequences = one_hot_encode(background_sequences)
    prediction_background_sequences = predict_logits(model,encoded_inserted_sequences = one_hot_encoded_background_sequences,
                                        output_seq_len = output_seq_len)

    fold_changes = []
    motifs_lst = str.split(motifs,sep=';')
    for motif in motifs_lst:
        motif_inserted_sequences = []
        
        for index,sequence in enumerate(background_sequences):
            inserted_sequence = (sequence[:(input_seq_len//2)] 
                                +motif
                                +sequence[(input_seq_len//2)+len(motif):])
            motif_inserted_sequences.append(inserted_sequence+random_seq(input_seq_len-len(inserted_sequence)))


        one_hot_encoded_sequence = one_hot_encode(motif_inserted_sequences)
        
        prediction_motif_sequences = predict_logits(model,encoded_inserted_sequences = one_hot_encoded_sequence,
                                        output_seq_len = output_seq_len,no_control_model=no_control_model)
        
        median_fold_change = np.median(np.log2(np.exp(prediction_motif_sequences[1]-prediction_background_sequences[1])))   
        
        
        fold_changes.append({'motif':motif,'median_fold_change':median_fold_change})
        
    if not not_test_reverse_complement:
        
        rc_fold_changes = []
        motifs_lst = str.split(motifs,sep=';')
        for motif in motifs_lst:
            motif_inserted_sequences = []
            rc_motif=motif.translate(str.maketrans("ACTG", "TGAC"))[::-1]
            for sequence in background_sequences:
                inserted_sequence = (sequence[:(input_seq_len//2)] 
                                    +rc_motif
                                    +sequence[(input_seq_len//2)+len(motif):])
                motif_inserted_sequences.append(inserted_sequence+random_seq(input_seq_len-len(inserted_sequence)))


            one_hot_encoded_sequence = one_hot_encode(motif_inserted_sequences)

            prediction_motif_sequences = predict_logits(model,encoded_inserted_sequences = one_hot_encoded_sequence,
                                            output_seq_len = output_seq_len)

            median_fold_change = np.median(np.log2(np.exp(prediction_motif_sequences[1]-prediction_background_sequences[1])))    
            rc_fold_changes.append({'motif':rc_motif,'median_fold_change':median_fold_change})
    
    
    return fold_changes,rc_fold_changes




with CustomObjectScope({'MultichannelMultinomialNLL': lambda n='0':n,
                        "kb": kb,
                        "CustomMeanSquaredError":lambda n='0':n,
                        "tf":tf,
                       "CustomModel":CustomModel}):
    model = load_model(args.h5model,compile=False)

print('not_test_reverse_complement:',args.not_test_reverse_complement) 
print('no_control_model:',args.no_control_model) 

fold_changes,rc_fold_changes = calculate_fold_change_in_predicted_signal(peak_path=args.peak,
                                                          model=model,no_control_model=args.no_control_model,
                                                          motifs=args.motifs,
                                                          number_of_backgrounds=args.number_of_backgrounds,
                                                          reference_genome = args.reference_genome,
                                                          not_test_reverse_complement=args.not_test_reverse_complement)

  
print(fold_changes,rc_fold_changes)

with open(f'{args.output_dir}/median_log2_fold_change.txt', 'w') as f:
    f.write(str(round(max(pd.DataFrame(fold_changes)['median_fold_change']),3)))

with open(f'{args.output_dir}/all_log2_fold_changes.txt', 'w') as f:
    all_log2_fold_changes=';'.join([f"{fold_change['motif']}:{fold_change['median_fold_change']:.3f}" for fold_change in fold_changes])
    f.write(all_log2_fold_changes)
    
with open(f'{args.output_dir}/median_log2_fold_change_rc.txt', 'w') as f:
    f.write(str(round(max(pd.DataFrame(rc_fold_changes)['median_fold_change']),3)))

with open(f'{args.output_dir}/all_log2_fold_changes_rc.txt', 'w') as f:
    all_log2_fold_changes_rc=';'.join([f"{fold_change['motif']}:{fold_change['median_fold_change']:.3f}" for fold_change in rc_fold_changes])
    f.write(all_log2_fold_changes_rc)


    
