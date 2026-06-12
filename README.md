# SingBox Node Cascade Manager v1.0.4

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
- смена SNI через меню;
- замена NODE2 на NODE1 без ручного редактирования JSON;
- просмотр параметров ноды;
- просмотр логов;
- live logs;
- диагностика;
- резервные копии конфигов;
- автозапуск sing-box;
- автоперезапуск sing-box при падении;
- русский и английский язык.

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

Запустить:

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

Запустить:

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

## Смена SNI

В меню:

```text
6) Изменить SNI
```

На NODE1 можно менять:

```text
1) SNI входа NODE1
2) SNI выхода NODE1 -> NODE2
3) Оба
```

---

## Замена NODE2

Если выходная нода умерла или нужно переключиться на другую:

1. Настроить новый NODE2.
2. Скопировать его данные.
3. На NODE1 выбрать:

```text
7) Изменить NODE2 на NODE1
```

4. Вставить новые параметры NODE2.

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
```
