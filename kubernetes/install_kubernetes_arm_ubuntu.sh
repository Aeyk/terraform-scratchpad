#!/usr/bin/env bash

set -o xtrace 

k8s_version=1.29.0
k8s_version_no_patch=1.29
ip_address=$(ip address show | perl -lane 'print if s/\s+inet ([\d\.]*)\/.*/$1/ and $_ != "127.0.0.1"')
public_ip=$(curl ifconfig.me && echo "")
node_name=$(hostname -s)

# install kubectl arm64 nodes
# cd /tmp
# curl -LO "https://dl.k8s.io/release/v$k8s_version/bin/linux/arm64/kubectl.sha256"
# curl -LO "https://dl.k8s.io/release/v$k8s_version/bin/linux/arm64/kubectl"
# if [ "$(echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check)" != "kubectl: OK" ]; then
#     echo "ERR: mismatched sha256sum."
#     exit
# fi
# 
# sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
# if [ "$(kubectl version --client | perl -lane 'print if s/(Client Version:).*/$1/')" != "Client Version:" ]; then
#     echo "ERR: kubectl not installed correctly"
#     exit
# fi

sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo mkdir -p /etc/apt/keyrings/

curl -fsSL https://pkgs.k8s.io/core:/stable:/v$k8s_version_no_patch/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$k8s_version_no_patch/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubectl

echo 'source <(kubectl completion bash)' >>~/.bashrc

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

curl -fsSL https://pkgs.k8s.io/core:/stable:/v$k8s_version_no_patch/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$k8s_version_no_patch/deb/ /" |
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# CRI-O doesnt work for me, no started containers
# PROJECT_PATH=prerelease:/main
# curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/deb/Release.key |
#     sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
# echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/$PROJECT_PATH/deb/ /" |
#     sudo tee /etc/apt/sources.list.d/cri-o.list
# sudo apt-get update && sudo apt install -y cri-o
# sudo systemctl start crio.service

sudo apt install containerd runc kubernetes-cni

sudo systemctl daemon-reload
sudo systemctl enable --now containerd

# disable swap
sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

sudo kubeadm init --ignore-preflight-errors=NumCPU --control-plane-endpoint=$ip_address -v=5 --pod-network-cidr=10.244.0.0/16

# enable kube
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# flannel networking overlay
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml


# cni network plugins
sudo mkdir -p /opt/cni/bin
sudo curl -O -L https://github.com/containernetworking/plugins/releases/download/v1.2.0/cni-plugins-linux-amd64-v1.2.0.tgz
sudo tar -C /opt/cni/bin -xzf cni-plugins-linux-amd64-v1.2.0.tgz


