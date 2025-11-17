#!/bin/bash

script_version="2.0.1"
# Do not allow to run as root
if (( $EUID == 0 )); then
 echo "ERROR: This script must not be run as root, run as normal user that will manage the containers. 'miadmin?'" >&2
 exit 1
fi

# Only allow to run as admin or uid 1000 -- else compatibility gets borked upd
if (( $EUID != 1000 )); then
 echo "ERROR: This script must only br run as the user \"admin\" or a user with UID=1000, your UID is $EUID" >&2
 exit 1
fi

# Check to make sure rsync, podman, and git-lfs are installed
if ! command -v rsync &> /dev/null; then
 echo "ERROR: rsync is required but not installed. Please install it first." >&2
 exit 1
fi

if ! command -v podman &> /dev/null; then
 echo "ERROR: podman is required but not installed. Please install it first." >&2
 exit 1
fi

if ! command -v git-lfs &> /dev/null; then
 echo "ERROR: git-lfs is required but not installed. Please install it first." >&2
 exit 1
fi


# Check if 'ip' command is available
if ! command -v ip >/dev/null 2>&1; then
   echo "ERROR: 'ip' command not found. Please install iproute2."
   exit 1
fi

# Integrated Monitoring Stack Deployment Tool
# Combines both privileged (root) and non-privileged (user) operations
# Always requests sudo password at start and uses it when needed

# ---------- Initial Setup ----------

# Clear the sudo password variable on exit
cleanup() {
 unset SUDO_PASSWORD
 # Clear sudo cache to ensure fresh prompt next time
 rm -f /tmp/install_config.* /tmp/install_errors_*.log
 sudo -k
}
trap cleanup EXIT

# ---------- Improved Sudo Password Handling ----------

get_sudo_password() {
 # Clear any existing sudo credentials
 sudo -k

 echo "===================================================="
 echo " Monitoring Stack Deployment Tool - Ver. $script_version"
 echo "===================================================="
 echo "INFO: This script requires root privileges for some operations."

 # Loop until we get a valid sudo password
 while true; do
 echo "INFO: Please enter your sudo password to proceed:"
 read -r -s SUDO_PASSWORD
 echo

 # Verify the password works by trying to list root directory
 echo -n "INFO: Verifying sudo access... "
 if echo "$SUDO_PASSWORD" | sudo -S ls /root >/dev/null 2>&1; then
 echo "SUCCESS: Sudo access verified"
 break
 else
 echo "ERROR: Incorrect sudo password. Please try again." >&2
 unset SUDO_PASSWORD
 fi
 done

 # Export the verified password
 export SUDO_PASSWORD
 echo
}

run_with_sudo() {
 # Use the verified password with proper newline handling
 echo -e "$SUDO_PASSWORD\n" | sudo -S "$@" 2>/dev/null
}

# ---------- Helper Functions ----------

check_permission() {
 local file="$1"
 local expected_perm="$2"
 local actual_perm=$(stat -c "%a" "$file" 2>/dev/null)

 if [[ "$actual_perm" != "$expected_perm" ]]; then
 echo "ERROR: $file has permissions $actual_perm (expected $expected_perm)" >&2
 echo "INFO: Please run the system configuration first or manually fix with:" >&2
 echo "sudo chmod $expected_perm $file" >&2
 return 1
 fi
 echo "SUCCESS: $file permissions verified as $expected_perm"
 return 0
}

safe_modify() {
 local file="$1"
 local action="$2"
 local description="$3"

 echo -n "INFO: ${description}... "
 if [ -f "$file" ]; then
 if eval "$action"; then
 echo "SUCCESS: ${description} completed"
 else
 echo "ERROR: Failed to ${description}" >&2
 return 1
 fi
 else
 echo "INFO: Skipped (file not found)"
 fi
}

check_success() {
 if [ $? -ne 0 ]; then
 echo "ERROR: $1" >&2
 return 1
 fi
 echo "SUCCESS: $1 completed"
}


collect_user_inputs() {
    # Check terminal compatibility
    if [[ "$TERM" == "dumb" || -z "$TERM" ]]; then
        echo "Error: Incompatible terminal type ($TERM). Setting TERM=xterm."
        export TERM=xterm
    fi

    # Check terminal size
    read -r rows cols < <(stty size)
    if [[ $rows -lt 10 || $cols -lt 60 ]]; then
        echo "Warning: Terminal size ($rows x $cols) is too small. Setting to 24x80."
        stty rows 24 cols 80
    fi

    # Define default values (customized for your environment)
    DEFAULT_OGS_DOMAIN_NAME="ogs18.ogs.mi.ds.army.smil.mil"
    #nifi
    DEFAULT_NIFI_DOMAIN_FQDN="nifi.$DEFAULT_OGS_DOMAIN_NAME"
    #nifi username
    DEFAULT_SINGLE_USER_CREDENTIALS_USERNAME="admin"
    #nifi pw has to be strong and at least 12 chars log
    DEFAULT_SINGLE_USER_CREDENTIALS_PASSWORD="!Changeme12345"

    # Check for variables.conf and load initial values
    VARS_FILE="variables.conf"
    if [ -f "$VARS_FILE" ]; then
        #echo "Loading initial values from $VARS_FILE" >> "$ERROR_LOG"
        if ! source "$VARS_FILE" 2>>"$ERROR_LOG"; then
            #echo "Warning: Failed to source $VARS_FILE. Using default values." | tee -a "$ERROR_LOG"
            echo "Variables config file found" > /dev/null
        fi
    else
        echo "Variables config NOT file found" > /dev/null
    fi

    while true; do
        # Create temporary configuration file
        CONFIG_FILE=$(mktemp /tmp/install_config.XXXXXX)
        ERROR_LOG="/tmp/install_errors_$(date +%s).log"

        # Write values to the configuration file with single quotes
        cat > "$CONFIG_FILE" << EOF
# Edit the values below for your installation.
# Lines starting with # are comments and ignored.
# Do not add spaces around = signs or remove single quotes.
# Keep values in single quotes to handle special characters.
# Example: LDAP_BIND_PASSWORD_VALUE='0o9i8u7y)O(I*U&Y'
# Save with (escape + :wq or cancel with escape + :q!) in vi.

#general-settings
OGS_DOMAIN_NAME='${OGS_DOMAIN_NAME:-$DEFAULT_OGS_DOMAIN_NAME}'
#Nifi
NIFI_DOMAIN_FQDN='${NIFI_DOMAIN_FQDN:-$DEFAULT_NIFI_DOMAIN_FQDN}'
#Nifi username
SINGLE_USER_CREDENTIALS_USERNAME='${SINGLE_USER_CREDENTIALS_USERNAME:-$DEFAULT_SINGLE_USER_CREDENTIALS_USERNAME}'
#Nifi pw has to be strong and at least 12 chars log
SINGLE_USER_CREDENTIALS_PASSWORD='${SINGLE_USER_CREDENTIALS_PASSWORD:-$DEFAULT_SINGLE_USER_CREDENTIALS_PASSWORD}'



EOF

        # Use vi as the editor
        EDITOR="vi"
        if ! command -v "$EDITOR" >/dev/null 2>&1; then
            echo "Error: No text editor (vi) found." | tee -a "$ERROR_LOG"
            exit 1
        fi

        # Open the file in the editor
        if ! $EDITOR "$CONFIG_FILE" 2>>"$ERROR_LOG"; then
            echo "Editor exited abnormally. Check $ERROR_LOG for details." | tee -a "$ERROR_LOG"
            whiptail --title "Confirm Exit" --yesno "Do you want to cancel and exit the installer?" 10 60 2>>"$ERROR_LOG" || {
                echo "Input cancelled by user."
                rm -f "$CONFIG_FILE"
                exit 1
            }
            rm -f "$CONFIG_FILE"
            continue
        fi

        # Log the raw configuration file for debugging
        echo "Raw configuration file contents:" >> "$ERROR_LOG"
        cat "$CONFIG_FILE" >> "$ERROR_LOG"
        echo "------------------------" >> "$ERROR_LOG"

        # Source the configuration file
        # Remove comments and empty lines, no modifications
        grep -v '^#' "$CONFIG_FILE" | grep -v '^$' > "${CONFIG_FILE}.clean"
        if ! source "${CONFIG_FILE}.clean" 2>>"$ERROR_LOG"; then
            echo "Error: Failed to source configuration file. Check syntax in $CONFIG_FILE." | tee -a "$ERROR_LOG"
            whiptail --msgbox "Error: Invalid configuration file syntax. Ensure each line has KEY='VALUE' format with no spaces around = and values in single quotes (e.g., '0o9i&Y')." 10 60 2>>"$ERROR_LOG"
            rm -f "$CONFIG_FILE" "${CONFIG_FILE}.clean"
            continue
        fi


        # Display summary screen with whiptail
        SUMMARY="Please review the entered values:\n\n"
	SUMMARY+="#General-Settings\n"
        SUMMARY+="OGS_DOMAIN_NAME: $OGS_DOMAIN_NAME\n\n"
        SUMMARY+="#Nifi-specific\n"
        SUMMARY+="NIFI_DOMAIN_FQDN: $NIFI_DOMAIN_FQDN\n\n"
        SUMMARY+="#Nifi username\n"
	SUMMARY+="SINGLE_USER_CREDENTIALS_USERNAME: $SINGLE_USER_CREDENTIALS_USERNAME\n\n"
        SUMMARY+="#Nifi pw has to be strong and at least 12 chars log\n"
        SUMMARY+="SINGLE_USER_CREDENTIALS_PASSWORD: $SINGLE_USER_CREDENTIALS_PASSWORD\n"

	SUMMARY+="\n"
        SUMMARY+="Does this look correct?"

        if ! whiptail --title "Confirm Values" --yesno "$SUMMARY" 40 80 2>>"$ERROR_LOG"; then
            echo "User rejected values, returning to editor." >> "$ERROR_LOG"
            continue
        fi

        # Save values to variables.conf
        cat > "$VARS_FILE" << EOF
# Edit the values below for your installation.
# Lines starting with # are comments and ignored.
# Do not add spaces around = signs or remove single quotes.
# Keep values in single quotes to handle special characters.
# Example: LDAP_BIND_PASSWORD_VALUE='0o9i8u7y)O(I*U&Y'
# Save with (escape + :wq or cancel with escape + :q!) in vi.

#general-settings
OGS_DOMAIN_NAME='$OGS_DOMAIN_NAME'
#Nifi-specific
NIFI_DOMAIN_FQDN='$NIFI_DOMAIN_FQDN'
#Nifi username
SINGLE_USER_CREDENTIALS_USERNAME='$SINGLE_USER_CREDENTIALS_USERNAME'
#Nifi pw has to be strong and at least 12 chars log
SINGLE_USER_CREDENTIALS_PASSWORD='$SINGLE_USER_CREDENTIALS_PASSWORD'

EOF
        echo "Saved values to $VARS_FILE" >> "$ERROR_LOG"

        # Export variables without modification
        export OGS_DOMAIN_NAME
        #nifi stuff
        export NIFI_DOMAIN_FQDN
        export SINGLE_USER_CREDENTIALS_USERNAME
	export SINGLE_USER_CREDENTIALS_PASSWORD
	# Exit the loop if user confirms
        break
    done
}




# ---------- Privileged Functions (run as root) ----------


rename_ssl() {
 local fqdn="$1"
 local dir="${2:-.}"

 # Check if fqdn is provided
 if [[ -z "$fqdn" ]]; then
 echo "ERROR: fqdn must be provided" >&2
 return 1
 fi

 # Check if the directory exists
 if [[ ! -d "$dir" ]]; then
 echo "ERROR: Directory '$dir' does not exist" >&2
 return 1
 fi

 # Normalize directory path to remove trailing slash
 dir="${dir%/}"

 # Initialize a flag to track if any files were found
 local files_found=false

 # Escape dots in fqdn for proper pattern matching
 local escaped_fqdn
 escaped_fqdn=$(echo "$fqdn" | sed 's/\./\\./g')

 # Use find to locate files matching the pattern
 echo "INFO: Renaming SSL files for '$fqdn' in '$dir'"
 while IFS= read -r file; do
 if [[ -f "$file" ]]; then
 local ext="${file##*.}"
 mv "$file" "$dir/ssl.$ext"
 echo "SUCCESS: Renamed $file to ssl.$ext"
 files_found=true
 fi
 done < <(find "$dir" -maxdepth 1 -type f -name "$escaped_fqdn.*")

 # Check if no files were found and print a warning
 if [[ "$files_found" == false ]]; then
 echo "WARNING: No files matching '$fqdn.*' were found in '$dir'"
 echo "INFO: Debug: Directory contents:"
 ls -l "$dir"
 return 1
 fi
 echo "SUCCESS: SSL file renaming completed"
}


generate_ssl_keys() {
 cd /mission-share/vast-ca/
 echo "INFO: Creating SSL certificates"

 #hostname -i | tr ' ' '\n' | sort | uniq
 #echo "INFO: Please enter msnsvr IP address:"
 #read -r msnsvr_ip
 #echo "INFO: You entered: $msnsvr_ip"
 msnsvr_ip=$LISTEN_IP_ADDRESS

 #hostname
 #echo "INFO: Please enter msnsvr FQDN (e.g. msnsvr.army.local):"
 #read -r msnsvr_fqdn
 #echo "INFO: You entered: $msnsvr_fqdn"
 msnsvr_fqdn=$NIFI_DOMAIN_FQDN

 #cat /etc/resolv.conf
 #echo "INFO: Please enter domain name (e.g. army.local):"
 #read -r domain
 #echo "INFO: You entered: $domain"
 domain=$OGS_DOMAIN_NAME
 #used by nginx template
 echo "DOMAIN=$domain" > /mission-share/podman/containers/keys/DOMAIN
 mkdir -p /mission-share/.tmp
 local temp_file=$(mktemp)
 echo "$msnsvr_ip $msnsvr_fqdn msnsvr grafana loki mimir nifi.$domain" > "$temp_file"
 echo "INFO: Updating /etc/hosts with msnsvr details"
 if echo "$SUDO_PASSWORD" | sudo -S sh -c "cat '$temp_file' >> /etc/hosts" 2>/dev/null; then
  echo "SUCCESS: Updated /etc/hosts"
 else
  echo "ERROR: Failed to update /etc/hosts" >&2
  rm -f "$temp_file"
  return 1
 fi
 rm -f "$temp_file"

 clear
 # Creating Nifi Certs
 echo "INFO: Creating Nifi certificates"
 printf "$NIFI_DOMAIN_FQDN\n\msnsvr.$OGS_DOMAIN_NAME\n\nUS\nMaryland\nAPG\nFII\n3650\nsilkwave\n" | ./server-cert-gen.sh /mission-share/podman/containers/keys/nifi/
 if rename_ssl "$NIFI_DOMAIN_FQDN" "/mission-share/podman/containers/keys/nifi/"; then
 podman unshare chmod 0644 /mission-share/podman/containers/keys/nifi/ssl.*
 echo "SUCCESS: Nifi certificates created and renamed"
 else
 echo "ERROR: Failed to create or rename Nifi certificates" >&2
 return 1
 fi
 
 clear
 # Creating NGINX proxy certs
 #  ?? maybe we should instead use the nifi certs above? can nginx access them?
 echo "INFO: Creating NGINX proxy certificates"
 printf "$NIFI_DOMAIN_FQDN\n\\$OGS_DOMAIN_NAME\n\nUS\nMaryland\nAPG\nFII\n3650\nsilkwave\n" | ./server-cert-gen.sh /mission-share/podman/containers/keys/nginx/
 if rename_ssl "$NIFI_DOMAIN_FQDN" "/mission-share/podman/containers/keys/nginx/"; then
  echo "INFO: Copying NGINX certificates to /etc/pki/tls"
  if run_with_sudo cp -v /mission-share/podman/containers/keys/nginx/ssl.* /etc/pki/tls/; then
  echo "SUCCESS: NGINX certificates copied to /etc/pki/tls"
 else
  echo "ERROR: Failed to copy NGINX certificates to /etc/pki/tls" >&2
  return 1
 fi

 # copy the dod ca
 cd $OLDPWD
  echo "INFO: Copying DOD CA  certificates to /etc/pki/ca-trust/extracted/pem"
  if run_with_sudo cp -v DOD_certs/DOD_CAs.pem /etc/pki/ca-trust/extracted/pem/; then
   echo "SUCCESS: DOD CA certificates copied to /etc/pki/ca-trust/extracted/pem/"
  else
   echo "ERROR: Failed to copy DOD CA certificates to /etc/pki/ca-trust/extracted/pem/" >&2
   return 1
  fi

 echo "INFO: Fixing SELinux context on NGINX keys"
 run_with_sudo semanage fcontext -a -t cert_t "/etc/pki/tls/ssl.crt"
 run_with_sudo semanage fcontext -a -t cert_t "/etc/pki/tls/ssl.key"
 run_with_sudo semanage fcontext -a -t cert_t "/etc/pki/ca-trust/extracted/pem/DOD_CAs.pem"
 run_with_sudo restorecon -v -F "/etc/pki/tls/ssl.crt"
 run_with_sudo restorecon -v -F "/etc/pki/tls/ssl.key"
 run_with_sudo restorecon -v -F "/etc/pki/ca-trust/extracted/pem/DOD_CAs.pem"
 run_with_sudo chmod 0444 "/etc/pki/ca-trust/extracted/pem/DOD_CAs.pem"

 echo "SUCCESS: SELinux context fixed for NGINX keys"
 else
 echo "ERROR: Failed to create or rename NGINX certificates" >&2
 return 1
 fi

 #cd "$OLDPWD"
 echo "SUCCESS: SSL certificate generation completed"
}

append_to_fstab() {
 local fstab_line="$1"
 if run_with_sudo grep -q "/mission-share" /etc/fstab; then
    echo "WARNING: /mission-share already exists in /etc/fstab. Please check manually."
 else
    # Create a temporary file with the fstab line
    local temp_file=$(mktemp)
    echo "$fstab_line" > "$temp_file"

    # Use sudo to append the temporary file to /etc/fstab
    echo "INFO: Appending to /etc/fstab"
    if echo "$SUDO_PASSWORD" | sudo -S sh -c "cat '$temp_file' >> /etc/fstab" 2>/dev/null; then
        echo "SUCCESS: Appended to /etc/fstab"
        echo "INFO: Reloading systemctl"
        if run_with_sudo systemctl daemon-reload; then
            echo "SUCCESS: Systemctl reloaded"
        else
            echo "ERROR: Failed to reload systemctl" >&2
        return 1
        fi
    else
        echo "ERROR: Failed to append to /etc/fstab" >&2
        rm -f "$temp_file"
        return 1
    fi

    # Clean up the temporary file
    rm -f "$temp_file"

    # Verify the fstab syntax
    echo "INFO: Verifying fstab syntax"
    if run_with_sudo mount -a >/dev/null 2>&1; then
        echo "SUCCESS: fstab syntax is valid"
    else
        echo "ERROR: Invalid fstab entry detected. Restoring backup" >&2

        if run_with_sudo cp /etc/fstab.bak /etc/fstab 2>/dev/null; then
            echo "SUCCESS: Restored /etc/fstab from backup"
        else
            echo "ERROR: Failed to restore /etc/fstab from backup" >&2
            return 1
        fi
            return 1
    fi
 fi
}

configure_system_settings() {
 echo "INFO: Configuring system settings"

 safe_modify "/etc/sysctl.d/99-sysctl.conf" \
 "run_with_sudo sed -i 's/^user\.max_user_namespaces=0/user.max_user_namespaces=9999/' /etc/sysctl.d/99-sysctl.conf" \
 "Modifying user.max_user_namespaces setting"

 safe_modify "/usr/share/rhel/secrets/rhsm/syspurpose/syspurpose.json" \
 "run_with_sudo chmod 0644 /usr/share/rhel/secrets/rhsm/syspurpose/syspurpose.json" \
 "Setting permissions for syspurpose.json"

 safe_modify "/etc/yum.repos.d/redhat.repo" \
 "run_with_sudo chmod 0644 /etc/yum.repos.d/redhat.repo" \
 "Setting permissions for redhat.repo"

    echo "INFO: Checking permissions on system files"
    if check_permission "/usr/share/rhel/secrets/rhsm/syspurpose/syspurpose.json" "644" && \
        check_permission "/etc/yum.repos.d/redhat.repo" "644"; then
        echo "SUCCESS: System file permissions verified"
    else
        echo "ERROR: System file permission checks failed" >&2
        return 1
    fi


 # Apply sysctl changes immediately
 echo "INFO: Applying sysctl changes"
 if run_with_sudo sysctl -p /etc/sysctl.d/99-sysctl.conf | grep -q 'user.max_user_namespaces = 9999'; then
    echo "SUCCESS: Sysctl changes applied"
 else
    echo "ERROR: Failed to apply sysctl changes" >&2
    return 1
 fi

 # Verify the setting was applied
 echo "INFO: Verifying sysctl settings"
 run_with_sudo sysctl -a | grep user.max_user_namespaces
 echo "SUCCESS: Sysctl settings verified"

 # Change podman image storage location
 echo "INFO: Setting podman image location"
 mkdir -p ~/.config/containers 2>/dev/null
 if cat configs/storage.conf > ~/.config/containers/storage.conf; then
    echo "SUCCESS: Overwrote ~/.config/containers/storage.conf"
 else
    echo "ERROR: Failed to overwrite ~/.config/containers/storage.conf" >&2
    return 1
 fi

 # Make pods run without active session
 echo "INFO: Enabling linger for user $USER"
 if loginctl enable-linger; then
    echo "SUCCESS: Linger enabled for user $USER"
 else
    echo "ERROR: Failed to enable linger for user $USER" >&2
    return 1
 fi

    #in order for podman image imports to work without the box halting, relax the auditd a little
    echo "INFO: fixing auditd to be leanient on podman"
    run_with_sudo cp configs/99-podman-load.rules /etc/audit/rules.d/
    echo "INFO: regenerating rules"
    run_with_sudo augenrules
    #this system has duplicated rules, which prevents it from loading, so be nice and filter them out of the final results
    #too bad augenrules does do this
    echo "INFO: backing up rules, and removing duplicate rules"
    run_with_sudo awk '!seen[$0]++' /etc/audit/audit.rules > audit.rules.fixed
    run_with_sudo cp -f /etc/audit/audit.rules audit.rules.orig
    run_with_sudo cp -f audit.rules.fixed /etc/audit/audit.rules
    #now load the rules, which should not log podman stuff, and not have duplicates
    echo "INFO: loading new ruleset"
    run_with_sudo augenrules --load
    #check for rule insertion



echo "SUCCESS: System settings configured"
}

provision_disk() {
 echo "INFO: Disk provisioning"

    list_available_disks() {
    # Get all disks (excluding CD-ROM devices)
    local disks=($(run_with_sudo lsblk -d -n -o NAME | grep -v sr))

    if [ ${#disks[@]} -eq 0 ]; then
        echo "ERROR: No disks detected in system" >&2
        return 1
    fi

    local available_disks=()
    for disk in "${disks[@]}"; do
        disk_path="/dev/$disk"

        # Check if disk has no filesystem and no partitions
        if ! run_with_sudo blkid -o device | grep -q "$disk_path" && \
        [ $(run_with_sudo lsblk -n -o TYPE "$disk_path" | grep -c part) -eq 0 ]; then
        available_disks+=("$disk_path")
        fi
    done

    if [ ${#available_disks[@]} -eq 0 ]; then
        echo "ERROR: No eligible disks found (must be unmounted with no filesystem/partitions)" >&2
        return 1
    fi

    # Display disks with numbers and sizes
    echo "INFO: Available disks:"
    for i in "${!available_disks[@]}"; do
        size=$(run_with_sudo lsblk -n -o SIZE "${available_disks[$i]}")
        echo "INFO: $((i+1)). ${available_disks[$i]} (${size})"
    done

    # Export results
    AVAILABLE_DISKS=("${available_disks[@]}")
    export AVAILABLE_DISKS
    return 0
    }

 while true; do
 read -p "INFO: Have you added a virtual disk for podman data? (yes/no) " response
 case $response in
 [yY]|[yY][eE][sS])
 if ! list_available_disks; then
    echo "ERROR: No suitable disks found. Please add a disk and try again" >&2
    return 1
 fi

 while true; do
    read -p "INFO: Select disk number (1-${#AVAILABLE_DISKS[@]}): " disk_num
    if [[ "$disk_num" =~ ^[0-9]+$ ]] && [ "$disk_num" -ge 1 ] && [ "$disk_num" -le ${#AVAILABLE_DISKS[@]} ]; then
        selected_disk="${AVAILABLE_DISKS[$((disk_num-1))]}"
        break
    else
        echo "ERROR: Invalid selection. Please enter a number between 1 and ${#AVAILABLE_DISKS[@]}" >&2
    fi
 done

 echo "INFO: You selected: $selected_disk"
 read -p "INFO: Confirm format with XFS and mount to /mission-share? (yes/no) " confirm
 if [[ "$confirm" =~ [yY]|[yY][eE][sS] ]]; then
    echo "INFO: Creating XFS filesystem on $selected_disk"
 if run_with_sudo mkfs.xfs -f "$selected_disk"; then
    echo "SUCCESS: Created XFS filesystem on $selected_disk"
 else
    echo "ERROR: Failed to create XFS filesystem on $selected_disk" >&2
    return 1
 fi

 echo "INFO: Triggering device rescan to force UUID"
 run_with_sudo udevadm trigger
 sleep 2

 echo "INFO: Creating mount point /mission-share"
 run_with_sudo mkdir -p /mission-share
 run_with_sudo chmod 0777 /mission-share

 echo "INFO: Mounting $selected_disk to /mission-share"
 if run_with_sudo mount "$selected_disk" /mission-share; then
    echo "SUCCESS: Mounted $selected_disk to /mission-share"
 else
    echo "ERROR: Failed to mount $selected_disk to /mission-share" >&2
    return 1
 fi

 run_with_sudo chmod 0777 /mission-share
 echo "INFO: Setting SELinux context for /mission-share"
 run_with_sudo semanage fcontext -a -t container_file_t "/mission-share(/.*)?"
 run_with_sudo restorecon -Rv /mission-share
 echo "SUCCESS: SELinux context set for /mission-share"

 echo "INFO: Creating upload directory"
 mkdir -p /mission-share/upload
 chmod 0777 /mission-share/upload
 echo "SUCCESS: Upload directory created"

 echo "INFO: Initializing podman storage directories"
 podman info >/dev/null
 podman unshare mkdir -p /mission-share/podman/containers
 echo "SUCCESS: Podman storage directories initialized"

 echo "INFO: Adding $selected_disk to /etc/fstab"
 uuid=$(run_with_sudo blkid -s UUID -o value "$selected_disk")
 echo "INFO: UUID found is $uuid"

 if [ -z "$uuid" ]; then
    echo "ERROR: Could not get UUID of $selected_disk" >&2
    return 1
 fi

 fstab_line="UUID=$uuid /mission-share xfs defaults 0 0"
 echo "INFO: fstab entry: $fstab_line"
 if run_with_sudo grep -q "/mission-share" /etc/fstab; then
    echo "WARNING: /mission-share already exists in /etc/fstab. Please check manually."
 else
    run_with_sudo cp /etc/fstab /etc/fstab.bak
    echo "SUCCESS: Backed up /etc/fstab"
    append_to_fstab "$fstab_line"
 fi

 echo "SUCCESS: Disk provisioning completed"
 return 0
 else
    echo "INFO: Operation cancelled"
    return 0
 fi
 ;;
 [nN]|[nN][oO])
 echo "INFO: Skipping disk provisioning"
 return 0
 ;;
 *)
 echo "ERROR: Please answer yes or no" >&2
 ;;
 esac
 done
}

install_nginx() {
 echo "INFO: Installing and configuring Nginx"

 if ! command -v nginx &> /dev/null; then
  echo "INFO: Installing nginx"
  if run_with_sudo dnf install nginx -y; then
   echo "SUCCESS: Nginx installed"
  else
   echo "ERROR: Failed to install nginx, please make sure the system has RHEL repository access configured." >&2
   return 1
  fi
 else
  echo "INFO: Nginx is already installed"
 fi




 #replace the DOMAIN in the nginx.conf template
 echo "substituting domain value in nginx template file"
    if cat configs/nginx.conf.template | \
       sed "s|nifi.DOMAIN|$NIFI_DOMAIN_FQDN|g" > configs/nginx.conf; then
       echo "SUCCESS: Generated nginx.conf"
    else
       echo "ERROR: Failed to create nginx.conf file" >&2
       return 1
    fi

 config_source="configs/nginx.conf"
 config_dest="/etc/nginx/nginx.conf"

 if [ ! -f "$config_source" ]; then
  echo "ERROR: Source config file $config_source not found" >&2
  return 1
 fi


 echo "INFO: Copying Nginx configuration"
 if run_with_sudo cp -vf "$config_source" "$config_dest" && \
 run_with_sudo chmod -v 0644 "/etc/nginx/nginx.conf"; then
    echo "SUCCESS: Nginx configuration and files copied"
    else
    echo "ERROR: Failed to copy Nginx configuration or files" >&2
    return 1
 fi

 run_with_sudo chmod -v 644 "$config_dest"
 echo "SUCCESS: Nginx configuration permissions set"

 configure_selinux

 echo "INFO: Enabling and starting Nginx service"
 if run_with_sudo systemctl enable nginx && run_with_sudo systemctl restart nginx; then
    echo "SUCCESS: Nginx service enabled and started"
    else
    echo "ERROR: Failed to enable or start Nginx service" >&2
    return 1
 fi

 echo "SUCCESS: Nginx configuration completed"
}

configure_selinux() {
 if command -v getenforce &> /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
 echo "INFO: Configuring SELinux for Nginx proxy"

 if run_with_sudo setsebool -P httpd_can_network_connect 1; then
 echo "SUCCESS: SELinux boolean set"
 else
 echo "ERROR: Failed to set SELinux boolean" >&2
 return 1
 fi

 for port in 8443; do
 if ! run_with_sudo semanage port -l | grep -q "http_port_t.*tcp.*${port}"; then
 echo "INFO: Adding SELinux exception for port $port"
 if run_with_sudo semanage port -a -t http_port_t -p tcp ${port} 2>/dev/null; then
 echo "SUCCESS: SELinux port $port added"
 else
 echo "WARNING: Failed to add SELinux port $port. May need to install policycoreutils-python-utils"
 fi
 else
 echo "INFO: SELinux port $port already configured"
 fi
 done

 echo "SUCCESS: SELinux configuration completed"
 else
 echo "INFO: SELinux is not enforcing, skipping configuration"
 fi
}

configure_firewall() {
 echo "INFO: Configuring firewall"

 if ! command -v firewall-cmd &> /dev/null; then
 echo "WARNING: firewalld is not installed. Skipping firewall configuration"
 return 0
 fi

 if ! systemctl is-active --quiet firewalld; then
 echo "INFO: Starting firewalld"
 if run_with_sudo systemctl start firewalld; then
 echo "SUCCESS: Firewalld started"
 else
 echo "ERROR: Failed to start firewalld" >&2
 return 1
 fi
 fi

 declare -A PORTS=(
 ["HTTP"]="80/tcp"
 ["HTTPs"]="443/tcp"
 ["Nifi-ssl"]="8443/tcp"
 )

 for service in "${!PORTS[@]}"; do
 port=${PORTS[$service]}
 if ! run_with_sudo firewall-cmd --query-port="$port" | grep -q "yes"; then
 echo "INFO: Opening port $port for $service"
 if run_with_sudo firewall-cmd --permanent --add-port="$port"; then
 echo "SUCCESS: Port $port opened for $service"
 else
 echo "ERROR: Failed to open port $port for $service" >&2
 return 1
 fi
 else
 echo "INFO: Port $port for $service is already configured"
 fi
 done

 echo "INFO: Reloading firewalld"
 if run_with_sudo firewall-cmd --reload; then
 echo "SUCCESS: Firewalld reloaded"
 else
 echo "ERROR: Failed to reload firewalld" >&2
 return 1
 fi

 echo "SUCCESS: Firewall configuration completed"
}

empty_firewall_rules() {
 echo "INFO: Removing firewall rules"

 if ! command -v firewall-cmd &> /dev/null; then
 echo "WARNING: firewalld is not installed. Skipping firewall configuration"
 return 0
 fi

 if ! systemctl is-active --quiet firewalld; then
 echo "INFO: Starting firewalld"
 if run_with_sudo systemctl start firewalld; then
 echo "SUCCESS: Firewalld started"
 else
 echo "ERROR: Failed to start firewalld" >&2
 return 1
 fi
 fi

 declare -A PORTS=(
 ["HTTP"]="80/tcp"
 ["HTTPs"]="443/tcp"
 ["Nifi-ssl"]="8443/tcp"
 )

 for service in "${!PORTS[@]}"; do
 port=${PORTS[$service]}
 if run_with_sudo firewall-cmd --query-port="$port" | grep -q "yes"; then
    echo "INFO: Removing port $port for $service"
    if run_with_sudo firewall-cmd --permanent --remove-port="$port"; then
        echo "SUCCESS: Port $port close for $service"
    else
        echo "ERROR: Failed to close port $port for $service" >&2
        return 1
    fi
 else
    echo "INFO: Port $port for $service was not already configured"
 fi
 done

 echo "INFO: Reloading firewalld"
 if run_with_sudo firewall-cmd --reload; then
 echo "SUCCESS: Firewalld reloaded"
 else
 echo "ERROR: Failed to reload firewalld" >&2
 return 1
 fi

 echo "SUCCESS: Firewall rule removal process completed"
}


pull_container_images() {
 echo "INFO: Pulling container images"

 if [ ! -f "versions.txt" ]; then
 echo "ERROR: versions.txt file not found" >&2
 return 1
 fi

 if [ $(grep -c /mission-share /etc/mtab) -eq 0 ]; then
 echo "ERROR: Please add the 2nd disk and run the mount option in this script first" >&2
 return 1
 fi

 # Login to registry
 echo "INFO: Logging into registry1.dso.mil"
 if podman login -u Brian_Bowen -p '1q2w3e4r!Q@W#E$R' registry1.dso.mil; then
 echo "SUCCESS: Logged into registry1.dso.mil"
 else
 echo "ERROR: Failed to log into registry1.dso.mil" >&2
 return 1
 fi

 # Load versions
 . versions.txt


 # Pull and tag Nifi
 echo "INFO: Downloading nifi version ${NIFI_VERSION}"
# if podman pull docker.io/phatblinkie/bigimage:tsb_py && \
  if podman pull "$NIFI_URL" && \
podman image tag nifi:${NIFI_VERSION} nifi-custom:${NIFI_VERSION}; then
 echo "SUCCESS: Nifi image pulled and tagged"
 else
 echo "ERROR: Failed to pull or tag Nifi image" >&2
 return 1
 fi

 echo "INFO: Listing custom images"
 podman images | egrep "custom|TAG"
 echo "SUCCESS: Image download process completed"
}

split_large_files() {
 local dir="${1:-.}"

 # Check if the directory exists
 if [[ ! -d "$dir" ]]; then
 echo "ERROR: Directory '$dir' does not exist" >&2
 return 1
 fi

 # Size threshold (.5GB in bytes)
 local threshold=$((500 * 1024 * 1024))

 # Find files larger than .5GB
 echo "INFO: Checking for files larger than 500MB in '$dir'"
 find "$dir" -maxdepth 1 -type f -size +${threshold}c | while IFS= read -r file; do
 local size
 size=$(ls -sh "$file" | awk '{print $1}')
 echo "INFO: Found file: $file ($size), splitting into 500MB chunks"
 if split --verbose -b 500m "$file" "${file}.part."; then
 echo "SUCCESS: Split $file into chunks"
 ls -lh "${file}.part."*
 else
 echo "ERROR: Failed to split $file" >&2
 return 1
 fi
 done
 echo "SUCCESS: File splitting process completed"
}

reassemble_files() {
 local dir="${1:-.}"

 # Check if the directory exists
 if [[ ! -d "$dir" ]]; then
 echo "ERROR: Directory '$dir' does not exist" >&2
 return 1
 fi

 # Normalize directory path to remove trailing slash
 dir="${dir%/}"

 # Initialize a flag to track if any files were reassembled
 local files_reassembled=false

 # Find unique base filenames from split parts
 echo "INFO: Checking for split files in '$dir'"
 find "$dir" -maxdepth 1 -type f -name '*.part.*' | sed 's/\.part\.[a-z]\+$//' | sort -u | while IFS= read -r base_file; do
 if [[ -f "$base_file" ]]; then
 echo "WARNING: Original file '$base_file' already exists. Skipping reassembly"
 continue
 fi

 local parts
 parts=$(find "$dir" -maxdepth 1 -type f -name "${base_file##*/}.part.*" | sort)

 if [[ -z "$parts" ]]; then
 echo "WARNING: No split parts found for '$base_file'"
 continue
 fi

 echo "INFO: Reassembling '$base_file' from parts:"
 echo "$parts" | while IFS= read -r part; do
 echo "INFO: $part"
 done

 if cat $parts > "$base_file"; then
 echo "SUCCESS: Reassembled '$base_file'"
 ls -lh "$base_file"
 rm "${base_file}.part."*
 echo "SUCCESS: Deleted split parts for '$base_file'"
 files_reassembled=true
 else
 echo "ERROR: Failed to reassemble '$base_file'" >&2
 return 1
 fi
 done

 if [[ "$files_reassembled" == false ]]; then
 echo "INFO: No files needed reassembly"
 fi
 echo "SUCCESS: File reassembly process completed"
}

install_tarball_images() {
 echo "INFO: Installing tarball container images"

 echo "INFO: Copying repo images to /mission-share/upload"
 if rsync -avh --progress upload_contents_to_mission-share_upload_dir/* /mission-share/upload/; then
 echo "SUCCESS: Copied images to /mission-share/upload"
 else
 echo "ERROR: Failed to copy images to /mission-share/upload" >&2
 return 1
 fi

 echo "INFO: Checking file integrity"
 if sha1sum -c --ignore-missing /mission-share/upload/sha1sum.txt; then
 echo "SUCCESS: File integrity check passed"
 else
 echo "ERROR: SHA1 checksum verification failed. Please check the uploaded files" >&2
 return 1
 fi

 echo "INFO: Reassembling split files if needed"
 if reassemble_files "/mission-share/upload"; then
 echo "SUCCESS: Reassembly completed"
 else
 echo "ERROR: Failed to reassemble split files" >&2
 return 1
 fi

 echo "INFO: Performing second integrity check"
 if sha1sum -c /mission-share/upload/sha1sum-after-assembly.txt; then
 echo "SUCCESS: Second integrity check passed"
 else
 echo "ERROR: SHA1 checksum verification after reassembly failed" >&2
 return 1
 fi

 echo "INFO: Importing tarball container images"
 for i in $(ls /mission-share/upload/*.tar.gz | grep -v part); do
 echo "INFO: Importing container image: $i"
 mkdir -p /mission-share/.tmp >/dev/null

 # Load versions
 . versions.txt

 if export TMPDIR=/mission-share/.tmp && podman load -i "$i" | awk '{print $3}' | xargs -I{} podman tag {} $NIFI_IMAGENAME:${NIFI_VERSION}; then
 echo "SUCCESS: Imported container image $i"
 echo "SUCCESS: Tagged imported image to name $NIFI_IMAGENAME:$NIFI_VERSION"
 else
 echo "ERROR: Failed to import container image $i" >&2
 return 1
 fi
 done
#export TMPDIR=/mission-share/.tmp && podman load -i /mission-share/upload/nifi-1.24-py.tar.gz | awk '{print $3}' | xargs -I{} podman tag {} test:latest

 # Load versions
# . versions.txt

  # tag Nifi
# echo "INFO: tagging tarball import to nifi version ${NIFI_VERSION}"
# if podman pull docker.io/phatblinkie/bigimage:tsb_py && \
#  if podman image tag nifi:${NIFI_VERSION} nifi-custom:${NIFI_VERSION}; then
# echo "SUCCESS: Nifi image pulled and tagged"
# else
# echo "ERROR: Failed to pull or tag Nifi image" >&2
# return 1
# fi

 echo "SUCCESS: Tarball image installation completed"

}

copy_source_directories() {
    echo "INFO: Copying source directories to /mission-share/"

    if ! command -v rsync &> /dev/null; then
        echo "ERROR: rsync is required but not installed. Please install it first" >&2
        return 1
    fi

    path="/mission-share/podman/containers"
    rootpath="/mission-share"
    podmanshare="/mission-share/podman"



    echo "INFO: Creating TMPDIR"
    mkdir $rootpath/.tmp
    echo "INFO: Creating container storage folders"
    run_with_sudo chcon -t -R container_file_t $podmanshare
    echo "SUCCESS: SELinux context set for $podmanshare"

    echo "INFO: Making needed directories"
    if podman unshare mkdir -vp "$path/nifi" \
          "$path/keys/"{nginx,nifi} \
          "$rootpath/tide/"{out,in,ccads-in,ccads-out,arc-out,fuse-out,sceptre-in,sceptre-out,esa-out,eped-out,fail,tmp,save,idm-in/save} \
          "$rootpath/audit_logs" \
	  "$rootpath/sar"; then
        echo "SUCCESS: Directories created"
        echo -e "\n\n-----> WARNING:    /SAR-NFS-REMOTE-SITE was not tested, as this should be already created and is outside of /mission-share\n\n"
   else
        echo "ERROR: Failed to create directories" >&2
        return 1
    fi

#    echo "INFO: Copying configuration files"
#    if podman unshare cp -v configs/* $path/configs/ && \
#       podman unshare chmod 0644 $path/configs/*; then
#        echo "SUCCESS: Configuration files copied and permissions set"
#    else
#        echo "ERROR: Failed to copy configuration files or set permissions" >&2
#        return 1
#    fi

    echo "INFO: Copying vast-ca and tools to new location"
    if podman unshare rsync -ah vast-ca $rootpath/ && \
       podman unshare rsync -ah tools $rootpath/; then
        echo "SUCCESS: Copied vast-ca and tools"
    else
        echo "ERROR: Failed to copy vast-ca or tools" >&2
        return 1
    fi
	
    echo "INFO: Copying zfts to new location"
    if podman unshare rsync -ah zfts $rootpath/ ; then
        echo "SUCCESS: Copied zfts"
    else
        echo "ERROR: Failed to copy zfts" >&2
        return 1
    fi


#    echo "INFO: Copying nifi/conf to new location"
#    if podman unshare rsync -ah nifi/conf/* $path/nifi/conf/ ; then
#        echo "SUCCESS: Copied nifi/conf/* files"
#    else
#        echo "ERROR: Failed to copy nifi/conf/* files" >&2
#        return 1
#    fi

#    echo "INFO: Setting permissions on tide directories"
#    if podman unshare chmod -R 777 $rootpath/tide; then
#        echo "SUCCESS: Permissions set on tide directories"
#    else
#        echo "ERROR: Failed to set permissions on tide directories" >&2
#        return 1
#    fi


#    echo "INFO: Setting permissions on nifi config filess"
#    if podman unshare chmod 666 $path/nifi/conf/nifi.properties $path/nifi/conf/login-identity-providers.xml  $path/nifi/conf/keystore.p12; then
#        echo "SUCCESS: Permissions set on nifi.properties"
#    else
#        echo "ERROR: Failed to set permissions on nifi.properties" >&2
#        return 1
#    fi


#    echo "INFO: Copying Nifi configuration files to $path/nifi"
#    if podman unshare rsync -avh nifi/ $path/nifi/; then
#        echo "SUCCESS: Nifi configuration files copied"
#    else
#        echo "ERROR: Failed to copy Nifi configuration files" >&2
#        return 1
#    fi


    echo "SUCCESS: Source directory copying completed"
}

# Function to validate an IP address
validate_ip() {
    local ip=$1
    # Regex for IPv4 address
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 || $octet -lt 0 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to get unique non-loopback IPv4 addresses
get_ip_addresses() {
    # Use 'ip addr show' to list IP addresses, filter for inet, exclude loopback (127.0.0.1)
    ip addr show | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | grep -v '^127\.' | sort -u
}


build_and_start_pod() {
    echo "INFO: Building and starting NIFI pod"

    podmanshare="/mission-share/podman"
    echo "INFO: Setting SELinux context for $podmanshare"
    if run_with_sudo chcon -t container_file_t -R $podmanshare; then
        echo "SUCCESS: SELinux context set for $podmanshare"
    else
        echo "ERROR: Failed to set SELinux context for $podmanshare"
        return 1
    fi

    if run_with_sudo restorecon -R $podmanshare; then
	echo "SUCCESS: SELinux restored context for $podmanshare"
    else
        echo "ERROR: Failed to set SELinux context for $podmanshare"
        return 1
    fi



    echo "INFO: Stopping NIFI pod if running - in case we need to replace it, has to be stopped"
    if podman pod stop -t 60 nifi 2>/dev/null; then
        echo "SUCCESS: NIFI pod stopped or not running"
    else
        echo "INFO: NIFI pod was not running or stop command ignored"
    fi

#    echo "INFO: Setting permissions on container directories"
#    if podman unshare chmod -v 0777 /mission-share/podman/containers/{nifi,nifi/*}; then
#        echo "SUCCESS: Container directory permissions set"
#    else
#        echo "ERROR: Failed to set container directory permissions" >&2
#        return 1
#    fi

    echo "INFO: Loading versions from versions.txt"
    if . versions.txt; then
        echo "SUCCESS: Versions loaded"
    else
        echo "ERROR: Failed to load versions.txt" >&2
        return 1
    fi

    echo "INFO: Generating new pod YAML from template"
    cd nifi-pod || { echo "ERROR: Failed to change to nifi-pod directory" >&2; return 1; }
    if cat nifi-pod.yml.template | \
       sed "s|NIFI_FQDN_NAME|$NIFI_DOMAIN_FQDN|g" |\
       sed "s|SINGLE_USER_CREDENTIALS_USERNAME_VALUE|$SINGLE_USER_CREDENTIALS_USERNAME|g" |\
       sed "s|SINGLE_USER_CREDENTIALS_PASSWORD_VALUE|$SINGLE_USER_CREDENTIALS_PASSWORD|g" |\
       sed "s|NIFI_IMAGENAME|$NIFI_IMAGENAME|g" |\
       sed "s|NIFI_VERSION|$NIFI_VERSION|g" > nifi-pod.yml; then
        echo "SUCCESS: Generated NIFI pod YAML"
	echo "---> credentials of user:$SINGLE_USER_CREDENTIALS_USERNAME, pw:$SINGLE_USER_CREDENTIALS_PASSWORD"
	echo "---> image name: $NIFI_IMAGENAME, image version: $NIFI_VERSION"
    else
        echo "ERROR: Failed to generate NIFI pod YAML" >&2
        return 1
    fi

    echo "INFO: Creating Systemd directories"
    if mkdir -p ~/.config/containers/systemd ~/.config/systemd/user; then
        echo "SUCCESS: Systemd directories created"
    else
        echo "ERROR: Failed to create Systemd directories" >&2
        return 1
    fi

    echo "INFO: Copying pod yml file"
    if podman unshare cp -vf nifi-pod.yml /mission-share/podman/containers/nifi-pod.yml; then
        echo "SUCCESS: pod yml file copied to /mission-share/podman/containers/nifi-pod.yml"
    else
        echo "ERROR: Failed to copy pod yml file" >&2
        return 1
    fi

    echo "INFO: Starting initial NIFI pod"
    if podman kube play --replace --userns=keep-id /mission-share/podman/containers/nifi-pod.yml; then
        echo "SUCCESS: Initial NIFI pod started"
    else
        echo "ERROR: Failed to start initial NIFI pod" >&2
        return 1
    fi

    echo "INFO: Generating systemd service files for NIFI pod"
    if podman generate systemd --name --files nifi && \
       mv -fv *.service ~/.config/systemd/user/; then
        echo "SUCCESS: Systemd service files generated and moved"
    else
        echo "ERROR: Failed to generate or move systemd service files" >&2
        return 1
    fi

    echo "INFO: Reloading systemd user daemon"
    if systemctl --user daemon-reload; then
        echo "SUCCESS: Systemd user daemon reloaded"
    else
        echo "ERROR: Failed to reload systemd user daemon" >&2
        return 1
    fi

    echo "INFO: Stopping existing NIFI pod if running - so we can start it with systemctl"
    if podman pod stop -t 60 nifi 2>/dev/null; then
        echo "SUCCESS: Existing NIFI pod stopped or not running"
    else
        echo "INFO: No NIFI pod was running or stop command ignored"
    fi

    echo "INFO: Enabling and starting pod-nifi.service"
    if systemctl --user enable --now pod-nifi.service; then
        echo "SUCCESS: pod-nifi.service enabled and started"
    else
        echo "ERROR: Failed to enable or start pod-nifi.service" >&2
        return 1
    fi

    sleep 3
    echo "INFO: Listing all containers"
    podman ps -a -p
    echo "SUCCESS: NIFI pod created and started"


    echo "INFO: Enabling linger for user $USER"
    if loginctl enable-linger; then
        echo "SUCCESS: Linger enabled for user $USER"
    else
        echo "ERROR: Failed to enable linger for user $USER" >&2
        return 1
    fi

    echo "SUCCESS: NIFI pod deployment completed"
    echo "INFO:   NIFI services available:"
    echo "INFO: - Nifi on ports 8443"
    echo "INFO: - Parent NGINX proxy on ports 80 and 443"
    echo "INFO: - initial login username $SINGLE_USER_CREDENTIALS_USERNAME"
    echo "INFO: - initial login password $SINGLE_USER_CREDENTIALS_PASSWORD"
    cd "$OLDPWD"
}

# ---------- Helper Functions ----------

check_permission() {
    local file="$1"
    local expected_perm="$2"
    local actual_perm=$(stat -c "%a" "$file" 2>/dev/null)

    if [[ "$actual_perm" != "$expected_perm" ]]; then
        echo "ERROR: $file has permissions $actual_perm (expected $expected_perm)" >&2
        echo "INFO: Please run the system configuration first or manually fix with:" >&2
        echo "sudo chmod $expected_perm $file" >&2
        return 1
    fi
    echo "SUCCESS: $file permissions verified as $expected_perm"
    return 0
}

safe_modify() {
    local file="$1"
    local action="$2"
    local description="$3"

    echo -n "INFO: ${description}... "
    if [ -f "$file" ]; then
        if eval "$action"; then
            echo "SUCCESS: ${description} completed"
        else
            echo "ERROR: Failed to ${description}" >&2
            return 1
        fi
    else
        echo "INFO: Skipped (file not found)"
    fi
}

check_success() {
    if [ $? -ne 0 ]; then
        echo "ERROR: $1" >&2
        return 1
    fi
    echo "SUCCESS: $1 completed"
}

# ---------- Pod Management Functions ----------

stop_pod_named() {
    local podname="$1"

    # Sanity check: Ensure podname is not empty
    if [[ -z "$podname" ]]; then
        echo "ERROR: No pod name provided to stop_pod_named" >&2
        return 1
    fi

    echo "INFO: Checking if pod '$podname' exists"
    if ! podman pod exists "$podname" &>/dev/null; then
        echo "ERROR: Pod '$podname' does not exist" >&2
        return 1
    fi

    echo "INFO: Stopping pod '$podname' with 'podman pod stop -t 60 $podname'"
    if ! podman pod stop -t 60 "$podname" &>/dev/null; then
        echo "ERROR: Failed to stop pod '$podname'" >&2
        return 1
    fi

    echo "SUCCESS: Pod '$podname' stopped successfully"
    return 0
}

stop_and_delete_pod() {
    local podname="$1"

    # Sanity check: Ensure podname is not empty
    if [[ -z "$podname" ]]; then
        echo "ERROR: No pod name provided to stop_and_delete_pod" >&2
        return 1
    fi

    echo "INFO: Beginning stop and delete process for pod '$podname'"

    # Check if the pod-$podname service exists
    echo "INFO: Checking if 'pod-$podname' service exists"
    if ! systemctl --user list-units --type=service --all | grep -q "pod-$podname"; then
        echo "INFO: 'pod-$podname' service does not exist, proceeding to podman operations"
    else
        # Check if the pod-$podname service is active
        echo "INFO: Checking if 'pod-$podname' service is active"
        if systemctl --user is-active --quiet "pod-$podname"; then
            echo "INFO: 'pod-$podname' service is active, stopping with 'systemctl --user stop pod-$podname'"
            if ! systemctl --user stop "pod-$podname"; then
                echo "ERROR: Failed to stop 'pod-$podname' service" >&2
                return 1
            fi
            echo "SUCCESS: 'pod-$podname' service stopped successfully"
        else
            echo "INFO: 'pod-$podname' service is not active"
        fi

        # Disable the pod-$podname service
        echo "INFO: Disabling 'pod-$podname' service with 'systemctl --user disable pod-$podname'"
        if ! systemctl --user disable "pod-$podname" &>/dev/null; then
            echo "ERROR: Failed to disable 'pod-$podname' service" >&2
            return 1
        fi
        echo "SUCCESS: 'pod-$podname' service disabled successfully"
    fi

    # Stop the pod
    if ! stop_pod_named "$podname"; then
        echo "ERROR: Failed to stop pod '$podname'" >&2
        return 1
    fi

    # Delete the pod
    echo "INFO: Deleting pod '$podname' with 'podman pod rm --force $podname'"
    if ! podman pod rm --force "$podname" &>/dev/null; then
        echo "ERROR: Failed to delete pod '$podname'" >&2
        return 1
    fi

    echo "SUCCESS: Pod '$podname' deleted successfully"

    echo
    echo
    read -p "INFO: Confirm you wish to delete the data from pod: $podname (yes/no) " confirm
    if [[ "$confirm" =~ [yY]|[yY][eE][sS] ]]; then
        echo "INFO: Removing Container files for pod named: $podname"
        if [ "$podname" == "ogs" ]; then
            deletepath="/mission-share/podman/containers/$podname-pod.yml
            /mission-share/podman/containers/$podname"
        fi
        #run the delete commands with deletepath variable data
        echo "Standby, this could take a minute"
        #if run_with_sudo rm -rf "$deletepath"; then
        for i in `echo -e $deletepath`; do
            if run_with_sudo rm -rf "$i"; then
                echo "SUCCESS: Removed files on path $deletepath"
            else
                echo "ERROR: Failed to Remove files on path $deletepath" >&2
                return 1
            fi
        done

    else
        echo -e "\nSkipping file deletion sequence\n"
    fi
    return 0
}

stop_and_delete_pod_auto() {
    local podname="$1"

    # Sanity check: Ensure podname is not empty
    if [[ -z "$podname" ]]; then
        echo "ERROR: No pod name provided to stop_and_delete_pod" >&2
        return 1
    fi

    echo "INFO: Beginning stop and delete process for pod '$podname'"

    # Check if the pod-$podname service exists
    echo "INFO: Checking if 'pod-$podname' service exists"
    if ! systemctl --user list-units --type=service --all | grep -q "pod-$podname"; then
        echo "INFO: 'pod-$podname' service does not exist, proceeding to podman operations"
    else
        # Check if the pod-$podname service is active
        echo "INFO: Checking if 'pod-$podname' service is active"
        if systemctl --user is-active --quiet "pod-$podname"; then
            echo "INFO: 'pod-$podname' service is active, stopping with 'systemctl --user stop pod-$podname'"
            if ! systemctl --user stop "pod-$podname"; then
                echo "ERROR: Failed to stop 'pod-$podname' service" >&2
                return 1
            fi
            echo "SUCCESS: 'pod-$podname' service stopped successfully"
        else
            echo "INFO: 'pod-$podname' service is not active"
        fi

        # Disable the pod-$podname service
        echo "INFO: Disabling 'pod-$podname' service with 'systemctl --user disable pod-$podname'"
        if ! systemctl --user disable "pod-$podname" &>/dev/null; then
            echo "ERROR: Failed to disable 'pod-$podname' service" >&2
            return 1
        fi
        echo "SUCCESS: 'pod-$podname' service disabled successfully"
    fi

    # Stop the pod
    if ! stop_pod_named "$podname"; then
        echo "ERROR: Failed to stop pod '$podname'" >&2
        return 1
    fi

    # Delete the pod
    echo "INFO: Deleting pod '$podname' with 'podman pod rm --force $podname'"
    if ! podman pod rm --force "$podname" &>/dev/null; then
        echo "ERROR: Failed to delete pod '$podname'" >&2
        return 1
    fi

    echo "SUCCESS: Pod '$podname' deleted successfully"

    echo
    echo
    #read -p "INFO: Confirm you wish to delete the data from pod: $podname (yes/no) " confirm
    confirm="yes"
    if [[ "$confirm" =~ [yY]|[yY][eE][sS] ]]; then
        echo "INFO: Removing Container files for pod named: $podname"
        if [ "$podname" == "ogs" ]; then
            deletepath="/mission-share/podman/containers/$podname-pod.yml
            /mission-share/podman/containers/$podname"
        fi
        #run the delete commands with deletepath variable data
        echo "Standby, this could take a minute"
        #if run_with_sudo rm -rf "$deletepath"; then
        for i in `echo -e $deletepath`; do
            if run_with_sudo rm -rf "$i"; then
                echo "SUCCESS: Removed files on path $deletepath"
            else
                echo "ERROR: Failed to Remove files on path $deletepath" >&2
                return 1
            fi
        done

    else
        echo -e "\nSkipping file deletion sequence\n"
    fi
    return 0
}

reset_podman() {
    echo "INFO: performing podman system reset to clear locked file handles"
    if podman system reset -f; then
        echo "SUCCESS: podman reset successful"
        return 0
    else
        echo "ERROR: podman reset failed- run 'podman system reset' -f manually"
        return 1
    fi
}

delete_all_mission-share_data() {
    run_with_sudo rm -rf "/mission-share"
    return 0
}

cleanup_pod_services() {
    local podname="$1"
    local systemd_user_dir="$HOME/.config/systemd/user"
    local pod_service="pod-$podname.service"

    # Sanity check: Ensure podname is not empty
    if [[ -z "$podname" ]]; then
        echo "ERROR: No pod name provided to cleanup_pod_services" >&2
        return 1
    fi

    echo "INFO: Beginning cleanup of service files for pod '$podname'"

    # Check if the pod-$podname service exists
    echo "INFO: Checking if '$pod_service' exists"
    if ! systemctl --user list-units --type=service --all | grep -q "$pod_service"; then
        echo "INFO: '$pod_service' does not exist, proceeding to file cleanup"
    else
        # Check if the pod-$podname service is active
        echo "INFO: Checking if '$pod_service' is active"
        if systemctl --user is-active --quiet "$pod_service"; then
            echo "INFO: '$pod_service' is active, stopping with 'systemctl --user stop $pod_service'"
            if ! systemctl --user stop "$pod_service"; then
                echo "ERROR: Failed to stop '$pod_service'" >&2
                return 1
            fi
            echo "SUCCESS: '$pod_service' stopped successfully"
        else
            echo "INFO: '$pod_service' is not active"
        fi

        # Disable the pod-$podname service
        echo "INFO: Disabling '$pod_service' with 'systemctl --user disable $pod_service'"
        if ! systemctl --user disable "$pod_service" &>/dev/null; then
            echo "ERROR: Failed to disable '$pod_service'" >&2
            return 1
        fi
        echo "SUCCESS: '$pod_service' disabled successfully"
    fi

    # Get container service dependencies dynamically
    echo "INFO: Retrieving dependencies for '$pod_service' using 'systemctl --user list-dependencies'"
    local wants_services
    wants_services=$(systemctl --user list-dependencies "$pod_service" | grep -E "container-$podname-.*\.service" | sed 's/.*├─//;s/.*└─//')
    if [[ -z "$wants_services" ]]; then
        echo "INFO: No container service dependencies found for '$pod_service'"
    else
        echo "INFO: Found container service dependencies: $wants_services"
    fi

    # Stop associated container services
    while IFS= read -r service; do
        if [[ -z "$service" ]]; then
            continue
        fi
        echo "INFO: Checking if '$service' exists"
        if ! systemctl --user list-units --type=service --all | grep -q "$service"; then
            echo "INFO: '$service' does not exist, skipping"
            continue
        fi

        echo "INFO: Checking if '$service' is active"
        if systemctl --user is-active --quiet "$service"; then
            echo "INFO: '$service' is active, stopping with 'systemctl --user stop $service'"
            if ! systemctl --user stop "$service"; then
                echo "ERROR: Failed to stop '$service'" >&2
                return 1
            fi
            echo "SUCCESS: '$service' stopped successfully"
        else
            echo "INFO: '$service' is not active"
        fi
    done <<< "$wants_services"

    # Remove pod service file
    echo "INFO: Removing service file '$systemd_user_dir/$pod_service'"
    if [[ -f "$systemd_user_dir/$pod_service" ]]; then
        if ! rm -f "$systemd_user_dir/$pod_service"; then
            echo "ERROR: Failed to remove '$systemd_user_dir/$pod_service'" >&2
            return 1
        fi
        echo "SUCCESS: '$pod_service' removed successfully"
    else
        echo "INFO: '$pod_service' file does not exist, skipping"
    fi

    # Remove container service files
    while IFS= read -r service; do
        if [[ -z "$service" ]]; then
            continue
        fi
        echo "INFO: Removing service file '$systemd_user_dir/$service'"
        if [[ -f "$systemd_user_dir/$service" ]]; then
            if ! rm -f "$systemd_user_dir/$service"; then
                echo "ERROR: Failed to remove '$systemd_user_dir/$service'" >&2
                return 1
            fi
            echo "SUCCESS: '$service' removed successfully"
        else
            echo "INFO: '$service' file does not exist, skipping"
        fi
    done <<< "$wants_services"

    # Reload systemd daemon
    echo "INFO: Reloading systemd user daemon with 'systemctl --user daemon-reload'"
    if ! systemctl --user daemon-reload; then
        echo "ERROR: Failed to reload systemd user daemon" >&2
        return 1
    fi
    echo "SUCCESS: Systemd user daemon reloaded successfully"

    echo "SUCCESS: Cleanup of service files for pod '$podname' completed successfully"
    return 0
}


check_vars_file() {
    # Check for variables.conf and load initial values
    VARS_FILE="variables.conf"
    if [ -f "$VARS_FILE" ]; then
        #echo "Loading initial values from $VARS_FILE"
        if ! source "$VARS_FILE" ; then
            echo "Warning: Failed to source $VARS_FILE. Check permissions on the file variables.conf"
        fi
        export OGS_DOMAIN_NAME
        #nifi stuff
        export NIFI_DOMAIN_FQDN
	export SINGLE_USER_CREDENTIALS_USERNAME
	export SINGLE_USER_CREDENTIALS_PASSWORD
        export VARS_FOUND=" \u2714 Vars file found"
        return 1
    else
        export VARS_FOUND=" \u2716 WARNING  <-- Vars file Not found -- run this option first"
        return 0
    fi
}

# ---------- Menu System ----------

show_menu() {
    clear
    check_vars_file
    echo "========================================================================"
    echo "       Monitoring Stack Deployment Tool - Ver. $script_version"
    echo "========================================================================"
    echo " Privileged Operations:"
    echo -e " 0) Input/adjust container variables $VARS_FOUND"
    echo " 1) Configure System Settings"
    echo " 2) Provision Disk for Podman Data"
    echo " 3) Copy container source directories"
    echo " 4) Generate SSL Certificates - NIFI and Nginx"
    echo " 5) Install and Configure Nginx Proxy"
    echo " 6) Configure Firewall"
    echo ""
    echo "======================== Image Imports ================================="
    echo "     NOTE: Choose based off networking available "
    echo " 7) Pull Container Images - Internet required"
    echo " 8) Install Packaged Images - No Internet required"
    echo ""
    echo "========================Pod Options====================================="
    echo " 9) Build and Start NIFI Pod"
    echo ""
    echo " q) Exit"
    echo ""
    echo "===================== Un-Install Options ==============================="
    echo " u1) Stop and Delete NIFI pod"
    echo " u2) RESET all back to before containers installed. "
    echo "      -- This Runs u1, AND completely clear out all PODS, "
    echo "      -- containers, keys, files and images on /mission-share"
    echo "      -- takes /mission-share back to empty state"
    echo " u3) Remove Container Firewall rules"
}


umount_disk() {
    #only unmount the /mission-share
    if [ grep -c mission-share /etc/mtab -eq 0 ]; then
        echo "/mission-share is not mounted"
        return 0
    fi
    if run_with_sudo umount /mission-share; then
        echo "SUCCESS: /mission-share unmounted"
        return 0
    else
        echo "ERROR: Failed to unmount /mission-share"
        return 1
    fi
}

remove_disk_from_fstab() {
    echo "INFO: making backup of fstab to /tmp/fstab.backup"
    cp -f /etc/fstab /tmp/fstab.backup
    if run_with_sudo sed -i '/\/mission-share/d' /etc/fstab; then
        echo "SUCCESS: fstab modified, reloading systemctl"
        run_with_sudo systemctl daemon-reload
        return 0
    else
        echo "ERROR: unable to modify /etc/fstab file"
        return 1
    fi
}



# ---------- Main Execution ----------

# Always get sudo password at the very start
get_sudo_password



# Interactive menu mode
while true; do
    show_menu
    read -p "Enter your choice: " choice

    case $choice in
        0) collect_user_inputs && show_menu ;;
        1) configure_system_settings ;;
        2) provision_disk ;;
        3) copy_source_directories ;;
        4) generate_ssl_keys ;;
        5) install_nginx ;;
        6) configure_firewall ;;
        7) pull_container_images ;;
        8) install_tarball_images ;;
        9) build_and_start_pod ;;
        u1)
            if stop_and_delete_pod "nifi"; then
                echo "SUCCESS: Stopped and deleted pod 'nifi'"
            else
                echo "ERROR: Failed to stop and delete pod 'nifi'" >&2
            fi
            if cleanup_pod_services "nifi"; then
                echo "SUCCESS: Cleaned up services for pod 'nifi'"
            else
                echo "ERROR: Failed to clean up services for pod 'nifi'" >&2
            fi
            ;;
        u2)
            if podman pod exists nifi; then
                echo "Removing pod 'nifi'"
                stop_and_delete_pod_auto "nifi"
                if cleanup_pod_services "nifi"; then
                    echo "SUCCESS: Cleaned up services for pod 'nifi'"
                else
                    echo "ERROR: Failed to clean up services for pod 'nifi'" >&2
                fi
            else
                echo "pod nifi not found, skipping" >&2
            fi
            reset_podman
            echo "INFO: Removing all files under /mission"
            delete_all_mission-share_data
            #run podman reset again, to rebuild silently the needed file structure for container images
            podman system reset -f >/dev/null 2>&1
            ;;
        u3) empty_firewall_rules ;;
        q)
            echo "INFO: Exiting. Have a nice day!"
            exit 0
            ;;
        Q)
            echo "INFO: Exiting. Have a nice day!"
            exit 0
            ;;
        *)
            echo "ERROR: Invalid option. Please try again" >&2
            ;;
    esac

    read -p "Press [Enter] to continue..."
done
