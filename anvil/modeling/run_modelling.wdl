version 1.0

task run_modelling {
	input {
		String experiment
		File input_bam
		String data_type
		File reference_file
		File peak_data
		File nonpeak_data
		File fold_file
		File bias_model
		Float learning_rate
	}
	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		git clone --depth 1 --branch master https://github.com/kundajelab/chrombpnet.git
		mkdir /cromwell_root/results/
		
		##modelling

		chrombpnet pipeline -ibam ${input_bam} -d ${data_type} -g ${reference_file} -p ${peak_data} -n ${nonpeak_data} -fl ${fold_file} -b ${bias_model} -o /cromwell_root/results/
		

	}
	
	output {
		File bias_model_scaled = "models/bias_model_scaled.h5"
		File chrombpnet = "models/chrombpnet.h5"
		File chrombpnet_no_bias = "models/chrombpnet_wo_bias.h5"
		File chrombpnet_log = "logs/chrombpnet.log"
		File chrombpnet_log_batch = "logs/chrombpnet.log.batch"
		File filtered_peaks = "auxilary/filtered.peaks"
		File filtered_nonpeaks = "auxilary/filtered.nonpeaks"

		File overall_report_pdf = "overall_report.pdf"
		File overall_report_html = "overall_report.html"
		File bw_shift_qc = "bw_shift_qc.png"
		File bias_metrics = "bias_metrics.json" 
		File chrombpnet_metrics = "chrombpnet_metrics.json"
		File chrombpnet_only_peaks_counts_pearsonr = "chrombpnet_only_peaks.counts_pearsonr.png"
		File chrombpnet_only_peaks_profile_jsd = "chrombpnet_only_peaks.profile_jsd.png"
		File chrombpnet_nobias_profile_motifs = "chrombpnet_nobias_profile_motifs.pdf"
		File chrombpnet_nobias_counts_motifs = "chrombpnet_nobias_counts_motifs.pdf"
		File chrombpnet_nobias_max_bias_response = "chrombpnet_nobias_max_bias_response.txt"
		Array[File] footprints = glob("chrombpnet_nobias*footprint.png")	
	
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
		File peak_data
		File nonpeak_data
		File fold_file
		File bias_model
		Float learning_rate
	}
	
	call run_modelling {
		input:
			experiment = experiment,
			input_bam = input_bam,
			data_type = data_type,
			reference_file = reference_file,
			peak_data = peak_data,
			nonpeak_data = nonpeak_data,
			fold_file = fold_file,
			bias_model = bias_model,
			learning_rate = learning_rate
	}
	output {
		File bias_model_scaled = "models/bias_model_scaled.h5"
		File chrombpnet = "models/chrombpnet.h5"
		File chrombpnet_no_bias = "models/chrombpnet_wo_bias.h5"
		File chrombpnet_log = "logs/chrombpnet.log"
		File chrombpnet_log_batch = "logs/chrombpnet.log.batch"
		File filtered_peaks = "auxilary/filtered.peaks"
		File filtered_nonpeaks = "auxilary/filtered.nonpeaks"

		File overall_report_pdf = "overall_report.pdf"
		File overall_report_html = "overall_report.html"
		File bw_shift_qc = "bw_shift_qc.png"
		File bias_metrics = "bias_metrics.json" 
		File chrombpnet_metrics = "chrombpnet_metrics.json"
		File chrombpnet_only_peaks_counts_pearsonr = "chrombpnet_only_peaks.counts_pearsonr.png"
		File chrombpnet_only_peaks_profile_jsd = "chrombpnet_only_peaks.profile_jsd.png"
		File chrombpnet_nobias_profile_motifs = "chrombpnet_nobias_profile_motifs.pdf"
		File chrombpnet_nobias_counts_motifs = "chrombpnet_nobias_counts_motifs.pdf"
		File chrombpnet_nobias_max_bias_response = "chrombpnet_nobias_max_bias_response.txt"
		Array[File] footprints = glob("chrombpnet_nobias*footprint.png")	
		
	}
}
