#!/bin/bash

packer build -var-file example-variables.json debian-bullseye.json
