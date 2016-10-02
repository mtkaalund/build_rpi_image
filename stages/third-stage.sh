#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt update
apt -y install git-core binutils ca-certificates rpi-update
touch /boot/start.elf
rpi-update
apt -y install locales console-common ntp openssh-server less vim
echo "root:raspberry" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f third-stage
