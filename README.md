# CoreOS multimachine 

## Startup

Start all VMs in parallel. 

```
vagrant up core-01
vagrant up core-02
vagrant up core-03
```
This should setup 3 machines with etcd cluster bootstrapped

## Bootstrap kubernetes

### Start one master
```
./install_master.sh
```

### SCP certs to other masters
```
scp /etc/kubernetes/pki/* to all masters
```

### Start other masters

```
kubeadm init --config=kubeadm-conf
```
