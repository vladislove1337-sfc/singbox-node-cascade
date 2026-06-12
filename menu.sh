#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/sing-box/config.json"
DATA_DIR="/root/singbox-node-cascade"
ENV_FILE="$DATA_DIR/node.env"
BACKUP_DIR="$DATA_DIR/backups"

mkdir -p "$DATA_DIR" "$BACKUP_DIR"

red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
cyan() { echo -e "\033[36m$*\033[0m"; }

pause() {
  echo
  read -rp "Press Enter..."
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    red "Run as root."
    exit 1
  fi
}

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

save_env_node2() {
  cat > "$ENV_FILE" <<EOF
ROLE=NODE2
NODE2_UUID=$NODE2_UUID
NODE2_PRIVATE_KEY=$NODE2_PRIVATE_KEY
NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY
NODE2_SHORT_ID=$NODE2_SHORT_ID
NODE2_SNI=$NODE2_SNI
EOF
}

save_env_node1() {
  CLIENT_LINK=$(build_client_link)
  cat > "$ENV_FILE" <<EOF
ROLE=NODE1
NODE1_ADDR=$NODE1_ADDR
NODE1_UUID=$NODE1_UUID
NODE1_PRIVATE_KEY=$NODE1_PRIVATE_KEY
NODE1_PUBLIC_KEY=$NODE1_PUBLIC_KEY
NODE1_SHORT_ID=$NODE1_SHORT_ID
NODE1_SNI=$NODE1_SNI
NODE2_ADDR=$NODE2_ADDR
NODE2_UUID=$NODE2_UUID
NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY
NODE2_SHORT_ID=$NODE2_SHORT_ID
NODE2_SNI=$NODE2_SNI
CLIENT_LINK=$CLIENT_LINK
EOF
}

gen_uuid() {
  sing-box generate uuid
}

gen_keypair() {
  sing-box generate reality-keypair
}

gen_shortid() {
  openssl rand -hex 8
}

backup_config() {
  if [ -f "$CONFIG" ]; then
    local file="$BACKUP_DIR/config-$(date +%F-%H%M%S).json"
    cp "$CONFIG" "$file"
    green "Backup saved: $file"
  else
    yellow "Config not found."
  fi
}

check_port_443() {
  if ss -tulpn | grep -qE '[:.]443\s'; then
    yellow "Port 443 is already used:"
    ss -tulpn | grep -E '[:.]443\s' || true
    echo
    read -rp "Continue anyway? [y/N]: " ans
    [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]] || exit 1
  fi
}

restart_safe() {
  sing-box check -c "$CONFIG"
  systemctl daemon-reload
  systemctl enable sing-box || true
  systemctl restart sing-box
  sleep 0.3
  systemctl status sing-box --no-pager || true
}

build_client_link() {
  echo "vless://${NODE1_UUID}@${NODE1_ADDR}:443?type=tcp&security=reality&pbk=${NODE1_PUBLIC_KEY}&fp=chrome&sni=${NODE1_SNI}&sid=${NODE1_SHORT_ID}&spx=%2F&flow=xtls-rprx-vision&encryption=none#SingBox-NODE1-NODE2"
}

configure_node2() {
  cyan "=== Configure NODE2 / EXIT ==="
  check_port_443

  read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
  NODE2_SNI=${NODE2_SNI:-api-maps.yandex.ru}

  NODE2_UUID=$(gen_uuid)
  KP=$(gen_keypair)
  NODE2_PRIVATE_KEY=$(echo "$KP" | awk '/PrivateKey:/ {print $2}')
  NODE2_PUBLIC_KEY=$(echo "$KP" | awk '/PublicKey:/ {print $2}')
  NODE2_SHORT_ID=$(gen_shortid)

  backup_config

  cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "node2-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$NODE2_UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$NODE2_SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$NODE2_SNI",
            "server_port": 443
          },
          "private_key": "$NODE2_PRIVATE_KEY",
          "short_id": [
            "$NODE2_SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF

  restart_safe
  save_env_node2

  green "NODE2 configured."
  echo
  cyan "COPY THESE VALUES TO NODE1:"
  echo "NODE2_UUID=$NODE2_UUID"
  echo "NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY"
  echo "NODE2_SHORT_ID=$NODE2_SHORT_ID"
  echo "NODE2_SNI=$NODE2_SNI"
}

configure_node1() {
  cyan "=== Configure NODE1 / ENTRY -> NODE2 ==="
  check_port_443

  read -rp "NODE2 IP/domain: " NODE2_ADDR
  read -rp "NODE2 UUID: " NODE2_UUID
  read -rp "NODE2 PublicKey: " NODE2_PUBLIC_KEY
  read -rp "NODE2 ShortID: " NODE2_SHORT_ID
  read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
  NODE2_SNI=${NODE2_SNI:-api-maps.yandex.ru}

  read -rp "NODE1 SNI [api-maps.yandex.ru]: " NODE1_SNI
  NODE1_SNI=${NODE1_SNI:-api-maps.yandex.ru}

  DETECTED_IP=$(curl -4 -s ifconfig.me || true)
  read -rp "NODE1 public IP/domain for client link [$DETECTED_IP]: " NODE1_ADDR
  NODE1_ADDR=${NODE1_ADDR:-$DETECTED_IP}

  NODE1_UUID=$(gen_uuid)
  KP=$(gen_keypair)
  NODE1_PRIVATE_KEY=$(echo "$KP" | awk '/PrivateKey:/ {print $2}')
  NODE1_PUBLIC_KEY=$(echo "$KP" | awk '/PublicKey:/ {print $2}')
  NODE1_SHORT_ID=$(gen_shortid)

  backup_config

  cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "node1-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$NODE1_UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$NODE1_SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$NODE1_SNI",
            "server_port": 443
          },
          "private_key": "$NODE1_PRIVATE_KEY",
          "short_id": [
            "$NODE1_SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "node2-out",
      "server": "$NODE2_ADDR",
      "server_port": 443,
      "uuid": "$NODE2_UUID",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$NODE2_SNI",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "$NODE2_PUBLIC_KEY",
          "short_id": "$NODE2_SHORT_ID"
        }
      }
    }
  ],
  "route": {
    "final": "node2-out"
  }
}
EOF

  restart_safe
  save_env_node1

  green "NODE1 configured."
  echo
  cyan "CLIENT LINK:"
  build_client_link
}

show_info() {
  load_env
  if [ ! -f "$ENV_FILE" ]; then
    yellow "No saved info."
    return
  fi

  echo "====================================="
  echo "ROLE: ${ROLE:-unknown}"
  echo "====================================="
  if [ "${ROLE:-}" = "NODE1" ]; then
    echo "NODE1 / ENTRY:"
    echo "Address:    ${NODE1_ADDR:-}"
    echo "UUID:       ${NODE1_UUID:-}"
    echo "PrivateKey: ${NODE1_PRIVATE_KEY:-}"
    echo "PublicKey:  ${NODE1_PUBLIC_KEY:-}"
    echo "ShortID:    ${NODE1_SHORT_ID:-}"
    echo "SNI:        ${NODE1_SNI:-}"
    echo
    echo "NODE2 / EXIT:"
    echo "Address:   ${NODE2_ADDR:-}"
    echo "UUID:      ${NODE2_UUID:-}"
    echo "PublicKey: ${NODE2_PUBLIC_KEY:-}"
    echo "ShortID:   ${NODE2_SHORT_ID:-}"
    echo "SNI:       ${NODE2_SNI:-}"
  elif [ "${ROLE:-}" = "NODE2" ]; then
    echo "NODE2 / EXIT:"
    echo "UUID:       ${NODE2_UUID:-}"
    echo "PrivateKey: ${NODE2_PRIVATE_KEY:-}"
    echo "PublicKey:  ${NODE2_PUBLIC_KEY:-}"
    echo "ShortID:    ${NODE2_SHORT_ID:-}"
    echo "SNI:        ${NODE2_SNI:-}"
  fi
}

show_link() {
  load_env
  if [ "${ROLE:-}" != "NODE1" ]; then
    yellow "Client link exists only on NODE1."
    return
  fi
  build_client_link
}

show_qr() {
  load_env
  if [ "${ROLE:-}" != "NODE1" ]; then
    yellow "QR exists only on NODE1."
    return
  fi
  LINK=$(build_client_link)
  echo "$LINK"
  echo
  qrencode -t ANSIUTF8 "$LINK"
}

choose_sni() {
  echo "Choose SNI:"
  echo "1) api-maps.yandex.ru"
  echo "2) yastatic.net"
  echo "3) avatars.mds.yandex.net"
  echo "4) mc.yandex.ru"
  echo "5) custom"
  read -rp "Choice: " n
  case "$n" in
    1) echo "api-maps.yandex.ru" ;;
    2) echo "yastatic.net" ;;
    3) echo "avatars.mds.yandex.net" ;;
    4) echo "mc.yandex.ru" ;;
    5) read -rp "Custom SNI: " custom; echo "$custom" ;;
    *) echo "api-maps.yandex.ru" ;;
  esac
}

change_sni() {
  load_env
  if [ ! -f "$CONFIG" ]; then
    red "Config not found."
    return
  fi

  if [ "${ROLE:-}" = "NODE2" ]; then
    NEW_SNI=$(choose_sni)
    jq --arg sni "$NEW_SNI" '
      .inbounds[0].tls.server_name = $sni |
      .inbounds[0].tls.reality.handshake.server = $sni
    ' "$CONFIG" > /tmp/singbox-config.json
    mv /tmp/singbox-config.json "$CONFIG"
    sed -i "s|^NODE2_SNI=.*|NODE2_SNI=$NEW_SNI|" "$ENV_FILE"
    restart_safe
    green "NODE2 SNI changed to $NEW_SNI"
    return
  fi

  if [ "${ROLE:-}" = "NODE1" ]; then
    echo "What SNI to change?"
    echo "1) NODE1 inbound SNI"
    echo "2) NODE2 outbound SNI"
    echo "3) Both"
    read -rp "Choice: " c
    NEW_SNI=$(choose_sni)

    case "$c" in
      1)
        jq --arg sni "$NEW_SNI" '
          .inbounds[0].tls.server_name = $sni |
          .inbounds[0].tls.reality.handshake.server = $sni
        ' "$CONFIG" > /tmp/singbox-config.json
        sed -i "s|^NODE1_SNI=.*|NODE1_SNI=$NEW_SNI|" "$ENV_FILE"
        ;;
      2)
        jq --arg sni "$NEW_SNI" '
          .outbounds[0].tls.server_name = $sni
        ' "$CONFIG" > /tmp/singbox-config.json
        sed -i "s|^NODE2_SNI=.*|NODE2_SNI=$NEW_SNI|" "$ENV_FILE"
        ;;
      3)
        jq --arg sni "$NEW_SNI" '
          .inbounds[0].tls.server_name = $sni |
          .inbounds[0].tls.reality.handshake.server = $sni |
          .outbounds[0].tls.server_name = $sni
        ' "$CONFIG" > /tmp/singbox-config.json
        sed -i "s|^NODE1_SNI=.*|NODE1_SNI=$NEW_SNI|" "$ENV_FILE"
        sed -i "s|^NODE2_SNI=.*|NODE2_SNI=$NEW_SNI|" "$ENV_FILE"
        ;;
      *)
        red "Wrong choice."
        return
        ;;
    esac

    mv /tmp/singbox-config.json "$CONFIG"
    restart_safe
    green "SNI changed to $NEW_SNI"
    echo
    cyan "New client link:"
    show_link
    return
  fi

  red "Unknown role. Configure node first."
}

change_node2() {
  load_env
  if [ "${ROLE:-}" != "NODE1" ]; then
    red "This option is only for NODE1."
    return
  fi

  read -rp "New NODE2 IP/domain: " NODE2_ADDR
  read -rp "New NODE2 UUID: " NODE2_UUID
  read -rp "New NODE2 PublicKey: " NODE2_PUBLIC_KEY
  read -rp "New NODE2 ShortID: " NODE2_SHORT_ID
  read -rp "New NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
  NODE2_SNI=${NODE2_SNI:-api-maps.yandex.ru}

  jq \
    --arg addr "$NODE2_ADDR" \
    --arg uuid "$NODE2_UUID" \
    --arg pbk "$NODE2_PUBLIC_KEY" \
    --arg sid "$NODE2_SHORT_ID" \
    --arg sni "$NODE2_SNI" \
    '
    .outbounds[0].server = $addr |
    .outbounds[0].uuid = $uuid |
    .outbounds[0].tls.server_name = $sni |
    .outbounds[0].tls.reality.public_key = $pbk |
    .outbounds[0].tls.reality.short_id = $sid
    ' "$CONFIG" > /tmp/singbox-config.json

  mv /tmp/singbox-config.json "$CONFIG"

  sed -i "s|^NODE2_ADDR=.*|NODE2_ADDR=$NODE2_ADDR|" "$ENV_FILE"
  sed -i "s|^NODE2_UUID=.*|NODE2_UUID=$NODE2_UUID|" "$ENV_FILE"
  sed -i "s|^NODE2_PUBLIC_KEY=.*|NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY|" "$ENV_FILE"
  sed -i "s|^NODE2_SHORT_ID=.*|NODE2_SHORT_ID=$NODE2_SHORT_ID|" "$ENV_FILE"
  sed -i "s|^NODE2_SNI=.*|NODE2_SNI=$NODE2_SNI|" "$ENV_FILE"

  restart_safe
  green "NODE2 changed."
}

status_logs() {
  systemctl status sing-box --no-pager || true
  echo
  ss -tulpn | grep -E '443|sing-box' || true
  echo
  journalctl -u sing-box -n 80 --no-pager || true
}

live_logs() {
  journalctl -u sing-box -f
}

diagnostics() {
  echo "=== sing-box check ==="
  sing-box check -c "$CONFIG" || true
  echo
  echo "=== service ==="
  systemctl is-enabled sing-box || true
  systemctl is-active sing-box || true
  echo
  echo "=== ports ==="
  ss -tulpn | grep -E '443|sing-box' || true
  echo
  load_env
  if [ "${ROLE:-}" = "NODE1" ]; then
    echo
    echo "=== NODE1 -> NODE2 TCP test ==="
    nc -vz "$NODE2_ADDR" 443 || true
  fi
}

main_menu() {
  while true; do
    clear
    echo "======================================"
    echo " SingBox Node Cascade Manager"
    echo " NODE1 -> NODE2"
    echo "======================================"
    echo "1) Configure NODE2 / EXIT"
    echo "2) Configure NODE1 / ENTRY -> NODE2"
    echo "3) Show node info"
    echo "4) Show client link"
    echo "5) Show QR code"
    echo "6) Change SNI"
    echo "7) Change NODE2 on NODE1"
    echo "8) Restart sing-box"
    echo "9) Status and last logs"
    echo "10) Live logs"
    echo "11) Backup config"
    echo "12) Diagnostics"
    echo "0) Exit"
    echo
    read -rp "Choice: " choice

    case "$choice" in
      1) configure_node2; pause ;;
      2) configure_node1; pause ;;
      3) show_info; pause ;;
      4) show_link; pause ;;
      5) show_qr; pause ;;
      6) change_sni; pause ;;
      7) change_node2; pause ;;
      8) restart_safe; pause ;;
      9) status_logs; pause ;;
      10) live_logs ;;
      11) backup_config; pause ;;
      12) diagnostics; pause ;;
      0) exit 0 ;;
      *) red "Wrong choice."; pause ;;
    esac
  done
}

need_root
main_menu
