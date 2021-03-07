#!/bin/bash

VCPE_NAME="$1"

VCLASS_VNF=$(sudo docker ps | grep vnf-img | grep "$VCPE_NAME" | awk 'NF>1{print $NF}')

sudo docker exec -it $VCLASS_VNF bash
