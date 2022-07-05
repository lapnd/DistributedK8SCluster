## Distributed K8S Cluster

There are a lot of challenges to making a distributed K8S cluster where nodes are located in multiple physical networks. These include:

* Allowing nodes to access eachother (VPN)
* Configuring the nodes as worker / master nodes
* Ensuring nodes use the correct (VPN) IP addresses
* Configuring a network plugin that works over the VPN
* Enabling LoadBalancers and Ingress 
* Exposing services to the Internet, and dealing with ingress / egress points to the cluster
* Managing machine outages without physical access

To solve these problems, this project creates a series of Terraform resources and Ansible playbooks which configure a distributed K8S cluster.

## How it works

### Requirements

To create the cluster, you need:

1. A dedicated machine on a cloud provider (AWS EC2, DigitalOcean Droplet) with a static ip at at least one vCPU and 1 GB of RAM.
2. At least one physical machine with Proxmox installed
3. Any number of physical edge devices
4. A control machine with Terraform and Ansible installed. Additionally, it needs SSH access to all the physical devices, API access to the Proxmox machines, and network access to the cloud machine.

The cloud machine hosts a [Netmaker VPN](https://www.netmaker.org/). This builds on top of wireguard to create virtual subnets, and provides explicit support for K8S network CNIs. The physical Proxmox machines will host VMs that will in turn become K8S nodes. This is the recomended way to run K8S nodes on sufficiently powerful hardware, because if the nodes networks break for whatever reason you can reboot it remotely without physical access. It enables you to develop your infrastructure on one set of VMs while running production code in another set. finally, it also makes common operations such as backups and restoring much simpler. 

However, when K8S nodes are run baremetal, problems that break networking require physical access to fix. The physical edge devices will run K8S nodes baremetal. This is recomended for devices that have insufficient computational power to run VMs, such as Raspberry Pis. Finally, the control machine will be what provisions the entire cluster.

### Network Architecture

The diagram below shows the final network architecutre:

![Network Diagram](img/network-map.png)

The cloud machine runs the Netmaker VPN and provides ingress. Physical machines are placed on their own subnet, VMs on another, K8S nodes on yet another, and finally access machines are on a fourth subnet. Each proxmox server can run multiple VMs.

Note that Netmaker is a mesh solution, which is not shown in the diagram. No DNS server is needed because Netmaker directly edits the `hosts` file of each machine.

Each physical machine and VM will run an SSH server to provide remote access. 

## Getting Started

### Netmaker Setup

Follow [these instructions](https://docs.netmaker.org/quick-start.html) to set up your netmaker machine. This should be the cloud device hosted on an external provider. 

After this is set up, create two networks: one for the Proxmox machines, and one for the VMs. For each network, create an access token. Especially for the VM network, make sure the number of uses on the access token is sufficiently high that you won't run out, as this token will be used to automatically provision VMs. 

### Proxmox Setup

We installed Proxmox 7.2. Make sure to update the apt repository at `/etc/apt/sources.list.d/pve-enterprise.list` by commenting out the `deb https://enterprise.proxmox.com/debian/pve bullseye pve-enterprise` line. Then add the no-subscription repository with 

```bash
echo deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription > /etc/apt/sources.list.d/pve-no-subscription.list
```

Make sure the Proxmox machine has a valid hosts file. Importatly, ensure `ping localhost` works. If it doesn't, add an entry for `localhost` to the `/etc/hosts` file.

Ensure each machine has a useful hostname, as this will become an addressable name on the Netmaker VPN. You can change it with `hostnamectl set-hostname {name-here}`. Before seting up the VPN, install wireguard libraries with `apt install wireguard-dkms`. This ensures `netclient` has all the software it needs without it overwriting libraries Proxmox needs. Then add the hypervisor to the VPN on the appropriate network by following [these instructions](https://docs.netmaker.org/netclient.html).

### Create a master node

#### Create a VM template

Before creating a master node, we need to create a template on Proxmox. This template will have VPN already configured, as well as a lot of necesarry provisioning to run Kubernetes. Additionally, using a template means that spining up a new VM takes seconds insteads of ~10 minutes. To create the template:

1. Clone this repository on a machine with SSH access to newly created VMs. In order to provision the template, we use Ansible playbooks which require SSH access to the VM before VPN is setup. The Proxmox machine should always work, as well as any machine on the same LAN as the Proxmox server.

2. [Install Packer](https://learn.hashicorp.com/tutorials/packer/get-started-install-cli). This allows us to create the template from an ISO. 

3. Install Ansible

```bash
apt update
apt install ansible
```

4. Install the Debian ISO on your Proxmox node. We use the [Debian 11.3.0-amd-64 image](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.3.0-amd64-netinst.iso).

5. Configure the variables in `create_template/example-variables.json`

6. Create the template:

```bash
cd create_template
packer build -var-file example-variables.json debian-bullseye.json
```

#### Create a master node

Ensure you are on a machine with access to the Proxmox API and has Terraform installed. Then make sure the variable values in `terraform/example-variables.tfvars` are correct, and run:

```bash
cd terraform
terraform init
terraform apply
terraform apply -auto-approve -var-file="example-variables.tfvars"
```

This will create a new, unprovisioned node. 

### Create a worker node (VM)

### Create a worker node (edge device)

## Working notes

### Setup notes

Got the master / worker to create succesfully using:
```bash
kubeadm init --apiserver-advertise-address $IPADDR --apiserver-cert-extra-sans k8s-master-1.vms --pod-network-cidr 10.244.0.0/16 --node-name k8s-master-1 --ignore-preflight-errors Swap --cri-socket unix:///var/run/containerd/containerd.sock --control-plane-endpoint k8s-master-1.vms
```

The key was to use the fully qualified domain name for `--apiserver-cert-extra-sans` and `--control-plane-endpoint`. With netmaker this can't be automatically found because there's no DNS server. The correct value can be found in the `/etc/hosts` file but will take some parsing. The format is `{hostname}.{networkname}`


- will need to set worker node ips on startup... perhaps in the `/etc/sysconfig/kubelet` file after we connect to netmaker. See [this](https://stackoverflow.com/questions/54942488/how-to-change-the-internal-ip-of-kubernetes-worker-nodes)

make sure we bind flannel to the right iface

mark a node as egress so other machines can talk to pods / services, bind egress to flannel iface
