#!/bin/bash
set -e

# ========= EDIT THESE =========
NEW_HOSTNAME="lab-ubuntu-01"
NEW_USERNAME="adam"
NEW_PASSWORD="TempPass123!"
NETWORK_URL="https://raw.githubusercontent.com/adam-chokri22/network-static-ip-address-configuration/refs/heads/main/Network-file.txt"
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
# ==============================

echo "===== Updating machine-id ====="
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo systemd-machine-id-setup

echo "===== Setting hostname ====="
sudo hostnamectl set-hostname "$NEW_HOSTNAME"

echo "===== Fixing /etc/hosts ====="
if grep -q "127.0.1.1" /etc/hosts; then
    sudo sed -i "s/^127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
else
    echo "127.0.1.1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts
fi

echo "===== Creating user if not exists ====="
if id "$NEW_USERNAME" &>/dev/null; then
    echo "User exists, skipping creation"
else
    sudo useradd -m -s /bin/bash "$NEW_USERNAME"
    echo "$NEW_USERNAME:$NEW_PASSWORD" | sudo chpasswd
    sudo usermod -aG sudo "$NEW_USERNAME"
    sudo chage -d 0 "$NEW_USERNAME"
fi

echo "===== Regenerating SSH host keys ====="
sudo rm -f /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server >/dev/null 2>&1
sudo systemctl restart ssh

echo "===== Downloading netplan config ====="
wget -q -O /tmp/netplan.yaml "$NETWORK_URL"

echo "===== Validating netplan file ====="
if sudo netplan try --config-file /tmp/netplan.yaml --timeout 5; then
    echo "Netplan file valid"
    sudo cp /tmp/netplan.yaml "$NETPLAN_FILE"
    sudo netplan apply
else
    echo "Netplan validation failed. Aborting network change."
fi

echo "===== Cleanup ====="
rm -f /tmp/netplan.yaml

echo "===== Initialization complete. Rebooting ====="
sudo reboot
