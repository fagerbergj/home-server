# Networking — Setup

Setup is split across two phases because the router config needs no software beyond bare Ubuntu, while NPM requires Docker.

---

## Phase 1 — Router & Firewall

Done after first boot, before the system update reboot — the server is on the network so its MAC address is visible in the router. The monitor is still connected.

### Static Local IP (DHCP Reservation)
> Manual: [Section 3.9.2 DHCP Server](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.49

1. In the router UI: **Advanced Settings > LAN > DHCP Server**
2. Scroll to **Enable Manual Assignment** — set to **Yes**
3. Find the server's MAC address in the client list, assign it a static IP (`192.168.50.186`)
4. Click **Add** then **Apply**

### DDNS

DDNS is handled by the `duckdns-updater` container — no router config needed.

1. Go to [duckdns.org](https://www.duckdns.org) and sign in
2. Claim the subdomain `jasonfagerberg` (or your preferred name)
3. Copy your token
4. Add to `~/.env`:
   ```
   DUCKDNS_SUBDOMAIN=jasonfagerberg
   DUCKDNS_TOKEN=<your-token>
   ```
5. The updater container will keep your IP current automatically once started in Phase 6

### Port Forwarding
> Manual: [Section 3.14.3 Virtual Server / Port Forwarding](E23448_RT-AX58U_V2_UM_V2_WEB.pdf) — p.72

1. In the router UI: **Advanced Settings > WAN > Virtual Server / Port Forwarding**
2. Set **Enable Port Forwarding** to **On**
3. Add the following rules pointing to the server's static IP:

| Service Name | External Port | Internal Port | Internal IP | Protocol |
|-------------|---------------|---------------|-------------|----------|
| NPM-HTTP | 80 | 80 | 192.168.50.186 | TCP |
| NPM-HTTPS | 443 | 443 | 192.168.50.186 | TCP |
| Minecraft | 25565 | 25565 | 192.168.50.186 | TCP |

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

### Request Wildcard SSL Certificate

Do this before adding proxy hosts so the cert is ready to assign.

1. Go to **SSL Certificates > Add SSL Certificate > Let's Encrypt**
2. Domain: `*.jasonfagerberg.duckdns.org`
3. Enable **Use a DNS Challenge**
4. DNS Provider: **DuckDNS**
5. Credentials: paste your DuckDNS token
6. Agree to ToS and click **Save** — cert will appear once issued

### Add / Update Proxy Hosts

For each service, go to **Proxy Hosts** and either edit an existing host or click **Add Proxy Host**:

| Service | Domain | Scheme | Forward Host | Port | Websockets | SSL cert |
|---------|--------|--------|--------------|------|------------|----------|
| Plex | `plex.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `32400` | Yes | `*.jasonfagerberg.duckdns.org` |
| Immich | `photos.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `2283` | Yes | `*.jasonfagerberg.duckdns.org` |
| Open WebUI | `llm.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `3000` | Yes | `*.jasonfagerberg.duckdns.org` |
| Ollama API | `llm-api.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `11434` | No | `*.jasonfagerberg.duckdns.org` |
| Audiobookshelf | `books.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `13378` | Yes | `*.jasonfagerberg.duckdns.org` |

Enable **Force SSL** on all. Select the wildcard cert from the dropdown — do not request a new cert per host.

> The API key set in `llm/.env` is the only auth layer here — keep it strong.

> Netdata is accessed via Netdata Cloud — no proxy host needed.
