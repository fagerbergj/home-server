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

> If you see `address already in use` on port 53, `systemd-resolved` wasn't fully stopped — re-run step 1 and try again.

## 3. Run the setup wizard

Open `http://192.168.50.186:3002` and follow the wizard. Set your admin username and password.

After the wizard completes the web UI is accessible at `http://jason-server:3003` (tailnet) or `http://192.168.50.186:3003` (LAN). Not exposed via NPM.

## 4. Point router DNS at the server

Both settings are needed: DHCP decides what devices ask, and WAN decides where the router itself forwards (devices are also handed the router's IPv4 and IPv6 addresses as DNS).

- **Advanced Settings > LAN > DHCP Server:** DNS Server 1 `192.168.50.186`, DNS Server 2 blank. Any public second server lets blocked domains through, because clients spread queries across every server they're given.
- **Advanced Settings > WAN > Internet Connection:** DNS Server → Assign → **Manual Setting**, DNS Server1 `192.168.50.186`, DNS Server2 blank; **DNS Privacy Protocol** None (DNS-over-TLS bypasses the list). Applying restarts the router.

AdGuard's upstream servers must not include `192.168.50.1`, or the router and AdGuard forward to each other in a loop. Tailnet clients already use AdGuard through Headscale's `override_local_dns`.

Trade-off: with no fallback, DNS is down for the whole LAN while AdGuard or the media box is down.

### Blocklists

Use **HaGeZi's Pro Blocklist**. Avoid **1Hosts (Xtra)**, which blocks legitimate sites outright (`opencode.ai`, `v0.dev`, `shadcn.com`), and **HaGeZi's URL Shortener Blocklist**.

## 5. Verify

From the server:
```bash
dig @192.168.50.186 doubleclick.net
```
Should return `0.0.0.0` if blocking is working.

From any device after pointing router DNS at the server:
```bash
nslookup doubleclick.net
```
Should return `0.0.0.0` or `NXDOMAIN`. Check the AdGuard **Query Log** to confirm DNS queries are flowing through.
