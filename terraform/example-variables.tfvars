# These variables tell Terraform how to connect to Proxmox
pm_password = "KFSCloud"
pm_user = "root@pam"
pm_api_url = "192.168.0.5"

# These variables configure the VM
name = "master-node-1"
template_name = "debian-template"
target_node = "kfscluster"
memory = 2048
cores = 4
sockets = 1
cpu = "host"

# These variables are used to provision the VM after it is created. Ansible is used to
# do the provisioning, with the Proxmox API server as a jumpbox to ensure the VM
# is reachable.
#
# pm_pam_user and pm_pam_password are SSH credentials to the Proxmox machine
pm_pam_user = "root"
pm_pam_password = "KFSCloud"
# vm_username and vm_password are SSH credentials to the VM, while 
# vm_root_password is used to get sudo access
vm_username = "cloud"
vm_password = "KFSCloud"
vm_root_password = "KFSCloud"
