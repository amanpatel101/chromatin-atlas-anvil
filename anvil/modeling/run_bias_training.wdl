version 1.0

task run_modelling {
	input {
		String experiment
		File input_bam
		String data_type
		File reference_file
		File chrom_sizes
		File peak_data
		File nonpeak_data
		File fold_file
		Float threshold
	}
	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		git clone --depth 1 --branch master https://github.com/kundajelab/chrombpnet.git
		mkdir /cromwell_root/results/
		
		##modelling

		chrombpnet bias pipeline -ibam ${input_bam} -d ${data_type} -g ${reference_file} -c ${chrom_sizes} -p ${peak_data} -n ${nonpeak_data} -fl ${fold_file} -o /cromwell_root/results/
		

	}
	
	output {
		File bias_model = "models/bias.h5"

		File overall_report_pdf = "evaluation/overall_report.pdf"
		File overall_report_html = "evaluation/overall_report.html"
		File pwm_from_input = "evaluation/pwm_from_input.png"
		File bias_metrics = "evaluation/bias_metrics.json" 
		File bias_only_peaks_counts_pearsonr = "evaluation/bias_only_peaks.counts_pearsonr.png"
		File bias_only_peaks_profile_jsd = "evaluation/bias_only_peaks.profile_jsd.png"
		File bias_only_nonpeaks_counts_pearsonr = "evaluation/bias_only_nonpeaks.counts_pearsonr.png"
		File bias_only_nonpeaks_profile_jsd = "evaluation/bias_only_nonpeaks.profile_jsd.png"
		File bias_predictions = "evaluation/bias_predictions.h5"
		File bias_profile = "evaluation/bias_profile.pdf"
		File bias_counts = "evaluation/bias_counts.pdf"
	
	}

	runtime {
		docker: 'kundajelab/chrombpnet:latest'
		memory: 32 + "GB"
		bootDiskSizeGb: 50
		disks: "local-disk 100 HDD"
		gpuType: "nvidia-tesla-k80"
		gpuCount: 1
		nvidiaDriverVersion: "418.87.00"
		maxRetries: 1
	}
}

workflow modelling {
	input {
		String experiment
		File input_bam
		String data_type
		File reference_file
		File chrom_sizes
		File peak_data
		File nonpeak_data
		File fold_file
		Float threshold
	}
	
	call run_modelling {
		input:
			experiment = experiment,
			input_bam = input_bam,
			data_type = data_type,
			reference_file = reference_file,
			chrom_sizes = chrom_sizes,
			peak_data = peak_data,
			nonpeak_data = nonpeak_data,
			fold_file = fold_file,
			threshold = threshold
	}
	output {
		File bias_model = "models/bias.h5"

		File overall_report_pdf = "evaluation/overall_report.pdf"
		File overall_report_html = "evaluation/overall_report.html"
		File pwm_from_input = "evaluation/pwm_from_input.png"
		File bias_metrics = "evaluation/bias_metrics.json" 
		File bias_only_peaks_counts_pearsonr = "evaluation/bias_only_peaks.counts_pearsonr.png"
		File bias_only_peaks_profile_jsd = "evaluation/bias_only_peaks.profile_jsd.png"
		File bias_only_nonpeaks_counts_pearsonr = "evaluation/bias_only_nonpeaks.counts_pearsonr.png"
		File bias_only_nonpeaks_profile_jsd = "evaluation/bias_only_nonpeaks.profile_jsd.png"
		File bias_predictions = "evaluation/bias_predictions.h5"
		File bias_profile = "evaluation/bias_profile.pdf"
		File bias_counts = "evaluation/bias_counts.pdf"
		
	}
}
