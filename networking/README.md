# Networking

Reverse proxy via Nginx Proxy Manager (NPM). Handles SSL automatically via Let's Encrypt.

## Architecture

```
Internet
    │
    ├── :80 / :443 ──► NPM ──► plex.yourname.asuscomm.com    ──► Plex       (32400)
    │                      ──► photos.yourname.asuscomm.com  ──► Immich     (2283)
    │                      ──► llm.yourname.asuscomm.com     ──► Open WebUI (3000)
    │
    └── :25565 ──────────────────────────────────────────────► Minecraft    (25565)
```

---

## Step 1 — Static Local IP (DHCP Reservation)
> Manual: [Section 3.9.2 DHCP Server](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.49

Port forwarding requires the server always has the same local IP.

1. Connect the server to the router via ethernet and boot it
2. In the router UI: **Advanced Settings > LAN > DHCP Server**
3. Scroll to **Enable Manual Assignment** — set to **Yes**
4. In the **Manually Assigned IP** table, find the server's MAC address in the client list and assign it a static IP e.g. `192.168.1.10`
5. Click **Add** then **Apply**
6. Reboot the server

Verify after reboot:
```bash
ip addr show | grep "inet " | grep -v 127.0.0.1
```

---

## Step 2 — DDNS
> Manual: [Section 3.14.5 DDNS](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.76

1. In the router UI: **Advanced Settings > WAN > DDNS**
2. Set **Enable the DDNS Client** to **Yes**
3. Under **Server and Host Name**, choose **WWW.ASUS.COM**
4. Enter your hostname — it will become `yourname.asuscomm.com`
5. Click **Apply**

Your services will be accessible at:
```
plex.yourname.asuscomm.com
photos.yourname.asuscomm.com
```

> You can swap to a custom domain later by updating NPM and DNS records — takes ~10 minutes.

---

## Step 3 — Port Forwarding
> Manual: [Section 3.14.3 Virtual Server / Port Forwarding](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.72

1. In the router UI: **Advanced Settings > WAN > Virtual Server / Port Forwarding**
2. Set **Enable Port Forwarding** to **On**
3. Add the following rules pointing to the server's static IP:

| Service Name | External Port | Internal Port | Internal IP | Protocol |
|-------------|---------------|---------------|-------------|----------|
| NPM-HTTP | 80 | 80 | 192.168.1.10 | TCP |
| NPM-HTTPS | 443 | 443 | 192.168.1.10 | TCP |
| Minecraft | 25565 | 25565 | 192.168.1.10 | TCP |

4. Click **Apply**

---

## Step 4 — Firewall (ufw)

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 25565/tcp
sudo ufw enable

# Port 3000 (Open WebUI) is intentionally not opened — external access goes through NPM on 443
```

---

## Step 5 — Start NPM

```bash
cd ~/workspace/home-server/networking
docker compose up -d
```

---

## Step 6 — NPM First-Time Setup

1. Open the admin UI: `http://<server-local-ip>:81`
2. Default login:
   - Email: `admin@example.com`
   - Password: `changeme`
3. Change your email and password immediately

---

## Step 7 — Add Proxy Hosts

For each service, go to **Proxy Hosts > Add Proxy Host**:

### Plex
- Domain: `plex.yourname.asuscomm.com`
- Scheme: `http`
- Forward Hostname/IP: `127.0.0.1`
- Forward Port: `32400`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

### Immich
- Domain: `photos.yourname.asuscomm.com`
- Scheme: `http`
- Forward Hostname/IP: `127.0.0.1`
- Forward Port: `2283`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

### Open WebUI (LLM)
- Domain: `llm.yourname.asuscomm.com`
- Scheme: `http`
- Forward Hostname/IP: `127.0.0.1`
- Forward Port: `3000`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

---

## Mobile Photo Uploads (Immich)

Install the Immich app on your phone (iOS or Android). In the app settings:
- Server URL: `https://photos.yourname.asuscomm.com`
- Log in with your Immich account
- Enable **Automatic Background Backup**

Photos will upload automatically over both WiFi and mobile data.

---

## Minecraft

Minecraft bypasses NPM entirely — it uses raw TCP on port 25565. Friends connect using:
```
yourname.asuscomm.com:25565
```

---

## Dynamic DNS

Handled automatically by your ASUS RT-AX58U via the built-in DDNS feature. No extra software needed.
