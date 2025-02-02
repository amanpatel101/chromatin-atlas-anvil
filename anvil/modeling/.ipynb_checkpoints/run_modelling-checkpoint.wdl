version 1.0

task run_modelling {
	input {
		String experiment
		File training_input_json
		File testing_input_json
		File bpnet_params_json
		File splits_json
		File reference_file
		File reference_file_index
		File chrom_sizes
		File chroms_txt
		Array [File] bigwigs
		File peaks
		File background_regions
		Float learning_rate
		Array [File]? indices_files
	}
	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		git clone --depth 1 --branch v1.6.0 https://github.com/viramalingam/tf-atlas-pipeline.git
		chmod -R 777 tf-atlas-pipeline
		cd tf-atlas-pipeline/anvil/modeling/
		
		##modelling
		
		echo "run /my_scripts/tf-atlas-pipeline/anvil/modeling/modelling_pipeline.sh" ${experiment} ${training_input_json} ${testing_input_json} ${bpnet_params_json} ${splits_json} ${reference_file} ${reference_file_index} ${chrom_sizes} ${chroms_txt} ${sep=',' bigwigs} ${peaks} ${background_regions} ${learning_rate} ${sep=',' indices_files}
		/my_scripts/tf-atlas-pipeline/anvil/modeling/modelling_pipeline.sh ${experiment} ${training_input_json} ${testing_input_json} ${bpnet_params_json} ${splits_json} ${reference_file} ${reference_file_index} ${chrom_sizes} ${chroms_txt} ${sep=',' bigwigs} ${peaks} ${background_regions} ${learning_rate} ${sep=',' indices_files}
		
		echo "copying all files to cromwell_root folder"
		
		cp /project/bpnet_params.json /cromwell_root/bpnet_params.json
		cp -r /project/model /cromwell_root/
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms /cromwell_root/
		cp -r /project/predictions_and_metrics_test_peaks_all_chroms /cromwell_root/
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms /cromwell_root/
		cp -r /project/predictions_and_metrics_all_peaks_all_chroms /cromwell_root/
		
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms/spearman.txt /cromwell_root/spearman.txt
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms/pearson.txt /cromwell_root/pearson.txt
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms/jsd.txt /cromwell_root/jsd.txt
		
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms/spearman.txt /cromwell_root/spearman_all_peaks.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms/pearson.txt /cromwell_root/pearson_all_peaks.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms/jsd.txt /cromwell_root/jsd_all_peaks.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms/auprc.txt /cromwell_root/auprc.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms/auroc.txt /cromwell_root/auroc.txt
		
		
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms_wo_bias/spearman.txt /cromwell_root/spearman_wo_bias.txt
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms_wo_bias/pearson.txt /cromwell_root/pearson_wo_bias.txt
		cp -r /project/predictions_and_metrics_test_peaks_test_chroms_wo_bias/jsd.txt /cromwell_root/jsd_wo_bias.txt
		
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms_wo_bias/spearman.txt /cromwell_root/spearman_all_peaks_wo_bias.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms_wo_bias/pearson.txt /cromwell_root/pearson_all_peaks_wo_bias.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms_wo_bias/jsd.txt /cromwell_root/jsd_all_peaks_wo_bias.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms_wo_bias/auprc.txt /cromwell_root/auprc_wo_bias.txt
		cp -r /project/predictions_and_metrics_all_peaks_test_chroms_wo_bias/auroc.txt /cromwell_root/auroc_wo_bias.txt
	}
	
	output {
		File bpnet_params_updated_json = "bpnet_params.json"
		Array[File] model = glob("model/*")
		Array[File] predictions_and_metrics_test_peaks_test_chroms = glob("predictions_and_metrics_test_peaks_test_chroms/*")
		Array[File] predictions_and_metrics_test_peaks_all_chroms = glob("predictions_and_metrics_test_peaks_all_chroms/*")

		Array[File] predictions_and_metrics_all_peaks_all_chroms = glob("predictions_and_metrics_all_peaks_all_chroms/*")
		Array[File] predictions_and_metrics_all_peaks_test_chroms = glob("predictions_and_metrics_all_peaks_test_chroms/*")
		
		Float spearman = read_float("spearman.txt")
		Float pearson = read_float("pearson.txt")
		Float jsd = read_float("jsd.txt")
		
		Float spearman_all_peaks = read_float("spearman_all_peaks.txt")
		Float pearson_all_peaks = read_float("pearson_all_peaks.txt")
		Float jsd_all_peaks = read_float("jsd_all_peaks.txt")
		Float auprc = read_float("auprc.txt")
		Float auroc = read_float("auroc.txt")
		
		Float spearman_wo_bias = read_float("spearman_wo_bias.txt")
		Float pearson_wo_bias = read_float("pearson_wo_bias.txt")
		Float jsd_wo_bias = read_float("jsd_wo_bias.txt")
		
		Float spearman_all_peaks_wo_bias = read_float("spearman_all_peaks_wo_bias.txt")
		Float pearson_all_peaks_wo_bias = read_float("pearson_all_peaks_wo_bias.txt")
		Float jsd_all_peaks_wo_bias = read_float("jsd_all_peaks_wo_bias.txt")
		Float auprc_wo_bias = read_float("auprc_wo_bias.txt")
		Float auroc_wo_bias = read_float("auroc_wo_bias.txt")
	
	
	}

	runtime {
		docker: 'vivekramalingam/tf-atlas:gcp-modeling_v1.6.0'
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
		File training_input_json
		File testing_input_json
		File bpnet_params_json
		File splits_json
		File reference_file
		File reference_file_index
		File chrom_sizes
		File chroms_txt
		Array [File] bigwigs
		File peaks
		File background_regions
		Float learning_rate
		Array [File]? indices_files
	}
	
	call run_modelling {
		input:
			experiment = experiment,
			training_input_json = training_input_json,
			testing_input_json = testing_input_json,
			bpnet_params_json = bpnet_params_json,
			splits_json = splits_json,
			reference_file = reference_file,
			reference_file_index = reference_file_index,	
			chrom_sizes = chrom_sizes,
			chroms_txt = chroms_txt,
			bigwigs = bigwigs,
			peaks = peaks,
			background_regions = background_regions,
			learning_rate = learning_rate,
			indices_files = indices_files
	}
	output {
		File bpnet_params_updated_json = run_modelling.bpnet_params_updated_json
		Array[File] model = run_modelling.model
		Array[File] predictions_and_metrics_all_peaks_test_chroms = run_modelling.predictions_and_metrics_all_peaks_test_chroms
		Array[File] predictions_and_metrics_test_peaks_test_chroms = run_modelling.predictions_and_metrics_test_peaks_test_chroms
		Array[File] predictions_and_metrics_all_peaks_all_chroms = run_modelling.predictions_and_metrics_all_peaks_all_chroms
		Array[File] predictions_and_metrics_test_peaks_all_chroms = run_modelling.predictions_and_metrics_test_peaks_all_chroms
		Float spearman = run_modelling.spearman
		Float pearson = run_modelling.pearson
		Float jsd = run_modelling.jsd
		Float spearman_all_peaks = run_modelling.spearman_all_peaks
		Float pearson_all_peaks = run_modelling.pearson_all_peaks
		Float jsd_all_peaks = run_modelling.jsd_all_peaks
		Float auprc = run_modelling.auprc
		Float auroc = run_modelling.auroc
		
		
		Float spearman_wo_bias = run_modelling.spearman_wo_bias
		Float pearson_wo_bias = run_modelling.pearson_wo_bias
		Float jsd_wo_bias = run_modelling.jsd_wo_bias
		Float spearman_all_peaks_wo_bias = run_modelling.spearman_all_peaks_wo_bias
		Float pearson_all_peaks_wo_bias = run_modelling.pearson_all_peaks_wo_bias
		Float jsd_all_peaks_wo_bias = run_modelling.jsd_all_peaks_wo_bias
		Float auprc_wo_bias = run_modelling.auprc_wo_bias
		Float auroc_wo_bias = run_modelling.auroc_wo_bias
		
	}
}
