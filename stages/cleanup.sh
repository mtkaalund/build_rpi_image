#!/bin/bash
apt update
apt autoremove -y
apt clean
apt-get clean
rm -f cleanup.sh
