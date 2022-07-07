variable "ansible_playbook_dir" {
  type    = string
  default = "../playbooks"
}

locals {
  # These variables tell Terraform how to connect to Proxmox
  pm_password = "KFSCloud"
  pm_user = "root@pam"
  pm_api_url = "192.168.0.5"

  # These variables configure the VM
  name = "test-node-2"
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

  # This is the name of the inventory file that will be created for this node
  inventory_file = "inventory1"
  # Which playbook from ../playbooks to provision the machine with
  playbook = "my-playbook.yml"
}

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.10"
    }
  }
}

provider "proxmox" {
  pm_debug = true
  pm_api_url = "https://${local.pm_api_url}:8006/api2/json"
  pm_tls_insecure = true
  pm_password = local.pm_password
  pm_user = local.pm_user
}

resource "proxmox_vm_qemu" "k8s_node" {
  name        = local.name
  bios        = "seabios"
  target_node = local.target_node
  memory      = local.memory

  # On Proxmox cores are more like threads, so if your CPU supports
  # hyper-threading the max value for this is double the number
  # of physical CPU cores.
  #
  # Proxmox docs indicate that using 2 cores with 2 socket, or 4 cores with
  # 1 socket, is pretty much irrelevent to performance.
  cores       = local.cores
  sockets     = local.sockets

  # The type of CPU will limit the CPU flags that can be passed in by QEMU
  # and thus can effect performance. Using 'host' will apply the same CPU 
  # type as the host CPU, but means if you need to do a live migration
  # between two Proxmox nodes with different CPU types, QEMU will break.
  #
  # The default CPU type is 'kvm64' which emulates a Pentium 4 processor
  # and ensures live migrations can always be done. Use this type if it's
  # important to you. Alternatively, if your CPUs are all from the same family
  # but different generations you can use the oldest CPU type as it will
  # provide a shared set of CPU flags that is still bigger than kvm64
  cpu         = "host"

  # The template name to clone this vm from
  clone       = local.template_name
  full_clone  = false
  agent       = 1

  lifecycle {
    prevent_destroy = true
  }
}

resource "local_file" "make_inventory_file" {
  filename = local.inventory_file
  content  = <<-EOT
    [nodes]
    ${proxmox_vm_qemu.k8s_node.default_ipv4_address}
    
    [nodes:vars]
    ansible_ssh_common_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"sshpass -p '${local.pm_pam_password}' ssh -W %h:%p -q ${local.pm_pam_user}@${local.pm_api_url}\""

    ansible_connection=ssh
    ansible_user=${local.vm_username}
    ansible_ssh_pass=${local.vm_password}
    ansible_become_pass=${local.vm_root_password}
  EOT

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ${local.inventory_file} ${var.ansible_playbook_dir}/${local.playbook}"
  }

  provisioner "local-exec" {
    command = "rm ${local.inventory_file}"
  }
}
