version 1.0

task run_mean_shap {
	input {
		Array [File]? counts_shap
		Array [File]? profile_shap

	}	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		git clone --depth 1 --branch main https://github.com/viramalingam/tf-atlas-pipeline.git
		chmod -R 777 tf-atlas-pipeline
		cd tf-atlas-pipeline/anvil/shap/

		##mean shap

		echo "python /my_scripts/tf-atlas-pipeline/anvil/shap/mean_shap.py" --counts_shaps ${sep=',' counts_shap} --profile_shaps ${sep=',' profile_shap}
		python /my_scripts/tf-atlas-pipeline/anvil/shap/mean_shap.py --counts_shaps ${sep=',' counts_shap} --profile_shaps ${sep=',' profile_shap}

		echo "copying all files to cromwell_root folder"
	}
	
	output {
		File profile_mean_shap_scores_h5 = "profile_mean_shap_scores.h5"
		File counts_mean_shap_scores_h5 = "counts_mean_shap_scores.h5"
		        
	
	
	}

	runtime {
		docker: 'vivekramalingam/tf-atlas:gcp-modeling_v1.6.5'
		memory: 32 + "GB"
		bootDiskSizeGb: 50
		disks: "local-disk 50 HDD"
	}
}

workflow mean_shap {
	input {
		Array [File]? counts_shap
		Array [File]? profile_shap




	}

	call run_mean_shap {
		input:
		counts_shap = counts_shap,
		profile_shap = profile_shap

	}
	output {
		File profile_mean_shap_scores_h5 = run_mean_shap.profile_mean_shap_scores_h5
		File counts_mean_shap_scores_h5 = run_mean_shap.counts_mean_shap_scores_h5
		
	}
}