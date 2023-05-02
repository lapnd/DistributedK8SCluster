#!/usr/bin/bash
test -f /install_vpn.sh
while [ $? -eq 0 ]
do
  sleep 1
  test -f /install_vpn.sh
done
touch /first-boot-ran
