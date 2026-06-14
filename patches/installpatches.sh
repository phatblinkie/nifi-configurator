if (( $EUID != 0 )); then
 echo "ERROR: This patching script must be run as root. sorry." >&2
 exit 1
fi

echo installing patch 1 - dated 6-13-2026
sleep 3
tar -zxvf msnsvr.patch1.tar.gz -C /

