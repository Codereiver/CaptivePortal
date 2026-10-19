#!/bin/bash

###############################################################################
# Update DHCP configuration to provide Google DNS instead of portal DNS
# This allows authorized clients to get proper DNS automatically
###############################################################################

echo "Updating DHCP configuration to use Google DNS (8.8.8.8)..."

# Backup the current configuration
cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup-$(date +%Y%m%d-%H%M%S)

# Update the DNS server option
sed -i 's/option domain-name-servers 192.168.100.1;/option domain-name-servers 8.8.8.8, 8.8.4.4;/' /etc/dhcp/dhcpd.conf

echo "DHCP configuration updated. Restarting DHCP server..."

# Restart DHCP server
systemctl restart isc-dhcp-server

# Show the updated configuration
echo ""
echo "Current DHCP configuration:"
grep -A 5 "subnet 192.168.100.0" /etc/dhcp/dhcpd.conf

echo ""
echo "Done! Clients will now receive Google DNS servers (8.8.8.8, 8.8.4.4)"
echo "Unauthorized clients will have their DNS queries redirected to the portal by iptables."
echo "Authorized clients will bypass the redirect and use Google DNS directly."
