# singbox-node-cascade

Automatic SingBox Reality cascade installer and menu.

Scheme:

```text
Client -> NODE1 / ENTRY -> NODE2 / EXIT -> Internet
```

## Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/vladislove1337-sfc/singbox-node-cascade/main/install.sh)
```

After install:

```bash
singbox-menu
```

## Setup order

### On NODE2 / EXIT

```bash
singbox-menu
```

Choose:

```text
1) Configure NODE2 / EXIT
```

Copy displayed values:

```text
NODE2_UUID
NODE2_PUBLIC_KEY
NODE2_SHORT_ID
NODE2_SNI
```

### On NODE1 / ENTRY

```bash
singbox-menu
```

Choose:

```text
2) Configure NODE1 / ENTRY -> NODE2
```

Paste NODE2 values.

Then choose:

```text
4) Show client link
5) Show QR code
```

## Important

Client connects only to NODE1.

NODE1 connects to NODE2.

```text
Client UUID = NODE1_UUID
NODE1 outbound UUID = NODE2_UUID
Client PublicKey = NODE1_PUBLIC_KEY
NODE1 outbound PublicKey = NODE2_PUBLIC_KEY
```

## Useful

```bash
systemctl status sing-box
journalctl -u sing-box -f
sing-box check -c /etc/sing-box/config.json
ss -tulpn | grep 443
```
