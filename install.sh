
systemctl stop update-engine
CNI_VERSION="v0.6.0"
mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"

mkdir -p /opt/bin
cd /opt/bin
curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
chmod +x {kubeadm,kubelet,kubectl}

curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service
mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" | sed "s:/usr/bin:/opt/bin:g" > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl enable kubelet && systemctl start kubelet
systemctl daemon-reload
systemctl restart kubelet

curl -o /opt/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
curl -o /opt/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x /opt/bin/cfssl*

export PATH=$PATH:/opt/bin

mkdir -p /etc/kubernetes/pki/etcd
pushd /etc/kubernetes/pki/etcd
cp /home/core/share/etcd-certs/* /etc/kubernetes/pki/etcd

export PEER_NAME=$(hostname)
export PRIVATE_IP=$(ip addr show eth1 | grep -Po 'inet \K[\d.]+')

cfssl print-defaults csr > config.json
sed -i '0,/CN/{s/example\.net/'"$PEER_NAME"'/}' config.json
sed -i 's/www\.example\.net/'"$PRIVATE_IP"'/' config.json
sed -i 's/example\.net/'"$PEER_NAME"'/' config.json

echo "172.17.8.101 core-01" >> /etc/hosts
echo "172.17.8.102 core-02" >> /etc/hosts
echo "172.17.8.103 core-03" >> /etc/hosts

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server config.json | cfssljson -bare server
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer config.json | cfssljson -bare peer
popd


export ETCD_VERSION="v3.1.12"
curl -sSL https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz | tar -xzv --strip-components=1 -C /opt/bin/
rm -rf etcd--linux-amd64*
chmod +x /opt/bin/etcd

touch /etc/etcd.env
echo "PEER_NAME=${PEER_NAME}" >> /etc/etcd.env
echo "PRIVATE_IP=${PRIVATE_IP}" >> /etc/etcd.env

cat >/etc/systemd/system/etcd.service <<EOF
   [Unit]
   Description=etcd
   Documentation=https://github.com/coreos/etcd
   Conflicts=etcd.service
   Conflicts=etcd2.service

   [Service]
   EnvironmentFile=/etc/etcd.env
   Type=notify
   Restart=always
   RestartSec=5s
   LimitNOFILE=40000
   TimeoutStartSec=0

   ExecStart=/opt/bin/etcd --name ${PEER_NAME} --data-dir /var/lib/etcd --listen-client-urls "http://localhost:2379,https://${PRIVATE_IP}:2379" --advertise-client-urls https://${PRIVATE_IP}:2379 --listen-peer-urls https://${PRIVATE_IP}:2380 --initial-advertise-peer-urls https://${PRIVATE_IP}:2380 --cert-file=/etc/kubernetes/pki/etcd/server.pem --key-file=/etc/kubernetes/pki/etcd/server-key.pem --client-cert-auth --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem --peer-cert-file=/etc/kubernetes/pki/etcd/peer.pem --peer-key-file=/etc/kubernetes/pki/etcd/peer-key.pem --peer-client-cert-auth --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem --initial-cluster core-01=https://172.17.8.101:2380,core-02=https://172.17.8.102:2380,core-03=https://172.17.8.103:2380 --initial-cluster-token my-etcd-token --initial-cluster-state new

   [Install]
   WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

