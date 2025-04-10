#!/usr/bin/env bash

sudo modprobe i2c-dev
sudo blstrobe -e -f -p 0 -o /dev/i2c-4 -t 5000 #brilho maximo
