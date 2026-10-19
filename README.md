# Captive Portal - Installation and Setup Guide

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Network Architecture](#network-architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## Overview

This captive portal system provides a simple "Click to Connect" interface for network access control. When clients connect to your network, they are presented with a web page requiring them to click a button before gaining internet access.

**Key Features:**
- Simple one-click authorization
- Automatic DNS redirection
- Firewall-based access control
- Systemd service integration
- MAC address-based client tracking

## Prerequisites

### Hardware Requirements
- Ubuntu ARM64 system (tested on VMWare Fusion)
- Minimum 1GB RAM
- 10GB disk space
- Two network interfaces:
  - One for WAN (internet connection)
  - One for LAN (guest network)

### Software Requirements
- Ubuntu 22.04 LTS or newer (ARM64)
- Root/sudo access
- Internet connection for initial setup

### Network Requirements
- Static IP address on LAN interface
- DHCP server capability
- Ability to configure iptables/netfilter

## Network Architecture

### Default Network Configuration

```
Internet
    |
    | (WAN Interface - typically ens160 or eth0)
    |
[Ubuntu Server - Captive Portal]
    |
    | (LAN Interface - typically ens192 or eth1)
    | IP: 192.168.100.1/24
    |
Guest Network (192.168.100.0/24)
    |
    +-- Client 1 (unauthorized) -> See portal page
    +-- Client 2 (authorized)    -> Full internet access
```

### Traffic Flow

1. **Unauthorized Client:**
   - DNS query → dnsmasq returns 192.168.100.1
   - HTTP request → iptables redirects to nginx on port 80
   - See captive portal page

2. **After Authorization:**
   - MAC address added to iptables whitelist
   - DNS queries forwarded to real DNS servers
   - HTTP/HTTPS traffic routed to internet

## Installation

### Quick Install

```bash
# Clone or download this repository
cd /opt
sudo git clone https://github.com/yourusername/CaptivePortal.git
cd CaptivePortal

# Run the installation script
sudo bash scripts/install.sh
```

### Manual Installation

Follow these steps if you prefer to install components individually:

#### Step 1: Update System

```bash
sudo apt update
sudo apt upgrade -y
```

#### Step 2: Install Required Packages

```bash
sudo apt install -y \
    nginx \
    dnsmasq \
    iptables \
    iptables-persistent \
    python3 \
    python3-pip \
    net-tools \
    isc-dhcp-server
```

#### Step 3: Configure Network Interfaces

Edit your network configuration to set a static IP on the LAN interface:

**For netplan (Ubuntu 20.04+):**

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

Add configuration:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens160:  # WAN interface (adjust to your interface name)
      dhcp4: true
    ens192:  # LAN interface (adjust to your interface name)
      dhcp4: false
      addresses:
        - 192.168.100.1/24
```

Apply configuration:

```bash
sudo netplan apply
```

**For older Ubuntu versions:**

```bash
sudo nano /etc/network/interfaces
```

Add:

```
auto eth1
iface eth1 inet static
    address 192.168.100.1
    netmask 255.255.255.0
```

Restart networking:

```bash
sudo systemctl restart networking
```

#### Step 4: Configure DHCP Server

```bash
sudo nano /etc/dhcp/dhcpd.conf
```

Add:

```
subnet 192.168.100.0 netmask 255.255.255.0 {
    range 192.168.100.10 192.168.100.250;
    option routers 192.168.100.1;
    option domain-name-servers 192.168.100.1;
    default-lease-time 600;
    max-lease-time 7200;
}
```

Specify the interface in DHCP defaults:

```bash
sudo nano /etc/default/isc-dhcp-server
```

Set:

```
INTERFACESv4="ens192"  # Adjust to your LAN interface
```

Enable and start DHCP:

```bash
sudo systemctl enable isc-dhcp-server
sudo systemctl restart isc-dhcp-server
```

#### Step 5: Configure dnsmasq

Disable systemd-resolved (conflicts with dnsmasq):

```bash
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

Copy dnsmasq configuration:

```bash
sudo cp config/dnsmasq.conf /etc/dnsmasq.d/captiveportal.conf
```

Enable and start dnsmasq:

```bash
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq
```

#### Step 6: Configure nginx

Copy the web files:

```bash
sudo mkdir -p /var/www/captiveportal
sudo cp html/index.html /var/www/captiveportal/
sudo chown -R www-data:www-data /var/www/captiveportal
```

Copy nginx configuration:

```bash
sudo cp config/nginx.conf /etc/nginx/sites-available/captiveportal
sudo ln -s /etc/nginx/sites-available/captiveportal /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default  # Remove default site
```

Test and restart nginx:

```bash
sudo nginx -t
sudo systemctl restart nginx
```

#### Step 7: Configure Firewall Rules

Enable IP forwarding:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Copy and run firewall script:

```bash
sudo cp scripts/firewall-rules.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/firewall-rules.sh
sudo /usr/local/bin/firewall-rules.sh
```

Save iptables rules:

```bash
sudo netfilter-persistent save
```

#### Step 8: Install Authorization Backend

Copy the authorization script:

```bash
sudo cp scripts/authorize-client.py /usr/local/bin/
sudo chmod +x /usr/local/bin/authorize-client.py
```

Install Python dependencies (if any added later):

```bash
sudo pip3 install flask
```

#### Step 9: Configure Systemd Services

Copy service files:

```bash
sudo cp systemd/captiveportal.service /etc/systemd/system/
sudo cp systemd/captiveportal-firewall.service /etc/systemd/system/
```

Reload systemd and enable services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable captiveportal.service
sudo systemctl enable captiveportal-firewall.service
sudo systemctl start captiveportal.service
sudo systemctl start captiveportal-firewall.service
```

## Configuration

### Customizing the Network Range

To change from the default 192.168.100.0/24 network:

1. Update `/etc/netplan/01-netcfg.yaml` (or `/etc/network/interfaces`)
2. Update `/etc/dhcp/dhcpd.conf`
3. Update `config/dnsmasq.conf`
4. Update `scripts/firewall-rules.sh`
5. Update `config/nginx.conf` if IP address is referenced

### Customizing the Portal Page

Edit the HTML file:

```bash
sudo nano /var/www/captiveportal/index.html
```

After changes, reload nginx:

```bash
sudo systemctl reload nginx
```

### Changing DNS Servers

Edit `/etc/dnsmasq.d/captiveportal.conf` and modify the `server=` lines to use your preferred DNS servers.

### Network Interface Names

If your interfaces have different names, update:
- DHCP configuration (`/etc/default/isc-dhcp-server`)
- Network configuration files
- Firewall script (`scripts/firewall-rules.sh`)

## Testing

### 1. Verify Services are Running

```bash
sudo systemctl status nginx
sudo systemctl status dnsmasq
sudo systemctl status isc-dhcp-server
sudo systemctl status captiveportal
```

### 2. Check Network Configuration

```bash
ip addr show
ip route show
```

Verify:
- LAN interface has IP 192.168.100.1
- Routing is configured

### 3. Test DHCP

Connect a client device to the guest network. It should receive an IP in the range 192.168.100.10-250.

### 4. Test DNS Redirection

From an unauthorized client:

```bash
nslookup google.com
```

Should return 192.168.100.1

### 5. Test Web Portal

From a client browser, visit any HTTP website (e.g., http://example.com). You should be redirected to the captive portal page.

### 6. Test Authorization

Click the "Click here to connect" button. The page should confirm connection, and you should then have internet access.

### 7. Verify Firewall Rules

```bash
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
```

## Troubleshooting

### Client Not Getting IP Address

**Check DHCP server:**
```bash
sudo systemctl status isc-dhcp-server
sudo journalctl -u isc-dhcp-server -n 50
```

**Verify interface:**
```bash
ip addr show  # Ensure LAN interface is up
```

### DNS Not Redirecting

**Check dnsmasq:**
```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

**Test DNS locally:**
```bash
dig @192.168.100.1 google.com
```

### Portal Page Not Loading

**Check nginx:**
```bash
sudo systemctl status nginx
sudo nginx -t  # Test configuration
sudo tail -f /var/log/nginx/error.log
```

**Verify firewall rules:**
```bash
sudo iptables -t nat -L PREROUTING -n -v
```

### No Internet After Authorization

**Check IP forwarding:**
```bash
cat /proc/sys/net/ipv4/ip_forward  # Should return 1
```

**Check NAT rules:**
```bash
sudo iptables -t nat -L POSTROUTING -n -v
```

**Verify WAN interface has internet:**
```bash
ping -I ens160 8.8.8.8  # Replace ens160 with your WAN interface
```

### Authorization Not Working

**Check authorization service:**
```bash
sudo systemctl status captiveportal
sudo journalctl -u captiveportal -n 50
```

**Check script permissions:**
```bash
ls -l /usr/local/bin/authorize-client.py
```

**Test manually:**
```bash
sudo python3 /usr/local/bin/authorize-client.py
```

### General Debugging

**View all logs:**
```bash
sudo journalctl -f  # Follow all system logs
```

**Check specific service:**
```bash
sudo journalctl -u SERVICE_NAME -f
```

## Maintenance

### Viewing Authorized Clients

```bash
sudo iptables -L FORWARD -n -v | grep ACCEPT
```

### Removing an Authorized Client

```bash
# Find the rule number
sudo iptables -L FORWARD --line-numbers -n

# Delete the rule
sudo iptables -D FORWARD <rule_number>

# Save changes
sudo netfilter-persistent save
```

### Clearing All Authorized Clients

```bash
sudo /usr/local/bin/firewall-rules.sh  # Reset to default rules
sudo netfilter-persistent save
```

### Updating the Portal Page

```bash
sudo nano /var/www/captiveportal/index.html
sudo systemctl reload nginx
```

### Viewing DHCP Leases

```bash
cat /var/lib/dhcp/dhcpd.leases
```

### Backup Configuration

```bash
# Backup all configuration files
sudo tar -czf captiveportal-backup-$(date +%Y%m%d).tar.gz \
    /etc/nginx/sites-available/captiveportal \
    /etc/dnsmasq.d/captiveportal.conf \
    /etc/dhcp/dhcpd.conf \
    /var/www/captiveportal/ \
    /usr/local/bin/firewall-rules.sh \
    /usr/local/bin/authorize-client.py
```

### Restore from Backup

```bash
sudo tar -xzf captiveportal-backup-YYYYMMDD.tar.gz -C /
sudo systemctl restart nginx dnsmasq isc-dhcp-server captiveportal
```

### Monitoring Logs

```bash
# Watch all captive portal related logs
sudo journalctl -u nginx -u dnsmasq -u isc-dhcp-server -u captiveportal -f
```

### Performance Monitoring

```bash
# Check system resources
htop

# Monitor network traffic
sudo iftop -i ens192  # Replace with your LAN interface

# View connection statistics
sudo netstat -an | grep :80
```

## Security Considerations

1. **HTTPS:** This initial release uses HTTP. For production, configure HTTPS with SSL certificates.

2. **Firewall:** Ensure only the LAN interface is accessible from the guest network.

3. **Updates:** Regularly update Ubuntu and all packages:
   ```bash
   sudo apt update && sudo apt upgrade
   ```

4. **Access Control:** Limit SSH access to the WAN interface only:
   ```bash
   sudo ufw allow in on ens160 to any port 22
   sudo ufw deny in on ens192 to any port 22
   ```

5. **Log Rotation:** Ensure logs are rotated to prevent disk space issues.

## Uninstallation

```bash
# Stop and disable services
sudo systemctl stop captiveportal captiveportal-firewall nginx dnsmasq isc-dhcp-server
sudo systemctl disable captiveportal captiveportal-firewall

# Remove service files
sudo rm /etc/systemd/system/captiveportal*.service
sudo systemctl daemon-reload

# Remove configurations
sudo rm /etc/nginx/sites-enabled/captiveportal
sudo rm /etc/nginx/sites-available/captiveportal
sudo rm /etc/dnsmasq.d/captiveportal.conf
sudo rm -rf /var/www/captiveportal

# Remove scripts
sudo rm /usr/local/bin/firewall-rules.sh
sudo rm /usr/local/bin/authorize-client.py

# Flush iptables (WARNING: This removes ALL rules)
sudo iptables -F
sudo iptables -t nat -F
sudo netfilter-persistent save

# Re-enable systemd-resolved if desired
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
```

## Support

For issues, questions, or contributions:
- Check the troubleshooting section above
- Review logs: `sudo journalctl -u captiveportal -n 100`
- Ensure all prerequisites are met

## License

[Add your license information here]

## Credits

Built for Ubuntu ARM64 on VMWare Fusion
