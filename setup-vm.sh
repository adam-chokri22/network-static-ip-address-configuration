#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
fi

read -p "Enter new username: " NEWUSER
read -p "Enter new IP (e.g., 192.168.50.15/24) dont forget the /24: " NEWIP
read -p "Enter gateway (e.g., 192.168.50.1): " GATEWAY

# Step 1: Reset machine-id
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# Step 2: Generate new unique ID
systemd-machine-id-setup

# Step 3: Change hostname
hostnamectl set-hostname "$NEWUSER"

# Step 4: Update /etc/hosts
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*$/127.0.1.1 $NEWUSER/" /etc/hosts
else
    echo "127.0.1.1 $NEWUSER" >> /etc/hosts
fi

# Step 5: Create new user
adduser --gecos "" "$NEWUSER"

# Step 6: Give sudo privileges
usermod -aG sudo "$NEWUSER"

# Step 7: Delete old SSH keys
rm -v /etc/ssh/ssh_host_*

# Step 8: Generate new SSH keys
dpkg-reconfigure openssh-server
systemctl restart ssh

# Step 11: Update netplan file
cat <<EOF >/etc/netplan/50-cloud-init.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - $NEWIP
      gateway4: $GATEWAY
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF

# Step 12: Apply netplan
netplan apply

echo "All done. The system will now reboot."
reboot
