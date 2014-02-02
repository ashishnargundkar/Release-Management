#!/usr/bin/env bash

source $HOME/.futuregrid/novarc
module load novaclient

function Usage() {
cat <<-ENDOFMESSAGE
options:
  -m Operation mode 
    1 -- Create XMPP Instance and configuration in FutureGrid
    2 -- Create VM and LXC isntances with given number 
    3 -- Copy executables to each instances and run 
    4 -- Stop depolyed instances
  -n Number of Nodes | Specify the number of node numer to configure
  -i IP address list
  -l lxc instance number 
  -p VPN Mode "SVPN" or "GVPN"

Examples:
  Create and configure XMPP instance with 2000 nodes
    ./social_graph.sh -m 1 -n 2000
  Create VM and LXC instance with given number 
    ./social_graph.sh -m 2 -v 5 -l 50
    Create 5 VMs and each VM contains 50 LXC isntances. All instances name 
    starts with prefix "IPOP" 
  Copy executables to each instances and run
    ./social_graph.sh -m 3 -i "10.35.23.165,10.35.23.178" -l 50 -p "SVPN"
    Each VM instance with IP address 10.35.23.165 and 10.35.23.178 contain
    50 LXC instances each. Don't put space between IP address.
    Before run, place ipop-tincan-x86_64, either of svpn/gvpn_controller.py, 
    config.json files at your working directory. These must have exactly the
    same file name. config.json file should have proper XMPP, STUN, TURN 
    configuration. But, xmpp_username, xmpp_password(for SocialVPN) or 
    IP address (GroupVPN) will be assigned automatically.
  Stop depolyed instances
    ./social_graph.sh -m 4 -i "10.35.23.165,10.35.23.178" -l 50 
     
  
ENDOFMESSAGE
exit 1
}

function xmpp {
NODES=$1
echo "Creating XMPP Server (Instance name \"XMPP\")"
ID=`nova boot --flavor m1.small --image "futuregrid/ubuntu-13.10" --key_name $USER-key XMPP | awk '{if (match($0,/'" id "'/)){print $4}}'`
echo "Created instance ID is $ID"
sleep 60
XMPP_IP=`nova list | grep "$ID" | awk -F'[=|]' '{print $6}' | tr -d ' '`
echo "XMPP Private IP Address is $XMPP_IP"
nova list

#Remove registered key as known_hosts to avoid warning message
sed -i "/$XMPP_IP/d" $HOME/.ssh/known_hosts

#If the host name is not specified in /etc/hosts, ejabberdctl intermittently cannot interface with ejabberd
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sudo sed -i \"2i $XMPP_IP xmpp\" /etc/hosts"

ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sudo apt-get update"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sudo apt-get -y install ejabberd unzip"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "wget -q -O ejabberd.cfg http://goo.gl/iObOjl"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sudo cp ejabberd.cfg /etc/ejabberd/"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sudo service ejabberd restart"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "wget https://pypi.python.org/packages/source/n/networkx/networkx-1.8.1.tar.gz#md5=b4a9e68ecd1b0164446ee432d2e20bd0"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "tar xzvf networkx-1.8.1.tar.gz 1> /dev/null"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "cp -r networkx-1.8.1/networkx ." 
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "wget -q http://current.cs.ucsb.edu/socialmodels/code/fittingCode.zip"  
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "unzip fittingCode.zip 1> /dev/null" 
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "cp fittingCode/socialModels.py ."
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "wget -q https://github.com/ipop-project/ipop-scripts/raw/master/synthesis_graph.py" 
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "chmod +x synthesis_graph.py"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "sed -i \"s/2000/$NODES/g\" synthesis_graph.py"
ssh -l ubuntu $XMPP_IP -i $HOME/.ssh/$USER-key "./synthesis_graph.py"
}

function deploy_lxc {

VM_IP=$0
LXC_COUNT=$1

echo "deploying $LXC_COUNT lxc instances at $VM_IP "
ssh -l ubuntu $VM_IP -i $HOME/.ssh/$USER-key "sudo apt-get update"
ssh -l ubuntu $VM_IP -i $HOME/.ssh/$USER-key "sudo apt-get -y lxc"
ssh -l ubuntu $VM_IP -i $HOME/.ssh/$USER-key "wget http://github.com/ipop-project/ipop-scripts/raw/master/gvpn_lxc.sh"
ssh -l ubuntu $VM_IP -i $HOME/.ssh/$USER-key "chmod +x gvpn_lxc.sh"
ssh -l ubuntu $VM_IP -i $HOME/.ssh/$USER-key "sudo ./gvpn_lxc.sh -m 1 -p IPOP -i $LXC_COUNT"

}
export -f deploy_lxc

function deploy_vm {

VM_COUNT=$1
LXC_COUNT=$2

for ((i=0; i<$VM_COUNT; i++))
do
  echo "Creating IPOP VM (Instance name prefix is \"IPOP\" such as \"IPOP0\", \"IPOP1\", \"IPOP2\", ...)" 1>&2
  ID=`nova boot --flavor m1.medium --image "futuregrid/ubuntu-13.10" --key_name $USER-key IPOP$i | awk '{if (match($0,/'" id "'/)){print $4}}'`
  echo "Created instance (IPOP$i, Instance ID is $ID)" 1>&2
  sleep 60
  VM_IP=`nova list | grep "$ID" | awk -F'[=|]' '{print $6}' | tr -d ' '`
  echo "IP Address is $VM_IP" 1>&2
  nova list 1>&2
  sed -i "/$VM_IP/d" $HOME/.ssh/known_hosts
  printf "%s\0%s\0" "$VM_IP" "$LXC_COUNT"
done | xargs -0 -n 2 -P $VM_COUNT bash -c 'deploy_lxc "$@"'

wait
}

function copy_and_run {

IP_LIST=$1
LXC_COUNT=$2
VPN_MODE=$3

echo "copy and run $IP_LIST $LXC_COUNT $VPN_MODE"

IP_ARRAY=(${IP_LIST//,/ })
for i in "${!IP_ARRAY[@]}"
do
  scp -i $HOME/.ssh/kyuhojeong-key ipop-tincan-x86_64 ubuntu@${IP_ARRAY[$i]}:
  scp -i $HOME/.ssh/kyuhojeong-key config.json ubuntu@${IP_ARRAY[$i]}:
  if [ "$VPN_MODE" == "GVPN" ] 
  then 
    scp -i $HOME/.ssh/kyuhojeong-key gvpn_controller.py ubuntu@${IP_ARRAY[$i]}:
    ssh -l ubuntu ${IP_ARRAY[$i]} -i $HOME/.ssh/$USER-key "./gvpn_lxc.sh -m 2 -p IPOP -i $LXC_COUNT -a 172.16.$i.1"
  else 
    scp -i $HOME/.ssh/kyuhojeong-key svpn_controller.py ubuntu@${IP_ARRAY[$i]}:
    ssh -l ubuntu ${IP_ARRAY[$i]} -i $HOME/.ssh/$USER-key "./gvpn_lxc.sh -m 3 -p IPOP -i $LXC_COUNT -a $(($i*$LXC_COUNT))"
  fi
done

}

function stop_ {

IP_LIST=$1
LXC_COUNT=$2

echo "stop instances $IP_LIST $LXC_COUNT"

IP_ARRAY=(${IP_LIST//,/ })
for i in "${!IP_ARRAY[@]}"
do
  ssh -l ubuntu ${IP_ARRAY[$i]} -i $HOME/.ssh/$USER-key "./gvpn_lxc.sh -m 4 -p IPOP -i $LXC_COUNT"
done
}

TEMP=`getopt -o m:n:v:l:i:p: -- "$@"`
eval set -- "$TEMP"
while true 
do
  case "$1" in
    -m) MODE=$2; shift 2;;
    -n) NODES=$2; shift 2;;
    -v) VM_COUNT=$2; shift 2;;
    -l) LXC_COUNT=$2; shift 2;;
    -i) IP_LIST=$2; shift 2;;
    -p) VPN_MODE=$2; shift 2;;
    --) shift; break ;;
    *) Usage; exit 1;;
  esac
done

case $MODE in
  1) xmpp $NODES; exit 1;;
  2) deploy_vm $VM_COUNT $LXC_COUNT; exit 1;;
  3) copy_and_run $IP_LIST $LXC_COUNT $VPN_MODE; exit 1;; 
  4) stop_ $IP_LIST $LXC_COUNT; exit 1;;
  *) echo "Unknown operation mode"; Usage; exit 1;;
esac
