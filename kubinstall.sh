#!/bin/bash
echo "Disabling swap...."
sudo swapoff -a
sudo sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
echo "Installing necessary dependencies...."
sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y
echo "Setting up hostname...."
sudo hostnamectl set-hostname "k8s-master"
PUBLIC_IP_ADDRESS=`hostname -I|cut -d" " -f 1`
sudo echo "${PUBLIC_IP_ADDRESS}  k8s-master" >> /etc/hosts
echo "Removing existing Docker Installation...."
sudo apt-get purge aufs-tools docker-ce docker-ce-cli containerd.io pigz cgroupfs-mount -y
sudo apt-get purge kubeadm kubernetes-cni -y
sudo rm -rf /etc/kubernetes
sudo rm -rf $HOME/.kube/config
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/docker
sudo rm -rf /opt/containerd
sudo apt autoremove -y

echo "Installing Docker...."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
### Add Docker apt repository.
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

## Install Docker CE.
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io -y

# Setup daemon.

sudo mkdir -p /etc/systemd/system/docker.service.d

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
# Restart docker.
sudo usermod -aG docker $USER
sudo systemctl daemon-reload
sudo systemctl restart docker
echo "Disabling Swap..."
echo "Setting up Kubernetes Package Repository..."
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
sudo apt-get -f install
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
echo "Installing Kubernetes..."
sudo apt-get --assume-yes install kubeadm
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
sudo sleep 10
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "Installing Flannel..."
sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
echo "Kubernetes Installation finished..."
echo "Waiting 30 seconds for the cluster to go online..."
sudo sleep 30
sudo export KUBECONFIG=$HOME/.kube/config
echo "Testing Kubernetes namespaces... "
kubectl get pods --all-namespaces
echo "Testing Kubernetes nodes... "
kubectl get nodes
sudo sleep 30
kubectl taint node k8s-master node-role.kubernetes.io/master:NoSchedule-
echo "Installing Kubernetes nginx ingress controller v1.1.1"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/cloud/deploy.yaml
echo "Configuring Ingress"
kubectl apply -f https://raw.githubusercontent.com/JasonPulse/kubernetesDashboard/master/IngressSettings/ingress-ConfigMap.yaml
kubectl apply -f https://raw.githubusercontent.com/JasonPulse/kubernetesDashboard/master/IngressSettings/custom-snippets.configmap.yaml
sudo sleep 10
sudo curl https://raw.githubusercontent.com/JasonPulse/kubernetesDashboard/master/IngressSettings/ingress-service.yaml > ingress-service.yaml
sudo sed -i 's/172.25.15.74/${PUBLIC_IP_ADDRESS}/g' ingress-service.yaml
kubectl patch service -n ingress-nginx ingress-nginx-controller --patch-file ingress-service.yaml
echo "Installing Kubernetes Dashboard v2.5.0"
kubectl -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.5.0/aio/deploy/recommended.yaml
sudo curl https://raw.githubusercontent.com/JasonPulse/kubernetesDashboard/master/Dashboard/dashboard-patch.yaml > dashboard-patch.yaml
kubectl patch deployment -n kubernetes-dashboard kubernetes-dashboard --patch-file dashboard-patch.yaml
echo "Installing Portainer-Nodeport"
sudo curl -L https://downloads.portainer.io/portainer-agent-k8s-nodeport.yaml -o portainer-agent-k8s.yaml
kubectl apply -f portainer-agent-k8s.yaml
echo "Portainer Agent should be accessable at ${PUBLIC_IP_ADDRESS}:30778"