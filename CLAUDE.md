# Captive Portal Project

## Overview
This project implements a Captive Portal designed to run on Ubuntu ARM64 in VMWare Fusion.

## Purpose
A captive portal is a web page that users are redirected to before being granted network access. This is commonly used in:
- Public WiFi networks (hotels, airports, coffee shops)
- Guest network authentication
- Network access control and user acceptance of terms

## Platform Requirements
- **OS**: Ubuntu ARM64
- **Virtualization**: VMWare Fusion
- **Architecture**: ARM64

## Project Status
Initial release - Simple "Click to Connect" portal

## System Architecture

### Components

This captive portal system consists of multiple integrated components:

#### 1. **Web Server (nginx)**
- Serves the captive portal HTML page
- Handles HTTP requests on port 80
- Provides the user interface for network authorization
- Location: `/etc/nginx/sites-available/captiveportal`

#### 2. **DNS Server (dnsmasq)**
- Intercepts all DNS queries from unauthorized clients
- Returns the captive portal IP for all domain requests
- Forces clients to see the portal page regardless of requested URL
- Configuration: `/etc/dnsmasq.d/captiveportal.conf`

#### 3. **Firewall Rules (iptables)**
- Blocks internet access for unauthorized clients
- Allows access only to the captive portal
- Redirects HTTP traffic to the portal page
- Manages authorized client whitelist
- Script: `scripts/firewall-rules.sh`

#### 4. **Authorization Backend (Python/Bash)**
- Processes "Connect" button clicks
- Adds client MAC addresses to authorized list
- Updates iptables rules to grant internet access
- Script: `scripts/authorize-client.py`

#### 5. **Network Configuration**
- Manages network interfaces
- Configures DHCP server for client IP assignment
- Sets up routing between guest network and internet
- Configuration files in `/etc/netplan/` or `/etc/network/interfaces`

#### 6. **Systemd Services**
- Ensures all components start on boot
- Manages service dependencies
- Handles automatic restarts on failure
- Service files: `systemd/*.service`

### Network Flow

1. **Client connects** to WiFi/Network
2. **DHCP assigns** IP address to client
3. **Client attempts** to browse any website
4. **DNS intercepts** request, returns portal IP
5. **Firewall redirects** HTTP to portal page
6. **Client sees** captive portal with "Connect" button
7. **Client clicks** "Connect" button
8. **Backend authorizes** client MAC address
9. **Firewall updated** to allow client internet access
10. **Client has** full internet access

### Directory Structure

```
CaptivePortal/
├── CLAUDE.md                  # This file - architecture documentation
├── README.md                  # Build and installation instructions
├── html/
│   └── index.html            # Captive portal web page
├── config/
│   ├── nginx.conf            # Nginx configuration
│   └── dnsmasq.conf          # DNS configuration
├── scripts/
│   ├── firewall-rules.sh     # iptables setup
│   ├── authorize-client.py   # Client authorization
│   └── install.sh            # Installation script
└── systemd/
    ├── captiveportal.service # Main service
    └── captiveportal-firewall.service # Firewall service
```

## Development Notes
- Started: 2026-10-19
- Target platform: Ubuntu ARM64 on VMWare Fusion
- Initial release: Simple click-to-connect interface
- Future enhancements: Terms acceptance, user registration, bandwidth limiting
