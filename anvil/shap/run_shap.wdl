version 1.0

task run_shap {
	input {
		String experiment
		File reference_file
		File peaks
		File model


  	}	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		mkdir /project/
		mkdir /project/shap_dir_peaks/
		git clone --depth 1 --branch master https://github.com/kundajelab/chrombpnet.git

		##shap

		echo "python /my_scripts/chrombpnet/chrombpnet/evaluation/interpret/interpret.py -g ${reference_file} -r ${peaks} -m ${model} -o /project/shap_dir_peaks/${experiment} -p profile"
		python /my_scripts/chrombpnet/chrombpnet/evaluation/interpret/interpret.py -g ${reference_file} -r ${peaks} -m ${model} -o /project/shap_dir_peaks/${experiment} -p "profile"

		echo "copying all files to cromwell_root folder"
		
		cp -r /project/shap_dir_peaks/${experiment}.profile_scores.h5 /cromwell_root/${experiment}.profile_scores.h5
		cp -r /project/shap_dir_peaks/${experiment}.interpreted_regions.bed /cromwell_root/${experiment}.interpreted_regions.bed
	}
	
	output {
		File profile_shap_scores = "${experiment}.profile_scores.h5"
		File interpreted_regions = "${experiment}.interpreted_regions.bed"
		        
	
	
	}

	runtime {
		docker: 'kundajelab/chrombpnet:latest'
		memory: 50 + "GB"
		bootDiskSizeGb: 50
		disks: "local-disk 100 HDD"
		gpuType: "nvidia-tesla-v100"
		gpuCount: 1
		nvidiaDriverVersion: "450.51.05" 
		maxRetries: 1
	}
}

workflow shap {
	input {
		String experiment
		File reference_file
		File peaks
		File model

	}

	call run_shap {
		input:
			experiment = experiment,
			reference_file = reference_file,
			peaks = peaks,
			model = model
 	}
	output {
		File profile_shap_scores = "${experiment}.profile_scores.h5"
		File interpreted_regions = "${experiment}.interpreted_regions.bed"
		
	}
}
