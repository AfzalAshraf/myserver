#!/usr/bin/env bash
# ==============================================================================
# Stremio VPS Stack — Boot Fix Script
# Ensures TCP BBR is active and Oracle Cloud / Ubuntu iptables rules allow
# HTTP (80), HTTPS/HTTP3 (443), TeleStremio (8000), and PencariMovie (8088).
# ==============================================================================
set -euo pipefail

# 1. Load TCP BBR kernel module & apply streaming sysctl parameters
modprobe tcp_bbr 2>/dev/null || true
if [ -f /etc/sysctl.d/99-stremio-turbo.conf ]; then
  sysctl -p /etc/sysctl.d/99-stremio-turbo.conf >/dev/null 2>&1 || true
fi

# 2. Oracle Cloud (OCI) Ubuntu images ship default iptables INPUT REJECT rules
#    that block ports 80/443/8000/8088 even after opening VCN Security Lists.
#    If INPUT contains a REJECT rule, ensure streaming ports are accepted above it.
if command -v iptables >/dev/null 2>&1; then
  if iptables -S INPUT 2>/dev/null | grep -qE -- '-j (REJECT|DROP)'; then
    allow_port() {
      local proto="$1" port="$2"
      if ! iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
      fi
    }
    allow_port tcp 80
    allow_port tcp 443
    allow_port udp 443
    allow_port tcp 8000
    allow_port tcp 8088
  fi
fi

# 3. Ensure static dashboard directory remains world-readable for Caddy
if [ -d /var/www/stremio-dashboard ]; then
  chmod 755 /var/www/stremio-dashboard 2>/dev/null || true
  chmod -R a+r /var/www/stremio-dashboard 2>/dev/null || true
fi

echo "stremio-boot-fix: BBR and firewall checks applied."
