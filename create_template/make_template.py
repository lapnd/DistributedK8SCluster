import json
import sys
from pathlib import Path
import tempfile
import subprocess
import os

args = sys.argv

customziation_script = None
var_file = None

for i in range(1, len(args)):
    token = args[i]
    tokens = token.split("=")

    if len(tokens) == 2:
        if tokens[0] == "customization":
            customziation_script = Path(tokens[1])
        elif tokens[0] == "var-file":
            var_file = Path(tokens[1])
        else:
            print(f"Invalid argument: {token}")
            exit(1)
    else:
        print(f"Invalid argument: {token}")
        exit(1)


template = {
    "variables": {
        "proxmox_host": None,
        "proxmox_node": None,
        "proxmox_api_user": None,
        "proxmox_api_password": None
    },
    "sensitive-variables": ["proxmox_api_password"],
    "builders": [
        {
            "type": "proxmox-iso",
            "proxmox_url": "https://{{ user `proxmox_host` }}/api2/json",
            "insecure_skip_tls_verify": True,
            "username": "{{ user `proxmox_api_user` }}",
            "password": "{{ user `proxmox_api_password` }}",

            "template_description": "Debian 11 template for use in a K8S network.",
            "node": "{{user `proxmox_node`}}",
            "network_adapters": [
                {
                    "model": "virtio",
                    "bridge": "{{user `bridge`}}",
                    "firewall": True,
                    "mtu": 1230
                }
            ],
            "disks": [
                {
                    "type": "scsi",
                    "disk_size": "{{user `disk_size`}}",
                    "storage_pool": "{{user `storage_pool`}}",
                    "storage_pool_type": "{{user `storage_pool_type`}}",
                    "format": "raw",
                    "io_thread": True
                }
            ],
            "scsi_controller": "virtio-scsi-single",

            "iso_file": "local:iso/{{user `iso`}}",
            "http_directory": "./",
            "boot_wait": "10s",
            "boot_command": [
                "<esc><wait>auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
            ],
            "unmount_iso": True,

            "cloud_init": True,
            "cloud_init_storage_pool": "{{user `cloud_init_storage_pool`}}",

            "vm_name": "{{ user `template_name` }}",
            "vm_id": "{{ user `vm_id` }}",
            "memory": "2048",

            "sockets": "1",
            "cores": "2",
            "os": "l26",

            "ssh_timeout": "90m",
            "ssh_username": "root",
            "ssh_password": "packer"
        }
    ],
    "provisioners": [
        {
            "type": "file",
            "source": "cloud.cfg",
            "destination": "/etc/cloud/cloud.cfg"
        },
        {
            "type": "ansible",
            "playbook_file": "../playbooks/setup-k8s.yml",
            "extra_arguments": ["--extra-vars", "{'root_password': '{{user `root_password`}}', 'username': '{{user `username`}}', 'password': '{{user `password`}}'}", "-vvv"]
        }
    ]
}

if customziation_script:
    print(f"Adding customizations at {customziation_script.resolve()}")

    template["provisioners"].append({
        "type": "shell",
        "script": str(customziation_script.resolve())
    })

if var_file is None:
    print("var-file not supplied: please pass in var-file=my-var-file.json")
    exit(1)

fd, path = tempfile.mkstemp(suffix='.json')
try:
    with os.fdopen(fd, 'w') as tmp:
        tmp.write(json.dumps(template, indent=4))
    
    cwd = Path(__file__).parent
    process = subprocess.Popen(['packer', 'build', '-var-file', str(var_file.resolve()), path],
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.PIPE,
                    cwd=str(cwd.resolve()))
    for line in process.stdout: print(line.decode(), end='')
    
    return_code = process.wait()
    if return_code:
        for line in process.stderr: print(line.decode(), end='')
        exit(return_code)
finally:
    os.remove(path)
