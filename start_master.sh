export PATH=$PATH:/opt/bin
token=$(kubeadm token generate)
sed -i "s/__TOKEN__/$token/g" kubeadm-conf
kubeadm init --config=kubeadm-conf
cp -r /etc/kubernetes/pki/* /home/core/share/certs

