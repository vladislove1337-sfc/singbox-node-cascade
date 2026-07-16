#!/usr/bin/env bash

set -euo pipefail

VERSION="1.1.0"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main}"

INSTALL_DIR="/opt/singbox-node-cascade"
CONFIG="/etc/sing-box/config.json"
DATA_DIR="/root/singbox-node-cascade"
ENV_FILE="$DATA_DIR/node.env"
SETTINGS_FILE="$DATA_DIR/settings.conf"
BACKUP_DIR="$DATA_DIR/backups"

SUB_ROOT="/var/lib/singbox-node-cascade-sub"
SUB_SERVICE="/etc/systemd/system/singbox-subscription.service"

CADDY_MAIN="/etc/caddy/Caddyfile"
CADDY_CONF_DIR="/etc/caddy/conf.d"
CADDY_SNIPPET="$CADDY_CONF_DIR/singbox-node-cascade.caddy"
WEB_ROOT="/var/www/singbox-node-cascade"

mkdir -p "$DATA_DIR" "$BACKUP_DIR"

red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
cyan()   { echo -e "\033[36m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        red "Run as root / Запусти от root."
        exit 1
    fi
}

is_ru() {
    [ "${LANGUAGE:-ru}" = "ru" ]
}

say() {
    local ru="$1"
    local en="$2"
    if is_ru; then
        echo "$ru"
    else
        echo "$en"
    fi
}

pause() {
    echo
    if is_ru; then
        read -rp "Нажми Enter..." _
    else
        read -rp "Press Enter..." _
    fi
}

confirm_yes() {
    local ru="$1"
    local en="$2"
    local answer
    if is_ru; then
        read -rp "$ru [y/N]: " answer
    else
        read -rp "$en [y/N]: " answer
    fi
    case "$answer" in
        y|Y|yes|YES|д|Д|да|ДА) return 0 ;;
        *) return 1 ;;
    esac
}

init_lang() {
    LANGUAGE=""
    if [ -f "$SETTINGS_FILE" ]; then
        # shellcheck disable=SC1090
        source "$SETTINGS_FILE" 2>/dev/null || true
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
        printf 'LANGUAGE=%q\n' "$LANGUAGE" > "$SETTINGS_FILE"
    fi
}

load_env() {
    local detected_domain=""

    unset ROLE \
        NODE1_ADDR NODE1_UUID NODE1_PRIVATE_KEY NODE1_PUBLIC_KEY NODE1_SHORT_ID NODE1_SNI NODE1_REALITY_PORT \
        NODE2_ADDR NODE2_PORT NODE2_UUID NODE2_PRIVATE_KEY NODE2_PUBLIC_KEY NODE2_SHORT_ID NODE2_SNI \
        SUB_PORT SUB_TOKEN \
        WORK_ENABLED WORK_DOMAIN WORK_UUID WORK_PATH WORK_LOCAL_PORT WORK_TLS_PORT \
        CADDY_INSTALLED_BY_MANAGER 2>/dev/null || true

    if [ -f "$ENV_FILE" ]; then
        # v1.0.6 and older stored an unquoted VLESS URL containing "&".
        sed -i '/^CLIENT_LINK=/d' "$ENV_FILE" 2>/dev/null || true
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi

    # Automatic migration for a WORK profile created before v1.1.0.
    # Nothing is written here: the values are only detected from the active config.
    if [ "${ROLE:-}" = "NODE1" ] && [ -f "$CONFIG" ]; then
        if [ -z "${NODE1_REALITY_PORT:-}" ]; then
            NODE1_REALITY_PORT="$(jq -r 'first(.inbounds[] | select(.tag == "node1-in") | .listen_port) // 443' "$CONFIG" 2>/dev/null || echo 443)"
        fi

        if jq -e '.inbounds[] | select(.tag == "work-ws-in")' "$CONFIG" >/dev/null 2>&1; then
            WORK_ENABLED="1"
            WORK_UUID="${WORK_UUID:-$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .users[0].uuid) // empty' "$CONFIG")}"
            WORK_PATH="${WORK_PATH:-$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .transport.path) // empty' "$CONFIG")}"
            WORK_LOCAL_PORT="${WORK_LOCAL_PORT:-$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .listen_port) // 2080' "$CONFIG")}"

            if [ -z "${WORK_DOMAIN:-}" ] && [ -f /root/work-ws.env ]; then
                detected_domain="$(sed -n 's/^WORK_DOMAIN=//p' /root/work-ws.env | tail -n 1)"
                detected_domain="${detected_domain%\"}"
                detected_domain="${detected_domain#\"}"
                detected_domain="${detected_domain%\'}"
                detected_domain="${detected_domain#\'}"
            fi

            if [ -z "${WORK_DOMAIN:-}" ] && [ -z "$detected_domain" ] && [ -f "$CADDY_SNIPPET" ]; then
                detected_domain="$(awk '/^[[:space:]]*[A-Za-z0-9.-]+[[:space:]]*\{/ {gsub(/[[:space:]\{]/, "", $0); print $0; exit}' "$CADDY_SNIPPET")"
            fi

            if [ -z "${WORK_DOMAIN:-}" ] && [ -z "$detected_domain" ] && [ -f "$CADDY_MAIN" ]; then
                detected_domain="$(awk '/^[[:space:]]*[A-Za-z0-9.-]+[[:space:]]*\{/ {gsub(/[[:space:]\{]/, "", $0); print $0; exit}' "$CADDY_MAIN")"
            fi

            WORK_DOMAIN="${WORK_DOMAIN:-$detected_domain}"
        fi
    fi

    NODE1_REALITY_PORT="${NODE1_REALITY_PORT:-443}"
    NODE2_PORT="${NODE2_PORT:-443}"
    WORK_ENABLED="${WORK_ENABLED:-0}"
    WORK_DOMAIN="${WORK_DOMAIN:-}"
    WORK_UUID="${WORK_UUID:-}"
    WORK_PATH="${WORK_PATH:-}"
    WORK_LOCAL_PORT="${WORK_LOCAL_PORT:-2080}"
    WORK_TLS_PORT="${WORK_TLS_PORT:-443}"
    CADDY_INSTALLED_BY_MANAGER="${CADDY_INSTALLED_BY_MANAGER:-0}"
}

env_set() {
    local key="$1"
    local value="$2"
    local tmp

    mkdir -p "$DATA_DIR"
    touch "$ENV_FILE"
    tmp="$(mktemp)"
    grep -v -E "^${key}=" "$ENV_FILE" > "$tmp" || true
    printf '%s=%q\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

env_unset() {
    local key="$1"
    local tmp

    [ -f "$ENV_FILE" ] || return 0
    tmp="$(mktemp)"
    grep -v -E "^${key}=" "$ENV_FILE" > "$tmp" || true
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

write_env_node2() {
    {
        printf 'ROLE=%q\n' "NODE2"
        printf 'NODE2_ADDR=%q\n' "${NODE2_ADDR:-}"
        printf 'NODE2_PORT=%q\n' "${NODE2_PORT:-443}"
        printf 'NODE2_UUID=%q\n' "$NODE2_UUID"
        printf 'NODE2_PRIVATE_KEY=%q\n' "$NODE2_PRIVATE_KEY"
        printf 'NODE2_PUBLIC_KEY=%q\n' "$NODE2_PUBLIC_KEY"
        printf 'NODE2_SHORT_ID=%q\n' "$NODE2_SHORT_ID"
        printf 'NODE2_SNI=%q\n' "$NODE2_SNI"
        printf 'WORK_ENABLED=%q\n' "0"
        printf 'CADDY_INSTALLED_BY_MANAGER=%q\n' "${CADDY_INSTALLED_BY_MANAGER:-0}"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

write_env_node1() {
    {
        printf 'ROLE=%q\n' "NODE1"
        printf 'NODE1_ADDR=%q\n' "$NODE1_ADDR"
        printf 'NODE1_UUID=%q\n' "$NODE1_UUID"
        printf 'NODE1_PRIVATE_KEY=%q\n' "$NODE1_PRIVATE_KEY"
        printf 'NODE1_PUBLIC_KEY=%q\n' "$NODE1_PUBLIC_KEY"
        printf 'NODE1_SHORT_ID=%q\n' "$NODE1_SHORT_ID"
        printf 'NODE1_SNI=%q\n' "$NODE1_SNI"
        printf 'NODE1_REALITY_PORT=%q\n' "${NODE1_REALITY_PORT:-443}"

        printf 'NODE2_ADDR=%q\n' "$NODE2_ADDR"
        printf 'NODE2_PORT=%q\n' "${NODE2_PORT:-443}"
        printf 'NODE2_UUID=%q\n' "$NODE2_UUID"
        printf 'NODE2_PUBLIC_KEY=%q\n' "$NODE2_PUBLIC_KEY"
        printf 'NODE2_SHORT_ID=%q\n' "$NODE2_SHORT_ID"
        printf 'NODE2_SNI=%q\n' "$NODE2_SNI"

        printf 'WORK_ENABLED=%q\n' "${WORK_ENABLED:-0}"
        printf 'CADDY_INSTALLED_BY_MANAGER=%q\n' "${CADDY_INSTALLED_BY_MANAGER:-0}"
        if [ "${WORK_ENABLED:-0}" = "1" ]; then
            printf 'WORK_DOMAIN=%q\n' "$WORK_DOMAIN"
            printf 'WORK_UUID=%q\n' "$WORK_UUID"
            printf 'WORK_PATH=%q\n' "$WORK_PATH"
            printf 'WORK_LOCAL_PORT=%q\n' "${WORK_LOCAL_PORT:-2080}"
            printf 'WORK_TLS_PORT=%q\n' "${WORK_TLS_PORT:-443}"
        fi

        if [ -n "${SUB_PORT:-}" ]; then
            printf 'SUB_PORT=%q\n' "$SUB_PORT"
        fi
        if [ -n "${SUB_TOKEN:-}" ]; then
            printf 'SUB_TOKEN=%q\n' "$SUB_TOKEN"
        fi
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

valid_domain() {
    local value="$1"
    [[ "$value" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

valid_host() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._:-]+$ ]]
}

valid_uuid() {
    local value="$1"
    [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

valid_short_id() {
    local value="$1"
    [[ "$value" =~ ^[0-9a-fA-F]{2,16}$ ]] && [ $(( ${#value} % 2 )) -eq 0 ]
}

valid_reality_public_key() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9_-]{40,64}$ ]]
}

valid_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

detect_public_ip() {
    curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null \
        || curl -4fsS --max-time 10 https://ifconfig.me 2>/dev/null \
        || true
}

urlencode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

gen_uuid() {
    sing-box generate uuid
}

gen_short_id() {
    openssl rand -hex 8
}

gen_reality_keypair() {
    local output private public
    output="$(sing-box generate reality-keypair)"
    private="$(awk -F': *' '/PrivateKey:/ {print $2; exit}' <<<"$output")"
    public="$(awk -F': *' '/PublicKey:/ {print $2; exit}' <<<"$output")"

    if [ -z "$private" ] || [ -z "$public" ]; then
        red "Failed to generate Reality keypair."
        return 1
    fi

    printf '%s\n%s\n' "$private" "$public"
}

install_restart_policy() {
    mkdir -p /etc/systemd/system/sing-box.service.d
    cat > /etc/systemd/system/sing-box.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5s
LimitNOFILE=infinity
EOF
    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1 || true
}

backup_config() {
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    if [ -f "$CONFIG" ]; then
        cp -a "$CONFIG" "$BACKUP_DIR/config.json.$stamp"
        green "$(say "Бэкап sing-box сохранён:" "sing-box backup saved:") $BACKUP_DIR/config.json.$stamp"
    fi
    if [ -f "$CADDY_MAIN" ]; then
        cp -a "$CADDY_MAIN" "$BACKUP_DIR/Caddyfile.$stamp"
    fi
    if [ -f "$CADDY_SNIPPET" ]; then
        cp -a "$CADDY_SNIPPET" "$BACKUP_DIR/singbox-node-cascade.caddy.$stamp"
    fi
}

check_config_file() {
    local file="$1"
    jq empty "$file"
    sing-box check -c "$file"
}

restart_singbox() {
    if [ ! -f "$CONFIG" ]; then
        red "$(say "Конфиг sing-box не найден." "sing-box config not found.")"
        return 1
    fi

    if ! check_config_file "$CONFIG"; then
        red "$(say "Конфиг не прошёл проверку." "Config validation failed.")"
        return 1
    fi

    systemctl restart sing-box
    if systemctl is-active --quiet sing-box; then
        green "$(say "sing-box перезапущен." "sing-box restarted.")"
        return 0
    fi

    red "$(say "sing-box не запустился." "sing-box failed to start.")"
    journalctl -u sing-box -n 80 --no-pager -l || true
    return 1
}

apply_singbox_config() {
    local candidate="$1"
    local old_config
    local had_old=0

    if ! check_config_file "$candidate"; then
        return 1
    fi

    old_config="$(mktemp)"
    if [ -f "$CONFIG" ]; then
        cp -a "$CONFIG" "$old_config"
        had_old=1
    fi

    mkdir -p "$(dirname "$CONFIG")"
    install -m 600 "$candidate" "$CONFIG"

    if restart_singbox; then
        rm -f "$old_config"
        return 0
    fi

    red "$(say "Новый конфиг не запустился — выполняю откат." "The new config failed to start — rolling back.")"

    if [ "$had_old" -eq 1 ]; then
        install -m 600 "$old_config" "$CONFIG"
        restart_singbox || true
    else
        rm -f "$CONFIG"
        systemctl stop sing-box 2>/dev/null || true
    fi

    rm -f "$old_config"
    return 1
}

build_reality_link() {
    load_env
    [ "${ROLE:-}" = "NODE1" ] || return 1
    printf 'vless://%s@%s:%s?type=tcp&security=reality&pbk=%s&fp=chrome&sni=%s&sid=%s&spx=%%2F&flow=xtls-rprx-vision&encryption=none#SingBox-NODE1-NODE2\n' \
        "$NODE1_UUID" "$NODE1_ADDR" "$NODE1_REALITY_PORT" \
        "$NODE1_PUBLIC_KEY" "$NODE1_SNI" "$NODE1_SHORT_ID"
}

build_work_link() {
    load_env
    [ "${ROLE:-}" = "NODE1" ] || return 1
    [ "${WORK_ENABLED:-0}" = "1" ] || return 1

    local encoded_path
    encoded_path="$(urlencode "$WORK_PATH")"

    printf 'vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&alpn=http%%2F1.1&type=ws&host=%s&path=%s#SingBox-WORK-NODE1-NODE2\n' \
        "$WORK_UUID" "$WORK_DOMAIN" "$WORK_TLS_PORT" \
        "$WORK_DOMAIN" "$WORK_DOMAIN" "$encoded_path"
}

update_subscription_file() {
    load_env
    [ "${ROLE:-}" = "NODE1" ] || return 0
    [ -n "${SUB_TOKEN:-}" ] || return 0
    [ -n "${SUB_PORT:-}" ] || return 0

    mkdir -p "$SUB_ROOT/$SUB_TOKEN"
    {
        build_reality_link
        if [ "${WORK_ENABLED:-0}" = "1" ]; then
            build_work_link
        fi
    } > "$SUB_ROOT/$SUB_TOKEN/sub.txt"

    chmod -R 700 "$SUB_ROOT"
}

remove_subscription_service() {
    systemctl disable --now singbox-subscription 2>/dev/null || true
    rm -f "$SUB_SERVICE"
    systemctl daemon-reload
}

configure_node2() {
    load_env

    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        red "$(say \
            "Сначала отключи Caddy / WORK-профиль в пункте 17. NODE2 должен освободить порт 443." \
            "Disable the Caddy / WORK profile in option 17 first. NODE2 needs port 443.")"
        return
    fi

    clear
    bold "======================================"
    bold " NODE2 / EXIT"
    bold "======================================"
    echo

    local detected_ip keypair tmp
    detected_ip="$(detect_public_ip)"

    if is_ru; then
        read -rp "Публичный IP/домен NODE2 [$detected_ip]: " NODE2_ADDR
        read -rp "SNI NODE2 [api-maps.yandex.ru]: " NODE2_SNI
    else
        read -rp "NODE2 public IP/domain [$detected_ip]: " NODE2_ADDR
        read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
    fi

    NODE2_ADDR="${NODE2_ADDR:-$detected_ip}"
    NODE2_SNI="${NODE2_SNI:-api-maps.yandex.ru}"
    NODE2_PORT=443

    if ! valid_host "$NODE2_ADDR"; then
        red "$(say "Некорректный IP/домен." "Invalid IP/domain.")"
        return
    fi
    if ! valid_domain "$NODE2_SNI"; then
        red "$(say "Некорректный SNI." "Invalid SNI.")"
        return
    fi

    NODE2_UUID="$(gen_uuid)"
    keypair="$(gen_reality_keypair)"
    NODE2_PRIVATE_KEY="$(sed -n '1p' <<<"$keypair")"
    NODE2_PUBLIC_KEY="$(sed -n '2p' <<<"$keypair")"
    NODE2_SHORT_ID="$(gen_short_id)"

    tmp="$(mktemp)"
    cat > "$tmp" <<EOF
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

    if ! check_config_file "$tmp"; then
        rm -f "$tmp"
        red "$(say "Новый конфиг NODE2 не прошёл проверку." "New NODE2 config failed validation.")"
        return
    fi

    backup_config
    install_restart_policy

    if ! apply_singbox_config "$tmp"; then
        rm -f "$tmp"
        return
    fi
    rm -f "$tmp"

    remove_subscription_service
    write_env_node2

    echo
    green "$(say "NODE2 готов." "NODE2 is ready.")"
    yellow "$(say "Скопируй эти параметры в NODE1:" "Copy these values to NODE1:")"
    echo
    echo "NODE2_ADDR=$NODE2_ADDR"
    echo "NODE2_PORT=443"
    echo "NODE2_UUID=$NODE2_UUID"
    echo "NODE2_PUBLIC_KEY=$NODE2_PUBLIC_KEY"
    echo "NODE2_SHORT_ID=$NODE2_SHORT_ID"
    echo "NODE2_SNI=$NODE2_SNI"
    echo
    yellow "$(say "NODE2_PRIVATE_KEY хранится только на NODE2." "NODE2_PRIVATE_KEY stays on NODE2 only.")"
}

configure_node1() {
    load_env

    clear
    bold "======================================"
    bold " NODE1 / ENTRY -> NODE2"
    bold "======================================"
    echo

    local detected_ip keypair tmp base_tmp
    local old_sub_port="${SUB_PORT:-}"
    local old_sub_token="${SUB_TOKEN:-}"
    local old_work_enabled="${WORK_ENABLED:-0}"
    local old_work_domain="${WORK_DOMAIN:-}"
    local old_work_uuid="${WORK_UUID:-}"
    local old_work_path="${WORK_PATH:-}"
    local old_work_local_port="${WORK_LOCAL_PORT:-2080}"
    local old_work_tls_port="${WORK_TLS_PORT:-443}"
    local old_caddy_owned="${CADDY_INSTALLED_BY_MANAGER:-0}"
    local old_reality_port="${NODE1_REALITY_PORT:-443}"

    if is_ru; then
        read -rp "IP или домен NODE2: " NODE2_ADDR
        read -rp "Порт NODE2 [443]: " NODE2_PORT
        read -rp "UUID NODE2: " NODE2_UUID
        read -rp "PublicKey NODE2: " NODE2_PUBLIC_KEY
        read -rp "ShortID NODE2: " NODE2_SHORT_ID
        read -rp "SNI NODE2 [api-maps.yandex.ru]: " NODE2_SNI
        read -rp "SNI входа NODE1 [api-maps.yandex.ru]: " NODE1_SNI
    else
        read -rp "NODE2 IP/domain: " NODE2_ADDR
        read -rp "NODE2 port [443]: " NODE2_PORT
        read -rp "NODE2 UUID: " NODE2_UUID
        read -rp "NODE2 PublicKey: " NODE2_PUBLIC_KEY
        read -rp "NODE2 ShortID: " NODE2_SHORT_ID
        read -rp "NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
        read -rp "NODE1 inbound SNI [api-maps.yandex.ru]: " NODE1_SNI
    fi

    NODE2_PORT="${NODE2_PORT:-443}"
    NODE2_SNI="${NODE2_SNI:-api-maps.yandex.ru}"
    NODE1_SNI="${NODE1_SNI:-api-maps.yandex.ru}"

    if ! valid_host "$NODE2_ADDR" || ! valid_port "$NODE2_PORT" || \
       ! valid_uuid "$NODE2_UUID" || ! valid_reality_public_key "$NODE2_PUBLIC_KEY" || \
       ! valid_short_id "$NODE2_SHORT_ID" || ! valid_domain "$NODE2_SNI" || \
       ! valid_domain "$NODE1_SNI"; then
        red "$(say "Один из параметров введён некорректно." "One or more values are invalid.")"
        return
    fi

    detected_ip="$(detect_public_ip)"
    if is_ru; then
        read -rp "Публичный IP/домен NODE1 для ссылки [$detected_ip]: " NODE1_ADDR
    else
        read -rp "NODE1 public IP/domain for client link [$detected_ip]: " NODE1_ADDR
    fi
    NODE1_ADDR="${NODE1_ADDR:-$detected_ip}"

    if ! valid_host "$NODE1_ADDR"; then
        red "$(say "Некорректный IP/домен NODE1." "Invalid NODE1 IP/domain.")"
        return
    fi

    NODE1_UUID="$(gen_uuid)"
    keypair="$(gen_reality_keypair)"
    NODE1_PRIVATE_KEY="$(sed -n '1p' <<<"$keypair")"
    NODE1_PUBLIC_KEY="$(sed -n '2p' <<<"$keypair")"
    NODE1_SHORT_ID="$(gen_short_id)"

    WORK_ENABLED="$old_work_enabled"
    WORK_DOMAIN="$old_work_domain"
    WORK_UUID="$old_work_uuid"
    WORK_PATH="$old_work_path"
    WORK_LOCAL_PORT="$old_work_local_port"
    WORK_TLS_PORT="$old_work_tls_port"
    CADDY_INSTALLED_BY_MANAGER="$old_caddy_owned"
    SUB_PORT="$old_sub_port"
    SUB_TOKEN="$old_sub_token"

    if [ "$WORK_ENABLED" = "1" ]; then
        NODE1_REALITY_PORT="$old_reality_port"
    else
        NODE1_REALITY_PORT=443
    fi

    base_tmp="$(mktemp)"
    cat > "$base_tmp" <<EOF
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
      "listen_port": $NODE1_REALITY_PORT,
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
      "server_port": $NODE2_PORT,
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

    tmp="$(mktemp)"
    if [ "$WORK_ENABLED" = "1" ]; then
        jq \
            --arg uuid "$WORK_UUID" \
            --arg path "$WORK_PATH" \
            --argjson local_port "$WORK_LOCAL_PORT" \
            '.inbounds += [
              {
                "type": "vless",
                "tag": "work-ws-in",
                "listen": "127.0.0.1",
                "listen_port": $local_port,
                "users": [
                  {
                    "uuid": $uuid
                  }
                ],
                "transport": {
                  "type": "ws",
                  "path": $path
                }
              }
            ]' "$base_tmp" > "$tmp"
        rm -f "$base_tmp"
    else
        mv "$base_tmp" "$tmp"
    fi

    if ! check_config_file "$tmp"; then
        rm -f "$tmp"
        red "$(say "Новый конфиг NODE1 не прошёл проверку." "New NODE1 config failed validation.")"
        return
    fi

    backup_config
    install_restart_policy

    if ! apply_singbox_config "$tmp"; then
        rm -f "$tmp"
        return
    fi
    rm -f "$tmp"

    write_env_node1
    update_subscription_file

    if [ "$WORK_ENABLED" = "1" ] && command -v caddy >/dev/null 2>&1; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
    fi

    echo
    green "$(say "NODE1 готов." "NODE1 is ready.")"
    show_links
}

show_info() {
    load_env

    if [ -z "${ROLE:-}" ]; then
        yellow "$(say "Сохранённые данные не найдены." "Saved node data not found.")"
        return
    fi

    echo "======================================"
    echo " ROLE: $ROLE"
    echo "======================================"

    if [ "$ROLE" = "NODE2" ]; then
        echo "NODE2_ADDR=${NODE2_ADDR:-}"
        echo "NODE2_PORT=${NODE2_PORT:-443}"
        echo "NODE2_UUID=${NODE2_UUID:-}"
        echo "NODE2_PUBLIC_KEY=${NODE2_PUBLIC_KEY:-}"
        echo "NODE2_SHORT_ID=${NODE2_SHORT_ID:-}"
        echo "NODE2_SNI=${NODE2_SNI:-}"
        echo
        yellow "$(say "Секрет, не передавать клиентам:" "Secret, do not share with clients:")"
        echo "NODE2_PRIVATE_KEY=${NODE2_PRIVATE_KEY:-}"
        return
    fi

    if [ "$ROLE" = "NODE1" ]; then
        echo "NODE1_ADDR=${NODE1_ADDR:-}"
        echo "NODE1_REALITY_PORT=${NODE1_REALITY_PORT:-443}"
        echo "NODE1_UUID=${NODE1_UUID:-}"
        echo "NODE1_PUBLIC_KEY=${NODE1_PUBLIC_KEY:-}"
        echo "NODE1_SHORT_ID=${NODE1_SHORT_ID:-}"
        echo "NODE1_SNI=${NODE1_SNI:-}"
        echo
        echo "NODE2_ADDR=${NODE2_ADDR:-}"
        echo "NODE2_PORT=${NODE2_PORT:-443}"
        echo "NODE2_UUID=${NODE2_UUID:-}"
        echo "NODE2_PUBLIC_KEY=${NODE2_PUBLIC_KEY:-}"
        echo "NODE2_SHORT_ID=${NODE2_SHORT_ID:-}"
        echo "NODE2_SNI=${NODE2_SNI:-}"
        echo
        yellow "$(say "Секрет NODE1:" "NODE1 secret:")"
        echo "NODE1_PRIVATE_KEY=${NODE1_PRIVATE_KEY:-}"

        if [ "${WORK_ENABLED:-0}" = "1" ]; then
            echo
            cyan "Caddy / WORK:"
            echo "WORK_DOMAIN=$WORK_DOMAIN"
            echo "WORK_TLS_PORT=$WORK_TLS_PORT"
            echo "WORK_LOCAL_PORT=$WORK_LOCAL_PORT"
            echo "WORK_UUID=$WORK_UUID"
            echo "WORK_PATH=$WORK_PATH"
        fi
    fi
}

show_links() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        yellow "$(say "Клиентские ссылки есть только на NODE1." "Client links exist only on NODE1.")"
        return
    fi

    cyan "$(say "REALITY-СЫЛКА:" "REALITY LINK:")"
    build_reality_link

    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        echo
        cyan "$(say "WORK TLS + WEBSOCKET:" "WORK TLS + WEBSOCKET:")"
        build_work_link
    fi
}

show_qr() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        yellow "$(say "QR-код есть только на NODE1." "QR code exists only on NODE1.")"
        return
    fi

    local choice link
    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        echo "1) Reality"
        echo "2) WORK TLS + WebSocket"
        read -rp "> " choice
    else
        choice=1
    fi

    case "$choice" in
        2) link="$(build_work_link)" ;;
        *) link="$(build_reality_link)" ;;
    esac

    echo "$link"
    echo
    qrencode -t ANSIUTF8 "$link"
}

choose_sni() {
    local n custom
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
            if is_ru; then
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
        red "$(say "Конфиг sing-box не найден." "sing-box config not found.")"
        return
    fi

    local new_sni choice tmp
    tmp="$(mktemp)"

    if [ "${ROLE:-}" = "NODE2" ]; then
        new_sni="$(choose_sni)"
        if ! valid_domain "$new_sni"; then
            rm -f "$tmp"
            red "$(say "Некорректный SNI." "Invalid SNI.")"
            return
        fi

        jq --arg sni "$new_sni" '
          (.inbounds[] | select(.tag == "node2-in") | .tls.server_name) = $sni
          | (.inbounds[] | select(.tag == "node2-in") | .tls.reality.handshake.server) = $sni
        ' "$CONFIG" > "$tmp"

        backup_config
        if ! apply_singbox_config "$tmp"; then
            rm -f "$tmp"
            return
        fi
        rm -f "$tmp"
        env_set "NODE2_SNI" "$new_sni"
        green "$(say "SNI NODE2 изменён." "NODE2 SNI changed.")"
        return
    fi

    if [ "${ROLE:-}" != "NODE1" ]; then
        rm -f "$tmp"
        yellow "$(say "Сначала настрой NODE1 или NODE2." "Configure NODE1 or NODE2 first.")"
        return
    fi

    if is_ru; then
        echo "Что менять?"
        echo "1) SNI входа NODE1"
        echo "2) SNI выхода NODE1 -> NODE2"
        echo "3) Оба"
    else
        echo "What should be changed?"
        echo "1) NODE1 inbound SNI"
        echo "2) NODE1 -> NODE2 outbound SNI"
        echo "3) Both"
    fi
    read -rp "> " choice

    new_sni="$(choose_sni)"
    if ! valid_domain "$new_sni"; then
        rm -f "$tmp"
        red "$(say "Некорректный SNI." "Invalid SNI.")"
        return
    fi

    case "$choice" in
        1)
            jq --arg sni "$new_sni" '
              (.inbounds[] | select(.tag == "node1-in") | .tls.server_name) = $sni
              | (.inbounds[] | select(.tag == "node1-in") | .tls.reality.handshake.server) = $sni
            ' "$CONFIG" > "$tmp"
            ;;
        2)
            jq --arg sni "$new_sni" '
              (.outbounds[] | select(.tag == "node2-out") | .tls.server_name) = $sni
            ' "$CONFIG" > "$tmp"
            ;;
        3)
            jq --arg sni "$new_sni" '
              (.inbounds[] | select(.tag == "node1-in") | .tls.server_name) = $sni
              | (.inbounds[] | select(.tag == "node1-in") | .tls.reality.handshake.server) = $sni
              | (.outbounds[] | select(.tag == "node2-out") | .tls.server_name) = $sni
            ' "$CONFIG" > "$tmp"
            ;;
        *)
            rm -f "$tmp"
            red "$(say "Неверный выбор." "Wrong choice.")"
            return
            ;;
    esac

    if ! check_config_file "$tmp"; then
        rm -f "$tmp"
        return
    fi

    backup_config
    if ! apply_singbox_config "$tmp"; then
        rm -f "$tmp"
        return
    fi
    rm -f "$tmp"

    case "$choice" in
        1) env_set "NODE1_SNI" "$new_sni" ;;
        2) env_set "NODE2_SNI" "$new_sni" ;;
        3)
            env_set "NODE1_SNI" "$new_sni"
            env_set "NODE2_SNI" "$new_sni"
            ;;
    esac

    update_subscription_file
    green "$(say "SNI изменён." "SNI changed.")"
    echo
    show_links
}

change_node2() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        yellow "$(say "Этот пункт работает только на NODE1." "This option is for NODE1 only.")"
        return
    fi

    if is_ru; then
        read -rp "Новый IP/домен NODE2: " NODE2_ADDR
        read -rp "Новый порт NODE2 [443]: " NODE2_PORT
        read -rp "Новый UUID NODE2: " NODE2_UUID
        read -rp "Новый PublicKey NODE2: " NODE2_PUBLIC_KEY
        read -rp "Новый ShortID NODE2: " NODE2_SHORT_ID
        read -rp "Новый SNI NODE2 [api-maps.yandex.ru]: " NODE2_SNI
    else
        read -rp "New NODE2 IP/domain: " NODE2_ADDR
        read -rp "New NODE2 port [443]: " NODE2_PORT
        read -rp "New NODE2 UUID: " NODE2_UUID
        read -rp "New NODE2 PublicKey: " NODE2_PUBLIC_KEY
        read -rp "New NODE2 ShortID: " NODE2_SHORT_ID
        read -rp "New NODE2 SNI [api-maps.yandex.ru]: " NODE2_SNI
    fi

    NODE2_PORT="${NODE2_PORT:-443}"
    NODE2_SNI="${NODE2_SNI:-api-maps.yandex.ru}"

    if ! valid_host "$NODE2_ADDR" || ! valid_port "$NODE2_PORT" || \
       ! valid_uuid "$NODE2_UUID" || ! valid_reality_public_key "$NODE2_PUBLIC_KEY" || \
       ! valid_short_id "$NODE2_SHORT_ID" || ! valid_domain "$NODE2_SNI"; then
        red "$(say "Один из параметров введён некорректно." "One or more values are invalid.")"
        return
    fi

    local tmp
    tmp="$(mktemp)"

    jq \
        --arg addr "$NODE2_ADDR" \
        --argjson port "$NODE2_PORT" \
        --arg uuid "$NODE2_UUID" \
        --arg pbk "$NODE2_PUBLIC_KEY" \
        --arg sid "$NODE2_SHORT_ID" \
        --arg sni "$NODE2_SNI" '
          (.outbounds[] | select(.tag == "node2-out") | .server) = $addr
          | (.outbounds[] | select(.tag == "node2-out") | .server_port) = $port
          | (.outbounds[] | select(.tag == "node2-out") | .uuid) = $uuid
          | (.outbounds[] | select(.tag == "node2-out") | .tls.server_name) = $sni
          | (.outbounds[] | select(.tag == "node2-out") | .tls.reality.public_key) = $pbk
          | (.outbounds[] | select(.tag == "node2-out") | .tls.reality.short_id) = $sid
        ' "$CONFIG" > "$tmp"

    if ! check_config_file "$tmp"; then
        rm -f "$tmp"
        return
    fi

    backup_config
    if ! apply_singbox_config "$tmp"; then
        rm -f "$tmp"
        return
    fi
    rm -f "$tmp"

    env_set "NODE2_ADDR" "$NODE2_ADDR"
    env_set "NODE2_PORT" "$NODE2_PORT"
    env_set "NODE2_UUID" "$NODE2_UUID"
    env_set "NODE2_PUBLIC_KEY" "$NODE2_PUBLIC_KEY"
    env_set "NODE2_SHORT_ID" "$NODE2_SHORT_ID"
    env_set "NODE2_SNI" "$NODE2_SNI"

    green "$(say "NODE2 на NODE1 изменён." "NODE2 on NODE1 changed.")"
}

status_logs() {
    echo "=== sing-box ==="
    systemctl status sing-box --no-pager -l || true
    echo
    echo "=== ports ==="
    ss -lntp | grep -E ':(80|443|8443|2080|2096)\b|sing-box|caddy' || true
    echo
    echo "=== Caddy ==="
    systemctl status caddy --no-pager -l 2>/dev/null || true
    echo
    echo "=== subscription ==="
    systemctl status singbox-subscription --no-pager -l 2>/dev/null || true
    echo
    echo "=== sing-box logs ==="
    journalctl -u sing-box -n 80 --no-pager -l || true
}

live_logs() {
    load_env
    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        journalctl -u sing-box -u caddy -f -n 0 -o cat
    else
        journalctl -u sing-box -f -n 0 -o cat
    fi
}

diagnostics() {
    load_env

    echo "=== sing-box config ==="
    if [ -f "$CONFIG" ]; then
        sing-box check -c "$CONFIG" || true
    else
        echo "missing: $CONFIG"
    fi

    echo
    echo "=== services ==="
    echo -n "sing-box enabled: "
    systemctl is-enabled sing-box 2>/dev/null || true
    echo -n "sing-box active:  "
    systemctl is-active sing-box 2>/dev/null || true
    echo -n "caddy active:     "
    systemctl is-active caddy 2>/dev/null || true

    echo
    echo "=== ports ==="
    ss -lntp | grep -E ':(80|443|8443|2080|2096)\b|sing-box|caddy' || true

    echo
    echo "=== public IPv4 ==="
    detect_public_ip
    echo

    if [ "${ROLE:-}" = "NODE1" ]; then
        echo
        echo "=== NODE1 -> NODE2 TCP ==="
        nc -vz -w 5 "$NODE2_ADDR" "$NODE2_PORT" || true
    fi

    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        echo
        echo "=== WORK DNS ==="
        getent ahostsv4 "$WORK_DOMAIN" | awk '!seen[$1]++ {print $1}' || true

        echo
        echo "=== Caddy validation ==="
        if command -v caddy >/dev/null 2>&1 && [ -f "$CADDY_MAIN" ]; then
            caddy validate --config "$CADDY_MAIN" --adapter caddyfile || true
        fi

        echo
        echo "=== HTTPS ==="
        curl -I --max-time 15 "https://$WORK_DOMAIN/" || true
    fi
}

port_owned_by() {
    local port="$1"
    local process="$2"
    ss -lntp 2>/dev/null | grep -E "[:.]${port}[[:space:]].*${process}" >/dev/null
}

cascade_check() {
    load_env

    echo "======================================"
    echo " Cascade check"
    echo "======================================"

    if [ ! -f "$CONFIG" ]; then
        red "❌ config.json not found"
        return
    fi

    if sing-box check -c "$CONFIG" >/dev/null 2>&1; then
        green "✅ sing-box config syntax OK"
    else
        red "❌ sing-box config syntax error"
        sing-box check -c "$CONFIG" || true
    fi

    if systemctl is-active --quiet sing-box; then
        green "✅ sing-box service active"
    else
        red "❌ sing-box service inactive"
    fi

    if systemctl is-enabled --quiet sing-box; then
        green "✅ sing-box autostart enabled"
    else
        yellow "⚠️ sing-box autostart disabled"
    fi

    if [ "${ROLE:-}" = "NODE1" ]; then
        local cfg_uuid cfg_sni cfg_out_uuid cfg_pbk cfg_sid cfg_port

        cfg_uuid="$(jq -r 'first(.inbounds[] | select(.tag == "node1-in") | .users[0].uuid) // empty' "$CONFIG")"
        cfg_sni="$(jq -r 'first(.inbounds[] | select(.tag == "node1-in") | .tls.server_name) // empty' "$CONFIG")"
        cfg_port="$(jq -r 'first(.inbounds[] | select(.tag == "node1-in") | .listen_port) // empty' "$CONFIG")"
        cfg_out_uuid="$(jq -r 'first(.outbounds[] | select(.tag == "node2-out") | .uuid) // empty' "$CONFIG")"
        cfg_pbk="$(jq -r 'first(.outbounds[] | select(.tag == "node2-out") | .tls.reality.public_key) // empty' "$CONFIG")"
        cfg_sid="$(jq -r 'first(.outbounds[] | select(.tag == "node2-out") | .tls.reality.short_id) // empty' "$CONFIG")"

        [ "$cfg_uuid" = "${NODE1_UUID:-}" ] \
            && green "✅ NODE1 inbound UUID matches node.env" \
            || red "❌ NODE1 inbound UUID mismatch"

        [ "$cfg_sni" = "${NODE1_SNI:-}" ] \
            && green "✅ NODE1 inbound SNI matches node.env" \
            || red "❌ NODE1 inbound SNI mismatch"

        [ "$cfg_port" = "${NODE1_REALITY_PORT:-443}" ] \
            && green "✅ NODE1 Reality port matches node.env" \
            || red "❌ NODE1 Reality port mismatch"

        [ "$cfg_out_uuid" = "${NODE2_UUID:-}" ] \
            && green "✅ NODE1 outbound UUID matches NODE2 UUID" \
            || red "❌ NODE1 outbound UUID mismatch"

        [ "$cfg_pbk" = "${NODE2_PUBLIC_KEY:-}" ] \
            && green "✅ NODE1 outbound PublicKey matches node.env" \
            || red "❌ NODE1 outbound PublicKey mismatch"

        [ "$cfg_sid" = "${NODE2_SHORT_ID:-}" ] \
            && green "✅ NODE1 outbound ShortID matches node.env" \
            || red "❌ NODE1 outbound ShortID mismatch"

        if nc -vz -w 5 "$NODE2_ADDR" "$NODE2_PORT" >/tmp/sbcm-nc.log 2>&1; then
            green "✅ NODE2 ${NODE2_ADDR}:${NODE2_PORT} reachable from NODE1"
        else
            red "❌ NODE2 ${NODE2_ADDR}:${NODE2_PORT} is NOT reachable from NODE1"
            cat /tmp/sbcm-nc.log || true
        fi

        if [ "${WORK_ENABLED:-0}" = "1" ]; then
            local cfg_work_uuid cfg_work_path cfg_work_port
            cfg_work_uuid="$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .users[0].uuid) // empty' "$CONFIG")"
            cfg_work_path="$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .transport.path) // empty' "$CONFIG")"
            cfg_work_port="$(jq -r 'first(.inbounds[] | select(.tag == "work-ws-in") | .listen_port) // empty' "$CONFIG")"

            [ "$cfg_work_uuid" = "${WORK_UUID:-}" ] \
                && green "✅ WORK UUID matches node.env" \
                || red "❌ WORK UUID mismatch"

            [ "$cfg_work_path" = "${WORK_PATH:-}" ] \
                && green "✅ WORK WebSocket path matches node.env" \
                || red "❌ WORK WebSocket path mismatch"

            [ "$cfg_work_port" = "${WORK_LOCAL_PORT:-2080}" ] \
                && green "✅ WORK local port matches node.env" \
                || red "❌ WORK local port mismatch"

            systemctl is-active --quiet caddy \
                && green "✅ Caddy active" \
                || red "❌ Caddy inactive"

            port_owned_by 443 caddy \
                && green "✅ Caddy listens on public 443" \
                || red "❌ Caddy does not listen on public 443"

            port_owned_by "$WORK_LOCAL_PORT" sing-box \
                && green "✅ sing-box listens on local WORK port $WORK_LOCAL_PORT" \
                || red "❌ sing-box does not listen on WORK port $WORK_LOCAL_PORT"
        else
            port_owned_by "$NODE1_REALITY_PORT" sing-box \
                && green "✅ sing-box listens on Reality port $NODE1_REALITY_PORT" \
                || red "❌ sing-box does not listen on Reality port $NODE1_REALITY_PORT"
        fi

        if [ -n "${SUB_PORT:-}" ] && [ -n "${SUB_TOKEN:-}" ]; then
            systemctl is-active --quiet singbox-subscription \
                && green "✅ subscription service active" \
                || yellow "⚠️ subscription service inactive"
        else
            yellow "⚠️ subscription is not configured"
        fi

        return
    fi

    if [ "${ROLE:-}" = "NODE2" ]; then
        local cfg_uuid cfg_sni
        cfg_uuid="$(jq -r 'first(.inbounds[] | select(.tag == "node2-in") | .users[0].uuid) // empty' "$CONFIG")"
        cfg_sni="$(jq -r 'first(.inbounds[] | select(.tag == "node2-in") | .tls.server_name) // empty' "$CONFIG")"

        [ "$cfg_uuid" = "${NODE2_UUID:-}" ] \
            && green "✅ NODE2 inbound UUID matches node.env" \
            || red "❌ NODE2 inbound UUID mismatch"

        [ "$cfg_sni" = "${NODE2_SNI:-}" ] \
            && green "✅ NODE2 SNI matches node.env" \
            || red "❌ NODE2 SNI mismatch"

        port_owned_by 443 sing-box \
            && green "✅ sing-box listens on 443" \
            || red "❌ sing-box does not listen on 443"
        return
    fi

    yellow "⚠️ Unknown role. Configure NODE1 or NODE2 first."
}

setup_subscription() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        yellow "$(say "Подписка настраивается только на NODE1." "Subscription is configured on NODE1 only.")"
        return
    fi

    if [ -z "${SUB_PORT:-}" ]; then
        if is_ru; then
            read -rp "Порт подписки [2096]: " SUB_PORT
        else
            read -rp "Subscription port [2096]: " SUB_PORT
        fi
        SUB_PORT="${SUB_PORT:-2096}"
    fi

    if ! valid_port "$SUB_PORT"; then
        red "$(say "Некорректный порт." "Invalid port.")"
        return
    fi

    if [ -z "${SUB_TOKEN:-}" ]; then
        SUB_TOKEN="$(openssl rand -hex 16)"
    fi

    env_set "SUB_PORT" "$SUB_PORT"
    env_set "SUB_TOKEN" "$SUB_TOKEN"
    update_subscription_file

    cat > "$SUB_SERVICE" <<EOF
[Unit]
Description=SingBox Node Cascade Subscription
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SUB_ROOT
ExecStart=/usr/bin/python3 -m http.server $SUB_PORT --bind 0.0.0.0 --directory $SUB_ROOT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now singbox-subscription

    echo
    green "$(say "Подписка готова:" "Subscription is ready:")"
    echo "http://${NODE1_ADDR}:${SUB_PORT}/${SUB_TOKEN}/sub.txt"
    echo
    yellow "$(say \
        "Открой TCP-порт $SUB_PORT в firewall, если он используется." \
        "Open TCP port $SUB_PORT in the firewall if one is enabled.")"
}

install_caddy_package() {
    load_env

    if command -v caddy >/dev/null 2>&1; then
        return 0
    fi

    say "Устанавливаю Caddy из официального репозитория..." \
        "Installing Caddy from the official repository..."

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        debian-keyring \
        debian-archive-keyring \
        apt-transport-https \
        curl \
        gnupg \
        ca-certificates

    mkdir -p /usr/share/keyrings
    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --batch --yes --dearmor \
            -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        > /etc/apt/sources.list.d/caddy-stable.list

    chmod o+r \
        /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
        /etc/apt/sources.list.d/caddy-stable.list

    apt-get update

    set +e
    DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
    local rc=$?
    set -e

    if ! command -v caddy >/dev/null 2>&1; then
        red "$(say "Caddy не установился, код: $rc" "Caddy installation failed, code: $rc")"
        return 1
    fi

    env_set "CADDY_INSTALLED_BY_MANAGER" "1"
    systemctl stop caddy 2>/dev/null || true
    return 0
}

ensure_caddy_import() {
    mkdir -p "$CADDY_CONF_DIR" "$(dirname "$CADDY_MAIN")"

    if [ ! -f "$CADDY_MAIN" ]; then
        printf 'import %s/*.caddy\n' "$CADDY_CONF_DIR" > "$CADDY_MAIN"
        return
    fi

    if ! grep -Fq "import $CADDY_CONF_DIR/*.caddy" "$CADDY_MAIN"; then
        {
            echo
            echo "# Managed include for SingBox Node Cascade"
            echo "import $CADDY_CONF_DIR/*.caddy"
        } >> "$CADDY_MAIN"
    fi
}

write_web_root() {
    mkdir -p "$WEB_ROOT"
    cat > "$WEB_ROOT/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Infrastructure Services</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: system-ui, -apple-system, sans-serif;
      background: #f4f6f8;
      color: #18212b;
    }
    main {
      max-width: 640px;
      margin: 24px;
      padding: 42px;
      background: #fff;
      border-radius: 18px;
      box-shadow: 0 12px 40px rgba(0,0,0,.08);
    }
  </style>
</head>
<body>
  <main>
    <h1>Infrastructure Services</h1>
    <p>Secure systems and technical services.</p>
  </main>
</body>
</html>
EOF
}

write_caddy_snippet() {
    local domain="$1"
    local path="$2"
    local local_port="$3"

    mkdir -p "$CADDY_CONF_DIR"
    cat > "$CADDY_SNIPPET" <<EOF
$domain {
    @work path $path

    handle @work {
        reverse_proxy 127.0.0.1:$local_port
    }

    handle {
        root * $WEB_ROOT
        file_server
    }
}
EOF

    caddy fmt --overwrite "$CADDY_SNIPPET"
}

setup_work_profile() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        red "$(say "Caddy / WORK-профиль настраивается только на NODE1." "Caddy / WORK profile is configured on NODE1 only.")"
        return
    fi

    if [ ! -f "$CONFIG" ] || ! jq -e '.inbounds[] | select(.tag == "node1-in")' "$CONFIG" >/dev/null; then
        red "$(say "Не найден управляемый вход node1-in." "Managed node1-in inbound was not found.")"
        return
    fi

    local domain reality_port local_port default_reality_port default_local_port
    local work_uuid work_path keep_old
    local public_ip resolved_ip
    local tmp old_config old_snippet had_snippet=0

    if is_ru; then
        read -rp "Домен WORK-профиля [${WORK_DOMAIN:-}]: " domain
    else
        read -rp "WORK profile domain [${WORK_DOMAIN:-}]: " domain
    fi
    domain="${domain:-${WORK_DOMAIN:-}}"

    if ! valid_domain "$domain"; then
        red "$(say "Нужен корректный домен или поддомен." "A valid domain or subdomain is required.")"
        return
    fi

    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        default_reality_port="${NODE1_REALITY_PORT:-8443}"
    else
        default_reality_port="8443"
    fi
    default_local_port="${WORK_LOCAL_PORT:-2080}"

    if is_ru; then
        read -rp "Порт старого Reality после включения Caddy [$default_reality_port]: " reality_port
        read -rp "Локальный порт WebSocket [$default_local_port]: " local_port
    else
        read -rp "Reality port after enabling Caddy [$default_reality_port]: " reality_port
        read -rp "Local WebSocket port [$default_local_port]: " local_port
    fi

    reality_port="${reality_port:-$default_reality_port}"
    local_port="${local_port:-$default_local_port}"

    if ! valid_port "$reality_port" || ! valid_port "$local_port"; then
        red "$(say "Некорректный порт." "Invalid port.")"
        return
    fi
    if [ "$reality_port" = "443" ] || [ "$local_port" = "443" ] || [ "$reality_port" = "$local_port" ]; then
        red "$(say \
            "Публичный 443 принадлежит Caddy; порты Reality и WebSocket должны отличаться." \
            "Public port 443 belongs to Caddy; Reality and WebSocket ports must differ.")"
        return
    fi

    keep_old=0
    if [ "${WORK_ENABLED:-0}" = "1" ] && [ -n "${WORK_UUID:-}" ] && [ -n "${WORK_PATH:-}" ]; then
        if confirm_yes \
            "Сохранить текущие UUID и секретный WebSocket-путь?" \
            "Keep the current UUID and secret WebSocket path?"; then
            keep_old=1
        fi
    fi

    if [ "$keep_old" -eq 1 ]; then
        work_uuid="$WORK_UUID"
        work_path="$WORK_PATH"
    else
        work_uuid="$(gen_uuid)"
        work_path="/assets/$(openssl rand -hex 16)"
    fi

    public_ip="$(detect_public_ip)"
    resolved_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1 {print $1}')"

    echo
    echo "Public IP: ${public_ip:-unknown}"
    echo "DNS A:     ${resolved_ip:-not resolved}"

    if [ -z "$resolved_ip" ] || { [ -n "$public_ip" ] && [ "$resolved_ip" != "$public_ip" ]; }; then
        yellow "$(say \
            "DNS пока не указывает на этот VPS. Сертификат не выпустится до исправления A-записи." \
            "DNS does not currently point to this VPS. The certificate cannot be issued until the A record is fixed.")"
        if ! confirm_yes "Продолжить всё равно?" "Continue anyway?"; then
            return
        fi
    fi

    install_caddy_package
    load_env

    old_config="$(mktemp)"
    cp -a "$CONFIG" "$old_config"

    old_snippet="$(mktemp)"
    if [ -f "$CADDY_SNIPPET" ]; then
        cp -a "$CADDY_SNIPPET" "$old_snippet"
        had_snippet=1
    fi

    backup_config

    # Migration from the one-file Caddy setup used before v1.1.0.
    # A duplicate site label would make the resulting Caddy config ambiguous,
    # so the manager offers to replace the dedicated legacy Caddyfile with imports.
    if [ ! -f "$CADDY_SNIPPET" ] && [ -f "$CADDY_MAIN" ] && grep -Fq "$domain {" "$CADDY_MAIN"; then
        yellow "$(say \
            "Домен уже описан прямо в /etc/caddy/Caddyfile. Для управления через меню нужен перенос в отдельный snippet." \
            "The domain is already defined directly in /etc/caddy/Caddyfile. Menu management requires moving it to a dedicated snippet.")"
        yellow "$(say \
            "Продолжай только если этот Caddyfile был создан для данного WORK-профиля. Бэкап уже сохранён." \
            "Continue only if this Caddyfile was created for this WORK profile. A backup has already been saved.")"

        if ! confirm_yes "Перенести существующую конфигурацию?" "Migrate the existing configuration?"; then
            rm -f "$old_config" "$old_snippet"
            return
        fi

        printf 'import %s/*.caddy\n' "$CADDY_CONF_DIR" > "$CADDY_MAIN"
    fi

    ensure_caddy_import
    write_web_root
    write_caddy_snippet "$domain" "$work_path" "$local_port"

    if ! caddy validate --config "$CADDY_MAIN" --adapter caddyfile; then
        red "$(say "Caddyfile не прошёл проверку." "Caddyfile validation failed.")"
        if [ "$had_snippet" -eq 1 ]; then
            cp -a "$old_snippet" "$CADDY_SNIPPET"
        else
            rm -f "$CADDY_SNIPPET"
        fi
        rm -f "$old_config" "$old_snippet"
        return
    fi

    tmp="$(mktemp)"
    jq \
        --arg uuid "$work_uuid" \
        --arg path "$work_path" \
        --argjson reality_port "$reality_port" \
        --argjson local_port "$local_port" '
          .inbounds |= map(select(.tag != "work-ws-in"))
          | (.inbounds[] | select(.tag == "node1-in") | .listen_port) = $reality_port
          | .inbounds += [
              {
                "type": "vless",
                "tag": "work-ws-in",
                "listen": "127.0.0.1",
                "listen_port": $local_port,
                "users": [
                  {
                    "uuid": $uuid
                  }
                ],
                "transport": {
                  "type": "ws",
                  "path": $path
                }
              }
            ]
        ' "$CONFIG" > "$tmp"

    if ! check_config_file "$tmp"; then
        rm -f "$tmp" "$old_config" "$old_snippet"
        return
    fi

    install -m 600 "$tmp" "$CONFIG"
    rm -f "$tmp"

    if ! restart_singbox; then
        red "$(say "Откатываю sing-box." "Rolling sing-box back.")"
        install -m 600 "$old_config" "$CONFIG"
        restart_singbox || true
        rm -f "$old_config" "$old_snippet"
        return
    fi

    systemctl enable caddy >/dev/null 2>&1 || true
    if ! systemctl restart caddy; then
        red "$(say "Caddy не запустился. Возвращаю предыдущий sing-box." "Caddy failed. Restoring the previous sing-box config.")"
        systemctl stop caddy 2>/dev/null || true
        install -m 600 "$old_config" "$CONFIG"
        restart_singbox || true

        if [ "$had_snippet" -eq 1 ]; then
            cp -a "$old_snippet" "$CADDY_SNIPPET"
        else
            rm -f "$CADDY_SNIPPET"
        fi

        journalctl -u caddy -n 100 --no-pager -l || true
        rm -f "$old_config" "$old_snippet"
        return
    fi

    rm -f "$old_config" "$old_snippet"

    env_set "WORK_ENABLED" "1"
    env_set "WORK_DOMAIN" "$domain"
    env_set "WORK_UUID" "$work_uuid"
    env_set "WORK_PATH" "$work_path"
    env_set "WORK_LOCAL_PORT" "$local_port"
    env_set "WORK_TLS_PORT" "443"
    env_set "NODE1_REALITY_PORT" "$reality_port"

    update_subscription_file

    echo
    green "$(say "Caddy / WORK-профиль включён." "Caddy / WORK profile enabled.")"
    echo
    show_links
    echo

    local https_ok=0
    for _ in $(seq 1 10); do
        if curl -fsSI --max-time 8 "https://$domain/" >/dev/null 2>&1; then
            https_ok=1
            break
        fi
        sleep 3
    done

    if [ "$https_ok" -eq 1 ]; then
        green "✅ HTTPS: https://$domain/"
    else
        yellow "$(say \
            "HTTPS ещё не ответил. Проверь DNS, открытые TCP 80/443 и журнал Caddy." \
            "HTTPS has not responded yet. Check DNS, open TCP 80/443, and the Caddy log.")"
        echo "journalctl -u caddy -n 100 --no-pager -l"
    fi
}

show_work_link() {
    load_env
    if [ "${WORK_ENABLED:-0}" != "1" ]; then
        yellow "$(say "WORK-профиль не настроен." "WORK profile is not configured.")"
        return
    fi
    build_work_link
}

show_work_qr() {
    load_env
    if [ "${WORK_ENABLED:-0}" != "1" ]; then
        yellow "$(say "WORK-профиль не настроен." "WORK profile is not configured.")"
        return
    fi

    local link
    link="$(build_work_link)"
    echo "$link"
    echo
    qrencode -t ANSIUTF8 "$link"
}

work_status() {
    load_env

    echo "=== WORK profile ==="
    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        echo "domain:       $WORK_DOMAIN"
        echo "TLS port:     $WORK_TLS_PORT"
        echo "local WS:     127.0.0.1:$WORK_LOCAL_PORT"
        echo "Reality port: $NODE1_REALITY_PORT"
        echo "path:         $WORK_PATH"
    else
        echo "disabled"
    fi

    echo
    echo "=== services ==="
    systemctl status caddy --no-pager -l 2>/dev/null || true
    systemctl status sing-box --no-pager -l || true

    echo
    echo "=== ports ==="
    ss -lntp | grep -E ':(80|443|8443|2080)\b|caddy|sing-box' || true

    echo
    echo "=== Caddy validation ==="
    if command -v caddy >/dev/null 2>&1 && [ -f "$CADDY_MAIN" ]; then
        caddy validate --config "$CADDY_MAIN" --adapter caddyfile || true
    fi

    if [ "${WORK_ENABLED:-0}" = "1" ]; then
        echo
        echo "=== HTTPS ==="
        curl -I --max-time 15 "https://$WORK_DOMAIN/" || true
    fi

    echo
    echo "=== recent Caddy logs ==="
    journalctl -u caddy -n 80 --no-pager -l 2>/dev/null || true
}

disable_work_profile() {
    load_env

    if [ "${ROLE:-}" != "NODE1" ]; then
        yellow "$(say "Этот пункт работает только на NODE1." "This option is for NODE1 only.")"
        return
    fi

    if [ "${WORK_ENABLED:-0}" != "1" ]; then
        yellow "$(say "WORK-профиль уже выключен." "WORK profile is already disabled.")"
        return
    fi

    if ! confirm_yes \
        "Отключить WORK, остановить Caddy и вернуть Reality на порт 443?" \
        "Disable WORK, stop Caddy, and restore Reality on port 443?"; then
        return
    fi

    local tmp old_config
    old_config="$(mktemp)"
    cp -a "$CONFIG" "$old_config"

    tmp="$(mktemp)"
    jq '
      .inbounds |= map(select(.tag != "work-ws-in"))
      | (.inbounds[] | select(.tag == "node1-in") | .listen_port) = 443
    ' "$CONFIG" > "$tmp"

    if ! check_config_file "$tmp"; then
        rm -f "$tmp" "$old_config"
        return
    fi

    backup_config
    systemctl stop caddy 2>/dev/null || true

    install -m 600 "$tmp" "$CONFIG"
    rm -f "$tmp"

    if ! restart_singbox; then
        red "$(say "Откат: возвращаю прежний конфиг." "Rollback: restoring previous config.")"
        install -m 600 "$old_config" "$CONFIG"
        restart_singbox || true
        systemctl restart caddy 2>/dev/null || true
        rm -f "$old_config"
        return
    fi

    rm -f "$old_config" "$CADDY_SNIPPET"
    systemctl disable caddy >/dev/null 2>&1 || true

    env_set "WORK_ENABLED" "0"
    env_set "NODE1_REALITY_PORT" "443"
    env_unset "WORK_DOMAIN"
    env_unset "WORK_UUID"
    env_unset "WORK_PATH"
    env_unset "WORK_LOCAL_PORT"
    env_unset "WORK_TLS_PORT"

    update_subscription_file

    green "$(say "WORK выключен. Reality снова слушает 443." "WORK disabled. Reality is listening on 443 again.")"
    echo
    show_links
}

caddy_menu() {
    while true; do
        clear
        bold "======================================"
        bold " Caddy / WORK TLS + WebSocket"
        bold "======================================"
        echo
        if is_ru; then
            echo "1) Настроить / обновить WORK-профиль"
            echo "2) Показать WORK-ссылку"
            echo "3) Показать WORK QR-код"
            echo "4) Статус и диагностика Caddy / WORK"
            echo "5) Отключить WORK и вернуть Reality на 443"
            echo "0) Назад"
        else
            echo "1) Configure / update WORK profile"
            echo "2) Show WORK link"
            echo "3) Show WORK QR code"
            echo "4) Caddy / WORK status and diagnostics"
            echo "5) Disable WORK and restore Reality on 443"
            echo "0) Back"
        fi
        echo
        read -rp "> " choice

        case "$choice" in
            1) setup_work_profile; pause ;;
            2) show_work_link; pause ;;
            3) show_work_qr; pause ;;
            4) work_status; pause ;;
            5) disable_work_profile; pause ;;
            0) return ;;
            *) red "$(say "Неверный выбор." "Wrong choice.")"; pause ;;
        esac
    done
}

update_manager() {
    local tmp
    tmp="$(mktemp)"

    say "Скачиваю новую версию menu.sh..." "Downloading the latest menu.sh..."
    if ! curl -fsSL "$REPO_RAW/menu.sh" -o "$tmp"; then
        rm -f "$tmp"
        red "$(say "Не удалось скачать обновление." "Failed to download the update.")"
        return
    fi

    if ! bash -n "$tmp"; then
        rm -f "$tmp"
        red "$(say "Скачанный файл содержит синтаксическую ошибку." "The downloaded file has a syntax error.")"
        return
    fi

    install -m 755 "$tmp" "$INSTALL_DIR/menu.sh"
    rm -f "$tmp"
    ln -sf "$INSTALL_DIR/menu.sh" /usr/local/bin/singbox-menu

    green "$(say "Менеджер обновлён. Перезапускаю..." "Manager updated. Restarting...")"
    sleep 1
    exec /usr/local/bin/singbox-menu
}

change_language() {
    echo "1) Русский"
    echo "2) English"
    read -rp "> " choice

    case "$choice" in
        2) LANGUAGE="en" ;;
        *) LANGUAGE="ru" ;;
    esac

    printf 'LANGUAGE=%q\n' "$LANGUAGE" > "$SETTINGS_FILE"
}

uninstall_all() {
    load_env

    clear
    echo "======================================"
    if is_ru; then
        echo " УДАЛЕНИЕ SingBox Node Cascade"
        echo "======================================"
        echo
        echo "Будут удалены sing-box, менеджер, его конфиги и сервис подписки."
        if [ "${CADDY_INSTALLED_BY_MANAGER:-0}" = "1" ]; then
            echo "Caddy также будет удалён, потому что его установил менеджер."
        else
            echo "Чужая установка Caddy не удаляется; удалится только наш сайт."
        fi
        echo
        read -rp "Напиши DELETE для подтверждения: " confirm
    else
        echo " UNINSTALL SingBox Node Cascade"
        echo "======================================"
        echo
        echo "sing-box, the manager, its configs, and subscription service will be removed."
        if [ "${CADDY_INSTALLED_BY_MANAGER:-0}" = "1" ]; then
            echo "Caddy will also be removed because it was installed by this manager."
        else
            echo "An existing Caddy package will be kept; only this manager's site is removed."
        fi
        echo
        read -rp "Type DELETE to confirm: " confirm
    fi

    [ "$confirm" = "DELETE" ] || return

    local remove_caddy="${CADDY_INSTALLED_BY_MANAGER:-0}"

    systemctl disable --now singbox-subscription 2>/dev/null || true
    systemctl disable --now sing-box 2>/dev/null || true
    systemctl stop caddy 2>/dev/null || true

    rm -f "$SUB_SERVICE"
    rm -f "$CADDY_SNIPPET"
    rm -rf "$WEB_ROOT"

    if [ "$remove_caddy" = "1" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y caddy 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    else
        systemctl restart caddy 2>/dev/null || true
    fi

    DEBIAN_FRONTEND=noninteractive apt-get purge -y sing-box 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>/dev/null || true

    rm -rf /etc/sing-box
    rm -rf "$INSTALL_DIR"
    rm -rf "$DATA_DIR"
    rm -rf "$SUB_ROOT"
    rm -f /usr/local/bin/singbox-menu
    rm -rf /etc/systemd/system/sing-box.service.d

    systemctl daemon-reload

    green "$(say "Готово. SingBox Node Cascade удалён." "Done. SingBox Node Cascade was removed.")"
    exit 0
}

main_menu() {
    while true; do
        clear
        bold "======================================"
        bold " SingBox Node Cascade Manager v$VERSION"
        bold " NODE1 -> NODE2 | Reality + optional HTTPS/WS"
        bold "======================================"
        echo

        if is_ru; then
            echo "1) Настроить NODE2 / выходной сервер"
            echo "2) Настроить NODE1 / входной сервер -> NODE2"
            echo "3) Показать параметры ноды"
            echo "4) Показать клиентские ссылки"
            echo "5) Показать QR-код"
            echo "6) Изменить SNI"
            echo "7) Изменить NODE2 на NODE1"
            echo "8) Перезапустить sing-box"
            echo "9) Статус и последние логи"
            echo "10) Смотреть логи онлайн"
            echo "11) Создать резервную копию"
            echo "12) Диагностика"
            echo "13) Обновить менеджер из GitHub"
            echo "14) Сменить язык"
            echo "15) Проверка каскада"
            echo "16) Настроить / показать подписку"
            echo "17) Caddy / WORK TLS + WebSocket"
            echo "18) Удалить SingBox Node Cascade"
            echo "0) Выход"
        else
            echo "1) Configure NODE2 / EXIT node"
            echo "2) Configure NODE1 / ENTRY node -> NODE2"
            echo "3) Show node info"
            echo "4) Show client links"
            echo "5) Show QR code"
            echo "6) Change SNI"
            echo "7) Change NODE2 on NODE1"
            echo "8) Restart sing-box"
            echo "9) Status and recent logs"
            echo "10) Live logs"
            echo "11) Create backup"
            echo "12) Diagnostics"
            echo "13) Update manager from GitHub"
            echo "14) Change language"
            echo "15) Cascade check"
            echo "16) Setup / show subscription"
            echo "17) Caddy / WORK TLS + WebSocket"
            echo "18) Uninstall SingBox Node Cascade"
            echo "0) Exit"
        fi

        echo
        read -rp "> " choice

        case "$choice" in
            1) configure_node2; pause ;;
            2) configure_node1; pause ;;
            3) show_info; pause ;;
            4) show_links; pause ;;
            5) show_qr; pause ;;
            6) change_sni; pause ;;
            7) change_node2; pause ;;
            8) restart_singbox; pause ;;
            9) status_logs; pause ;;
            10) live_logs ;;
            11) backup_config; pause ;;
            12) diagnostics; pause ;;
            13) update_manager; pause ;;
            14) change_language ;;
            15) cascade_check; pause ;;
            16) setup_subscription; pause ;;
            17) caddy_menu ;;
            18) uninstall_all; pause ;;
            0) exit 0 ;;
            *) red "$(say "Неверный выбор." "Wrong choice.")"; pause ;;
        esac
    done
}

need_root
init_lang
main_menu
