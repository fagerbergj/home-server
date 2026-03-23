# AdGuard Home — Setup

## 1. Check port 53 is free

Ubuntu's `systemd-resolved` uses port 53 by default — disable it first:

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

## 2. Start the container

```bash
cd ~/workspace/home-server/adblock
docker compose up -d
```

## 3. Run the setup wizard

Open `http://192.168.50.186:3002` and follow the wizard. Set your admin username and password.

After the wizard completes AdGuard moves to port 80 inside the container — the web UI will be accessible via the NPM proxy host.

## 4. Configure NPM proxy host

| Field | Value |
|-------|-------|
| Domain | `adblock.jasonfagerberg.duckdns.org` |
| Scheme | `http` |
| Forward Host | `192.168.50.186` |
| Forward Port | `3002` |
| SSL | `*.jasonfagerberg.duckdns.org`, force SSL |
| WebSockets | Yes |

## 5. Point router DNS at the server

In the router UI: **Advanced Settings > LAN > DHCP Server**

Set **DNS Server 1** to `192.168.50.186`.

Leave DNS Server 2 as `1.1.1.1` as a fallback in case AdGuard goes down.

## 6. Verify

On any device, visit a site that normally shows ads. Check the AdGuard query log to confirm DNS queries are being processed.
