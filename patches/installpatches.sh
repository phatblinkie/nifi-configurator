if (( $EUID != 0 )); then
 echo "ERROR: This patching script must be run as root. sorry." >&2
 exit 1
fi

echo "Stopping fapolicyd"
systemctl stop fapolicyd

echo "Installing patch 1 - dated 6-15-2026"
sleep 3
tar -zxvf msnsvr.patch1.tar.gz -C /

#echo "restarting fapolicyd"
#systemctl restart fapolicyd
sleep 3
echo "Stopping zfts services"
systemctl stop zfts-105
systemctl stop zfts-107
systemctl stop zfts-dops-p2
systemctl stop zcompd-105
systemctl stop zcompd-107
systemctl stop zcompd-dops-p2

echo "Fixing zfts permissions"
sleep 3
chmod -v 0777 /mission-share/zfts/receive/*/.working
chown -R admin:admin /mission-share/zfts/receive/

echo "Installing zfts services and patched files"

#systemd services
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zcompd-105.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zcompd-107.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zcompd-dops-p2.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zfts-105.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zfts-107.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zfts-collector.service
install --group=root --owner=root --verbose --mode=0644 -t /etc/systemd/system /opt/upload/nifi-configurator/zfts_html/etc/systemd/zfts-dops-p2.service
#logrotators
install --group=root --owner=root --verbose --mode=0644 -t /etc/logrotate.d /opt/upload/nifi-configurator/zfts_html/etc/logrotate.d/zfts-105
install --group=root --owner=root --verbose --mode=0644 -t /etc/logrotate.d /opt/upload/nifi-configurator/zfts_html/etc/logrotate.d/zfts-107
install --group=root --owner=root --verbose --mode=0644 -t /etc/logrotate.d /opt/upload/nifi-configurator/zfts_html/etc/logrotate.d/zfts-dops-p2
#user bin
install --group=root --owner=root --verbose --mode=0755 -t /usr/local/bin /opt/upload/nifi-configurator/zfts_html/bin/zfts_collector.py
#website update
install --group=root --owner=root --verbose --mode=0644 -t /usr/share/nginx/html/zfts/v3 /opt/upload/nifi-configurator/zfts_html/zfts/v3/stats.js
#fapolicyd rules
install --group=fapolicyd --owner=root --verbose --mode=0644 -t /etc/fapolicyd/rules.d /opt/upload/nifi-configurator/fapolicyd_rules/50-ansible.rules
install --group=fapolicyd --owner=root --verbose --mode=0644 -t /etc/fapolicyd/rules.d /opt/upload/nifi-configurator/fapolicyd_rules/60-opt-upload.rules

#fix perms (damn umask is annoying)
chmod -v 0755 /opt/upload/nifi-configurator/Install_Menu.sh 
chmod -v 0644 /opt/upload/nifi-configurator/configs/nginx.conf.nopki.template
chmod -v 0644 /opt/upload/nifi-configurator/configs/nginx.conf.template
sleep 3

echo "Starting Zcompd/ZFTS services"
sleep 1
echo "reloading systemctl daemon"
systemctl daemon-reload

echo "Starting zcompd-105"
systemctl start zcompd-105
sleep 1

echo "Starting zcompd-107"
systemctl start zcompd-107
sleep 1

echo "Starting zcompd-dops-p2"
systemctl start zcompd-dops-p2
sleep 1

echo "Starting zfts-105"
systemctl start zfts-105
sleep 1

echo "Starting zfts-107"
systemctl start zfts-107
sleep 1

echo "Starting zfts-dops-p1"
systemctl start zfts-dops-p2

sleep 2
echo "Detecting nginx configuration that was applied"
sleep 1

usepki=$(grep -c "ssl_verify_client on" /opt/upload/nifi-configurator/configs/nginx.conf)

if [ "$usepki" -eq 1 ]; then
  echo "pki config detected"
  nginxtemplate="/opt/upload/nifi-configurator/configs/nginx.conf.template"
else
  echo "no pki config detected"
  nginxtemplate="/opt/upload/nifi-configurator/configs/nginx.conf.nopki.template"
fi

echo "applying nginx configuration fix"

#source the variables
. /opt/upload/nifi-configurator/variables.conf

 if cat $nginxtemplate | \
    sed "s|NIFI_DOMAIN_FQDN|$NIFI_DOMAIN_FQDN|g" | sed "s|ZFTS_DOMAIN_FQDN|$ZFTS_DOMAIN_FQDN|g" | sed "s|IP_ADDRESS|$IP_ADDRESS|g"> /opt/upload/nifi-configurator/configs/nginx.conf; then
    echo "SUCCESS: Generated nginx.conf"
 else
    echo "ERROR: Failed to create nginx.conf file" >&2
 fi

 config_source="/opt/upload/nifi-configurator/configs/nginx.conf"
 config_dest="/etc/nginx/nginx.conf"

 echo "INFO: Copying Nginx configuration"
 if cat "$config_source" > "$config_dest" && chmod -v 0644 "/etc/nginx/nginx.conf"; then
    echo "SUCCESS: Nginx configuration and files copied"
 else
    echo "ERROR: Failed to copy Nginx configuration or files" >&2
 fi

 echo "INFO: Restarting Nginx service"
 if systemctl restart nginx; then
    echo "SUCCESS: Nginx service started"
 else
    echo "ERROR: Failed to enable or start Nginx service" >&2
 fi
 echo "SUCCESS: Nginx configuration completed"


echo "Starting fapolicyd"
systemctl start fapolicyd
