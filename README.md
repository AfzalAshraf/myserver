# 🎬 Stremio All-in-One VPS Media Stack

A lightweight, high-performance self-hosted media streaming stack for **Oracle Cloud (ARM64 Ampere / x86_64)** and **Ubuntu 22.04 / 24.04 LTS** servers.

---

## ✨ Included Components

1. **TeleStremio (`weebzone/Telegram-Stremio`)** — Self-hosted Telegram-to-Stremio & Nuvio media server (FastAPI + MongoDB + PyroFork) managed via Docker Compose and `systemd` (`telestremio.service`).
2. **PencariMovie Server (`aiskendi/pencarimovie-server`)** — Native Rust MTProto HTTP 206 byte-range streaming bridge & on-demand search addon for Stremio, Nuvio, and Eclipse Music. Auto-detects **ARM64 (`aarch64`)** vs **Intel/AMD (`x86_64`)** and verifies SHA-256 release checksums.
3. **Caddy Reverse Proxy (`Caddyfile.example`)** — Automatic Let's Encrypt HTTPS with unbuffered video streaming (`flush_interval -1`), persistent upstream keepalives, and selective metadata compression.
4. **Kernel TCP BBR & Socket Buffer Tuning (`config/99-stremio-turbo.conf`)** — Enables `fq` + `bbr` congestion control and 16 MB TCP buffers for fast seek times and bufferless HD/4K playback.
5. **DuckDNS Auto-Updater & Cloud Boot-Fix (`duckdns.timer` + `stremio-boot-fix.service`)** — Keeps your DuckDNS IP updated every 5 minutes and automatically ensures Oracle Cloud `iptables` rules and `tcp_bbr` stay active across reboots.
6. **Unified Landing Dashboard (`dashboard/index.html`)** — Zero-dependency control hub with live health/latency checks, Stremio `stremio://` 1-click install links, Nuvio Collection & Eclipse Music URL builders, and quick SSH commands.

---

## 🚀 Quick Install (Fresh Ubuntu 22.04 / 24.04 VPS)

SSH into your server and run:

```bash
git clone https://github.com/AfzalAshraf/myserver.git
cd myserver
sudo ./install.sh
```

> **Oracle Cloud Security List Note:** Make sure ingress ports **`80/TCP`**, **`443/TCP`**, and **`443/UDP`** (plus **`8000/TCP`** and **`8088/TCP`** if testing directly via IP without HTTPS) are open in your cloud provider's VCN Security List / Firewall. Host-level Ubuntu `iptables` rules are handled automatically by `stremio-boot-fix.service`.

Immediately after `install.sh` finishes:
- **Unified Dashboard** is live at `http://<YOUR_VPS_IP>/`
- **PencariMovie Server** is live at `http://<YOUR_VPS_IP>:8088/` with an auto-generated `SERVER_PASSWORD` and permanent `SERVER_TOKEN` printed in the terminal summary.

---

## ⚙️ Post-Install Configuration

### 1. Configure TeleStremio (`:8000`)

Edit `/home/ubuntu/telegram-stremio/config.env` with your credentials from [my.telegram.org](https://my.telegram.org), [@BotFather](https://t.me/BotFather), and MongoDB Atlas (2 comma-separated URIs for tracking & storage):

```bash
nano /home/ubuntu/telegram-stremio/config.env
sudo tsrestart
```

*First launch builds the container (~1–2 minutes). Follow live build/runtime logs anytime with `tsrestart --logs`.*

---

### 2. Configure PencariMovie Server (`:8088`)

`install.sh` automatically creates `/home/ubuntu/pencarimovie/.env` with a unique `SERVER_TOKEN` and `SERVER_PASSWORD` so your Stremio manifest URL never changes across restarts.

To view or customize settings:

```bash
sudo nano /home/ubuntu/pencarimovie/.env
sudo systemctl restart pencarimovie
```

- **Direct Stremio / Nuvio Manifest:** `http://<YOUR_VPS_IP>:8088/<SERVER_TOKEN>/manifest.json`
- **Eclipse Music Manifest:** `http://<YOUR_VPS_IP>:8088/eclipse/manifest.json`

---

### 3. Enable Free HTTPS with DuckDNS + Caddy (Recommended)

Stremio Web, Android TV, and mobile apps work best over **HTTPS**. A **single** free [DuckDNS](https://www.duckdns.org) domain (e.g. `mystremio.duckdns.org`) automatically resolves wildcard subdomains (`ts.mystremio.duckdns.org` and `pm.mystremio.duckdns.org`) to your server IP, allowing Caddy to issue Let's Encrypt certificates for all three services automatically:

1. **Configure DuckDNS auto-updater:**
   ```bash
   sudo nano /etc/duckdns.conf
   # Set DUCKDNS_DOMAIN="yoursubdomain" and DUCKDNS_TOKEN="your-duckdns-token"

   sudo /usr/local/bin/duckdns-update.sh
   ```

2. **Activate the streaming Caddyfile:**
   ```bash
   sudo cp /etc/caddy/Caddyfile.example /etc/caddy/Caddyfile
   sudo sed -i 's/YOUR_DOMAIN\.duckdns\.org/yoursubdomain.duckdns.org/g' /etc/caddy/Caddyfile
   sudo caddy validate --config /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

3. **Your HTTPS endpoints are now live:**
   | Service | HTTPS URL |
   | :--- | :--- |
   | **Unified Landing Dashboard** | `https://yoursubdomain.duckdns.org` |
   | **TeleStremio Web Panel** | `https://ts.yoursubdomain.duckdns.org/login` |
   | **TeleStremio Manifest** | `https://ts.yoursubdomain.duckdns.org/stremio/<TOKEN>/manifest.json` |
   | **PencariMovie Dashboard** | `https://pm.yoursubdomain.duckdns.org` |
   | **PencariMovie Manifest** | `https://pm.yoursubdomain.duckdns.org/<SERVER_TOKEN>/manifest.json` |

> Remember to set **Settings → Base URL** in TeleStremio's web panel to `https://ts.yoursubdomain.duckdns.org`.

---

## 🛠️ Management CLI Commands

The installer registers helper utilities in `/usr/local/bin`:

| Command | Description |
| :--- | :--- |
| `stack-status` | Check CPU arch, active BBR congestion control, systemd service health, and local HTTP probes |
| `sudo tsrestart` | Restart TeleStremio and verify port `8000` health |
| `sudo tsrestart --update` | Pull latest `weebzone/Telegram-Stremio` commits and rebuild container |
| `tsrestart --logs` | Tail live TeleStremio logs (`journalctl -u telestremio -f`) |
| `sudo systemctl restart pencarimovie` | Restart PencariMovie Server |
| `journalctl -u pencarimovie -f` | Tail live PencariMovie logs |
| `sudo ./install.sh` | Re-run safely anytime to update PencariMovie binary & refresh stack files (preserves `storage/`, `.env`, and `config.env`) |

---

## 📂 Repository Layout

```text
.
├── install.sh                         # All-in-one ARM64 / x86_64 Ubuntu installer
├── Caddyfile.example                  # Streaming-optimized Caddy reverse proxy config
├── config/
│   ├── 99-stremio-turbo.conf          # Kernel TCP BBR + 16 MB socket buffer tuning
│   ├── duckdns.conf.example           # DuckDNS credentials template
│   ├── pencarimovie.env.example       # PencariMovie Server .env template
│   └── telestremio.config.env.example # TeleStremio config.env template
├── dashboard/
│   └── index.html                     # Unified Landing Dashboard UI
├── scripts/
│   ├── duckdns-update.sh              # Dynamic DNS updater script
│   ├── stack-status                   # Full stack diagnostics & endpoint summary
│   ├── stremio-boot-fix.sh            # Boot-time BBR & Oracle Cloud iptables helper
│   └── tsrestart                      # TeleStremio lifecycle CLI
└── systemd/
    ├── duckdns.service                # DuckDNS oneshot unit
    ├── duckdns.timer                  # 5-minute periodic DuckDNS timer
    ├── pencarimovie.service           # PencariMovie systemd daemon (65536 fd limit)
    ├── stremio-boot-fix.service       # Boot ordering & firewall persistence unit
    └── telestremio.service            # TeleStremio Docker Compose systemd unit
```
