# Notes — Setup

reMarkable cloud replacement. quack's `remarkable` extension logs into this
rmfakecloud with its own account (see `quack/docker-compose.yml`) and handles
uploaded notes from there; nothing else consumes them.

## 1. Generate secrets

```bash
notes/generate-env.sh
```

This generates `RMFAKECLOUD_JWT_SECRET_KEY` and `COUCHDB_PASSWORD`. Safe to re-run — skips keys that are already set.

## 2. Create the vault directory

```bash
sudo mkdir -p /mnt/personal/obsidian-vault/remarkable
sudo chown -R jason-server:personal-rw /mnt/personal/obsidian-vault
sudo chmod -R 2775 /mnt/personal/obsidian-vault
```

## 3. Start the stack

```bash
cd ~/workspace/home-server/notes
docker compose up -d
```

## 4. Configure NPM proxy host

In Nginx Proxy Manager, add a proxy host:

**reMarkable cloud:**
- Domain: `remarkable.jasonfagerberg.duckdns.org`
- Forward Host: `192.168.50.186`, Port: `3005`
- WebSockets: on, Force SSL: on

## 5. Connect your reMarkable tablet

1. Install [rmfakecloud-proxy](https://github.com/ddvk/rmfakecloud-proxy) on your tablet (requires enabling developer mode)
2. In the proxy config, set the server URL to `https://remarkable.jasonfagerberg.duckdns.org`
3. Visit `https://remarkable.jasonfagerberg.duckdns.org` — log in and generate a one-time code
4. On the tablet, enter the code to register

## 6. Give quack access

Create a second rmfakecloud user for quack and put its credentials in
`quack/.env` (the `extensions.remarkable` block in `quack/quack.yaml` reads
them). quack polls the cloud itself; no webhook integration is needed.

## Monitoring

```bash
docker logs rmfakecloud -f
docker logs quack -f | grep remarkable
```
