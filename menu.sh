#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.1"

choose_sni() {
  echo "SNI:" >&2
  echo "1) api-maps.yandex.ru" >&2
  echo "2) yastatic.net" >&2
  echo "3) avatars.mds.yandex.net" >&2
  echo "4) mc.yandex.ru" >&2
  echo "5) custom" >&2

  read -rp "> " n

  case "$n" in
    1) echo "api-maps.yandex.ru" ;;
    2) echo "yastatic.net" ;;
    3) echo "avatars.mds.yandex.net" ;;
    4) echo "mc.yandex.ru" ;;
    5)
      read -rp "Custom SNI: " custom
      echo "$custom"
      ;;
    *) echo "api-maps.yandex.ru" ;;
  esac
}

echo "SingBox Node Cascade Manager v$VERSION"
echo "SNI stdout bug fixed"
echo
echo "Вставь эту функцию choose_sni() вместо старой в основном menu.sh"
