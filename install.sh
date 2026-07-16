#!/usr/bin/env bash

set -euo pipefail

VERSION="1.1.0"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main}"
INSTALL_DIR="/opt/singbox-node-cascade"
BIN="/usr/local/bin/singbox-menu"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root:"
    echo "sudo bash install.sh"
    exit 1
fi

echo "======================================"
echo " SingBox Node Cascade Installer v$VERSION"
echo " NODE1 -> NODE2"
echo "======================================"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    wget \
    nano \
    jq \
    qrencode \
    openssl \
    ca-certificates \
    iproute2 \
    netcat-openbsd \
    python3 \
    gnupg \
    debian-keyring \
    debian-archive-keyring \
    apt-transport-https \
    dnsutils

mkdir -p "$INSTALL_DIR"
mkdir -p /root/singbox-node-cascade/backups

echo "[+] Installing / updating sing-box..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

echo "[+] Downloading manager menu..."
tmp_menu="$(mktemp)"
curl -fsSL "$REPO_RAW/menu.sh" -o "$tmp_menu"

if ! bash -n "$tmp_menu"; then
    rm -f "$tmp_menu"
    echo "Downloaded menu.sh has a syntax error."
    exit 1
fi

install -m 755 "$tmp_menu" "$INSTALL_DIR/menu.sh"
rm -f "$tmp_menu"
ln -sf "$INSTALL_DIR/menu.sh" "$BIN"

mkdir -p /etc/systemd/system/sing-box.service.d
cat > /etc/systemd/system/sing-box.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5s
LimitNOFILE=infinity
EOF

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1 || true

echo
echo "Installed."
echo "Run:"
echo "singbox-menu"
echo
