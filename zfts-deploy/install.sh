#!/bin/bash

echo "Installing ZFTS SELinux module..."
semodule -i zfts_all.pp

echo "Installing polkit rule..."
cp 49-zfts.rules /etc/polkit-1/rules.d/

echo "Adding nginx to systemd-journal group..."
usermod -aG systemd-journal nginx

echo "Restarting services..."
systemctl restart nginx php-fpm

echo "Done."
