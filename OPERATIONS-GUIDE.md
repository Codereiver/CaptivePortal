# Captive Portal - Operations Guide

## Quick Reference Commands

### View Portal Status
```bash
sudo /usr/local/bin/portal-status.sh
```

### Force Client Re-authentication

**De-authorize all clients:**
```bash
sudo /usr/local/bin/deauthorize-client.sh all
```

**De-authorize specific client by MAC:**
```bash
sudo /usr/local/bin/deauthorize-client.sh 00:0c:29:10:2c:75
```

**List current authorizations:**
```bash
sudo /usr/local/bin/deauthorize-client.sh
```

### View Logs

**Authorization service logs:**
```bash
sudo journalctl -u captiveportal -f
```

**All portal services:**
```bash
sudo journalctl -u captiveportal -u nginx -u dnsmasq -u isc-dhcp-server -f
```

**nginx access log:**
```bash
sudo tail -f /var/log/nginx/captiveportal-access.log
```

### Restart Services

**All services:**
```bash
sudo systemctl restart captiveportal nginx dnsmasq isc-dhcp-server
```

**Individual service:**
```bash
sudo systemctl restart captiveportal
```

## How the Portal Detection Works

Modern operating systems automatically detect captive portals by attempting to fetch specific URLs:

### Windows Detection
Windows tries to fetch: `http://www.msftconnecttest.com/connecttest.txt`

When it gets redirected to your portal (instead of the expected text file), Windows:
1. Detects a captive portal is present
2. Shows a notification: "Sign in to network"
3. Opens a browser window to the portal page

### Other OS Detection URLs

- **Apple iOS/macOS**: `http://captive.apple.com/hotspot-detect.html`
- **Android**: `http://connectivitycheck.gstatic.com/generate_204`
- **Firefox**: `http://detectportal.firefox.com/success.txt`

All these URLs are configured in nginx to redirect to the portal page.

## Why You Might Need Multiple Refreshes

This can happen for several reasons:

### 1. Browser DNS Caching
Browsers cache DNS responses. After authorization:
- Old cached DNS entries still point to portal IP
- Solution: Clear browser cache or wait for TTL expiration

### 2. Established TCP Connections
If the browser already has open connections:
- Those connections remain pointed at the portal
- Solution: Close and reopen browser, or wait for connections to timeout

### 3. HSTS (HTTP Strict Transport Security)
Some sites enforce HTTPS and are in browser HSTS lists:
- Browser automatically upgrades HTTP to HTTPS
- Before authorization, HTTPS requests fail (firewall blocks them)
- Solution: Use HTTP-only sites for initial testing

### 4. Timing Issues
The authorization process takes a moment:
- Firewall rules are added sequentially
- DNS exceptions may take effect before HTTP exceptions
- Solution: Wait 2-3 seconds after clicking "Connect" before browsing

## Best Practices for Smooth Experience

### For Testing/Demo:

1. **Always start fresh:**
   ```bash
   sudo /usr/local/bin/deauthorize-client.sh all
   ```

2. **On Windows client:**
   ```cmd
   ipconfig /release
   ipconfig /renew
   ipconfig /flushdns
   ```

3. **Close all browsers**

4. **Open browser and go to:**
   - `http://neverssl.com` (best for testing)
   - `http://example.com`
   - Any HTTP site (not HTTPS)

5. **You should see portal immediately**

6. **Click "Connect"**

7. **Wait 3-5 seconds**

8. **Try browsing - should work seamlessly**

### For Production:

1. **Don't clear authorized clients** - let them stay authorized

2. **DHCP lease time** is set to 600 seconds (10 minutes)
   - Clients remain authorized even after lease expires
   - They're tracked by MAC address, not IP

3. **Firewall rules persist** through reboots
   - Saved with `netfilter-persistent save`

4. **Client authorizations persist** through reboots
   - Stored in `/var/lib/captiveportal/authorized_clients.txt`

## Automatic Portal Detection (Windows)

Windows **should** automatically detect the portal when you connect. If it doesn't:

### Common Reasons:

1. **Windows Network Location Awareness (NLA) service not running**
   ```cmd
   # On Windows, check if running:
   sc query NlaSvc
   ```

2. **Windows thinks it's a "private" or "domain" network**
   - Solution: Set network to "Public" in Windows settings

3. **Firewall blocking detection requests**
   - Check: `sudo tail -f /var/log/nginx/captiveportal-access.log`
   - You should see requests to `/connecttest.txt`

4. **Windows has cached a previous network state**
   - Solution: Forget the network and reconnect

### Force Windows to Re-Detect:

On Windows client:
```cmd
# Restart Network Location Awareness service
net stop NlaSvc
net start NlaSvc

# Or restart networking entirely
ipconfig /release
ipconfig /renew
```

## Seamless Experience - How Real Portals Do It

Real captive portals (Starbucks, airports, hotels) achieve seamless experience by:

### 1. **Only Redirecting HTTP (not HTTPS)**
- HTTPS sites fail silently for unauthorized clients
- No scary SSL errors
- ✅ **Your portal now does this**

### 2. **Responding to OS Detection URLs**
- Windows, iOS, Android all probe for captive portals
- Portal intercepts and redirects these probes
- ✅ **Your portal now does this**

### 3. **Fast Authorization**
- Single click grants access
- No forms, no passwords
- ✅ **Your portal does this**

### 4. **Proper DNS Handling**
- Unauthorized: DNS returns portal IP
- Authorized: DNS returns real IPs
- ✅ **Your portal now does this**

### 5. **MAC-based Tracking**
- Clients stay authorized even if IP changes
- Works across DHCP lease renewals
- ✅ **Your portal does this**

## Troubleshooting Smooth Experience

### Issue: "Takes several refreshes to work"

**Diagnosis:**
```bash
# Watch what's happening in real-time
sudo tcpdump -i ens192 -n host [CLIENT_IP]

# In another terminal
sudo journalctl -u captiveportal -f

# In another terminal
sudo tail -f /var/log/nginx/captiveportal-access.log
```

**Common causes:**

1. **Browser trying HTTPS sites**
   - Test with `http://neverssl.com` instead

2. **DNS cache**
   - On Windows: `ipconfig /flushdns`

3. **Browser cache**
   - Hard refresh: Ctrl+Shift+R (Windows)

4. **Multiple firewall rules for same MAC**
   - Check: `sudo iptables -t nat -L PREROUTING -n -v --line-numbers`
   - Should see only 2 rules per authorized MAC (DNS UDP + TCP, HTTP)
   - If duplicates: `sudo /usr/local/bin/deauthorize-client.sh all`

### Issue: "Windows doesn't show portal notification"

**Fix:**
```bash
# On portal server - check if detection URLs are being requested
sudo grep "connecttest\|generate_204" /var/log/nginx/captiveportal-access.log

# Should see entries like:
# 192.168.100.10 - - [date] "GET /connecttest.txt HTTP/1.1" 302
```

If you **don't** see these requests:
- Windows may not be probing for captive portal
- Set network to "Public" on Windows
- Restart NLA service on Windows

If you **do** see these requests but no popup:
- Windows detected it but didn't show notification
- Manually open browser and go to any HTTP site

### Issue: "SSL errors on some sites"

This is **normal** for unauthorized clients attempting HTTPS:
- Unauthorized clients can't access internet at all
- HTTPS requests will timeout or fail
- This is intentional - it prevents access until authorized

After authorization:
- If still getting SSL errors, check time/date on client
- Ensure client DNS is resolving correctly: `nslookup google.com`

## Monitoring

### Watch authorizations happen in real-time:
```bash
sudo journalctl -u captiveportal -f
```

You'll see:
```
Authorization request from IP: 192.168.100.10
Client MAC address: 00:0c:29:10:2c:75
Added NAT exceptions for MAC 00:0c:29:10:2c:75
Added firewall rule for MAC 00:0c:29:10:2c:75 (IP: 192.168.100.10)
Successfully authorized client 00:0c:29:10:2c:75 (192.168.100.10)
```

### See active connections:
```bash
sudo netstat -an | grep :80 | grep ESTABLISHED
```

### Monitor DNS queries:
```bash
sudo tail -f /var/log/dnsmasq.log
```

## Performance Tips

### If you have many clients:

1. **Increase dnsmasq cache:**
   Edit `/etc/dnsmasq.d/captiveportal.conf`:
   ```
   cache-size=10000
   ```

2. **Monitor firewall rule count:**
   ```bash
   sudo iptables -L -n | wc -l
   ```
   If > 1000 rules, performance may degrade

3. **Periodically clean old authorizations:**
   ```bash
   # Clear clients that haven't been seen in 24 hours
   # (You'd need to implement time-based tracking)
   ```

## Security Notes

1. **Anyone can click "Connect"** - there's no authentication
   - This is a simple "click to accept" portal
   - For user auth, you'd need to add login functionality

2. **MAC addresses can be spoofed**
   - This provides basic access control, not security
   - Don't use for high-security environments

3. **HTTP traffic is unencrypted**
   - Portal uses HTTP (not HTTPS)
   - For production, add SSL certificate

4. **Firewall rules persist**
   - Authorized clients stay authorized until you clear them
   - Consider implementing time-based expiry

## Backup and Restore

### Backup authorized clients:
```bash
cp /var/lib/captiveportal/authorized_clients.txt ~/authorized_clients_backup.txt
```

### Backup firewall rules:
```bash
sudo iptables-save > ~/iptables_backup.rules
```

### Restore:
```bash
# Restore client list
sudo cp ~/authorized_clients_backup.txt /var/lib/captiveportal/authorized_clients.txt

# Restore firewall
sudo iptables-restore < ~/iptables_backup.rules
sudo netfilter-persistent save
```

## Summary

Your captive portal now works like commercial captive portals:

✅ Automatic OS detection (Windows, iOS, Android, etc.)
✅ No HTTPS redirection (no SSL errors)
✅ Smooth one-click authorization
✅ MAC-based tracking (survives IP changes)
✅ Proper DNS handling for auth/unauth clients
✅ Easy management commands

The "multiple refreshes" issue should be largely resolved with these updates.
