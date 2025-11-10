#!/bin/bash
# Do not allow to run as root
if (( $EUID == 0 )); then
 echo "ERROR: This script must not be run as root, run as normal user that will manage the containers. 'miadmin?'" >&2
 exit 1
fi

    echo "INFO: Removing old systemctl user files"
    rm -fv  ~/.config/systemd/user/*.service

    echo "INFO: Replacing and Starting initial NIFI pod"
    echo "INFO: using  /mission-share/podman/containers/nifi-pod.yml"
    if podman kube play --replace --userns=keep-id /mission-share/podman/containers/nifi-pod.yml; then
        echo "SUCCESS: Initial NIFI pod started"
    else
        echo "ERROR: Failed to start initial NIFI pod" >&2
    fi

    echo "INFO: Generating systemd service files for NIFI pod"
    if podman generate systemd --name --files nifi && \
       mv -fv *.service ~/.config/systemd/user/; then
        echo "SUCCESS: Systemd service files generated and moved"
    else
        echo "ERROR: Failed to generate or move systemd service files" >&2
    fi

    echo "INFO: Reloading systemd user daemon"
    if systemctl --user daemon-reload; then
        echo "SUCCESS: Systemd user daemon reloaded"
    else
        echo "ERROR: Failed to reload systemd user daemon" >&2
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
    fi

