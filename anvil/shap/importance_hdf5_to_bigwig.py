import argparse
import pyBigWig
import numpy as np
import h5py
import gzip
import hdf5plugin

# need full paths!
parser = argparse.ArgumentParser(description="Convery importance scores in hdf5 format to bigwig. PROVIDE ABSOLUTE PATHS!")
parser.add_argument("-h5", "--hdf5", type=str, required=True, help="HDF5 file f such that f['projected_shap']['seq'] has (N x 4 x seqlen) shape with importance score * sequence so that at each f['projected_shap']['seq'][i, :, j] has 3 zeros and 1 non-zero value")
parser.add_argument("-r", "--regions", type=str, required=True, help="10 column BED file of length = N which matches f['projected_shap']['seq'].shape[0]. The ith region in the imBED file corresponds to ith entry in importance matrix. If start=2nd col, summit=10th col, then the importance scores are for [start+summit-(seqlen/2):start+summit+(seqlen/2)]")
parser.add_argument("-c", "--chrom_sizes", type=str, required=True, help="Chromosome sizes 2 column file")
parser.add_argument("-o", "--outfile", type=str, required=True, help="Output bigwig file")
parser.add_argument("-s", "--outstats", type=str, required=True, help="Output file with stats of low and high quantiles")
parser.add_argument("-t", "--tqdm", type=int,default=0, help="Use tqdm")
parser.add_argument("-z", "--gzipped", action='store_true', help="peak file is gzipped")

args = parser.parse_args()
print(args)
with open(args.chrom_sizes) as f:
    gs = [x.strip().split('\t') for x in f]
gs = [(x[0], int(x[1])) for x in gs]

chr_to_idx = {}
for i,x in enumerate(gs):
    chr_to_idx[x[0]] = i


scores = h5py.File(args.hdf5, 'r')

shap_scores = scores['hyp_scores']
one_hot_seqs = scores['input_seqs']

print("Computing projected shap scores")
proj_shap_scores = np.multiply(one_hot_seqs, shap_scores)
print("Done computing projected shap scores")

scores.close()

proj_shap_scores = proj_shap_scores.transpose((0,2,1))

SEQLEN = proj_shap_scores.shape[2]
assert(SEQLEN%2==0)

if args.gzipped:
    with gzip.open(args.regions) as f:
        regions = [x.decode('utf8').strip().split('\t') for x in f]
else:
    with open(args.regions) as r:
        regions = [x.strip().split('\t') for x in r]

regions = [[x[0], int(x[1])+int(x[9])-int(SEQLEN/2), int(x[1])+int(x[9])+int(SEQLEN/2)] for x in regions]

# regions may not be sorted, so get their sorted order
order_of_regs = sorted(range(len(regions)), key=lambda x:(chr_to_idx[regions[x][0]], regions[x][1]))

# regions may overlap but as we go in sorted order, we will ignore the values that are repeated 
# and only consider the first instance

bw = pyBigWig.open(args.outfile, 'w')
bw.addHeader(gs)
all_entries = []
cur_chr = ""
cur_end = 0
if args.tqdm:
    from tqdm import tqdm
    iterator = tqdm(order_of_regs)
else:
    iterator = order_of_regs

for i in iterator:
    # subset to chromosome (debugging)
    #if regions[i][0]!="chr12":
    #    continue
    if regions[i][0]!=cur_chr: 
        cur_chr = regions[i][0]
        cur_end = 0
    # bring current end to at least start of current region
    if cur_end < regions[i][1]:
        cur_end = regions[i][1]
    assert(regions[i][2]>=cur_end)
   
    vals = np.sum(proj_shap_scores[i], axis=0)[cur_end-regions[i][1]:]
    bw.addEntries([regions[i][0]]*(regions[i][2]-cur_end), 
                   list(range(cur_end,regions[i][2])), 
                   ends=list(range(cur_end+1, regions[i][2]+1)), 
                   values=vals)
    all_entries.append(vals)
    
    cur_end = regions[i][2]+1
bw.close()

all_entries = np.hstack(all_entries)
with open(args.outstats, 'w') as f:
    f.write("Min\t{:.6f}\n".format(np.min(all_entries)))
    f.write(".1%\t{:.6f}\n".format(np.quantile(all_entries, 0.001)))
    f.write("1%\t{:.6f}\n".format(np.quantile(all_entries, 0.01)))
    f.write("50%\t{:.6f}\n".format(np.quantile(all_entries, 0.5)))
    f.write("99%\t{:.6f}\n".format(np.quantile(all_entries, 0.99)))
    f.write("99.9%\t{:.6f}\n".format(np.quantile(all_entries, 0.999)))
    f.write("99.95%\t{:.6f}\n".format(np.quantile(all_entries, 0.9995)))
    f.write("99.99%\t{:.6f}\n".format(np.quantile(all_entries, 0.9999)))
    f.write("Max\t{:.6f}\n".format(np.max(all_entries)))

