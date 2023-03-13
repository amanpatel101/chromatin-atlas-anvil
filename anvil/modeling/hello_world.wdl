version 1.0

task run_hello_world {
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
		echo "Hello world"
		touch /cromwell_root/hello_world.txt

	}
	
	output {
		File hello_world = "hello_world.txt"
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

workflow hello_world {
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
	
	call run_hello_world {
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
		File hello_world = "hello_world.txt"
	}
}
