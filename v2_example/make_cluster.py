calvin_node = ProxmoxNode("calvin-proxmox", "root", "KFSCloud")
david_node = ProxmoxNode("david-proxmox-host", "root@pam", "KFSCloud")

class CustomPackerConfigGenerator extends PackerConfigGenerator:
    def get_network_adapters(packer_settings):
        return [
            {
                "model": "virtio",
                "bridge": packer_settings.bridge,
                "firewall": True,
                "mtu": 1
            }
        ]
    
    # This one is really hard to handle because provisioners are file-path
    # specific.... not sure what to do
    def get_provisioners(packer_settings):
        return [
            {
                "type": "file",
                "source": "cloud.cfg",
                "destination": "/etc/cloud/cloud.cfg"
            },
            {
                "type": "ansible",
                "playbook_file": "../playbooks/setup-k8s.yml",
                "extra_arguments": ["--extra-vars", "{'root_password': '{{user `root_password`}}', 'username': '{{user `username`}}', 'password': '{{user `password`}}'}", "-vvv", "--ssh-extra-args='-J root@{{user `proxmox_node`}}'"]
            }
        ]
    
    '''
    # These functions should be very coarsew-grain, and delegate to finer-grianed functions
    # like get_provisioners() when possible. However, if our finer-grained functions
    # dont provide enough customziation, users can still override these functions
    def get_source_block(packer_settings):
        ...

    def get_build_block(packer_settings):
        ...
    '''
    
packer_generator = CustomPackerConfigGenerator()

packer_settings_calvin = PackerSettings
    .username("cloud")
    .password("KFSCloud")
    .root_password("KFSCloud")
    .bridge("vmbr0")
    ...

packer_settings_david = PackerSettings
    .username("cloud")
    .password("KFSCloud")
    .root_password("KFSCloud")
    .bridge("vmbr1")
    ...

packer_template_config_calvin = packer_generator.generate(packer_settings_calvin)
packer_template_config_david = packer_generator.generate(packer_settings_david)

calvin_node.install_prereqs()
david_node.install_prereqs()

# this function should assert our networking assumptions and output useful errors if 
# they fail
make_packer_templates([calvin_node, david_node], [packer_template_config_calvin, packer_template_config_david])
