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
4. Add to `~/workspace/home-server/networking/.env`:
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
| Games | 3000 | 3000 | 192.168.50.186 | TCP |
| Minecraft | 25565 | 25565 | 192.168.50.186 | TCP |

4. Click **Apply**

### DNS (AdGuard Home)

Once AdGuard Home is running, point the router's DNS at the server so all devices get ad blocking:

1. In the router UI: **Advanced Settings > LAN > DHCP Server**
2. Set **DNS Server 1** to `192.168.50.186`
3. Set **DNS Server 2** to `1.1.1.1` (fallback if AdGuard goes down)
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
| API Gateway | `api.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8090` | Yes | `*.jasonfagerberg.duckdns.org` |
| Authentik | `auth.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8090` | Yes | `*.jasonfagerberg.duckdns.org` |
| Audiobookshelf | `books.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `13378` | Yes | `*.jasonfagerberg.duckdns.org` |
| Games | `games.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `3000` | Yes | `*.jasonfagerberg.duckdns.org` |
| Open WebUI | `llm.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `3000` | Yes | `*.jasonfagerberg.duckdns.org` |
| Vaultwarden | `passwords.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8888` | Yes | `*.jasonfagerberg.duckdns.org` |
| Immich | `photos.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `2283` | Yes | `*.jasonfagerberg.duckdns.org` |
| Plex | `plex.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `32400` | Yes | `*.jasonfagerberg.duckdns.org` |
| quack | `quack.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8090` | Yes | `*.jasonfagerberg.duckdns.org` |
| rmfakecloud | `remarkable.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `3005` | Yes | `*.jasonfagerberg.duckdns.org` |

Enable **Force SSL** on all. Select the wildcard cert from the dropdown — do not request a new cert per host.

> **quack** routes through **Traefik** (like API Gateway / Authentik — forward to `:8090`), not a direct
> container port. Traefik then splits it: `POST /api/v1/github/webhook` is **public** (GitHub delivers
> there, HMAC-signed), while the UI + rest of the API sit behind **Authentik**. The GitHub App's webhook
> URL must point at `https://quack.jasonfagerberg.duckdns.org/api/v1/github/webhook`, so this host must
> stay public + Force-SSL (GitHub only delivers over HTTPS).

> Grafana, Uptime Kuma, and the LLM API used to live here. They were moved to tailnet-only access in Phase 7 — pure admin surfaces, no off-tailnet device needs them.

---

## Phase 7 — Tailscale

Tailscale gives every device in the tailnet a stable `100.x.x.x` IP and a `*.ts.net` hostname, so admin UIs that aren't safe to expose publicly (NPM `:81`, Traefik `:8091`, AdGuard, qBittorrent, Grafana, Uptime Kuma, Authentik direct on `:9000`, llm-swap on `:11436`) become reachable from any enrolled client without touching the router. NPM + Authentik continue to handle the genuinely public hosts on `*.jasonfagerberg.duckdns.org`.

### Install on the Server

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up \
  --ssh \
  --advertise-routes=192.168.50.0/24 \
  --advertise-exit-node \
  --accept-dns=false
```

- `--ssh` lets you SSH to the host over the tailnet (no port 22 forwarding needed).
- `--advertise-routes` exposes the LAN so tailnet clients can reach the router and other LAN devices through the server.
- `--advertise-exit-node` lets phones/laptops route all traffic through home (useful on hostile Wi-Fi).
- `--accept-dns=false` keeps the server's own resolver pointed at AdGuard locally; only clients use MagicDNS.

Open the printed login URL once and authenticate with your identity provider.

### Enable IP Forwarding (Required for Subnet Route + Exit Node)

`tailscale up` will warn that IPv6 forwarding is disabled. Without this, advertised subnet routes and exit-node mode silently drop traffic.

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

### UDP GRO Tuning (Optional, Throughput)

Tailscale also warns that UDP GRO forwarding is suboptimally configured. Apply once and persist via systemd:

```bash
sudo ethtool -K enp5s0 rx-udp-gro-forwarding on rx-gro-list off

sudo tee /etc/systemd/system/tailscale-ethtool.service >/dev/null <<'EOF'
[Unit]
Description=Tailscale ethtool tuning
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K enp5s0 rx-udp-gro-forwarding on rx-gro-list off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now tailscale-ethtool.service
```

Replace `enp5s0` with your primary NIC if different — find it with `ip -o route get 8.8.8.8 | awk '{print $5}'`.

### Enroll Clients (Laptop / Phone)

On every other device that should join the tailnet, install Tailscale and run plain `tailscale up` — **no advertise flags**, those are server-only. On Linux:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

On macOS / iOS / Android, install the official app and sign in with the same identity provider as the server.

### Approve in the Admin Console

In [login.tailscale.com](https://login.tailscale.com):

1. **Machines > server > Edit route settings**
   - Enable the `192.168.50.0/24` subnet route.
   - Enable **Use as exit node**.
2. **Machines > server > Disable key expiry** — server should not need re-auth.
3. **DNS > Nameservers** — add `192.168.50.186` (AdGuard) as a global nameserver, enable **Override local DNS**. Now every tailnet client uses AdGuard for ad blocking, anywhere.
4. **DNS > MagicDNS** — enable. The server is reachable at `server.<tailnet>.ts.net`.

### Enroll Clients

Install the Tailscale app on phone/laptop/tablet, sign in with the same identity provider. Then:

- Direct hits work immediately: `http://<server-tailnet-name>:81` for NPM admin, `:8091` for Traefik dashboard, `:3001` for Uptime Kuma, etc.
- LAN passthrough works: `http://192.168.50.186:81` resolves over the tailnet via the subnet route.
- Toggle the server as exit node from the client app when on untrusted networks.

### What Stays Public

Do not change ingress for these — they are intentionally public via NPM + Authentik:

- `auth.jasonfagerberg.duckdns.org` (Authentik UI)
- `api.jasonfagerberg.duckdns.org` (Traefik gateway, document-pipeline, swagger-ui)
- `documents.jasonfagerberg.duckdns.org`
- `photos.`, `plex.`, `books.`, `passwords.`, `remarkable.`, `llm.` — anything you'd hand to a non-tailnet device.

The `80/443/25565` port-forwards on the router stay as-is.

### What Becomes Tailnet-Only

These never need to leave the tailnet — no NPM proxy host, no Authentik route. Access them directly via the server's tailnet IP/hostname:

- NPM admin (`:81`)
- Traefik dashboard (`:8091`)
- AdGuard Home admin (see `adblock/`)
- qBittorrent web UI
- Authentik direct (`:9000`) — only useful for break-glass; normal use is the public `auth.` host
- llm-swap API (`:11436`) — no auth on the upstream; tailnet membership is the access boundary
- deepwiki (`:3007`) — no auth of its own, and it indexes `home-server`, so tailnet membership is the access boundary. Deliberately no NPM proxy host: its Traefik router exists but nothing public routes to it.
- Grafana (`:3004`) — admin-only metrics dashboard
- Uptime Kuma (`:3001`) — personal status board, not a public status page

The `dashboard.`, `status.`, and `llm-api.` proxy hosts that previously fronted Grafana, Uptime Kuma, and the LLM API have been deleted from NPM. The wildcard cert still covers the namespace if you ever want to re-add a public host.

### Updates

The `tailscaled` package auto-updates via apt's unattended upgrades hook installed by the official script. Confirm with:

```bash
sudo tailscale status
sudo tailscale version
```
