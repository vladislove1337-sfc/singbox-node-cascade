# singbox-node-cascade

SingBox Node Cascade Manager v1.0.0.

Схема:

```text
Client -> NODE1 / ENTRY -> NODE2 / EXIT -> Internet
```

## Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/install.sh)
```

После установки:

```bash
singbox-menu
```

## Порядок настройки

### На NODE2 / выходном сервере

```bash
singbox-menu
```

Выбрать:

```text
1) Настроить NODE2 / выходной сервер
```

Скопировать:

```text
NODE2_UUID
NODE2_PUBLIC_KEY
NODE2_SHORT_ID
NODE2_SNI
```

### На NODE1 / входном сервере

```bash
singbox-menu
```

Выбрать:

```text
2) Настроить NODE1 / входной сервер -> NODE2
```

Вставить данные NODE2.

Потом:

```text
4) Показать клиентскую ссылку
5) Показать QR-код
```

## Важно

Клиент подключается только к NODE1.

NODE1 подключается к NODE2.

```text
Client UUID = NODE1_UUID
NODE1 outbound UUID = NODE2_UUID
Client PublicKey = NODE1_PUBLIC_KEY
NODE1 outbound PublicKey = NODE2_PUBLIC_KEY
```

## Что умеет меню

- русский / английский язык
- настройка NODE1 и NODE2
- смена SNI
- замена NODE2 на NODE1
- QR-код
- live logs
- диагностика NODE1 -> NODE2
- backup конфига
- автостарт sing-box
- автоперезапуск sing-box при падении

## Полезные команды

```bash
systemctl status sing-box
journalctl -u sing-box -f
sing-box check -c /etc/sing-box/config.json
ss -tulpn | grep 443
```
