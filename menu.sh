#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main}"
INSTALL_DIR="/opt/singbox-node-cascade"
CONFIG="/etc/sing-box/config.json"
DATA_DIR="/root/singbox-node-cascade"
ENV_FILE="$DATA_DIR/node.env"
SETTINGS_FILE="$DATA_DIR/settings.conf"
BACKUP_DIR="$DATA_DIR/backups"

mkdir -p "$DATA_DIR" "$BACKUP_DIR"

red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
cyan() { echo -e "\033[36m$*\033[0m"; }
bold() { echo -e "\033[1m$*\033[0m"; }

pause() {
  echo
  read -rp "$(tr pause)" _
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    red "Run as root."
    exit 1
  fi
}

init_lang() {
  if [ -f "$SETTINGS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$SETTINGS_FILE"
  fi

  if [ -z "${LANGUAGE:-}" ]; then
    clear
    echo "======================================"
    echo " SingBox Node Cascade Manager"
    echo "======================================"
    echo
    echo "Choose language / Выберите язык:"
    echo "1) Русский"
    echo "2) English"
    echo
    read -rp "> " lang_choice
    case "$lang_choice" in
      2) LANGUAGE="en" ;;
      *) LANGUAGE="ru" ;;
    esac
    echo "LANGUAGE=$LANGUAGE" > "$SETTINGS_FILE"
  fi
}

tr() {
  local key="$1"
  case "${LANGUAGE:-ru}:$key" in
    ru:pause) echo "Нажми Enter..." ;;
    en:pause) echo "Press Enter..." ;;

    ru:title) echo "SingBox Node Cascade Manager" ;;
    en:title) echo "SingBox Node Cascade Manager" ;;

    ru:subtitle) echo "NODE1 -> NODE2 | VLESS Reality Vision" ;;
    en:subtitle) echo "NODE1 -> NODE2 | VLESS Reality Vision" ;;

    ru:menu1) echo "1) Настроить NODE2 / выходной сервер" ;;
    en:menu1) echo "1) Configure NODE2 / EXIT node" ;;
    ru:menu2) echo "2) Настроить NODE1 / входной сервер -> NODE2" ;;
    en:menu2) echo "2) Configure NODE1 / ENTRY node -> NODE2" ;;
    ru:menu3) echo "3) Показать параметры ноды" ;;
    en:menu3) echo "3) Show node info" ;;
    ru:menu4) echo "4) Показать клиентскую ссылку" ;;
    en:menu4) echo "4) Show client link" ;;
    ru:menu5) echo "5) Показать QR-код" ;;
    en:menu5) echo "5) Show QR code" ;;
    ru:menu6) echo "6) Изменить SNI" ;;
    en:menu6) echo "6) Change SNI" ;;
    ru:menu7) echo "7) Изменить NODE2 на NODE1" ;;
    en:menu7) echo "7) Change NODE2 on NODE1" ;;
    ru:menu8) echo "8) Перезапустить sing-box" ;;
    en:menu8) echo "8) Restart sing-box" ;;
    ru:menu9) echo "9) Статус и последние логи" ;;
    en:menu9) echo "9) Status and last logs" ;;
    ru:menu10) echo "10) Смотреть логи онлайн" ;;
    en:menu10) echo "10) Live logs" ;;
    ru:menu11) echo "11) Создать резервную копию конфига" ;;
    en:menu11) echo "11) Backup config" ;;
    ru:menu12) echo "12) Диагностика" ;;
    en:menu12) echo "12) Diagnostics" ;;
    ru:menu13) echo "13) Обновить менеджер из GitHub" ;;
    en:menu13) echo "13) Update manager from GitHub" ;;
    ru:menu14) echo "14) Сменить язык" ;;
    en:menu14) echo "14) Change language" ;;
    ru:menu0) echo "0) Выход" ;;
    en:menu0) echo "0) Exit" ;;

    ru:choice) echo "Выбор: " ;;
    en:choice) echo "Choice: " ;;

    ru:wrong) echo "Неверный выбор." ;;
    en:wrong) echo "Wrong choice." ;;

    ru:no_info) echo "Сохранённые данные не найдены. Сначала настрой NODE1 или NODE2." ;;
    en:no_info) echo "No saved node info. Configure NODE1 or NODE2 first." ;;

    ru:node2_ready) echo "NODE2 готов." ;;
    en:node2_ready) echo "NODE2 is ready." ;;
    ru:node1_ready) echo "NODE1 готов." ;;
    en:node1_ready) echo "NODE1 is ready." ;;

    ru:copy_node2) echo "СКОПИРУЙ ЭТИ ДАННЫЕ В NODE1:" ;;
    en:copy_node2) echo "COPY THESE VALUES TO NODE1:" ;;

    ru:client_link) echo "КЛИЕНТСКАЯ ССЫЛКА:" ;;
    en:client_link) echo "CLIENT LINK:" ;;

    ru:only_node1_link) echo "Клиентская ссылка есть только на NODE1." ;;
    en:only_node1_link) echo "Client link exists only on NODE1." ;;

    ru:config_missing) echo "Конфиг sing-box не найден." ;;
    en:config_missing) echo "sing-box config not found." ;;

    ru:sni_changed) echo "SNI изменён." ;;
    en:sni_changed) echo "SNI changed." ;;

    ru:node2_changed) echo "NODE2 изменён." ;;
    en:node2_changed) echo "NODE2 changed." ;;

    ru:updated) echo "Менеджер обновлён." ;;
    en:updated) echo "Manager updated." ;;

    *) echo "$key" ;;
  esac
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

gen_uuid() { sing-box generate uuid; }
gen_keypair() { sing-box generate reality-keypair; }
gen_shortid() { openssl rand -hex 8; }

backup_config() {
  if [ -f "$CONFIG" ]; then
    local file="$BACKUP_DIR/config-$(date +%F-%H%M%S).json"
    cp "$CONFIG" "$file"
    green "Backup saved: $file"
  else
    yellow "$(tr config_missing)"
  fi
}

check_port_443() {
  if ss -tulpn | grep -qE '[:.]443\s'; then
    yellow "Port 443 is already used:"
    ss -tulpn | grep -E '[:.]443\s' || true
    echo
    if [ "${LANGUAGE:-ru}" = "ru" ]; then
      read -rp "Продолжить всё равно? [y/N]: " ans
    else
      read -rp "Continue anyway? [y/N]: " ans
    fi
    [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]] || exit 1
  fi
}

ensure_autostart() {
  mkdir -p /etc/systemd/system/sing-box.service.d
  cat >/etc/systemd/system/sing-box.service.d/restart.conf <<EOF
[Service]
Restart=always
RestartSec=5s
LimitNOFILE=infinity
EOF
  systemctl daemon-reload
  systemctl enable sing-box || true
}

restart_safe() {
  sing-box check -c "$CONFIG"
  ensure_autostart
  systemctl restart sing-box
  sleep 0.3
  systemctl status sing-box --no-pager || true
}

build_client_link() {
  echo "vless://${NODE1_UUID}@${NODE1_ADDR}:443?type=tcp&security=reality&pbk=${NODE1_PUBLIC_KEY}&fp=chrome&sni=${NODE1_SNI}&sid=${NODE1_SHORT_ID}&spx=%2F&flow=xtls-rprx-vision&encryption=none#SingBox-NODE1-NODE2"
}

configure_node2() {
  cyan "=== NODE2 / EXIT ==="
  check_port_443

  if [ "${LANGUAGE:-ru}" = "ru" ]; then
    read -rp "SNI для NODE2 [api-maps.yandex.ru]: " NODE2_SNI
  else
    read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
  fi
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

  green "$(tr node2_ready)"
  echo
  cyan "$(tr copy_node2)"
  echo "NODE2_UUID=$NODE2_UUID"
  echo "NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY"
  echo "NODE2_SHORT_ID=$NODE2_SHORT_ID"
  echo "NODE2_SNI=$NODE2_SNI"
}

configure_node1() {
  cyan "=== NODE1 / ENTRY -> NODE2 ==="
  check_port_443

  if [ "${LANGUAGE:-ru}" = "ru" ]; then
    read -rp "IP или домен NODE2: " NODE2_ADDR
    read -rp "UUID NODE2: " NODE2_UUID
    read -rp "PublicKey NODE2: " NODE2_PUBLIC_KEY
    read -rp "ShortID NODE2: " NODE2_SHORT_ID
    read -rp "SNI NODE2 [api-maps.yandex.ru]: " NODE2_SNI
    NODE2_SNI=${NODE2_SNI:-api-maps.yandex.ru}
    read -rp "SNI NODE1 [api-maps.yandex.ru]: " NODE1_SNI
  else
    read -rp "NODE2 IP/domain: " NODE2_ADDR
    read -rp "NODE2 UUID: " NODE2_UUID
    read -rp "NODE2 PublicKey: " NODE2_PUBLIC_KEY
    read -rp "NODE2 ShortID: " NODE2_SHORT_ID
    read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
    NODE2_SNI=${NODE2_SNI:-api-maps.yandex.ru}
    read -rp "NODE1 SNI [api-maps.yandex.ru]: " NODE1_SNI
  fi
  NODE1_SNI=${NODE1_SNI:-api-maps.yandex.ru}

  DETECTED_IP=$(curl -4 -s ifconfig.me || true)
  if [ "${LANGUAGE:-ru}" = "ru" ]; then
    read -rp "Публичный IP/домен NODE1 для клиентской ссылки [$DETECTED_IP]: " NODE1_ADDR
  else
    read -rp "NODE1 public IP/domain for client link [$DETECTED_IP]: " NODE1_ADDR
  fi
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

  green "$(tr node1_ready)"
  echo
  cyan "$(tr client_link)"
  build_client_link
}

show_info() {
  load_env
  if [ ! -f "$ENV_FILE" ]; then
    yellow "$(tr no_info)"
    return
  fi

  echo "====================================="
  echo "ROLE: ${ROLE:-unknown}"
  echo "VERSION: $VERSION"
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
    yellow "$(tr only_node1_link)"
    return
  fi
  build_client_link
}

show_qr() {
  load_env
  if [ "${ROLE:-}" != "NODE1" ]; then
    yellow "$(tr only_node1_link)"
    return
  fi
  LINK=$(build_client_link)
  echo "$LINK"
  echo
  qrencode -t ANSIUTF8 "$LINK"
}

choose_sni() {
  echo "SNI:"
  echo "1) api-maps.yandex.ru"
  echo "2) yastatic.net"
  echo "3) avatars.mds.yandex.net"
  echo "4) mc.yandex.ru"
  echo "5) custom"
  read -rp "> " n
  case "$n" in
    1) echo "api-maps.yandex.ru" ;;
    2) echo "yastatic.net" ;;
    3) echo "avatars.mds.yandex.net" ;;
    4) echo "mc.yandex.ru" ;;
    5)
      if [ "${LANGUAGE:-ru}" = "ru" ]; then
        read -rp "Свой SNI: " custom
      else
        read -rp "Custom SNI: " custom
      fi
      echo "$custom"
      ;;
    *) echo "api-maps.yandex.ru" ;;
  esac
}

change_sni() {
  load_env
  if [ ! -f "$CONFIG" ]; then
    red "$(tr config_missing)"
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
    green "$(tr sni_changed): $NEW_SNI"
    return
  fi

  if [ "${ROLE:-}" = "NODE1" ]; then
    if [ "${LANGUAGE:-ru}" = "ru" ]; then
      echo "Что менять?"
      echo "1) SNI входа NODE1"
      echo "2) SNI выхода NODE1 -> NODE2"
      echo "3) Оба"
    else
      echo "What SNI to change?"
      echo "1) NODE1 inbound SNI"
      echo "2) NODE2 outbound SNI"
      echo "3) Both"
    fi
    read -rp "> " c
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
        red "$(tr wrong)"
        return
        ;;
    esac

    mv /tmp/singbox-config.json "$CONFIG"
    restart_safe
    green "$(tr sni_changed): $NEW_SNI"
    echo
    cyan "$(tr client_link)"
    show_link
    return
  fi

  red "$(tr no_info)"
}

change_node2() {
  load_env
  if [ "${ROLE:-}" != "NODE1" ]; then
    red "This option is only for NODE1."
    return
  fi

  if [ "${LANGUAGE:-ru}" = "ru" ]; then
    read -rp "Новый IP/домен NODE2: " NODE2_ADDR
    read -rp "Новый UUID NODE2: " NODE2_UUID
    read -rp "Новый PublicKey NODE2: " NODE2_PUBLIC_KEY
    read -rp "Новый ShortID NODE2: " NODE2_SHORT_ID
    read -rp "Новый SNI NODE2 [api-maps.yandex.ru]: " NODE2_SNI
  else
    read -rp "New NODE2 IP/domain: " NODE2_ADDR
    read -rp "New NODE2 UUID: " NODE2_UUID
    read -rp "New NODE2 PublicKey: " NODE2_PUBLIC_KEY
    read -rp "New NODE2 ShortID: " NODE2_SHORT_ID
    read -rp "New NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
  fi
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
  green "$(tr node2_changed)"
}

status_logs() {
  systemctl status sing-box --no-pager || true
  echo
  cyan "Ports:"
  ss -tulpn | grep -E '443|sing-box' || true
  echo
  cyan "Logs:"
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
  echo -n "enabled: "
  systemctl is-enabled sing-box || true
  echo -n "active: "
  systemctl is-active sing-box || true
  echo
  echo "=== ports ==="
  ss -tulpn | grep -E '443|sing-box' || true
  echo
  echo "=== public IP ==="
  curl -4 -s ifconfig.me || true
  echo
  load_env
  if [ "${ROLE:-}" = "NODE1" ]; then
    echo
    echo "=== NODE1 -> NODE2 TCP test ==="
    nc -vz "$NODE2_ADDR" 443 || true
  fi
}

update_manager() {
  mkdir -p "$INSTALL_DIR"
  wget -qO "$INSTALL_DIR/menu.sh" "$REPO_RAW/menu.sh"
  chmod +x "$INSTALL_DIR/menu.sh"
  ln -sf "$INSTALL_DIR/menu.sh" /usr/local/bin/singbox-menu
  green "$(tr updated)"
}

change_language() {
  echo "1) Русский"
  echo "2) English"
  read -rp "> " n
  case "$n" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="ru" ;;
  esac
  echo "LANGUAGE=$LANGUAGE" > "$SETTINGS_FILE"
}

main_menu() {
  while true; do
    clear
    bold "======================================"
    bold " $(tr title) v$VERSION"
    bold " $(tr subtitle)"
    bold "======================================"
    echo "$(tr menu1)"
    echo "$(tr menu2)"
    echo "$(tr menu3)"
    echo "$(tr menu4)"
    echo "$(tr menu5)"
    echo "$(tr menu6)"
    echo "$(tr menu7)"
    echo "$(tr menu8)"
    echo "$(tr menu9)"
    echo "$(tr menu10)"
    echo "$(tr menu11)"
    echo "$(tr menu12)"
    echo "$(tr menu13)"
    echo "$(tr menu14)"
    echo "$(tr menu0)"
    echo
    read -rp "$(tr choice)" choice

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
      13) update_manager; pause ;;
      14) change_language; pause ;;
      0) exit 0 ;;
      *) red "$(tr wrong)"; pause ;;
    esac
  done
}

need_root
init_lang
main_menu
