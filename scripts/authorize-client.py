#!/usr/bin/env python3

"""
Captive Portal - Client Authorization Backend
This Flask application handles client authorization requests from the portal page.
It extracts the client's IP and MAC address, then adds firewall rules to grant internet access.
"""

import subprocess
import re
import json
import logging
import os
from flask import Flask, request, jsonify
from flask_cors import CORS

# Configuration
AUTHORIZED_CLIENTS_FILE = "/var/lib/captiveportal/authorized_clients.txt"
LOG_FILE = "/var/log/captiveportal/authorization.log"

# Create Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configure logging
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


def get_mac_from_ip(ip_address):
    """
    Get MAC address from IP using the ARP table.

    Args:
        ip_address (str): The IP address to look up

    Returns:
        str: MAC address or None if not found
    """
    try:
        # Try using ip neigh (modern systems)
        result = subprocess.run(
            ['ip', 'neigh', 'show', ip_address],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            # Parse output: "192.168.100.10 dev ens192 lladdr aa:bb:cc:dd:ee:ff REACHABLE"
            match = re.search(r'lladdr\s+([0-9a-fA-F:]{17})', result.stdout)
            if match:
                return match.group(1).lower()

        # Fallback to arp command (older systems)
        result = subprocess.run(
            ['arp', '-n', ip_address],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            # Parse output looking for MAC address pattern
            match = re.search(r'([0-9a-fA-F:]{17})', result.stdout)
            if match:
                return match.group(1).lower()

        logger.warning(f"Could not find MAC address for IP {ip_address}")
        return None

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout while looking up MAC for {ip_address}")
        return None
    except Exception as e:
        logger.error(f"Error getting MAC for {ip_address}: {str(e)}")
        return None


def is_already_authorized(mac_address):
    """
    Check if a MAC address is already authorized.

    Args:
        mac_address (str): The MAC address to check

    Returns:
        bool: True if authorized, False otherwise
    """
    try:
        # Check iptables rules
        result = subprocess.run(
            ['iptables', '-L', 'FORWARD', '-n', '-v'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            # Look for MAC address in the output
            if mac_address.lower() in result.stdout.lower():
                return True

        # Check authorized clients file
        if os.path.exists(AUTHORIZED_CLIENTS_FILE):
            with open(AUTHORIZED_CLIENTS_FILE, 'r') as f:
                for line in f:
                    if mac_address.lower() in line.lower():
                        return True

        return False

    except Exception as e:
        logger.error(f"Error checking authorization for {mac_address}: {str(e)}")
        return False


def add_firewall_rule(mac_address, ip_address):
    """
    Add iptables rule to allow traffic from a specific MAC address.

    Args:
        mac_address (str): The MAC address to authorize
        ip_address (str): The IP address (for logging)

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # Add NAT PREROUTING exceptions for DNS/HTTP/HTTPS (to skip portal redirect)
        # These must be added BEFORE the general redirect rules
        nat_cmds = [
            # Exception for DNS UDP (port 53)
            ['iptables', '-t', 'nat', '-I', 'PREROUTING', '1',
             '-i', 'ens192', '-p', 'udp', '--dport', '53',
             '-m', 'mac', '--mac-source', mac_address, '-j', 'RETURN'],
            # Exception for DNS TCP (port 53)
            ['iptables', '-t', 'nat', '-I', 'PREROUTING', '1',
             '-i', 'ens192', '-p', 'tcp', '--dport', '53',
             '-m', 'mac', '--mac-source', mac_address, '-j', 'RETURN'],
            # Exception for HTTP (port 80)
            ['iptables', '-t', 'nat', '-I', 'PREROUTING', '1',
             '-i', 'ens192', '-p', 'tcp', '--dport', '80',
             '-m', 'mac', '--mac-source', mac_address, '-j', 'RETURN'],
            # Exception for HTTPS (port 443)
            ['iptables', '-t', 'nat', '-I', 'PREROUTING', '1',
             '-i', 'ens192', '-p', 'tcp', '--dport', '443',
             '-m', 'mac', '--mac-source', mac_address, '-j', 'RETURN']
        ]

        for cmd in nat_cmds:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                logger.error(f"Failed to add NAT rule: {result.stderr}")
                return False

        logger.info(f"Added NAT exceptions for MAC {mac_address}")

        # Add rule to allow forwarding for this MAC address
        # Insert at position 1 (before the DROP rule)
        cmd = [
            'iptables',
            '-I', 'FORWARD', '1',
            '-m', 'mac',
            '--mac-source', mac_address,
            '-j', 'ACCEPT'
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            logger.error(f"Failed to add iptables rule: {result.stderr}")
            return False

        logger.info(f"Added firewall rule for MAC {mac_address} (IP: {ip_address})")

        # Save to authorized clients file
        os.makedirs(os.path.dirname(AUTHORIZED_CLIENTS_FILE), exist_ok=True)
        with open(AUTHORIZED_CLIENTS_FILE, 'a') as f:
            f.write(f"{mac_address},{ip_address}\n")

        # Save iptables rules permanently
        subprocess.run(
            ['netfilter-persistent', 'save'],
            capture_output=True,
            timeout=10
        )

        return True

    except subprocess.TimeoutExpired:
        logger.error("Timeout while adding firewall rule")
        return False
    except Exception as e:
        logger.error(f"Error adding firewall rule: {str(e)}")
        return False


@app.route('/authorize', methods=['POST'])
def authorize():
    """
    Handle authorization requests from clients.
    Extract client IP and MAC, then add firewall rule.
    """
    try:
        # Get client IP address
        # Check X-Forwarded-For header first (if behind proxy)
        client_ip = request.headers.get('X-Forwarded-For', request.remote_addr)
        if ',' in client_ip:
            client_ip = client_ip.split(',')[0].strip()

        logger.info(f"Authorization request from IP: {client_ip}")

        # Get MAC address from IP
        mac_address = get_mac_from_ip(client_ip)

        if not mac_address:
            logger.error(f"Could not determine MAC address for IP {client_ip}")
            return jsonify({
                'success': False,
                'message': 'Could not determine device MAC address'
            }), 400

        logger.info(f"Client MAC address: {mac_address}")

        # Check if already authorized
        if is_already_authorized(mac_address):
            logger.info(f"Client {mac_address} is already authorized")
            return jsonify({
                'success': True,
                'message': 'Already authorized',
                'ip': client_ip,
                'mac': mac_address
            })

        # Add firewall rule
        if add_firewall_rule(mac_address, client_ip):
            logger.info(f"Successfully authorized client {mac_address} ({client_ip})")
            return jsonify({
                'success': True,
                'message': 'Authorization successful',
                'ip': client_ip,
                'mac': mac_address
            })
        else:
            logger.error(f"Failed to authorize client {mac_address} ({client_ip})")
            return jsonify({
                'success': False,
                'message': 'Failed to add authorization rule'
            }), 500

    except Exception as e:
        logger.error(f"Error processing authorization request: {str(e)}")
        return jsonify({
            'success': False,
            'message': f'Server error: {str(e)}'
        }), 500


@app.route('/check-auth', methods=['GET'])
def check_auth():
    """
    Check if a client is already authorized.
    """
    try:
        # Get client IP
        client_ip = request.headers.get('X-Forwarded-For', request.remote_addr)
        if ',' in client_ip:
            client_ip = client_ip.split(',')[0].strip()

        # Get MAC address
        mac_address = get_mac_from_ip(client_ip)

        if not mac_address:
            return jsonify({
                'authorized': False,
                'message': 'Could not determine MAC address'
            })

        # Check if authorized
        authorized = is_already_authorized(mac_address)

        return jsonify({
            'authorized': authorized,
            'ip': client_ip,
            'mac': mac_address
        })

    except Exception as e:
        logger.error(f"Error checking authorization: {str(e)}")
        return jsonify({
            'authorized': False,
            'message': f'Error: {str(e)}'
        })


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint.
    """
    return jsonify({
        'status': 'healthy',
        'service': 'captiveportal-authorization'
    })


if __name__ == '__main__':
    # Ensure directories exist
    os.makedirs(os.path.dirname(AUTHORIZED_CLIENTS_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

    # Run Flask app
    # In production, use gunicorn or uwsgi instead
    logger.info("Starting Captive Portal Authorization Service")
    app.run(
        host='127.0.0.1',
        port=5000,
        debug=False
    )
