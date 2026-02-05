#!/bin/bash

#===============================================================================
# VM Clone Setup Script
# Automates: machine-id reset, hostname change, user creation, SSH keys, networking
#===============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              VM Clone Setup Script                             ║"
echo "║  Configures: hostname, user, SSH keys, and networking          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

#-------------------------------------------------------------------------------
# Get Current Info
#-------------------------------------------------------------------------------
CURRENT_HOSTNAME=$(hostname)
echo -e "${YELLOW}Current hostname:${NC} $CURRENT_HOSTNAME"
echo ""

#-------------------------------------------------------------------------------
# 1. New Hostname Configuration
#-------------------------------------------------------------------------------
read -p "Enter NEW hostname: " NEW_HOSTNAME

if [[ -z "$NEW_HOSTNAME" ]]; then
    echo -e "${RED}[ERROR] Hostname cannot be empty${NC}"
    exit 1
fi

#-------------------------------------------------------------------------------
# 2. New User Configuration
#-------------------------------------------------------------------------------
echo ""
read -p "Enter NEW username: " NEW_USERNAME

if [[ -z "$NEW_USERNAME" ]]; then
    echo -e "${RED}[ERROR] Username cannot be empty${NC}"
    exit 1
fi

# Check if user already exists
if id "$NEW_USERNAME" &>/dev/null; then
    echo -e "${YELLOW}[WARNING] User '$NEW_USERNAME' already exists${NC}"
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        exit 1
    fi
    USER_EXISTS=true
else
    USER_EXISTS=false
fi

# Get password for new user
if [[ "$USER_EXISTS" == false ]]; then
    while true; do
        read -sp "Enter password for '$NEW_USERNAME': " NEW_PASSWORD
        echo ""
        read -sp "Confirm password: " NEW_PASSWORD_CONFIRM
        echo ""
        
        if [[ "$NEW_PASSWORD" == "$NEW_PASSWORD_CONFIRM" ]]; then
            if [[ -z "$NEW_PASSWORD" ]]; then
                echo -e "${RED}[ERROR] Password cannot be empty${NC}"
            else
                break
            fi
        else
            echo -e "${RED}[ERROR] Passwords do not match. Try again.${NC}"
        fi
    done
fi

#-------------------------------------------------------------------------------
# 3. Network Configuration
#-------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                    NETWORK CONFIGURATION                          ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"

# Find netplan config file
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)

if [[ -z "$NETPLAN_FILE" ]]; then
    echo -e "${YELLOW}[WARNING] No netplan configuration file found${NC}"
    CONFIGURE_NETWORK=false
else
    echo -e "${YELLOW}Current network configuration (${NETPLAN_FILE}):${NC}"
    echo -e "${CYAN}-----------------------------------------------------------${NC}"
    cat "$NETPLAN_FILE"
    echo -e "${CYAN}-----------------------------------------------------------${NC}"
    echo ""
    
    read -p "Do you want to configure networking? (y/n): " CONFIGURE_NETWORK_CHOICE
    
    if [[ "$CONFIGURE_NETWORK_CHOICE" == "y" || "$CONFIGURE_NETWORK_CHOICE" == "Y" ]]; then
        CONFIGURE_NETWORK=true
        
        echo ""
        echo -e "${YELLOW}Network Configuration Options:${NC}"
        echo "  1) DHCP (automatic IP assignment)"
        echo "  2) Static IP (manual configuration)"
        echo "  3) Edit configuration file manually"
        echo ""
        read -p "Select option [1/2/3]: " NETWORK_OPTION
        
        # Get network interface name
        DEFAULT_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)
        read -p "Enter network interface name [$DEFAULT_IFACE]: " NETWORK_IFACE
        NETWORK_IFACE=${NETWORK_IFACE:-$DEFAULT_IFACE}
        
        case $NETWORK_OPTION in
            1)
                # DHCP Configuration
                NETWORK_CONFIG="network:
  version: 2
  renderer: networkd
  ethernets:
    ${NETWORK_IFACE}:
      dhcp4: true"
                ;;
            2)
                # Static IP Configuration
                echo ""
                read -p "Enter IP address (e.g., 192.168.1.100/24): " STATIC_IP
                read -p "Enter gateway (e.g., 192.168.1.1): " GATEWAY
                read -p "Enter DNS servers (comma-separated, e.g., 8.8.8.8,8.8.4.4): " DNS_SERVERS
                
                # Format DNS servers for YAML
                DNS_FORMATTED=$(echo "$DNS_SERVERS" | sed 's/,/, /g')
                
                NETWORK_CONFIG="network:
  version: 2
  renderer: networkd
  ethernets:
    ${NETWORK_IFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS_FORMATTED}]"
                ;;
            3)
                # Manual edit - will open nano later
                MANUAL_EDIT=true
                ;;
            *)
                echo -e "${YELLOW}[INFO] Keeping current network configuration${NC}"
                CONFIGURE_NETWORK=false
                ;;
        esac
    else
        CONFIGURE_NETWORK=false
    fi
fi

#-------------------------------------------------------------------------------
# Summary and Confirmation
#-------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                         SUMMARY                                   ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "  Hostname:        ${GREEN}$NEW_HOSTNAME${NC}"
echo -e "  New User:        ${GREEN}$NEW_USERNAME${NC}"
echo -e "  Network Config:  ${GREEN}$(if [[ "$CONFIGURE_NETWORK" == true ]]; then echo "Will be modified"; else echo "No changes"; fi)${NC}"
echo ""
echo -e "${YELLOW}The following actions will be performed:${NC}"
echo "  • Reset machine-id"
echo "  • Change hostname to '$NEW_HOSTNAME'"
echo "  • Update /etc/hosts"
if [[ "$USER_EXISTS" == false ]]; then
    echo "  • Create user '$NEW_USERNAME' with sudo privileges"
fi
echo "  • Regenerate SSH host keys"
if [[ "$CONFIGURE_NETWORK" == true ]]; then
    echo "  • Apply new network configuration"
fi
echo "  • Reboot system"
echo ""

read -p "Proceed with these changes? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}[CANCELLED] No changes were made${NC}"
    exit 0
fi

#-------------------------------------------------------------------------------
# Execute Changes
#-------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}Applying changes...${NC}"
echo ""

# 1. Reset machine-id
echo -e "${YELLOW}[1/8] Resetting machine-id...${NC}"
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
echo -e "${GREEN}      ✓ Machine-id reset${NC}"

# 2. Generate new machine-id
echo -e "${YELLOW}[2/8] Generating new machine-id...${NC}"
systemd-machine-id-setup
echo -e "${GREEN}      ✓ New machine-id generated${NC}"

# 3. Change hostname
echo -e "${YELLOW}[3/8] Setting hostname to '$NEW_HOSTNAME'...${NC}"
hostnamectl set-hostname "$NEW_HOSTNAME"
echo -e "${GREEN}      ✓ Hostname changed${NC}"

# 4. Update /etc/hosts
echo -e "${YELLOW}[4/8] Updating /etc/hosts...${NC}"
# Remove old hostname entries and add new one
sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
# If the line doesn't exist, add it
if ! grep -q "127.0.1.1" /etc/hosts; then
    echo "127.0.1.1	$NEW_HOSTNAME" >> /etc/hosts
fi
echo -e "${GREEN}      ✓ /etc/hosts updated${NC}"

# 5. Create new user
if [[ "$USER_EXISTS" == false ]]; then
    echo -e "${YELLOW}[5/8] Creating user '$NEW_USERNAME'...${NC}"
    useradd -m -s /bin/bash "$NEW_USERNAME"
    echo "$NEW_USERNAME:$NEW_PASSWORD" | chpasswd
    echo -e "${GREEN}      ✓ User created${NC}"
    
    # 6. Add to sudo group
    echo -e "${YELLOW}[6/8] Adding '$NEW_USERNAME' to sudo group...${NC}"
    usermod -aG sudo "$NEW_USERNAME"
    echo -e "${GREEN}      ✓ Sudo privileges granted${NC}"
else
    echo -e "${YELLOW}[5/8] Skipping user creation (user exists)${NC}"
    echo -e "${YELLOW}[6/8] Skipping sudo configuration${NC}"
fi

# 7. Regenerate SSH host keys
echo -e "${YELLOW}[7/8] Regenerating SSH host keys...${NC}"
rm -f /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server -f noninteractive 2>/dev/null || ssh-keygen -A
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
echo -e "${GREEN}      ✓ SSH keys regenerated${NC}"

# 8. Network configuration
if [[ "$CONFIGURE_NETWORK" == true ]]; then
    echo -e "${YELLOW}[8/8] Configuring network...${NC}"
    
    if [[ "$MANUAL_EDIT" == true ]]; then
        echo -e "${CYAN}Opening network configuration for manual editing...${NC}"
        nano "$NETPLAN_FILE"
    else
        # Backup existing config
        cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup"
        
        # Write new configuration
        echo "$NETWORK_CONFIG" > "$NETPLAN_FILE"
        chmod 600 "$NETPLAN_FILE"
        
        echo -e "${GREEN}      ✓ Network configuration updated${NC}"
        echo -e "${YELLOW}      Backup saved to: ${NETPLAN_FILE}.backup${NC}"
    fi
    
    # Apply netplan (will take effect after reboot anyway)
    echo -e "${YELLOW}      Applying netplan configuration...${NC}"
    netplan apply 2>/dev/null || true
else
    echo -e "${YELLOW}[8/8] Skipping network configuration${NC}"
fi

#-------------------------------------------------------------------------------
# Complete
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    SETUP COMPLETE                                 ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "New hostname:  ${CYAN}$NEW_HOSTNAME${NC}"
echo -e "New user:      ${CYAN}$NEW_USERNAME${NC}"
echo ""
echo -e "${YELLOW}The system will reboot in 10 seconds...${NC}"
echo -e "${YELLOW}Press Ctrl+C to cancel reboot${NC}"
echo ""

for i in {10..1}; do
    echo -ne "\rRebooting in ${i} seconds... "
    sleep 1
done

echo ""
reboot
