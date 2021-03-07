#!/bin/bash

#change terminal name
#echo -ne "\033]0;vCPE-VYOS\007"

VCPE_NAME="$1"

VYOS_VNF=$(sudo docker ps | grep vnf-vyos | grep "$VCPE_NAME" | awk 'NF>1{print $NF}')

sudo docker exec -it $VYOS_VNF bash -c 'su - vyos'