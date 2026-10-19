#!/bin/bash

###############################################################################
# Captive Portal - Automated Installation Script
# This script installs and configures all components of the captive portal
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (adjust these as needed)
INSTALL_DIR="/opt/CaptivePortal"
WAN_INTERFACE="ens160"
LAN_INTERFACE="ens192"
LAN_IP="192.168.100.1"
LAN_NETWORK="192.168.100.0/24"
DHCP_RANGE_START="192.168.100.10"
DHCP_RANGE_END="192.168.100.250"

# Functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║        Captive Portal Installation Script             ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot detect OS. This script is designed for Ubuntu."
        exit 1
    fi

    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        print_warning "This script is designed for Ubuntu. Your OS: $ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_network_interfaces() {
    print_step "Checking network interfaces..."

    # List available interfaces
    echo "Available network interfaces:"
    ip link show | grep "^[0-9]" | awk '{print "  " $2}' | sed 's/://'

    if ! ip link show "$WAN_INTERFACE" &> /dev/null; then
        print_warning "WAN interface '$WAN_INTERFACE' not found"
        read -p "Enter your WAN interface name: " WAN_INTERFACE
    fi

    if ! ip link show "$LAN_INTERFACE" &> /dev/null; then
        print_warning "LAN interface '$LAN_INTERFACE' not found"
        read -p "Enter your LAN interface name: " LAN_INTERFACE
    fi

    echo "Using WAN interface: $WAN_INTERFACE"
    echo "Using LAN interface: $LAN_INTERFACE"
}

install_packages() {
    print_step "Updating package lists..."
    apt update || { print_error "Failed to update package lists"; exit 1; }

    print_step "Installing required packages..."
    apt install -y \
        nginx \
        dnsmasq \
        iptables \
        iptables-persistent \
        python3 \
        python3-pip \
        python3-flask \
        python3-flask-cors \
        net-tools \
        isc-dhcp-server \
        || { print_error "Failed to install packages"; exit 1; }

    print_step "Installing Python dependencies..."
    pip3 install flask flask-cors || print_warning "Failed to install some Python packages"
}

configure_network() {
    print_step "Configuring network interface..."

    # Backup existing configuration
    if [ -d /etc/netplan ]; then
        # Ubuntu 18.04+ uses netplan
        NETPLAN_FILE="/etc/netplan/99-captiveportal.yaml"

        cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_INTERFACE:
      dhcp4: false
      addresses:
        - $LAN_IP/24
EOF

        chmod 600 "$NETPLAN_FILE"
        netplan apply || print_warning "Failed to apply netplan configuration"

    else
        # Older Ubuntu versions use /etc/network/interfaces
        if ! grep -q "^auto $LAN_INTERFACE" /etc/network/interfaces; then
            cat >> /etc/network/interfaces <<EOF

# Captive Portal LAN Interface
auto $LAN_INTERFACE
iface $LAN_INTERFACE inet static
    address $LAN_IP
    netmask 255.255.255.0
EOF

            ifdown "$LAN_INTERFACE" 2>/dev/null
            ifup "$LAN_INTERFACE" || print_warning "Failed to bring up $LAN_INTERFACE"
        fi
    fi
}

configure_dhcp() {
    print_step "Configuring DHCP server..."

    # Backup original config
    cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup 2>/dev/null

    # Configure DHCP
    cat > /etc/dhcp/dhcpd.conf <<EOF
# Captive Portal DHCP Configuration
default-lease-time 600;
max-lease-time 7200;

subnet ${LAN_NETWORK%/*} netmask 255.255.255.0 {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option routers $LAN_IP;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option domain-name "portal.local";
}
EOF

    # Configure DHCP interface
    sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$LAN_INTERFACE\"/" /etc/default/isc-dhcp-server

    # Enable and restart DHCP
    systemctl enable isc-dhcp-server
    systemctl restart isc-dhcp-server || print_warning "DHCP server failed to start"
}

configure_dnsmasq() {
    print_step "Configuring dnsmasq..."

    # Disable systemd-resolved (conflicts with dnsmasq)
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved

    # Remove systemd-resolved's resolv.conf
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # Copy dnsmasq configuration
    cp "$INSTALL_DIR/config/dnsmasq.conf" /etc/dnsmasq.d/captiveportal.conf

    # Update interface in config
    sed -i "s/^interface=.*/interface=$LAN_INTERFACE/" /etc/dnsmasq.d/captiveportal.conf
    sed -i "s|address=/#/.*|address=/#/$LAN_IP|" /etc/dnsmasq.d/captiveportal.conf

    # Enable and restart dnsmasq
    systemctl enable dnsmasq
    systemctl restart dnsmasq || print_warning "dnsmasq failed to start"
}

configure_nginx() {
    print_step "Configuring nginx..."

    # Create web directory
    mkdir -p /var/www/captiveportal

    # Copy HTML files
    cp "$INSTALL_DIR/html/index.html" /var/www/captiveportal/
    chown -R www-data:www-data /var/www/captiveportal

    # Copy nginx configuration
    cp "$INSTALL_DIR/config/nginx.conf" /etc/nginx/sites-available/captiveportal

    # Enable site
    ln -sf /etc/nginx/sites-available/captiveportal /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Test configuration
    nginx -t || { print_error "nginx configuration test failed"; exit 1; }

    # Restart nginx
    systemctl enable nginx
    systemctl restart nginx || { print_error "nginx failed to start"; exit 1; }
}

configure_firewall() {
    print_step "Configuring firewall rules..."

    # Copy firewall script
    cp "$INSTALL_DIR/scripts/firewall-rules.sh" /usr/local/bin/
    chmod +x /usr/local/bin/firewall-rules.sh

    # Update interface names in script
    sed -i "s/^WAN_INTERFACE=.*/WAN_INTERFACE=\"$WAN_INTERFACE\"/" /usr/local/bin/firewall-rules.sh
    sed -i "s/^LAN_INTERFACE=.*/LAN_INTERFACE=\"$LAN_INTERFACE\"/" /usr/local/bin/firewall-rules.sh
    sed -i "s/^PORTAL_IP=.*/PORTAL_IP=\"$LAN_IP\"/" /usr/local/bin/firewall-rules.sh
    sed -i "s|^LAN_NETWORK=.*|LAN_NETWORK=\"$LAN_NETWORK\"|" /usr/local/bin/firewall-rules.sh

    # Run firewall script
    /usr/local/bin/firewall-rules.sh || print_warning "Firewall configuration had warnings"

    # Install firewall service
    cp "$INSTALL_DIR/systemd/captiveportal-firewall.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable captiveportal-firewall.service
}

install_authorization_service() {
    print_step "Installing authorization service..."

    # Copy authorization script
    cp "$INSTALL_DIR/scripts/authorize-client.py" /usr/local/bin/
    chmod +x /usr/local/bin/authorize-client.py

    # Create necessary directories
    mkdir -p /var/lib/captiveportal
    mkdir -p /var/log/captiveportal

    # Copy systemd service
    cp "$INSTALL_DIR/systemd/captiveportal.service" /etc/systemd/system/

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable captiveportal.service
    systemctl start captiveportal.service || print_warning "Authorization service failed to start"
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║           Installation Complete!                      ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Configuration Summary:"
    echo "  WAN Interface:  $WAN_INTERFACE"
    echo "  LAN Interface:  $LAN_INTERFACE"
    echo "  Portal IP:      $LAN_IP"
    echo "  Guest Network:  $LAN_NETWORK"
    echo "  DHCP Range:     $DHCP_RANGE_START - $DHCP_RANGE_END"
    echo ""
    echo "Service Status:"
    systemctl is-active --quiet nginx && echo -e "  nginx:          ${GREEN}Running${NC}" || echo -e "  nginx:          ${RED}Stopped${NC}"
    systemctl is-active --quiet dnsmasq && echo -e "  dnsmasq:        ${GREEN}Running${NC}" || echo -e "  dnsmasq:        ${RED}Stopped${NC}"
    systemctl is-active --quiet isc-dhcp-server && echo -e "  DHCP:           ${GREEN}Running${NC}" || echo -e "  DHCP:           ${RED}Stopped${NC}"
    systemctl is-active --quiet captiveportal && echo -e "  Authorization:  ${GREEN}Running${NC}" || echo -e "  Authorization:  ${RED}Stopped${NC}"
    echo ""
    echo "Next Steps:"
    echo "  1. Verify all services are running"
    echo "  2. Connect a client device to the $LAN_INTERFACE network"
    echo "  3. Open a web browser on the client"
    echo "  4. You should be redirected to the captive portal"
    echo ""
    echo "Troubleshooting:"
    echo "  View logs: sudo journalctl -u captiveportal -f"
    echo "  Check firewall: sudo iptables -L -n -v"
    echo "  Test DHCP: Check if clients get IP addresses"
    echo ""
    echo "For detailed documentation, see README.md"
    echo ""
}

# Main installation flow
main() {
    print_header

    check_root
    check_ubuntu
    check_network_interfaces

    # Confirm installation
    echo ""
    echo "This script will install and configure the captive portal."
    echo "The following will be modified:"
    echo "  - Network configuration"
    echo "  - DHCP server configuration"
    echo "  - DNS server (dnsmasq)"
    echo "  - Web server (nginx)"
    echo "  - Firewall rules (iptables)"
    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    # Set INSTALL_DIR to current directory if running from source
    if [ -f "./scripts/install.sh" ]; then
        INSTALL_DIR="$(pwd)"
        print_step "Installing from source directory: $INSTALL_DIR"
    fi

    install_packages
    configure_network
    configure_dhcp
    configure_dnsmasq
    configure_nginx
    configure_firewall
    install_authorization_service

    print_summary
}

# Run main installation
main "$@"
