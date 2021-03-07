#!/bin/bash



read -r -a host_names <<< "${@:1}"
CONNECTION_ERROR=true

while [ "$CONNECTION_ERROR"=true ];
do
	for hname in "${host_names[@]}";
	do
		HOME_HOST="$hname"

		echo ""
		echo "[*] Host ${HOME_HOST}: Testing Connectivity..."

		HOST_NOT_VALID=$(sshpass -p 'xxxx' ssh root@"$HOME_HOST" uname)
		IS_BRG=$(echo "$HOME_HOST" | grep brg)

		if [  -z "$HOST_NOT_VALID" ];
		then 
			echo -e "[\xE2\x9C\x97] ERROR. Could not connect to $HOME_HOST."
			CONNECTION_ERROR=true
			break
		else
			echo -e "[\xE2\x9C\x94] SUCCESS: SSHing to $HOME_HOST was successful. Starting connectivity tests..."
		fi

		if [  ! -z "$IS_BRG" ];
		then
			echo "brg needs no further checks."
			exit 0
		fi

		echo ""
		echo "[1/4] Dynamically assigning 192.168.255.X IPv4 address to iface eth1..."
		sshpass -p 'xxxx' ssh root@"$HOME_HOST" dhclient
		sshpass -p 'xxxx' ssh root@"$HOME_HOST" dhclient -6

		echo ""
		echo "[2/4] Checking if IPv4 address has been correctly assigned to iface eth1... "


		DHCP_ASSIGNED_IPV4=$(sshpass -p 'xxxx' ssh root@"$HOME_HOST" ifconfig |  grep 192.168.255 | awk '{print $2}')

		if [ -z "$DHCP_ASSIGNED_IPV4" ];
		then 
			echo -e "[\xE2\x9C\x97] ERROR. No IPv4 address found."
			CONNECTION_ERROR=true
			break
		else
			echo -e "[\xE2\x9C\x94] SUCCESS: IPv4 address found for iface eth1: $DHCP_ASSIGNED_IPV4"
	
		fi

		echo ""
		echo "[3/4] Checking connectivity between $HOME_HOST and server s1 (10.2.2.2)"


		S1_PING_RESPONSE=$(sshpass -p 'xxxx' ssh root@"$HOME_HOST" ping -c 1 -W 4 10.2.2.2 | grep 'bytes from')

		if [ -z "$S1_PING_RESPONSE" ];
		then 
			echo -e "[\xE2\x9C\x97] ERROR. Host $HOME_HOST was unable to ping server S1 (10.2.2.2)."
			# we exit because in this case if host cannot ping, the xml vnx scenario is not the one that is failing.
			exit 1
		else
			echo -e "[\xE2\x9C\x94] SUCCESS: Connection successful betwen host $HOME_HOST and server s1!"
		fi

		sleep 2

		echo ""
		echo "[4/4] Checking connectivity and DNS resolution with external networks (www.google.es)."
		echo "Pinging... This make take a bit if DNS is not yet fully running"

		
		count=0

		while [ "$count" -le 1 ];
		do
			GOOGLE_PING_RESPONSE=$(sshpass -p 'xxxx' ssh root@$HOME_HOST ping -c 1 -W 5 www.google.es | grep 'bytes from')

			if [ -z "$GOOGLE_PING_RESPONSE" ];
			then 
				echo -e "Ping number $count failed. Retrying..."
				sleep 1
				count=$(( $count + 1 ))
			else
				echo -e "[\xE2\x9C\x94] SUCCESS: Connection successful!"
				break
			fi
		done

		if [ "$count" -gt 1 ];
		then 
			echo -e "[!] WARNING. Host $HOME_HOST was unable to ping external network by name (www.google.es)"
			CONNECTION_ERROR=true
			break
		fi
		
		# si todo va bien, pongo flag a false al final de cada iteracion de host names
		CONNECTION_ERROR=false
	done

	if [ "$CONNECTION_ERROR"=true ];
	then
		sudo vnx -f vnx/nfv3_home_lxc_ubuntu64.xml --destroy
		echo "Wait time to let the scenario gracefully shutdown..."
		sleep 10
		sudo vnx -f vnx/nfv3_home_lxc_ubuntu64.xml -t
		sleep 10
	fi
done