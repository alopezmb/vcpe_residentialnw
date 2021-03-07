#!/bin/bash

echo ""
echo "[1/3] --Destroying Residental + (Server + Public) Network Scenarios..."

./bin/stop_vnx.sh --destroy

echo ""
echo "[2/3] --Deleting NS instances..."

./bin/offboarding.sh --delete-instance --all


echo ""
echo "[3/3] --Deleting AccessNet and ExtNet..."

sudo ovs-vsctl --if-exists del-br AccessNet
sudo ovs-vsctl --if-exists del-br ExtNet








