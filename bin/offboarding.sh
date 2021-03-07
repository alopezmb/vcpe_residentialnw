#!/bin/bash

## OJO!! FALTA quitar las conexiones a los puertos de ExtNet y accessnet

### AUX Functions definition ###
delete_instance () {

	read -r -a instances_to_delete <<< "${@:1}"
	local NS_COLUMN_INITIAL=$(osm ns-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
	local NS_ROWS=$(echo "$NS_COLUMN_INITIAL" | wc -l)

	if [ "$NS_ROWS" -eq 1 ]; then
		echo "[*] No Network Service instances are running."

	else

		local deleted_instances=()
		local error_count=0

		for ns_instance_name in "${instances_to_delete[@]}";
		do
			if [[ "$NS_COLUMN_INITIAL" = *"$ns_instance_name"* ]]; then

				echo "[*] Preparing to delete $ns_instance_name."
				
				VCLASS_VNF=$(sudo docker ps | grep vnf-img | grep "$ns_instance_name" | awk 'NF>1{print $NF}')
				VYOS_VNF=$(sudo docker ps | grep vnf-vyos | grep "$ns_instance_name"  | awk 'NF>1{print $NF}')
				sudo ovs-docker del-port AccessNet veth0 $VCLASS_VNF
				sudo ovs-docker del-port ExtNet eth2 $VYOS_VNF

				osm ns-delete "$ns_instance_name"
				deleted_instances+=("$ns_instance_name")
				
			else
				echo -e "[\xE2\x9C\x97] ERROR: NS instance $ns_instance_name not found."
				error_count=$((error_count+1))	
			fi
		done

		#if all provided instances do not exist, exit immediately, else continue
		if [ "$error_count" -eq "${#instances_to_delete[@]}" ];
		then
			exit 1

		#checks that the specified network service instances have been successfully deleted.
		else
			sleep 10

			local NS_COLUMN_FINAL=$(osm ns-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')

			for ns_instance_name in "${deleted_instances[@]}";
			do
				if [[ "$NS_COLUMN_FINAL" != *"$ns_instance_name"* ]]; then
					echo -e "[\xE2\x9C\x94] NS $ns_instance_name successfully deleted."
				else
					echo -e "[\xE2\x9C\x97] ERROR: NS $ns_instance_name could not be deleted."
				fi	
			done
			#not entirely correct for multiple instances, will need to create a loop and get names and delete
			
		fi
	fi
}




OPTION_GIVEN="$1"

USAGE="
Usage:
    
offboarding --[OPTIONS]
    OPTIONS:
        -> --reset: Deletes all ns instances and descriptors.
        -> --delete-instance:  
        			-> --all: deletes all network service instances
        			-> \e[4mns-name(s)\e[0m: deletes the specified network services.
        			   e.g. offboarding --delete-instance vcpe-1 vcpe-2 ...
        -> help: shows this usage dialog.  
"


### Main code ###

if [ "$OPTION_GIVEN" = "--reset" ]; then
	echo "## RESET: Delete all instantiated NS and descriptors ##"

	#1. Delete network service instances
	echo ""
	echo "1. Deleting NS instances..."

	# delete_instance takes as input an array, so let's prepare an array of all instances to delete
	NS_COLUMN=$(osm ns-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
	IFS=$'\n' read -d '\n' -r -a all_instances <<< "$NS_COLUMN"
	delete_instance "${all_instances[@]:1}"

	#Now, the corresponding NSD has to be deleted in order to be able to delete the VNFDs.
	#2. Delete NSDs
	echo ""
	echo "2. Checking for NSDs to delete..."

	NSD_COLUMN=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
	NSD_ROWS=$(echo "$NSD_COLUMN" | wc -l)

	if [ "$NSD_ROWS" -eq 1 ]; then
		echo "[*] No NSDs to delete."
	else
		while IFS= read -r line
		do 
			if [[("$line" != "nsd") && (! -z "$line")]]; then
				echo "[*]deleting nsd: $line"
				osm nsd-delete "$line"
			fi
		done < <(printf '%s\n' "$NSD_COLUMN")

		sleep 3
		NSD_ROWS=$(osm nsd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)


		if [ "$NSD_ROWS" -eq 1 ]; then
			echo -e "\xE2\x9C\x94 All NSDs have been removed successfully."
		else
	    	echo -e "\xE2\x9C\x97 ERROR: problems encountered while deleting NSDs."
	    	exit 1
	    fi
	fi

	#Finally, VNFDs can be deleted.
	#3. Delete VNFDs

	echo ""
	echo "3. Checking for VNFDs to delete..."

	VNFD_COLUMN=$(osm vnfd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
	VNF_ROWS=$(echo "$VNFD_COLUMN" | wc -l)

	if [ "$VNF_ROWS" -eq 1 ]; then
		echo "[*] Nothing to delete."
	else
		while IFS= read -r line
		do 
			if [[("$line" != "nfpkg") && (! -z "$line")]]; then
				echo "[*]deleting VNFD: $line"
				osm vnfd-delete "$line"
				fi
		done < <(printf '%s\n' "$VNFD_COLUMN")

		sleep 3
		VNF_ROWS=$(osm vnfd-list | awk -F "|" '{print $2}' | awk 'NF {print $1}' | wc -l)


		if [ "$VNF_ROWS" -eq 1 ]; then
			echo -e "[\xE2\x9C\x94] All VNFDs have been removed successfully."
		else
	    	echo -e "[\xE2\x9C\x97] ERROR: problems encountered while deleting VNFDs."
	    	exit 1
	    fi
	fi


elif [ "$OPTION_GIVEN" = "--delete-instance" ]; then
	echo "## Delete NS instances ##"

	if [ "$2" = "--all" ]; then
		echo ""
		echo "[*] Deleting ALL NS instances."
		
		NS_COLUMN=$(osm ns-list | awk -F "|" '{print $2}' | awk 'NF {print $1}')
		IFS=$'\n' read -d '\n' -r -a all_instances <<< "$NS_COLUMN"
		delete_instance "${all_instances[@]:1}"

	elif [[ ("$2" != "--all") && (! -z "$2") ]]; then
		echo ""
		echo "[*] Deleting selected NS instances..."

		read -r -a selected_instances <<< "${@:2}"
		delete_instance "${selected_instances[@]}"

	else
		echo "[\xE2\x9C\x97] ERROR: bad usage for '--delete-instance' option."
	fi

elif [ "$OPTION_GIVEN" = "--help" ]; then
	echo -e "$USAGE"
else
	echo "ERROR: option '$1' not recognised for onboarding script."
	echo -e "$USAGE"
	
fi




