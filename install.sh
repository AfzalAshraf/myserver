#!/usr/bin/env bash
# ==============================================================================
# Stremio Media Server Stack — All-in-One VPS Deployer
# Repository: https://github.com/AfzalAshraf/myserver
# Supports:   Ubuntu 22.04 / 24.04 LTS (ARM64 aarch64 & x86_64)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "    Stremio Media Server Stack - Deployer"
echo "=================================================="

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root: sudo ./install.sh" >&2
  exit 1
fi

# Detect CPU architecture
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64)
    PENCARI_ARCH="aarch64"
    ;;
  x86_64|amd64)
    PENCARI_ARCH="x86_64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH (requires aarch64 or x86_64)" >&2
    exit 1
    ;;
esac

# Resolve non-root service user & home directory (supports sudo, sudo-rs, OCI ubuntu, Debian)
LOGIN_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -n "$LOGIN_USER" ] && [ "$LOGIN_USER" != "root" ] && id "$LOGIN_USER" >/dev/null 2>&1; then
  STACK_USER="$LOGIN_USER"
elif id ubuntu >/dev/null 2>&1; then
  STACK_USER="ubuntu"
else
  echo "Creating service user 'ubuntu'..."
  useradd -m -s /bin/bash ubuntu
  STACK_USER="ubuntu"
fi
STACK_GROUP="$(id -gn "$STACK_USER")"
STACK_HOME="$(getent passwd "$STACK_USER" | cut -d: -f6)"
[ -n "$STACK_HOME" ] || STACK_HOME="/home/$STACK_USER"

echo "Detected Architecture : $PENCARI_ARCH ($ARCH)"
echo "Target Stack User     : $STACK_USER ($STACK_HOME)"
echo ""

# ------------------------------------------------------------------------------
# [1/6] Dependencies
# ------------------------------------------------------------------------------
echo "[1/6] Installing Dependencies (Docker, Caddy, Curl, Git)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git tar unzip openssl iptables iproute2

if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y -qq caddy
fi

if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y -qq docker.io
fi

if ! docker compose version >/dev/null 2>&1; then
  if ! apt-get install -y -qq docker-compose-v2 2>/dev/null && ! apt-get install -y -qq docker-compose-plugin 2>/dev/null; then
    echo "Installing Docker Compose v2 CLI plugin directly..."
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${PENCARI_ARCH}" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi
fi

usermod -aG docker "$STACK_USER" 2>/dev/null || true

# ------------------------------------------------------------------------------
# [2/6] Kernel & Network BBR Tuning
# ------------------------------------------------------------------------------
echo "[2/6] Applying Kernel & Network BBR Tuning..."
install -m 0644 "$SCRIPT_DIR/config/99-stremio-turbo.conf" /etc/sysctl.d/99-stremio-turbo.conf
mkdir -p /etc/modules-load.d
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
modprobe tcp_bbr 2>/dev/null || true
sysctl -p /etc/sysctl.d/99-stremio-turbo.conf >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# [3/6] TeleStremio Setup
# ------------------------------------------------------------------------------
echo "[3/6] Setting up TeleStremio..."
TS_DIR="$STACK_HOME/telegram-stremio"
mkdir -p "$TS_DIR"
if [ ! -d "$TS_DIR/.git" ]; then
  git clone https://github.com/weebzone/Telegram-Stremio.git "$TS_DIR"
fi

# Prevent Docker from mounting config.env as a directory if missing
if [ -d "$TS_DIR/config.env" ]; then
  rm -rf "$TS_DIR/config.env"
fi
if [ ! -f "$TS_DIR/config.env" ]; then
  cp "$SCRIPT_DIR/config/telestremio.config.env.example" "$TS_DIR/config.env"
  chmod 600 "$TS_DIR/config.env"
fi
chown -R "$STACK_USER:$STACK_GROUP" "$TS_DIR"

# ------------------------------------------------------------------------------
# [4/6] PencariMovie Server Setup (Auto-detects ARM64 vs x86_64 + SHA-256 verify)
# ------------------------------------------------------------------------------
echo "[4/6] Downloading PencariMovie Server ($PENCARI_ARCH)..."
PM_DIR="$STACK_HOME/pencarimovie"
mkdir -p "$PM_DIR/storage"

TMP_STAGE="$(mktemp -d)"
trap 'rm -rf "$TMP_STAGE"' EXIT

PENCARI_ASSET="pencarimovie-server-linux-${PENCARI_ARCH}.tar.gz"
PENCARI_URL="https://github.com/aiskendi/pencarimovie-server/releases/latest/download/${PENCARI_ASSET}"

curl -fsSL "$PENCARI_URL" -o "$TMP_STAGE/$PENCARI_ASSET"

if curl -fsSL "${PENCARI_URL}.sha256" -o "$TMP_STAGE/${PENCARI_ASSET}.sha256" 2>/dev/null; then
  EXPECTED_SHA="$(grep -oE '[0-9a-fA-F]{64}' "$TMP_STAGE/${PENCARI_ASSET}.sha256" | head -n1 | tr 'A-F' 'a-f')"
  ACTUAL_SHA="$(sha256sum "$TMP_STAGE/$PENCARI_ASSET" | awk '{print tolower($1)}')"
  if [ -n "$EXPECTED_SHA" ] && [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "SHA-256 mismatch for $PENCARI_ASSET (expected $EXPECTED_SHA, got $ACTUAL_SHA)" >&2
    exit 1
  fi
fi

mkdir -p "$TMP_STAGE/extracted"
tar -xzf "$TMP_STAGE/$PENCARI_ASSET" --strip-components=1 -C "$TMP_STAGE/extracted"

# Stop running binary cleanly before replacing to avoid 'Text file busy'
systemctl stop pencarimovie 2>/dev/null || true

for item in "$TMP_STAGE/extracted"/*; do
  [ -e "$item" ] || continue
  base="$(basename "$item")"
  [ "$base" = "storage" ] && continue
  rm -rf "$PM_DIR/$base"
  cp -R "$item" "$PM_DIR/$base"
done
chmod +x "$PM_DIR/pencarimovie-server"
chmod +x "$PM_DIR"/*.sh 2>/dev/null || true

# Maintain legacy arch-subfolder symlink for compatibility
mkdir -p "$PM_DIR/pencarimovie-server-linux-${PENCARI_ARCH}"
ln -sfn ../pencarimovie-server "$PM_DIR/pencarimovie-server-linux-${PENCARI_ARCH}/pencarimovie-server"

# Generate persistent .env with random SERVER_TOKEN & SERVER_PASSWORD on first install
if [ ! -f "$PM_DIR/.env" ]; then
  GEN_TOKEN="$(openssl rand -hex 16)"
  GEN_PASS="$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 12)"
  cat <<EOF > "$PM_DIR/.env"
PM_LISTEN_HOST=0.0.0.0
PORT=8088
PM_APP_ROOT=$PM_DIR/storage
SERVER_PASSWORD=$GEN_PASS
SERVER_TOKEN=$GEN_TOKEN
EOF
  chmod 600 "$PM_DIR/.env"
fi
cp "$SCRIPT_DIR/config/pencarimovie.env.example" "$PM_DIR/.env.example"
chown -R "$STACK_USER:$STACK_GROUP" "$PM_DIR"

# ------------------------------------------------------------------------------
# [5/6] Unified Dashboard, Caddy & Systemd Services
# ------------------------------------------------------------------------------
echo "[5/6] Installing Dashboard, Caddy Config & Systemd Services..."

# Static Unified Landing Dashboard (world-readable for Caddy user)
mkdir -p /var/www/stremio-dashboard
install -m 0644 "$SCRIPT_DIR/dashboard/index.html" /var/www/stremio-dashboard/index.html
chmod 0755 /var/www/stremio-dashboard

# Caddy templates & initial HTTP dashboard config (auto-falls back to :8880 if :80 is occupied by AdGuard/Pi-hole/Nginx)
mkdir -p /etc/caddy
install -m 0644 "$SCRIPT_DIR/Caddyfile.example" /etc/caddy/Caddyfile.example
DASHBOARD_PORT="80"
if command -v ss >/dev/null 2>&1 && ss -tlnp '( sport = :80 )' 2>/dev/null | grep -v -q -E 'caddy|Local Address|^$'; then
  DASHBOARD_PORT="8880"
fi
if [ ! -f /etc/caddy/Caddyfile ] || grep -q "/usr/share/caddy" /etc/caddy/Caddyfile 2>/dev/null; then
  [ -f /etc/caddy/Caddyfile ] && cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
  if [ "$DASHBOARD_PORT" = "8880" ]; then
    cat <<'CADDY_INIT_ALT' > /etc/caddy/Caddyfile
{
	auto_https off
}

:8880 {
	root * /var/www/stremio-dashboard
	encode zstd gzip
	file_server
}
CADDY_INIT_ALT
  else
    cat <<'CADDY_INIT' > /etc/caddy/Caddyfile
:80 {
	root * /var/www/stremio-dashboard
	encode zstd gzip
	file_server
}
CADDY_INIT
  fi
fi

# DuckDNS config template
install -m 0644 "$SCRIPT_DIR/config/duckdns.conf.example" /etc/duckdns.conf.example
if [ ! -f /etc/duckdns.conf ]; then
  install -m 0600 "$SCRIPT_DIR/config/duckdns.conf.example" /etc/duckdns.conf
fi

# Helper CLI scripts (rewrite /home/ubuntu if custom user)
for script_path in "$SCRIPT_DIR"/scripts/*; do
  [ -f "$script_path" ] || continue
  script_name="$(basename "$script_path")"
  sed "s|/home/ubuntu|$STACK_HOME|g" "$script_path" > "/usr/local/bin/$script_name"
  chmod 0755 "/usr/local/bin/$script_name"
done

# Systemd units (rewrite user/group/home dynamically if needed)
for unit_path in "$SCRIPT_DIR"/systemd/*; do
  [ -f "$unit_path" ] || continue
  unit_name="$(basename "$unit_path")"
  sed \
    -e "s|/home/ubuntu|$STACK_HOME|g" \
    -e "s|^User=ubuntu$|User=$STACK_USER|g" \
    -e "s|^Group=ubuntu$|Group=$STACK_GROUP|g" \
    "$unit_path" > "/etc/systemd/system/$unit_name"
  chmod 0644 "/etc/systemd/system/$unit_name"
done

systemctl daemon-reload
systemctl enable stremio-boot-fix.service docker.service caddy.service pencarimovie.service telestremio.service duckdns.timer >/dev/null 2>&1 || true

systemctl start stremio-boot-fix.service
systemctl start docker.service
systemctl restart pencarimovie.service
systemctl reload-or-restart caddy.service || echo "Warning: Caddy failed to bind port (check /etc/caddy/Caddyfile)"
systemctl start duckdns.timer
# Starts TeleStremio if config.env is already populated; skips cleanly otherwise
systemctl start telestremio.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# [6/6] Summary
# ------------------------------------------------------------------------------
PUB_IP="$(curl -4 -fsSL --connect-timeout 3 --max-time 4 https://api4.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "<YOUR_VPS_IP>")"
PM_TOKEN="$(grep -E '^SERVER_TOKEN=' "$PM_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
PM_PASS="$(grep -E '^SERVER_PASSWORD=' "$PM_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
DASH_URL="http://${PUB_IP}/"
[ "$DASHBOARD_PORT" = "8880" ] && DASH_URL="http://${PUB_IP}:8880/ (port 80 was already in use)"

echo ""
echo "=================================================="
echo "[6/6] Installation Complete!"
echo "=================================================="
echo "Unified Dashboard   : ${DASH_URL}"
echo "PencariMovie UI     : http://${PUB_IP}:8088/"
echo "PencariMovie Pass   : ${PM_PASS}"
echo "PencariMovie Addon  : http://${PUB_IP}:8088/${PM_TOKEN}/manifest.json"
echo ""
echo "Next steps:"
echo " 1. Configure TeleStremio credentials:"
echo "      nano $TS_DIR/config.env"
echo "      sudo tsrestart"
echo " 2. (Optional) Enable DuckDNS + Automatic HTTPS via Caddy:"
echo "      sudo nano /etc/duckdns.conf"
echo "      sudo /usr/local/bin/duckdns-update.sh"
echo "      sudo cp /etc/caddy/Caddyfile.example /etc/caddy/Caddyfile"
echo "      sudo nano /etc/caddy/Caddyfile   # replace YOUR_DOMAIN.duckdns.org"
echo "      sudo systemctl reload caddy"
echo " 3. Check full stack status anytime:"
echo "      stack-status"
echo "=================================================="
