## Distributed K8S Cluster

There are a lot of challenges to making a distributed K8S cluster where nodes are located in multiple physical networks. These include:

* Allowing nodes to access eachother (VPN)
* Configuring the nodes as worker / master nodes
* Ensuring nodes use the correct (VPN) IP addresses
* Configuring a network plugin that works over the VPN
* Enabling LoadBalancers and Ingress 
* Exposing services to the Internet, and dealing with ingress / egress points to the cluster
* Managing machine outages without physical access

This ignores the normal challenges of creating a K8S server, such as:

* Security
* Network policy
* Backups, restoration, and other operations
* User management
* Secret management

To solve these problems, this project creates a series of Terraform resources and Ansible playbooks which configure a distributed K8S cluster.

## How it works

### Requirements

To create the cluster, you need:

1. A dedicated machine on a cloud provider (AWS EC2, DigitalOcean Droplet) with a static ip at at least one vCPU and 1 GB of RAM.
2. At least one physical machine with Proxmox installed
3. Any number of physical edge devices
4. A control machine with Terraform and Ansible installed. Additionally, it needs SSH access to all the physical edge devices, API access to the Proxmox machines, and network access to the cloud machine.

The cloud machine hosts a [Netmaker VPN](https://www.netmaker.org/). This builds on top of wireguard to create virtual subnets, and provides explicit support for K8S network CNIs. The physical Proxmox machines will host VMs that will in turn become K8S nodes. This is the recomended way to run K8S nodes on sufficiently powerful hardware, because if the nodes networks break for whatever reason you can reboot it remotely without physical access. It also makes common operations such as backups and restoring much simpler. However, when K8S nodes are run baremetal, problems that break networking require physical access to fix. The physical edge devices will run K8S nodes baremetal. This is recomended for devices that have insufficient computational power to run VMs, such as Raspberry Pis. Finally, the control machine will be what provisions the entire cluster.

### Network Architecture

The diagram below shows the final network architecutre:

![Network Diagram](img/network-map.png)

The cloud machine runs the Netmaker VPN and provides ingress. Physical machines are placed on their own subnet, VMs on another, K8S nodes on yet another, and finally access machines are on a fourth subnet. Each proxmox server can run multiple VMs.

Note that Netmaker is a mesh solution, which is not shown in the diagram. No DNS server is needed because Netmaker directly edits the `hosts` file of each machine.

Each physical machine and VM will run a lightweight SSH server (Dropbear) to provide remote access. 

### What we tested with

* Proxmox 7.2

We had trouble installing this. Grub wouldn't detect the USB. We went into grub by pressing `c`, printed the drives (`ls`), found our drive and set it with the command `set root=(hd1,gpt3)`. Then when we did `ls /` we could see files that were clearly proxmox. We then set the loader with `chainloader /efi/boot/bootx64.efi` and ran `boot`.


### Working notes

#### Proxmox setup

install `apt install wireguard-dkms` before `netclient`

Disable the enterprise repository
vi /etc/apt/sources.list.d/pve-enterprise.list
by commenting the line
#deb https://enterprise.proxmox.com/debian/pve bullseye pve-enterprise
and enable the "no-subscription" repository by creating a new file
vi /etc/apt/sources.list.d/pve-no-subscription.list
with
deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription

### Setup notes

Got the master / worker to create succesfully using:
```bash
kubeadm init --apiserver-advertise-address $IPADDR --apiserver-cert-extra-sans kfs-master.vms --pod-network-cidr 10.244.0.0/16 --node-name kfs-master --ignore-preflight-errors Swap --cri-socket unix:///var/run/containerd/containerd.sock --control-plane-endpoint kfs-master.vms
```

The key was to use the fully qualified domain name for `--apiserver-cert-extra-sans` and `--control-plane-endpoint`. With netmaker this can't be automatically found because there's no DNS server. The correct value can be found in the `/etc/hosts` file but will take some parsing. The format is `{hostname}.{networkname}`


- will need to set worker node ips on startup... perhaps in the `/etc/sysconfig/kubelet` file after we connect to netmaker. See [this](https://stackoverflow.com/questions/54942488/how-to-change-the-internal-ip-of-kubernetes-worker-nodes)

make sure we bind flannel to the right iface

mark a node as egress so other machines can talk to pods / services, bind egress to flannel iface
