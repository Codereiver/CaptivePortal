#!/bin/bash

###############################################################################
# Captive Portal Status Display
# Shows authorized clients, firewall rules, and service status
###############################################################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Captive Portal Status                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}=== Service Status ===${NC}"
systemctl is-active --quiet nginx && echo -e "  nginx:          ${GREEN}Running${NC}" || echo -e "  nginx:          \033[0;31mStopped\033[0m"
systemctl is-active --quiet dnsmasq && echo -e "  dnsmasq:        ${GREEN}Running${NC}" || echo -e "  dnsmasq:        \033[0;31mStopped\033[0m"
systemctl is-active --quiet isc-dhcp-server && echo -e "  DHCP:           ${GREEN}Running${NC}" || echo -e "  DHCP:           \033[0;31mStopped\033[0m"
systemctl is-active --quiet captiveportal && echo -e "  Authorization:  ${GREEN}Running${NC}" || echo -e "  Authorization:  \033[0;31mStopped\033[0m"

echo ""
echo -e "${YELLOW}=== Authorized Clients ===${NC}"
if [ -f /var/lib/captiveportal/authorized_clients.txt ] && [ -s /var/lib/captiveportal/authorized_clients.txt ]; then
    echo "  MAC Address         IP Address"
    echo "  ----------------    ---------------"
    cat /var/lib/captiveportal/authorized_clients.txt | column -t -s ','
else
    echo "  No authorized clients"
fi

echo ""
echo -e "${YELLOW}=== Current DHCP Leases ===${NC}"
if [ -f /var/lib/dhcp/dhcpd.leases ]; then
    LEASES=$(grep "^lease" /var/lib/dhcp/dhcpd.leases | awk '{print $2}' | sort -u)
    if [ ! -z "$LEASES" ]; then
        for ip in $LEASES; do
            MAC=$(grep -A 3 "lease $ip" /var/lib/dhcp/dhcpd.leases | grep "hardware ethernet" | tail -1 | awk '{print $3}' | sed 's/;//')
            HOSTNAME=$(grep -A 5 "lease $ip" /var/lib/dhcp/dhcpd.leases | grep "client-hostname" | tail -1 | sed 's/.*"\(.*\)".*/\1/')
            echo "  $ip - $MAC - $HOSTNAME"
        done
    else
        echo "  No active leases"
    fi
else
    echo "  Lease file not found"
fi

echo ""
echo -e "${YELLOW}=== Firewall Statistics ===${NC}"
FORWARD_RULES=$(iptables -L FORWARD -n | grep -c "MAC")
NAT_RULES=$(iptables -t nat -L PREROUTING -n | grep -c "MAC")
echo "  Authorized MAC rules in FORWARD: $FORWARD_RULES"
echo "  Authorized MAC rules in NAT:     $NAT_RULES"

echo ""
echo -e "${YELLOW}=== Quick Actions ===${NC}"
echo "  View logs:             sudo journalctl -u captiveportal -f"
echo "  De-auth all:           sudo /usr/local/bin/deauthorize-client.sh all"
echo "  De-auth specific MAC:  sudo /usr/local/bin/deauthorize-client.sh XX:XX:XX:XX:XX:XX"
echo "  Restart services:      sudo systemctl restart captiveportal nginx dnsmasq"
echo ""
