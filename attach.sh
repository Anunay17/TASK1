#!/bin/bash

sudo mkfs.ext4  /dev/xvdh
sudo mount  /dev/xvdh  /var/www/html
sudo rm -rf /var/www/html/*
sudo git clone https://github.com/sanchitg18/WebServer-Data.git /var/www/html/
