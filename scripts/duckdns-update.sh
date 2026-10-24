#!/usr/bin/env bash
# ==============================================================================
# DuckDNS Dynamic IP Auto-Updater
# Reads /etc/duckdns.conf (DUCKDNS_DOMAIN & DUCKDNS_TOKEN)
# ==============================================================================
set -euo pipefail

CONF_FILE="${DUCKDNS_CONF:-/etc/duckdns.conf}"
if [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

DOMAIN="${DUCKDNS_DOMAIN:-}"
TOKEN="${DUCKDNS_TOKEN:-}"
EXPLICIT_IP="${DUCKDNS_IP:-}"

# Strip accidental .duckdns.org suffix if user included it
DOMAIN="${DOMAIN%.duckdns.org}"

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
  # Not configured yet; exit cleanly so duckdns.timer stays quiet
  exit 0
fi

# Detect public IPv4 if not explicitly provided (letting DuckDNS auto-detect if all fail)
IPV4="$EXPLICIT_IP"
if [ -z "$IPV4" ]; then
  for endpoint in "https://api4.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me/ip"; do
    IPV4="$(curl -4 -fsSL --connect-timeout 4 --max-time 6 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$IPV4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      break
    fi
    IPV4=""
  done
fi

UPDATE_URL="https://www.duckdns.org/update?domains=${DOMAIN}&token=${TOKEN}&ip=${IPV4}"
RESPONSE="$(curl -fsSL --connect-timeout 8 --max-time 15 "$UPDATE_URL" 2>/dev/null || echo "ERROR")"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if [ "$RESPONSE" = "OK" ]; then
  echo "[$TIMESTAMP] DuckDNS OK: ${DOMAIN}.duckdns.org -> ${IPV4:-auto}"
else
  echo "[$TIMESTAMP] DuckDNS update failed for ${DOMAIN}.duckdns.org (response: $RESPONSE)" >&2
  exit 1
fi
