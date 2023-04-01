version 1.0

task run_modisco {
	input {
		String experiment
		Array [File] shap
		Int? mem_gb
		Int? max_seqlets        
		Int? number_of_cpus


  	}	
	command {
		#create data directories and download scripts
		cd /; mkdir my_scripts
		cd /my_scripts
		git clone --depth 1 --branch v1.6.11 https://github.com/viramalingam/chromatin-atlas-anvil.git
		chmod -R 777 chromatin-atlas-anvil
		cd chromatin-atlas-anvil/anvil/modisco/

		##modisco

		echo "run /my_scripts/chromatin-atlas-anvil/anvil/modisco/modisco_pipeline.sh" ${experiment} ${sep=',' shap} ${max_seqlets}
		/my_scripts/chromatin-atlas-anvil/anvil/modisco/modisco_pipeline.sh ${experiment} ${sep=',' shap} ${max_seqlets}

		echo "copying all files to cromwell_root folder"
		
		cp -r /project/modisco_profile /cromwell_root/
		cp -r /project/modisco_counts /cromwell_root/
		
	}
	
	output {
		Array[File] modisco_profile_motifs = glob("modisco_profile/trimmed_logos/*")
		Array[File] modisco_counts_motifs = glob("modisco_counts/trimmed_logos/*")
		File modisco_profile_h5 = "modisco_profile/modisco_results.h5"
		File modisco_counts_h5 = "modisco_counts/modisco_results.h5"
		
	
	}

	runtime {
		docker: 'vivekramalingam/tf-atlas:gcp-modisco_modiscolite'
		memory: 16 + "GB"
		cpu: number_of_cpus
		bootDiskSizeGb: 50
		disks: "local-disk 50 HDD"
  		maxRetries: 1
	}
}

workflow modisco {
	input {
		String experiment
		Array [File] shap
		Int? mem_gb=16
		Int? number_of_cpus=4
		Int? max_seqlets=25000        



	}




	call run_modisco {
		input:
			experiment = experiment,
			shap = shap,
			mem_gb = mem_gb,
			number_of_cpus = number_of_cpus,
			max_seqlets = max_seqlets
	}
	output {
		Array[File] modisco_profile = run_modisco.modisco_profile_motifs
		Array[File] modisco_counts = run_modisco.modisco_counts_motifs
		File modisco_profile_h5 = run_modisco.modisco_profile_h5
		File modisco_counts_h5 = run_modisco.modisco_counts_h5
		
	}
}
