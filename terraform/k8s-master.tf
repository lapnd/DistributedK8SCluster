variable "pm_password" {
  type        = string
  default     = "KFSCloud"
  description = "Password to the Proxmox server."
}

variable "pm_user" {
  type        = string
  default     = "root@pam"
  description = "User to log into the Proxmox server as."
}

variable "pm_api_url" {
  type        = string
  default     = "192.168.0.5"
  description = "Domain name or IP to the Proxmox API."
}

variable "name" {
  type        = string
  default     = "my-k8s-node"
  description = "Name for the new node."
}

variable "target_node" {
  type        = string
  default     = "kfscluster"
  description = "Node on the Proxmox server to make the VM on."
}

variable "memory" {
  type        = number
  default     = 4096
  description = "How much memory to give the node."
}

variable "cores" {
  type        = number
  default     = 4
  description = "How many cores to give the node."
}

variable "sockets" {
  type        = number
  default     = 1
  description = "How many sockets to give the node."
}

variable "cpu" {
  type        = string
  default     = "host"
  description = "What type of CPU Qemu should emulate: effects CPU flags."
}

variable "template_name" {
  type        = string
  default     = "debian-template"
  description = "Name of the template to clone."
}

variable "pm_pam_user" {
  type        = string
  default     = "root"
  description = "User with SSH access to the Proxmox machine."
}

variable "pm_pam_password" {
  type        = string
  default     = "KFSCloud"
  description = "Password for user with SSH access to the Proxmox machine."
}

variable "vm_username" {
  type        = string
  default     = "cloud"
  description = "User with SSH access to the new VM."
}

variable "vm_password" {
  type        = string
  default     = "KFSCloud"
  description = "Password to the SSH user on the new VM."
}

variable "vm_root_password" {
  type        = string
  default     = "KFSCloud"
  description = "Password for the root user on the new VM."
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
  pm_api_url = "https://${var.pm_api_url}:8006/api2/json"
  pm_tls_insecure = true
  pm_password = var.pm_password
  pm_user = var.pm_user
}

resource "proxmox_vm_qemu" "k8s_node" {
  name        = var.name
  bios        = "seabios"
  target_node = var.target_node
  memory      = var.memory

  # On Proxmox cores are more like threads, so if your CPU supports
  # hyper-threading the max value for this is double the number
  # of physical CPU cores.
  #
  # Proxmox docs indicate that using 2 cores with 2 socket, or 4 cores with
  # 1 socket, is pretty much irrelevent to performance.
  cores       = var.cores
  sockets     = var.sockets

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
  clone       = var.template_name
  full_clone  = false
  agent       = 1
}

resource "local_file" "ip" {
  filename = "inventory"
  content  = <<-EOT
    [nodes]
    ${proxmox_vm_qemu.k8s_node.default_ipv4_address}
    
    [nodes:vars]
    ansible_ssh_common_args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"sshpass -p '${var.pm_pam_password}' ssh -W %h:%p -q ${var.pm_pam_user}@${var.pm_api_url}\""

    ansible_connection=ssh
    ansible_user=${var.vm_username}
    ansible_ssh_pass=${var.vm_password}
    ansible_become_pass=${var.vm_root_password}
  EOT

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory ../playbooks/test.yml || rm inventory"
  }
}
