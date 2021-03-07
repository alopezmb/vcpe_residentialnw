#!/bin/bash

USAGE="
Usage:
    
vcpe_start <vcpe_name> <vnf_tunnel_ip> <home_tunnel_ip> <vcpe_private_ip> <vcpe_public_ip> 
		   -ipv6 <vnf_tunnel_ipv6> <home_tunnel_ipv6>
		 
    being:
        <vcpe_name>: the name of the network service instance in OSM 
        <vnf_tunnel_ip>: the ip address for the vnf side of the tunnel
        <home_tunnel_ip>: the ip address for the home side of the tunnel
        <vcpe_private_ip>: the private ip address for the vcpe
        <vcpe_public_ip>: the public ip address for the vcpe (10.2.2.0/24)

       ipv6 support:
         <vnf_tunnel_ipv6>: the ipv6 address for the vnf side of the tunnel
         <home_tunnel_ipv6>: the ipv6 address for the home side of the tunnel

"

if [[ $# -ne 8 ]]; then
        echo ""       
    echo "ERROR: incorrect number of parameters"
    echo "$USAGE"
    exit 1
fi



VCPE_NAME="$1"
VNFTUNIP="$2"
HOMETUNIP="$3"
VCPEPRIVIP="$4"
VCPEPUBIP="$5"

HOMENET_NUMBER=$(echo "$VCPE_NAME" | sed 's/[^0-9]*//g')
HX1="h${HOMENET_NUMBER}1"
HX2="h${HOMENET_NUMBER}2"
BRGX="brg${HOMENET_NUMBER}"

#IPV6 Parameters
VNF_TUNNEL_IPV6="$7"
HOME_TUNNEL_IPV6="$8"
VCPE_EXTERNAL_IPV6="fd3b:d9c5:9f73:bb6d::${HOMENET_NUMBER}"

VCPE_HOMENET_IPV6_PREFIX_TEMPLATE="fd3b:d9c5:9f73:bb6X::"

VCPE_HOMENET_IPV6_PREFIX=$(echo "$VCPE_HOMENET_IPV6_PREFIX_TEMPLATE" | tr X "$HOMENET_NUMBER")

echo "$VCPE_HOMENET_IPV6_PREFIX"

DHCPV6_START="${VCPE_HOMENET_IPV6_PREFIX}255:9"
DHCPV6_END="${VCPE_HOMENET_IPV6_PREFIX}255:199"


VNF1=$(sudo docker ps | grep vnf-img | grep "$VCPE_NAME" | awk 'NF>1{print $NF}')
VNF2=$(sudo docker ps | grep vnf-vyos | grep "$VCPE_NAME" | awk 'NF>1{print $NF}')

ETH11=$(sudo docker exec -it $VNF1 ifconfig | grep eth1 | awk '{print $1}' | sed 's/.$//')
ETH21=$(sudo docker exec -it $VNF2 ifconfig | grep eth1 | awk '{print $1}' | sed 's/.$//')
IP11=$(sudo docker exec -it $VNF1 hostname -I | awk '{printf "%s\n", $1}{print $2}' | grep 192.168.100)
IP21=$(sudo docker exec -it $VNF2 hostname -I | awk '{printf "%s\n", $1}{print $2}' | grep 192.168.100)
IP11_V6="fd3b:d9c5:9f73:bb6a::100:3"
IP21_V6="fd3b:d9c5:9f73:bb6a::100:4"



##################### VNFs Settings #####################
## 0. Iniciar el Servicio OpenVirtualSwitch VNF1:
echo "--"
echo "[1/12] OVS Starting..."
sudo docker exec -it $VNF1 /usr/share/openvswitch/scripts/ovs-ctl start

echo "--"
echo "[2/12] Connecting vCPE service with AccessNet and ExtNet..."

sudo ovs-docker add-port AccessNet veth0 $VNF1
sudo ovs-docker add-port ExtNet eth2 $VNF2

sudo docker exec -it $VNF1 sudo sysctl -p
sudo docker exec -it $VNF2 sudo sysctl -p

echo "--"
echo "[3/12] Configuring Bridge in vClass..."

## 1. En VNF:vclass agregar un bridge y asociar interfaces.
sudo docker exec -it $VNF1 ip -6 address add "${IP11_V6}/64" dev $ETH11

sudo docker exec -it $VNF1 ovs-vsctl add-br br0
sudo docker exec -it $VNF1 ifconfig veth0 $VNFTUNIP/24
sudo docker exec -it $VNF1 ifconfig veth0 add "${VNF_TUNNEL_IPV6}"/64
sudo docker exec -it $VNF1 ip link add vxlan1 type vxlan id 0 remote $HOMETUNIP dstport 4789 dev veth0
sudo docker exec -it $VNF1 ip -6 link add vxlan1 type vxlan id 0 remote "${HOME_TUNNEL_IPV6}" dstport 4789 dev veth0
sudo docker exec -it $VNF1 ip link add vxlan2 type vxlan id 1 remote $IP21 dstport 8472 dev $ETH11
sudo docker exec -it $VNF1 ip -6 link add vxlan2 type vxlan id 1 remote "${IP21_V6}" dstport 8472 dev $ETH11
sudo docker exec -it $VNF1 ovs-vsctl add-port br0 vxlan1
sudo docker exec -it $VNF1 ovs-vsctl add-port br0 vxlan2
sudo docker exec -it $VNF1 ifconfig vxlan1 up
sudo docker exec -it $VNF1 ifconfig vxlan2 up



echo "--"
echo "[4/12] Configuring vxlan tunnel"

## 2. En VNF:vcpe configurar túnel vxlan entre vclass y vcpe
sudo docker exec -it $VNF2 /bin/bash -c "
source /opt/vyatta/etc/functions/script-template
configure
ip -6 address add ${IP21_V6}/64 dev $ETH21
set interfaces vxlan vxlan1 address ${VCPE_HOMENET_IPV6_PREFIX}255:1/64
set interfaces vxlan vxlan1 address ${VCPEPRIVIP}/24
set interfaces vxlan vxlan1 remote ${IP11}
set interfaces vxlan vxlan1 vni 1
set interfaces vxlan vxlan1 port 8472
set interfaces vxlan vxlan1 mtu 1400
commit
save
exit
"

sleep 2
echo "--"
echo "[5/12] Routing configuration"

## 3. En VNF:vcpe configurar interfaz de salida y ruta por defecto hacia r1.
# usamos ip route del con la ruta por defecto porque desde vyos no deja eliminarla
sudo docker exec -it $VNF2 /bin/bash -c "
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth2 address '${VCPEPUBIP}/24'
set interfaces ethernet eth2 address '${VCPE_EXTERNAL_IPV6}/64'
ip route del 0.0.0.0/0 via 172.17.0.1
set protocols static route 0.0.0.0/0 next-hop 10.2.3.254
set protocols static route6 ::/0 next-hop fd3b:d9c5:9f73:bb6d::254
commit
save
exit
"

sleep 2

echo "--"
echo "[6/12] Router Advertisement Configuration"

## Configurar Router Advertisements IPv6
sudo docker exec -it $VNF2 /bin/bash -c "
source /opt/vyatta/etc/functions/script-template
configure
set service router-advert interface vxlan1
set service router-advert interface vxlan1 prefix ${VCPE_HOMENET_IPV6_PREFIX}/64
set service router-advert interface vxlan1 prefix ${VCPE_HOMENET_IPV6_PREFIX}/64 no-autonomous-flag
set service router-advert interface vxlan1 default-preference high
set service router-advert interface vxlan1 managed-flag
commit
save
exit
"
#set service router-advert interface vxlan1 other-config-flag
sleep 2

echo "--"
echo "[6/12] DHCP/DHCPv6 and DNS configuration"

## 4. En VNF:vcpe configurar dhcp y dns
sudo docker exec -it $VNF2 /bin/bash -c "
source /opt/vyatta/etc/functions/script-template
configure
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 default-router '${VCPEPRIVIP}'
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 dns-server '${VCPEPRIVIP}'
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 domain-name 'vyos.net'
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 lease '86400'
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 range 0 start 192.168.255.9
set service dhcp-server shared-network-name LAN subnet 192.168.255.0/24 range 0 stop '192.168.255.254'
set service dns forwarding cache-size '0'
set service dns forwarding listen-address '${VCPEPRIVIP}'
set service dns forwarding allow-from '192.168.255.0/24'
set service dhcpv6-server shared-network-name 'LAN' subnet ${VCPE_HOMENET_IPV6_PREFIX}/64 address-range start ${DHCPV6_START} stop ${DHCPV6_END}
set service dhcpv6-server shared-network-name 'LAN' subnet ${VCPE_HOMENET_IPV6_PREFIX}/64 name-server '${VCPE_HOMENET_IPV6_PREFIX}255:1'
set service dns forwarding listen-address '${VCPE_HOMENET_IPV6_PREFIX}255:1'
set service dns forwarding allow-from ${VCPE_HOMENET_IPV6_PREFIX}/64
commit
save
exit
"

sleep 2

echo "--"
echo "[7/12] NAT configuration"

## 5. En VNF:vcpe configurar NAT
sudo docker exec -it $VNF2 /bin/bash -c "
source /opt/vyatta/etc/functions/script-template
configure
set nat source rule 100 outbound-interface 'eth2'
set nat source rule 100 source address '192.168.255.0/24'
set nat source rule 100 translation address masquerade
commit
save
exit
"

sleep 5

echo "--"
echo "[8/12] Configuring OF Switch in vClass.."

sudo docker exec -it $VNF1 ovs-vsctl set bridge br0 protocols=OpenFlow10,OpenFlow12,OpenFlow13
sudo docker exec -it $VNF1 ovs-vsctl set-fail-mode br0 secure
sudo docker exec -it $VNF1 ovs-vsctl set bridge br0 other-config:datapath-id=0000000000000001
sudo docker exec -it $VNF1 ovs-vsctl set-controller br0 tcp:127.0.0.1:6633
sudo docker exec -it $VNF1 ovs-vsctl set-manager ptcp:6632
sleep 5

echo ""
echo "[9/12] Ryu Controller and Switch to establish connection..."

sudo docker exec -d $VNF1 ryu-manager ryu.app.rest_qos ryu.app.rest_conf_switch ./qos_simple_switch_13.py
echo "Wait for connection..."
sleep 10

echo "--"
echo "[10/12] Connectivity Test"


./bin/connectivity_test.sh "$HX1" "$HX2" "$BRGX"

HX1_ASSIGNED_IPV4=$(sshpass -p 'xxxx' ssh root@"$HX1" ifconfig |  grep 192.168.255 | awk '{print $2}')
HX2_ASSIGNED_IPV4=$(sshpass -p 'xxxx' ssh root@"$HX2" ifconfig |  grep 192.168.255 | awk '{print $2}')

HX1_ASSIGNED_IPV6=$(sshpass -p 'xxxx' ssh root@"$HX1" ifconfig |  grep "$VCPE_HOMENET_IPV6_PREFIX" | awk '{print $2}')
HX2_ASSIGNED_IPV6=$(sshpass -p 'xxxx' ssh root@"$HX2" ifconfig |  grep "$VCPE_HOMENET_IPV6_PREFIX" | awk '{print $2}')


if [ "$?" -eq 1 ];
then
    echo "ERRORS in connectivity test sequence."
    exit 1
fi

echo "--"
echo "[11/12] QoS: Configuring Download Restrictions for Residential Network $HOMENET_NUMBER ..."

sudo docker exec -it "$VNF1" curl -X PUT -d '"tcp:127.0.0.1:6632"' http://127.0.0.1:8080/v1.0/conf/switches/0000000000000001/ovsdb_addr
sudo docker exec -it "$VNF1" curl -X POST -d '{"port_name": "vxlan1", "type": "linux-htb", "max_rate": "12000000", "queues": [{"min_rate": "8000000"}, {"max_rate": "4000000"}]}' http://127.0.0.1:8080/qos/queue/0000000000000001
sudo docker exec -it "$VNF1" curl -X POST -d '{"match": {"nw_dst": "'$HX1_ASSIGNED_IPV4'"}, "actions":{"queue": "0"}}' http://127.0.0.1:8080/qos/rules/0000000000000001
sudo docker exec -it "$VNF1" curl -X POST -d '{"match": {"nw_dst": "'$HX2_ASSIGNED_IPV4'"}, "actions":{"queue": "1"}}' http://127.0.0.1:8080/qos/rules/0000000000000001
sudo docker exec -it "$VNF1" curl -X POST -d '{"match": {"ipv6_dst": "'$HX1_ASSIGNED_IPV6'"}, "actions":{"queue": "0"}}' http://127.0.0.1:8080/qos/rules/0000000000000001
sudo docker exec -it "$VNF1" curl -X POST -d '{"match": {"ipv6_dst": "'$HX2_ASSIGNED_IPV6'"}, "actions":{"queue": "1"}}' http://127.0.0.1:8080/qos/rules/0000000000000001


echo "--"
echo "[12/12] QoS: Configuring Upload Restrictions for Residential Network $HOMENET_NUMBER ..."

sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X PUT -d '\"tcp:'$HOMETUNIP':6632\"' http://'$VNFTUNIP':8080/v1.0/conf/switches/0000000000000002/ovsdb_addr"
sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X POST -d '{\"port_name\": \"vxlan1\", \"type\": \"linux-htb\", \"max_rate\": \"6000000\", \"queues\": [{\"min_rate\": \"2000000\"}, {\"max_rate\": \"2000000\"}]}' http://'$VNFTUNIP':8080/qos/queue/0000000000000002"
sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X POST -d '{\"match\": {\"nw_src\": \"'$HX1_ASSIGNED_IPV4'\"}, \"actions\":{\"queue\": \"0\"}}' http://'$VNFTUNIP':8080/qos/rules/0000000000000002"
sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X POST -d '{\"match\": {\"nw_src\": \"'$HX2_ASSIGNED_IPV4'\"}, \"actions\":{\"queue\": \"1\"}}' http://'$VNFTUNIP':8080/qos/rules/0000000000000002"
sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X POST -d '{\"match\": {\"ipv6_src\": \"'$HX1_ASSIGNED_IPV6'\"}, \"actions\":{\"queue\": \"0\"}}' http://'$VNFTUNIP':8080/qos/rules/0000000000000002"
sshpass -p 'xxxx' ssh root@"$BRGX" "curl -X POST -d '{\"match\": {\"ipv6_src\": \"'$HX2_ASSIGNED_IPV6'\"}, \"actions\":{\"queue\": \"1\"}}' http://'$VNFTUNIP':8080/qos/rules/0000000000000002"

echo ""
echo "-- All set!"