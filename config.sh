#!/bin/bash

sudo yum install httpd php git -y
sudo systemctl restart httpd
sudo systemctl enable httpd
