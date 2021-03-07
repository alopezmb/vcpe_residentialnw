#!/bin/bash

echo "[*] Initialising..."

echo "--"
echo "--[1/5] Creating AccessNet and ExtNet..."


sudo ovs-vsctl --if-exists del-br AccessNet
sudo ovs-vsctl --if-exists del-br ExtNet
sudo ovs-vsctl add-br AccessNet
sudo ovs-vsctl add-br ExtNet

echo "--"
echo "--[2/5] Starting Residental + (Server + Public) Network Scenarios..."

#for file in vnx/*; do
#	sudo vnx -f $file -t
#done
sudo vnx -f vnx/nfv3_home_lxc_ubuntu64.xml -t
sudo vnx -f vnx/nfv3_server_lxc_ubuntu64.xml -t

echo "--"
echo "--[3/5] Starting NS instances"

./bin/onboarding.sh --upload-descriptors
./bin/onboarding.sh --instantiate vcpe-1 vcpe-2
#vcpe-2

if [ "$?" -eq 1 ];
then
	echo "ERRORS in initialisation sequence. Deleting the scenario..."
	./end.sh
	sleep 5
	./init.sh
	exit 1
fi

echo "--"
echo "--[4/5] Configuring VCPE-1"

sleep 10
./bin/vcpe_start_mod.sh vcpe-1 10.255.0.1 10.255.0.2 192.168.255.1 10.2.3.1 -ipv6 fd3b:d9c5:9f73:bb6c::1 fd3b:d9c5:9f73:bb6c::2
if [ "$?" -eq 1 ];
then
    ./end.sh
    sleep 5
    ./init.sh
    exit 1
fi

echo "--"
echo "--[5/5] Configuring VCPE-2"

./bin/vcpe_start_mod.sh vcpe-2 10.255.0.3 10.255.0.4 192.168.255.1 10.2.3.2 -ipv6 fd3b:d9c5:9f73:bb6c::3 fd3b:d9c5:9f73:bb6c::4 
if [ "$?" -eq 1 ];
then
    ./end.sh
    sleep 5
    ./init.sh
    exit 1
fi

echo ""
echo "[SUCCESS] Scenario up and fully operational!"