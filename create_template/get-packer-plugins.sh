#!/usr/bin/env bash

cleanup() {
    local dir=$1
    echo "Cleaning up ${dir}"
    rm -rf $dir
}

get_zipped_plugin() {
    local plugin_name=$1
    local plugin_url=$2
    local dir=$(mktemp -d)
    trap "cleanup $dir" EXIT
    echo "Created tempdir: $dir"
    cd $dir
    wget $plugin_url -O file.zip
    unzip -d archive file.zip
    mv archive/* ./$plugin_name
    cd -
    cp $dir/$plugin_name .
}

main() {
    set -euo pipefail
    declare -A plugins=(
            ["packer-plugin-proxmox"]="https://github.com/hashicorp/packer-plugin-proxmox/releases/download/v1.1.3/packer-plugin-proxmox_v1.1.3_x5.0_linux_amd64.zip"
        )
    for plugin in "${!plugins[@]}"; do
        local url="${plugins[$plugin]}"

        if [[ -f "./$plugin" ]]; then
            continue
        fi

        if [[ $url =~ .*\.zip ]]; then
            get_zipped_plugin $plugin "${plugins[$plugin]}"
        fi
    done
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
