#!/usr/bin/env bash

set -o xtrace 

k8s_version=1.29.0
k8s_version_no_patch=1.29
ip_address=$(ip address show | perl -lane 'print if s/\s+inet ([\d\.]*)\/.*/$1/ and $_ != "127.0.0.1"')
public_ip=$(curl ifconfig.me && echo "")
node_name=$(hostname -s)

# install kubectl arm64 nodes
cd /tmp

curl -LO "https://dl.k8s.io/release/v$k8s_version/bin/linux/arm64/kubectl.sha256"
curl -LO "https://dl.k8s.io/release/v$k8s_version/bin/linux/arm64/kubectl"
if [ "$(echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check)" != "kubectl: OK" ]; then
    echo "ERR: mismatched sha256sum."
    exit
fi

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
if [ "$(kubectl version --client | perl -lane 'print if s/(Client Version:).*/$1/')" != "Client Version:" ]; then
    echo "ERR: kubectl not installed correctly"
    exit
fi

# install CRI-O (no arm packages for OL9?)
cat <<EOF | sudo tee /etc/yum.repos.d/oracle_linux_8.repo
[ol8_latest]
name=Oracle Linux 8 Latest OLCNE (AArch64)
baseurl=http://yum.oracle.com/repo/OracleLinux/OL8/developer/olcne/aarch64
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
EOF

# install kubeadm, kubectl, kubeadm
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

sudo dnf install -y dnf-plugins-core 
sudo dnf install -y oracle-olcne-release-el9.src
sudo dnf module enable cri-o:$k8s_version
sudo dnf install -y cri-o
sudo systemctl daemon-reload
sudo systemctl enable crio
sudo systemctl start crio

# setup cluster 
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

# disable swap
sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

cat << EOF | sudo tee /etc/default/kubelet 
KUBELET_EXTRA_ARGS=--node-ip=$ip_address
EOF

sudo kubeadm init --control-plane-endpoint=$public_ip  --apiserver-cert-extra-sans=$public_ip  --node-name $node_name --ignore-preflight-errors Swap

