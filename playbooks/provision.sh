#!/bin/bash

# Uses kubeadm to configure a new master node with flannel, metallb, 
# nginx LoadBalancer, and the Kubernetes Dashboard. This creates a new
# control plane and does not join an existing one.

USAGE="Usage: [create_first]"

set -xe

sleep 10
FQDN=$(hostname -A)
HOSTNAME=$(hostname -s)
DOMAIN_NAME=$(cut -d "." -f2 <<< $FQDN)
IP_INTERFACE=$(ip a | grep -Po 'ens[0-9]+' | head -n1)
VPN_IP=$(ip -f inet addr show $IP_INTERFACE  | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

create_first_node() {
  # Initialize kubelet
  kubeadm reset -f
  kubeadm init --apiserver-advertise-address $VPN_IP --apiserver-cert-extra-sans $FQDN --pod-network-cidr 10.244.0.0/16 --node-name $HOSTNAME --ignore-preflight-errors Swap --cri-socket unix:///var/run/containerd/containerd.sock --control-plane-endpoint $FQDN

  # Setup kube config
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  # Untaint master (necesarry to ensure metallb can run, as the API pod needs to be schedulable)
  kubectl taint nodes --all node-role.kubernetes.io/master- | true
  kubectl taint node $HOSTNAME node-role.kubernetes.io/control-plane:NoSchedule-

  # Set up cilium
  cilium install

  # Set up metallb (requires helm)
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
  rm get_helm.sh

  cat > addresspool.yaml <<EOL
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.244.0.0/16
... 
EOL

  helm repo add metallb https://metallb.github.io/metallb
  helm install --namespace metallb-system --create-namespace metallb metallb/metallb
  kubectl rollout status deployment metallb-controller -n metallb-system
  sleep 10
  kubectl apply -f addresspool.yaml

  # Set up nginx LoadBalancer
  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.loadBalancerIP=10.244.0.1

  # Set up the kube dashboard
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
}

# --- Options processing -------------------------------------------
if [ $# == 0 ] ; then
    echo $USAGE
    exit 1;
fi

case "$1" in
  "create_first")
    echo "Creating first master node"
    create_first_node
    ;;
esac
