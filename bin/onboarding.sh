#!/bin/bash


OPTION_GIVEN="$1"

USAGE="
Usage:
    
onboarding --[OPTIONS]
    OPTIONS:
        -> upload-descriptors: uploads to OSM the VNF and NS descriptors found in the 'packages' directory.
        -> instantiate \e[4mns-name(s)\e[0m: instantiate the virtual residential router NS with the provided name.
        			   Several NS can be instanced simultaneously by leaving a blank space between their names. 
        			   e.g instantiate vcpe-1 vcpe-2 ...  
        -> help: shows this usage dialog.  
"


if [ "$OPTION_GIVEN" = "--upload-descriptors" ]; then
	
	echo "## Upload Descriptors ##"

	#First, the constituent VNFDs have to be created in order to create the corresponding NSD.
	#1. Create VNFDs
	echo ""
	echo "1. Uploading VNFDs..."
	#Number of rows of vnfds, min=1 which is the header.
	VNFD_ROWS=$(osm vnfd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)

	#If there is only 1 row, it means it is the column header, so there are no vnfs created.
	if [ "$VNFD_ROWS" -gt 1 ]; then
		echo "[*] VNFDs already loaded."
	else     
	    echo "[*] VNFDs not loaded. Uploading to OSM..."
	    
	    for file in packages/*; do
	    	if [[ "$file" == *"vnf"* ]]; then
	    		echo "[*] Uploading vnfd: $line"
	    		osm vnfd-create "$file"
	    	fi
		done

		sleep 3
		VNFD_ROWS=$(osm vnfd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)

		if [ "$VNFD_ROWS" -gt 1 ]; then
			echo -e "[\xE2\x9C\x94] VNFDs have been successfully uploaded."
		else
	    	echo -e "[\xE2\x9C\x97] ERROR: problems encountered in VNFDs upload."
	    	exit 1
	    	fi
	fi


	#2. Create NSDs

	NSD_ROWS=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)

	echo ""
	echo "2. Uploading NSDs..."

	if [ "$NSD_ROWS" -gt 1 ]; then
		echo "[*] NSDs already loaded."
	else      
	    echo "[*] NSDs not loaded. Uploading to OSM..."
		 for file in packages/*; do
	    	if [[ "$file" == *"ns"* ]]; then
	    		echo "[*] Uploading nsd: $line"
	    		osm nsd-create "$file"
	    	fi
		done

		sleep 3
		NSD_ROWS=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)


		if [ "$NSD_ROWS" -gt 1 ]; then
			echo -e "[\xE2\x9C\x94] All NSDs have been successfully uploaded."
		else
	    	echo -e "[\xE2\x9C\x97] ERROR: problems encountered in NSD upload."
	    	exit 1
	    fi
	fi
	echo ""
	echo "[*] VNF and NS descriptor upload finished."
	echo "[*] The Virtualised Residential Router Network Service still needs to be instantiated."


elif [ "$OPTION_GIVEN" = "--instantiate" ]; then

	echo "## Network Service Instantiation ##"
	NSD_ROWS=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)

	echo ""
	echo "[*] Searching if the Network Service Descriptor (NSD) has been loaded..."


	if [ "$NSD_ROWS" -eq 2 ]; then
		
		NSD_NAME=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | awk 'NR==2')
		echo "[*] Network Service Descriptor $NSD_NAME found! Proceeding with network service instantiation:"


		NS_INSTANCENAME_COLUMNS=$(osm ns-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
		created_instances=()
		read -r -a instances_to_create <<< "${@:2}"

		echo ""

		for ns_instance_name in "${instances_to_create[@]}";
		do
			if [[ "$NS_INSTANCENAME_COLUMNS" == *"$ns_instance_name"* ]]; then

				echo "[!] WARNING: Network Service $ns_instance_name is already instantiated. No action will be taken."

			else

				echo "[*] Instantiating Network Service $ns_instance_name..."
				osm ns-create --ns_name "$ns_instance_name" --nsd_name "$NSD_NAME" --vim_account emu-vim
				created_instances+=("$ns_instance_name")
			fi
		done

		#Do ns status check if any at least one ns been created.
		if [ ! -z "$created_instances" ]; then
			#Wait to give network services time to be up and running and thus be able to check their status
			sleep 20
			#CHECK STATUS OF CREATED INSTANCES
			echo ""
			echo "[*] Checking status of instantiated network services..."

			for created_instance in "${created_instances[@]}";
			do
				INFO=$(osm ns-list | grep "$created_instance")
				STATUS_BROKEN=$(echo "$INFO" | grep BROKEN)
				STATUS_READY=$(echo "$INFO" | grep READY)

				if [[(! -z "$INFO") && (! -z "$STATUS_READY")]]; then
					echo -e "[\xE2\x9C\x94] $created_instance NS instance is READY!"

				elif [[(! -z "$INFO") && (! -z "$STATUS_BROKEN")]]; then
					echo -e "[\xE2\x9C\x97] ERROR: $created_instance NS instance status is BROKEN. Use 'osm ns-list' to check further information on the cause of this error."
					exit 1

				else
					echo "[*] INFO: other status not yet recognised by script."
				fi
			done
		fi
		echo ""
		echo "[*] Network Service (NS) instantiation process has finished."

	#NSD not found error
	else
		echo -e "[\xE2\x9C\x97] ERROR: no NSD (Network Service Descriptor) found. Upload the NSD by calling '--upload-descriptors' option.
		Then, run again '--instantiate' option to retry the NS instantiation process."
		exit 1
		
	fi

elif [ "$OPTION_GIVEN" = "--help" ]; then
	echo -e "$USAGE"
else
	echo "ERROR: option '$1' not recognised for onboarding script."
	echo -e "$USAGE"
	
fi
