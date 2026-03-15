# Networking — Setup

Setup is split across two phases because the router config needs no software beyond bare Ubuntu, while NPM requires Docker.

---

## Phase 1 — Router & Firewall

Done after first boot, before the system update reboot — the server is on the network so its MAC address is visible in the router. The monitor is still connected.

### Static Local IP (DHCP Reservation)
> Manual: [Section 3.9.2 DHCP Server](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.49

1. In the router UI: **Advanced Settings > LAN > DHCP Server**
2. Scroll to **Enable Manual Assignment** — set to **Yes**
3. Find the server's MAC address in the client list, assign it a static IP (e.g. `192.168.1.10`)
4. Click **Add** then **Apply**

### DDNS
> Manual: [Section 3.14.5 DDNS](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.76

1. In the router UI: **Advanced Settings > WAN > DDNS**
2. Set **Enable the DDNS Client** to **Yes**
3. Under **Server and Host Name**, choose **WWW.ASUS.COM**
4. Enter your hostname — it will become `jasonfagerberg.asuscomm.com`
5. Click **Apply**

> You can swap to a custom domain later by updating NPM and DNS records — takes ~10 minutes.

### Port Forwarding
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

## Phase 6 — Nginx Proxy Manager

Done after Docker is installed (Phase 5). Fully headless — all steps via SSH or browser from your main PC.

### Start NPM

```bash
cd ~/workspace/home-server/networking
docker compose up -d
```

### First-Time Setup

1. Open the admin UI: `http://<server-local-ip>:81`
2. Default login: `admin@example.com` / `changeme`
3. Change your email and password immediately

### Add Proxy Hosts

For each service, go to **Proxy Hosts > Add Proxy Host**:

#### Plex
- Domain: `plex.jasonfagerberg.asuscomm.com`
- Scheme: `http`, Forward to: `127.0.0.1:32400`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

#### Immich
- Domain: `photos.jasonfagerberg.asuscomm.com`
- Scheme: `http`, Forward to: `127.0.0.1:2283`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

#### Open WebUI (LLM)
- Domain: `llm.jasonfagerberg.asuscomm.com`
- Scheme: `http`, Forward to: `127.0.0.1:3000`
- Enable **Websockets Support**
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

#### Ollama API
- Domain: `llm-api.jasonfagerberg.asuscomm.com`
- Scheme: `http`, Forward to: `127.0.0.1:11434`
- SSL tab: request a Let's Encrypt cert, enable **Force SSL**

> The API key set in `llm/.env` is the only auth layer here — keep it strong.
