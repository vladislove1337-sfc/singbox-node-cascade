# SingBox Node Cascade Manager v1.1.0

Менеджер для двухузлового каскада:

```text
CLIENT -> NODE1 -> NODE2 -> INTERNET
```

Основной режим:

```text
VLESS + Reality + Vision
```

Дополнительный режим для сетей, где Reality фильтруется:

```text
VLESS + TLS + WebSocket -> Caddy -> sing-box
```

NODE1 в обоих режимах отправляет трафик через один и тот же NODE2.

---

## Возможности

- установка и обновление sing-box;
- настройка NODE2 как выходного сервера;
- настройка NODE1 как входного сервера с каскадом на NODE2;
- автоматическая генерация UUID, Reality keypair и ShortID;
- клиентская Reality-ссылка и QR-код;
- отдельный WORK-профиль через настоящий HTTPS, Caddy и WebSocket;
- автоматическая установка Caddy из официального репозитория;
- автоматическое получение и продление TLS-сертификата;
- обычная веб-страница на WORK-домене;
- перенос Reality-входа с `443` на выбранный резервный порт при включении Caddy;
- возврат Reality на `443` при отключении WORK-профиля;
- подписка, содержащая Reality и WORK-ссылки;
- смена SNI;
- замена NODE2 на NODE1 без ручного редактирования JSON;
- проверка каскада;
- диагностика sing-box, Caddy, DNS, HTTPS и портов;
- резервные копии конфигов;
- автозапуск и автоматический перезапуск sing-box;
- русский и английский язык;
- безопасное обновление `menu.sh` с проверкой синтаксиса;
- полное удаление через меню.

---

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/install.sh)
```

После установки:

```bash
singbox-menu
```

Обновление существующей установки выполняется тем же установочным вызовом или пунктом `13` в меню. Конфиги и `node.env` при обновлении не удаляются.

Если WORK-профиль ранее был настроен вручную, v1.1.0 автоматически обнаруживает inbound с тегом `work-ws-in`, его UUID, путь и локальный порт. Домен читается из `/root/work-ws.env`, отдельного Caddy snippet или существующего `/etc/caddy/Caddyfile`. При первом изменении такого профиля менеджер предложит перенести однофайловую конфигурацию Caddy в управляемый snippet, предварительно создав резервную копию.

---

## Базовая схема Reality

```text
Клиент
  ↓ VLESS Reality Vision
NODE1:443
  ↓ VLESS Reality Vision
NODE2:443
  ↓
Интернет
```

Клиент подключается только к NODE1.

### 1. Настроить NODE2

На выходном VPS:

```bash
singbox-menu
```

Выбрать:

```text
1) Настроить NODE2 / выходной сервер
```

Менеджер выдаст:

```text
NODE2_ADDR
NODE2_PORT
NODE2_UUID
NODE2_PUBLIC_KEY
NODE2_SHORT_ID
NODE2_SNI
```

`NODE2_PRIVATE_KEY` остаётся только на NODE2.

### 2. Настроить NODE1

На входном VPS:

```bash
singbox-menu
```

Выбрать:

```text
2) Настроить NODE1 / входной сервер -> NODE2
```

Ввести параметры, полученные на NODE2. После настройки менеджер покажет Reality-ссылку клиента.

---

## WORK-профиль: Caddy + настоящий TLS + WebSocket

Этот режим предназначен для сетей, где TCP-соединение до NODE1 проходит, но Reality ClientHello фильтруется или обрывается.

Схема:

```text
Клиент
  ↓ VLESS + TLS + WebSocket, public TCP 443
Caddy на NODE1
  ↓ localhost
sing-box NODE1
  ↓ существующий Reality-outbound
sing-box NODE2
  ↓
Интернет
```

### Требования

1. NODE1 уже настроен через пункт `2`.
2. Есть домен или поддомен.
3. DNS A-запись домена указывает на публичный IPv4 NODE1.
4. На NODE1 доступны входящие TCP-порты:
   - `80` — ACME-проверка и HTTP;
   - `443` — HTTPS / WORK;
   - выбранный резервный порт Reality, по умолчанию `8443`.

Пример с документационными адресами:

```text
office.example.com -> 203.0.113.10
exit.example.com   -> 198.51.100.20
```

Для первой настройки рекомендуется режим `DNS only`, без CDN-проксирования.

### Включение

На NODE1:

```bash
singbox-menu
```

Выбрать:

```text
17) Caddy / WORK TLS + WebSocket
1) Настроить / обновить WORK-профиль
```

Менеджер:

- проверит роль NODE1;
- попросит WORK-домен;
- проверит DNS;
- установит Caddy;
- создаст отдельный Caddy snippet;
- сгенерирует новый UUID и секретный WebSocket-путь;
- добавит локальный inbound `127.0.0.1:2080`;
- перенесёт Reality-вход на `8443` или другой выбранный порт;
- проверит оба конфига;
- перезапустит sing-box и Caddy;
- покажет готовую VLESS-ссылку.

После включения:

```text
domain.example.com:443 -> Caddy -> 127.0.0.1:2080 -> sing-box
NODE1_IP:8443          -> старый Reality-вход
```

Параметры NODE1 -> NODE2 не меняются.

### Клиентская WORK-ссылка

WORK-ссылка имеет параметры:

```text
security=tls
type=ws
host=your-domain.example
path=/assets/RANDOM_TOKEN
```

В ней отсутствуют:

```text
security=reality
pbk=
sid=
flow=xtls-rprx-vision
```

### Отключение WORK

```text
17) Caddy / WORK TLS + WebSocket
5) Отключить WORK и вернуть Reality на 443
```

Менеджер:

- остановит Caddy;
- удалит локальный WebSocket-inbound;
- вернёт Reality на `443`;
- обновит клиентскую ссылку и подписку.

---

## Подписка

На NODE1 выбрать:

```text
16) Настроить / показать подписку
```

URL имеет вид:

```text
http://NODE1_IP:2096/RANDOM_TOKEN/sub.txt
```

Если WORK-профиль включён, файл подписки содержит две строки:

```text
Reality-ссылка
WORK TLS + WebSocket-ссылка
```

После изменения SNI, NODE2, WORK-домена, UUID или WebSocket-пути подписка обновляется автоматически.

При активном firewall откройте выбранный TCP-порт подписки.

---

## Проверка каскада

На NODE1 или NODE2:

```text
15) Проверка каскада
```

Проверяются:

- синтаксис `config.json`;
- служба и автозапуск sing-box;
- UUID, SNI, PublicKey и ShortID;
- фактический порт Reality;
- доступность NODE2 с NODE1;
- локальный WebSocket-inbound;
- состояние Caddy и публичного `443`;
- состояние подписки.

Расширенная диагностика:

```text
12) Диагностика
```

Для WORK-профиля дополнительно проверяются DNS, Caddyfile и HTTPS.

---

## Главное правило ключей

```text
Клиент -> NODE1 Reality:
UUID      = NODE1_UUID
PublicKey = NODE1_PUBLIC_KEY
ShortID   = NODE1_SHORT_ID
SNI       = NODE1_SNI
```

```text
NODE1 -> NODE2:
UUID      = NODE2_UUID
PublicKey = NODE2_PUBLIC_KEY
ShortID   = NODE2_SHORT_ID
SNI       = NODE2_SNI
```

```text
NODE2:
UUID       = NODE2_UUID
PrivateKey = NODE2_PRIVATE_KEY
ShortID    = NODE2_SHORT_ID
```

PrivateKey не передаётся клиенту и не публикуется.

WORK-профиль использует отдельные:

```text
WORK_UUID
WORK_PATH
WORK_DOMAIN
```

---

## Полезные команды

```bash
systemctl status sing-box
journalctl -u sing-box -f
sing-box check -c /etc/sing-box/config.json
```

```bash
systemctl status caddy
journalctl -u caddy -f
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

```bash
ss -lntp | grep -E ':(80|443|8443|2080)'
curl -I https://your-domain.example/
```

---

## Файлы

```text
/etc/sing-box/config.json
/root/singbox-node-cascade/node.env
/root/singbox-node-cascade/settings.conf
/root/singbox-node-cascade/backups/

/etc/caddy/Caddyfile
/etc/caddy/conf.d/singbox-node-cascade.caddy
/var/www/singbox-node-cascade/

/var/lib/singbox-node-cascade-sub/
/etc/systemd/system/singbox-subscription.service
```

`node.env` создаётся на сервере с правами `600`. Реальные IP, домены, UUID, ключи и токены в репозитории не хранятся.

---

## Меню

```text
1)  Настроить NODE2
2)  Настроить NODE1 -> NODE2
3)  Показать параметры
4)  Показать ссылки
5)  QR-код
6)  Изменить SNI
7)  Изменить NODE2
8)  Перезапустить sing-box
9)  Статус и логи
10) Live logs
11) Резервная копия
12) Диагностика
13) Обновить менеджер
14) Сменить язык
15) Проверка каскада
16) Подписка
17) Caddy / WORK TLS + WebSocket
18) Удаление
```

---

## Обновление v1.1.0

Добавлено:

- Caddy как отдельный пункт меню;
- WORK-профиль `VLESS + TLS + WebSocket`;
- автоматическое управление портами `443`, `8443` и `2080`;
- два клиентских профиля на одном каскаде;
- добавление обеих ссылок в подписку;
- диагностика Caddy, DNS и HTTPS;
- безопасный откат при ошибке запуска;
- tag-based редактирование JSON вместо жёсткой привязки к номеру inbound/outbound;
- поддержка `NODE2_PORT`;
- проверка скачанного обновления через `bash -n`.

Исправление v1.0.7 сохранено: клиентская VLESS-ссылка не записывается в `node.env`, поэтому символы `&` не ломают `source`.

---

## Безопасность

- Не публикуйте `node.env`.
- Не публикуйте клиентские VLESS-ссылки.
- Не передавайте Reality PrivateKey.
- Секретный WebSocket-путь является частью доступа и должен храниться вместе с UUID.
- Перед публичной публикацией логов удаляйте IP-адреса, UUID, ключи и токены.
- Менеджер не меняет firewall автоматически.
