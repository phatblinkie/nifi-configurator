rsync -avXS /opt/ /opt_backup/
umount /opt
lvremove /dev/vg1/lv_opt
#create new 50g lv for opt
lvcreate -L 50G -n lv_opt vg1
lvs vg1
mkfs.xfs /dev/vg1/lv_opt
#blkid /dev/vg1/lv_opt
# Replace UUID= line in /etc/fstab if the old UUID changed
mount /opt
chown root:root /opt
chmod 755 /opt
#extend /home lv by all remaining free space on the volume group
lvextend -l +100%FREE /dev/vg1/lv_home
#increase xfs size on /home to match
xfs_growfs /home
df -h /home /opt
rsync -avXS /opt_backup/ /opt/
rm -rf /opt_backup

fapolicyd-cli --update
systemctl restart fapolicyd

echo "resizing complete, opt should be 50G and /home should be 160G"
echo
echo
df -h
