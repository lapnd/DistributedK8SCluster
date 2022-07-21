### Where we started

In mid-2021, we had a need to run a single, simple webserver. This could have easily been done on a cloud provider like AWS, but our entire team are tech nerds and we really wanted expertice with K8S, so we decided to buy a cheap machine to run Kubernetes on. We found a small form-factor server for $200 with 16 GB of RAM and a functioning CPU, installed K3S (to reduce computation overhead), and deployed our server. It was deployed as a `ClusterIP` type so it was exposed on the server to enable egress. 

### Expansion

This worked perfectly well and was super easy to do. However, a few months later we needed to run a cronjob that was CPU intensive, and on this cheap machine the job wasn't running fast enough. Fortunatly, one of us had an old laptop that could handle the workload, and we decided to add it to the cluster. That's what Kubernetes is for!

The two machines were not physically located in the same network so we set up a simple Wireguard VPN between them. The new node was easily added to K3S as a worker node and everything seemed to work.

### Problems begin

After a few weeks, the master node restarted and we realized we had a problem. The server was re-scheduled on the worker node instead of the master node (still as a `ClusterIP`) and suddenly our egress point changed. This wasn't good. Fortunatly, K8S comes with a lot of ways to handle this, and the main one we found was to use a `LoadBalancer` to get an external IP and forward traffic to there. However, K3S doesn't support the type `LoadBalancer`, so it was time to swap to the fully-featured K8S.

It was a lot of effort to tear our cluster down and rebuild it, and even after we did that we learned we couldn't just immediatly use a `LoadBalancer` because we weren't on a cloud provider. First, we needed to install a network plugin (or CNI), and then we needed to install a load balancer (like MetallB) and then we could deploy nginx to the cluster and make services of type `LoadBalancer`. We tried to use Calico first as the CNI because it's higher performance vs flannel, but it didn't easily work. It wasn't binding correctly to the wireguard ifaces, and pods on one node couldn't connect to pods on another node. We figured there was some configuration that could fix it, but Calico was a complicated beast and we decided to move on.

We then swapped to flannel because it was much simpler, we knew it could work because it's what K3S used, and there was a simple configuration option to bind to an iface of choice. Removing Calico was difficult (multiple configuration files needed to be deleted, as well as four or five directories, and if any of them lingered it would break flannel) but eventually our node was clean again and we had flannel running. To our delight, it worked! Pods on the master node could see pods on the worker and vice versa.

### We need to pivot

We then deployed metallb, nginx, and re-deployed our software. At last, our servers were running again. All seemed well for a couple of days, until the worker node mysteriously went down. We couldn't SSH to it and `kubelet` wasn't responding, but we could ping it. Very weird. The machine was physically rebooted, and everything worked again.

However, a few hours later the problems re-appeared. Once again, we couldn't SSH onto the machine and see what was wrong. After rebooting, the logs showed no problems. Then, the next day, the master node went down -- but this time we had an SSH session. The session was very slow... unimaginably slow... Some commands would randomly fail, but some worked after minutes of delay. `systemctl` didn't work. `journalctl` didn't work. It seemed that there might be something wrong with PID 0. It was a nightmare. Some painful debugging later and we speculated it was due to K8S making the machine OOM.

We deleted our memory intensive deployments, verified that we weren't using enough RAM to go OOM, and hoped we were stable. We weren't. Further analysis indicates there was some problems with how flannel and wireguard interacted. Flannel would change the ip rules of the VPN iface, and this would break the VPN. Restarting the VPN would fix this, but the problem would then re-appear after a few hours. We never learned if this was related to the weird SSH and memory behavior we originally identified on the worker node.

Our networking wasn't working. Wireguard wasn't cooperating with the K8S CNIs, and our limited networking knowledge couldn't solve this. We needed to upgrade our VPN solution.

### Re-architect Everything

We quickly identified Netmaker as a possible solution. It could make dedicated networks, had full featured support for K8S CNIs, including both flannel and Calico, and it was free. Additionally, on the flat Wireguard VPN our network space was discorganized and cluttered. All machines needed static IPs and there weren't clear subnets for different types of machines. Netmaker make it easy to clean all that up, while also supplyind dynamic IP addresses. We could have easily replaced our VPN and done nothing else, but this whole ordeal had shown that there were other problems to fix as well.

First, every time we changed something about our cluster took significant effort - and this was with just two nodes, and we expected to get more nodes in the future. Replacing Calico with flannel took at least half a day as we kept learning new ways we hadn't fully uninstalled Calico. Figuring out how to use cgroups v2 with K8S took a few days. Why wasn't this better documented? We had robust playbooks at this point for manually creating new master and worker nodes, but it still took time.

Additionally, when we had VPN problems on the worker node physical access was needed to resolve the problem. This is a big issue for us, because our nodes are frequently unattended and remote. If there are problems, we need to resolve them with SSH access, and if we can't do that our network could be broken for an extended period of time.

We decided, in addition to swapping our VPN solution, we would solve these two problems together by virtualizing our cluster. Everything would be VMs now (except our Raspberry Pi edge devices). This would ensure we could always reboot the machines, as long as the physical host was up. And if the hosts only needed to run VMs, there was very little that could break them.

These VMs would be automatically provisioned, so when we needed to change our network in the future we could do so automatically. We would automate the manual playbooks we had spent months creating. This would also give us a bunch of other benefits that we weren't mature enough to need, but would have eventually -- easy backups, restorations, and more freedom with our file storage.

### Technology Selection

The leader in the VM space is definitly VMWare. We had experience with ESXi clusters in the past, and they were super cool, very powerful, and allowed for some incredibly robust clusters. If we had a budget and more teammembers, this is probably the solution we would choose.

However, VMWare products also came with complications such as licensing and configuration difficulties. These would slow down how long it would take us to get the cluster up and running again, and we really needed this working as soon as possible. Additionally, we wern't sure our cheap nodes could even run VMWare software.

We briefly looked into Vagrant, because it's ability to provision VMs is convenient, but its lack of an API or any sort of management tools made it a bad choice. 

We then found Proxmox, and it seemed perfect (spoiler: it isn't perfect, but it's still pretty good). It was super easy to install and use. No problems with lisences. It provided a nice server to manage our VMs, see our hardware utilization, and an API. Furthermore, it would integrate with industry tools like Terraform, allowing us to treat our network like a real cloud provider with severe limitations and not just a bunch of servers we ran in a corner! 

We then needed to figure out how we would provision our machines. We eliminated Puppet and Chef as options because we didn't want to run a server that would need network access to each physical and virtual machine. That would make provisioning very difficult. That pretty much left Ansible as the big player in the room, which was appealing because it didn't need a server, and it just required SSH access. We went with Ansible and didn't look back.

We then quickly realized we needed a VM template. There were a bunch of benefits to this:

1. A lot of provisioning would only need to be done once, instead of for each VM, making it much faster to make new nodes
2. If provisioning fails (as it sometimes can) it's better to fail on the template and re-try than to fail on the VM
3. Having a template plays better with tooks like Terraform

Our team had experience with Packer, and Packer had Ansible integrations, so we decided to use that tool without considering alternatives.

### Putting it all together

Linking together all the tools into a coherant process is still a string-noodly mess. There are a lot of steps that can all fail, mainly due to complicated network setups or varying proxmox setups. The following shows how the tech can be linked together (assumume two Proxmox machines on different networks).

1. Add both Proxmox nodes to a Netmaker network
2. Create the VM template. If your Proxmox nodes don't use a clustered filesystem like Ceph, you can't migrate VMs or templates over the network from one node to another (even if you are clustered) so you will need to make the template twice, once on each node. This can be extra annoying because the machine running Packer needs to be on the same physical network as the Proxmox machine.
3. Use Terraform to make the VMs. Ansible is then used to provision the VMs, which uses the Proxmox node as a ssh pass-through. 


### Limitations

Figuring out which machines can do what provisioning steps and getting all the SSH pass-through to work is a massive headache, and is the biggest headache. However, there are other issues we encountered, mostly with Proxmox:

* Clustering Proxmox nodes together doesn't allow for migrations or copies between nodes. This makes deployment the template a pain.
* Proxmox doesn't have good integration with Terraform. All the plugins are community made. There are a few different ones, but most aren't still being supported. The one we use (the only one we found still being supported, and the only one that works with Proxmox 7+) has very few features compared to Terraform plugins for AWS or Azure.
* Netmaker doesn't allow for subnets -- just distinct networks that can't communicate. 
* Packer runs a local HTTP server to host the cloud config. The VM then tries to reach this server to get the config. This doesn't play nice with VPNs, and it doesn't fail as obviously or quickly as it should.
* Packer, because it uses JSON, doesn't allow for conditional expression. Thus, when we wanted to add a provisioner that ran only when customization scripts were supplied, but not otherwise, we found this very difficult. Our solution was to make a simple Python script that dynamically generates the JSON and wraps around Packer, which is a gross solution.
