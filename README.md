# SingBox Node Cascade Manager v1.0.6

Менеджер для каскада:

```text
CLIENT -> NODE1 -> NODE2 -> INTERNET
```

Стек:

```text
SingBox
VLESS
Reality
Vision
TCP 443
```

---

## Возможности

- установка SingBox;
- настройка NODE2 как выходного сервера;
- настройка NODE1 как входного сервера с каскадом на NODE2;
- автоматическая генерация UUID;
- автоматическая генерация Reality PrivateKey/PublicKey;
- автоматическая генерация ShortID;
- создание клиентской VLESS-ссылки;
- QR-код для телефона;
- подписка для клиентов;
- автоматическое обновление файла подписки после смены SNI;
- смена SNI через меню;
- замена NODE2 на NODE1 без ручного редактирования JSON;
- проверка каскада;
- просмотр параметров ноды;
- просмотр логов;
- live logs;
- диагностика;
- резервные копии конфигов;
- автозапуск sing-box;
- автоперезапуск sing-box при падении;
- русский и английский язык;
- полное удаление через меню.

---

## Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/install.sh)
```

После установки:

```bash
singbox-menu
```

---

## Схема работы

```text
Клиент / телефон / ПК
        ↓
NODE1 — входной сервер
        ↓
NODE2 — выходной сервер
        ↓
Интернет
```

Клиент подключается только к NODE1.

NODE1 сам отправляет весь трафик на NODE2.

---

## Порядок настройки

### 1. На NODE2

```bash
singbox-menu
```

Выбрать:

```text
1) Настроить NODE2 / выходной сервер
```

После настройки скрипт выдаст:

```text
NODE2_UUID
NODE2_PUBLIC_KEY
NODE2_SHORT_ID
NODE2_SNI
```

Эти данные нужно скопировать и использовать при настройке NODE1.

---

### 2. На NODE1

```bash
singbox-menu
```

Выбрать:

```text
2) Настроить NODE1 / входной сервер -> NODE2
```

Вставить данные от NODE2:

```text
IP или домен NODE2
NODE2_UUID
NODE2_PUBLIC_KEY
NODE2_SHORT_ID
NODE2_SNI
```

После настройки NODE1 выдаст клиентскую ссылку.

---

## Подписка

На NODE1 выбрать:

```text
16) Настроить / показать подписку
```

Будет создан URL вида:

```text
http://NODE1_IP:2096/TOKEN/sub.txt
```

Этот URL добавляется в клиент как подписка.

После смены SNI через меню файл подписки обновляется автоматически.

Если на VPS включён firewall, нужно открыть TCP порт подписки.

---

## Проверка каскада

На NODE1 выбрать:

```text
15) Проверка каскада
```

Проверяется:

- синтаксис sing-box config;
- активен ли sing-box;
- включён ли автозапуск;
- слушает ли 443;
- совпадает ли UUID NODE1;
- совпадают ли параметры NODE2;
- доступен ли NODE2:443 с NODE1;
- активна ли подписка.

---

## Главное правило

```text
Клиент -> NODE1:
UUID = NODE1_UUID
PublicKey = NODE1_PUBLIC_KEY
ShortID = NODE1_SHORT_ID
SNI = NODE1_SNI
```

```text
NODE1 -> NODE2:
UUID = NODE2_UUID
PublicKey = NODE2_PUBLIC_KEY
ShortID = NODE2_SHORT_ID
SNI = NODE2_SNI
```

```text
NODE2:
UUID = NODE2_UUID
PrivateKey = NODE2_PRIVATE_KEY
ShortID = NODE2_SHORT_ID
```

PrivateKey никогда не уходит наружу.

PublicKey используется на противоположной стороне.

---

## Полезные команды

```bash
systemctl status sing-box
journalctl -u sing-box -f
sing-box check -c /etc/sing-box/config.json
ss -tulpn | grep 443
```

---

## Файлы

```text
/etc/sing-box/config.json
/root/singbox-node-cascade/node.env
/root/singbox-node-cascade/settings.conf
/root/singbox-node-cascade/backups/
/var/lib/singbox-node-cascade-sub/
```


---

## Удаление

В меню:

```text
17) Удалить SingBox Node Cascade
```

Для подтверждения нужно написать:

```text
DELETE
```

Будет удалено:

```text
sing-box
/etc/sing-box
/opt/singbox-node-cascade
/root/singbox-node-cascade
/var/lib/singbox-node-cascade-sub
/usr/local/bin/singbox-menu
сервис подписки
```

SSH, firewall и системные пакеты curl/wget/jq/nano не трогаются.
