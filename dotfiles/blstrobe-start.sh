#!/usr/bin/env bash

# set this script in a local folder
# set exec-once = ~/Documents/scripts/blstrobe-start.sh in hyprland.conf
sudo modprobe i2c-dev
sudo blstrobe -e -f -p 0 -o /dev/i2c-4 -t 5000 #brilho maximo
