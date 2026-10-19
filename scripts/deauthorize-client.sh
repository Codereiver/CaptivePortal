#!/bin/bash

###############################################################################
# De-authorize a client - removes all firewall rules for a MAC address
# Usage: sudo ./deauthorize-client.sh [MAC_ADDRESS]
#        sudo ./deauthorize-client.sh all  (clears all authorized clients)
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

if [ "$1" == "all" ]; then
    echo -e "${YELLOW}Removing all authorized clients...${NC}"

    # Flush and rebuild firewall rules from scratch
    /usr/local/bin/firewall-rules.sh

    # Clear authorized clients file
    truncate -s 0 /var/lib/captiveportal/authorized_clients.txt

    echo -e "${GREEN}All clients de-authorized. Firewall rules reset.${NC}"

elif [ -z "$1" ]; then
    echo "Usage: $0 [MAC_ADDRESS|all]"
    echo ""
    echo "Current authorized clients:"
    if [ -f /var/lib/captiveportal/authorized_clients.txt ]; then
        cat /var/lib/captiveportal/authorized_clients.txt
    else
        echo "  None"
    fi
    echo ""
    echo "Current firewall rules with MAC addresses:"
    iptables -L FORWARD -n -v --line-numbers | grep -i mac
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep -i mac

else
    MAC="$1"
    echo -e "${YELLOW}Removing authorization for MAC: $MAC${NC}"

    # Remove from authorized clients file
    if [ -f /var/lib/captiveportal/authorized_clients.txt ]; then
        sed -i "/$MAC/d" /var/lib/captiveportal/authorized_clients.txt
    fi

    # Remove from FORWARD chain
    while iptables -L FORWARD -n -v | grep -qi "$MAC"; do
        RULE_NUM=$(iptables -L FORWARD -n -v --line-numbers | grep -i "$MAC" | head -n1 | awk '{print $1}')
        if [ ! -z "$RULE_NUM" ]; then
            iptables -D FORWARD $RULE_NUM
            echo "Removed FORWARD rule #$RULE_NUM"
        else
            break
        fi
    done

    # Remove from NAT PREROUTING chain
    while iptables -t nat -L PREROUTING -n -v | grep -qi "$MAC"; do
        RULE_NUM=$(iptables -t nat -L PREROUTING -n -v --line-numbers | grep -i "$MAC" | head -n1 | awk '{print $1}')
        if [ ! -z "$RULE_NUM" ]; then
            iptables -t nat -D PREROUTING $RULE_NUM
            echo "Removed NAT PREROUTING rule #$RULE_NUM"
        else
            break
        fi
    done

    # Save rules
    netfilter-persistent save

    echo -e "${GREEN}Client de-authorized: $MAC${NC}"
    echo "Client will need to re-authenticate to access internet."
fi
