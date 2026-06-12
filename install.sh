#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main}"
INSTALL_DIR="/opt/singbox-node-cascade"
BIN="/usr/local/bin/singbox-menu"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "======================================"
echo " SingBox Node Cascade Installer v1.0.4"
echo " NODE1 -> NODE2"
echo "======================================"

apt update
apt install -y curl wget nano jq qrencode openssl ca-certificates iproute2 netcat-openbsd

mkdir -p "$INSTALL_DIR"

echo "[+] Installing / updating sing-box..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh)

echo "[+] Downloading manager menu..."
wget -qO "$INSTALL_DIR/menu.sh" "$REPO_RAW/menu.sh"
chmod +x "$INSTALL_DIR/menu.sh"

ln -sf "$INSTALL_DIR/menu.sh" "$BIN"

mkdir -p /etc/systemd/system/sing-box.service.d

cat >/etc/systemd/system/sing-box.service.d/restart.conf <<EOF
[Service]
Restart=always
RestartSec=5s
LimitNOFILE=infinity
EOF

systemctl daemon-reload
systemctl enable sing-box || true

echo
echo "Installed."
echo "Run:"
echo "singbox-menu"
echo
