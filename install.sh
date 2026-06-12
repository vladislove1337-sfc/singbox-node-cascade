#!/usr/bin/env bash
set -e

apt update
apt install -y curl wget jq qrencode openssl netcat-openbsd

bash <(curl -fsSL https://sing-box.app/deb-install.sh)

mkdir -p /opt/singbox-node-cascade

wget -O /opt/singbox-node-cascade/menu.sh \
https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/menu.sh

chmod +x /opt/singbox-node-cascade/menu.sh

ln -sf /opt/singbox-node-cascade/menu.sh /usr/local/bin/singbox-menu

mkdir -p /etc/systemd/system/sing-box.service.d

cat >/etc/systemd/system/sing-box.service.d/restart.conf <<EOF
[Service]
Restart=always
RestartSec=5
LimitNOFILE=infinity
EOF

systemctl daemon-reload
systemctl enable sing-box || true

singbox-menu
