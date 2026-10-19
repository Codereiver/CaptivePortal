#!/bin/bash

###############################################################################
# Captive Portal - Firewall Rules Setup Script
# This script configures iptables rules for the captive portal
###############################################################################

# Configuration
WAN_INTERFACE="ens160"      # External/Internet interface (adjust as needed)
LAN_INTERFACE="ens192"      # Internal/Guest network interface (adjust as needed)
PORTAL_IP="192.168.100.1"   # Captive portal IP address
LAN_NETWORK="192.168.100.0/24"  # Guest network range

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Captive Portal Firewall Setup ===${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Verify interfaces exist
echo -e "${YELLOW}Checking network interfaces...${NC}"
if ! ip link show "$WAN_INTERFACE" &> /dev/null; then
    echo -e "${RED}WARNING: WAN interface $WAN_INTERFACE not found${NC}"
    echo "Available interfaces:"
    ip link show | grep "^[0-9]" | awk '{print $2}' | sed 's/://'
fi

if ! ip link show "$LAN_INTERFACE" &> /dev/null; then
    echo -e "${RED}WARNING: LAN interface $LAN_INTERFACE not found${NC}"
    echo "Available interfaces:"
    ip link show | grep "^[0-9]" | awk '{print $2}' | sed 's/://'
fi

# Flush existing rules
echo -e "${YELLOW}Flushing existing iptables rules...${NC}"
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
iptables -t nat -X
iptables -t mangle -X

# Set default policies
echo -e "${YELLOW}Setting default policies...${NC}"
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

###############################################################################
# INPUT CHAIN - Traffic destined for the portal server itself
###############################################################################

echo -e "${YELLOW}Configuring INPUT chain...${NC}"

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from WAN (adjust or remove for security)
iptables -A INPUT -i "$WAN_INTERFACE" -p tcp --dport 22 -j ACCEPT

# Allow DNS queries from LAN
iptables -A INPUT -i "$LAN_INTERFACE" -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i "$LAN_INTERFACE" -p tcp --dport 53 -j ACCEPT

# Allow DHCP from LAN
iptables -A INPUT -i "$LAN_INTERFACE" -p udp --dport 67:68 -j ACCEPT

# Allow HTTP to portal from LAN
iptables -A INPUT -i "$LAN_INTERFACE" -p tcp --dport 80 -j ACCEPT

# Allow HTTPS to portal from LAN (for future use)
iptables -A INPUT -i "$LAN_INTERFACE" -p tcp --dport 443 -j ACCEPT

# Allow authorization backend port (Flask default)
iptables -A INPUT -i lo -p tcp --dport 5000 -j ACCEPT

# Allow ping from LAN (optional, for troubleshooting)
iptables -A INPUT -i "$LAN_INTERFACE" -p icmp --icmp-type echo-request -j ACCEPT

# Drop everything else
iptables -A INPUT -j DROP

###############################################################################
# FORWARD CHAIN - Traffic passing through the portal server
###############################################################################

echo -e "${YELLOW}Configuring FORWARD chain...${NC}"

# Allow established and related connections
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow traffic from LAN to WAN for authorized clients (will be added dynamically)
# The authorization script will add rules like:
# iptables -I FORWARD -m mac --mac-source XX:XX:XX:XX:XX:XX -s 192.168.100.0/24 -j ACCEPT

# Block all other forwarding by default
iptables -A FORWARD -j DROP

###############################################################################
# NAT TABLE - Network Address Translation
###############################################################################

echo -e "${YELLOW}Configuring NAT rules...${NC}"

# POSTROUTING - Masquerade LAN traffic going to internet
iptables -t nat -A POSTROUTING -o "$WAN_INTERFACE" -s "$LAN_NETWORK" -j MASQUERADE

# PREROUTING - Redirect DNS queries to local dnsmasq for unauthorized clients
# Authorized clients will have RETURN rules added before this to bypass the redirect
echo -e "${YELLOW}Adding DNS redirection for unauthorized clients...${NC}"
iptables -t nat -A PREROUTING -i "$LAN_INTERFACE" -p udp --dport 53 -j DNAT --to-destination "$PORTAL_IP:53"
iptables -t nat -A PREROUTING -i "$LAN_INTERFACE" -p tcp --dport 53 -j DNAT --to-destination "$PORTAL_IP:53"

# PREROUTING - Redirect HTTP traffic to captive portal for unauthorized clients
# This ensures that any HTTP request goes to our portal page
iptables -t nat -A PREROUTING -i "$LAN_INTERFACE" -p tcp --dport 80 -j DNAT --to-destination "$PORTAL_IP:80"

# Redirect HTTPS to HTTP (optional - breaks HTTPS sites but forces portal display)
# Comment out if you don't want to intercept HTTPS
# Note: Modern browsers may show security warnings
iptables -t nat -A PREROUTING -i "$LAN_INTERFACE" -p tcp --dport 443 -j DNAT --to-destination "$PORTAL_IP:80"

###############################################################################
# IP FORWARDING
###############################################################################

echo -e "${YELLOW}Enabling IP forwarding...${NC}"

# Enable IP forwarding temporarily
echo 1 > /proc/sys/net/ipv4/ip_forward

# Make it permanent
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

###############################################################################
# SAVE RULES
###############################################################################

echo -e "${YELLOW}Saving iptables rules...${NC}"

# Save rules (method depends on distribution)
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
    echo -e "${GREEN}Rules saved with netfilter-persistent${NC}"
elif command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}Rules saved to /etc/iptables/rules.v4${NC}"
else
    echo -e "${YELLOW}WARNING: Could not save iptables rules permanently${NC}"
    echo "Install iptables-persistent: apt install iptables-persistent"
fi

###############################################################################
# DISPLAY CURRENT RULES
###############################################################################

echo -e "${GREEN}=== Firewall setup complete ===${NC}"
echo ""
echo -e "${YELLOW}Current iptables rules:${NC}"
echo ""
echo "FILTER table:"
iptables -L -n -v --line-numbers
echo ""
echo "NAT table:"
iptables -t nat -L -n -v --line-numbers
echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "To add an authorized client, use the authorize-client.py script"
echo "or manually add with:"
echo "  iptables -I FORWARD 1 -m mac --mac-source XX:XX:XX:XX:XX:XX -j ACCEPT"
