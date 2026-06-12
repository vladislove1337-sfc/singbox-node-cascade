# SingBox Node Cascade Manager v1.0.3

Автоматический менеджер каскада:

CLIENT -> NODE1 -> NODE2 -> INTERNET

## Возможности

- установка SingBox
- настройка NODE2 (выход)
- настройка NODE1 (вход -> NODE2)
- VLESS Reality Vision
- генерация UUID
- генерация Reality ключей
- смена SNI через меню
- замена NODE2 без пересборки NODE1
- клиентская ссылка
- QR-код
- резервные копии
- диагностика
- просмотр логов
- автоперезапуск sing-box
- RU/EN язык

## Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/install.sh)
```

После установки:

```bash
singbox-menu
```

## Схема настройки

### 1. На NODE2

Запустить меню:

```bash
singbox-menu
```

Выбрать:

```
1) Настроить NODE2
```

Получишь:

```
UUID
PublicKey
ShortID
SNI
```

Их сохранить.

---

### 2. На NODE1

Выбрать:

```
2) Настроить NODE1 -> NODE2
```

Вставить данные от NODE2:

```
IP NODE2
UUID NODE2
PublicKey NODE2
ShortID NODE2
SNI NODE2
```

После этого NODE1 выдаст ссылку для клиента.

---

### Смена SNI

Меню:

```
6) Изменить SNI
```

Можно менять:

- вход NODE1
- выход NODE1 -> NODE2
- оба

---

### Если NODE2 умер

Поднять новый NODE2.

На NODE1:

```
7) Изменить NODE2 на NODE1
```

Вставить новые параметры.

Готово.
