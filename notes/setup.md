# Notes — Setup

reMarkable cloud replacement + OCR pipeline + Obsidian sync.

## 1. Pull the OCR model into Ollama

```bash
cd ~/workspace/home-server/llm
docker compose exec ollama ollama pull richardyoung/olmocr2:7b-q8
```

## 2. Generate secrets

```bash
notes/generate-env.sh
```

This generates `RMFAKECLOUD_JWT_SECRET_KEY` and `COUCHDB_PASSWORD`. Safe to re-run — skips keys that are already set.

## 3. Create the vault directory

```bash
sudo mkdir -p /mnt/personal01/obsidian-vault/remarkable
sudo chown -R jason-server:personal-rw /mnt/personal01/obsidian-vault
sudo chmod -R 2775 /mnt/personal01/obsidian-vault
```

## 4. Start the stack

```bash
cd ~/workspace/home-server/notes
docker compose up -d
```

## 5. Configure NPM proxy hosts

In Nginx Proxy Manager, add two proxy hosts:

**reMarkable cloud:**
- Domain: `remarkable.jasonfagerberg.duckdns.org`
- Forward Host: `192.168.50.186`, Port: `3005`
- WebSockets: on, Force SSL: on

**Obsidian sync:**
- Domain: `obsidian.jasonfagerberg.duckdns.org`
- Forward Host: `192.168.50.186`, Port: `5984`
- WebSockets: on, Force SSL: on

## 6. Initialise CouchDB

```bash
source ../.env
curl -s https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/couchdb/couchdb-init.sh | \
  hostname="http://localhost:5984" username="$COUCHDB_USER" password="$COUCHDB_PASSWORD" bash
```

## 7. Connect your reMarkable tablet

1. Install [rmfakecloud-proxy](https://github.com/ddvk/rmfakecloud-proxy) on your tablet (requires enabling developer mode)
2. In the proxy config, set the server URL to `https://remarkable.jasonfagerberg.duckdns.org`
3. Visit `https://remarkable.jasonfagerberg.duckdns.org` — log in and generate a one-time code
4. On the tablet, enter the code to register

## 8. Configure the webhook

In the rmfakecloud web UI:
1. Go to **Integrations**
2. Add a new webhook pointing to `http://remarkable-bridge:8000/webhook`
   (bridge is on the same Docker network, no external URL needed)

## 9. Test OCR immediately

After syncing a note from the tablet, trigger OCR without waiting for 2am:

```bash
curl -X POST http://localhost:3006/jobs/ocr
```

Check the output:
```bash
ls /mnt/personal01/obsidian-vault/remarkable/
```

## 10. Set up Obsidian LiveSync

In Obsidian on each device:

1. **Community Plugins** → Browse → search **Self-hosted LiveSync** → Install → Enable
2. In the plugin settings:
   - Server URI: `https://obsidian.jasonfagerberg.duckdns.org`
   - Username / Password: the CouchDB credentials from step 2
   - Database: `obsidian`
3. Complete the setup wizard

## 11. Set up the Obsidian Ollama plugin

In Obsidian:

1. **Community Plugins** → Browse → search **Ollama** (by hinterdupfinger) → Install → Enable
2. In plugin settings, change the URL to:
   `https://llm-api.jasonfagerberg.duckdns.org`
3. Set the API key to match `OLLAMA_API_KEY` in your `.env`

## Monitoring

```bash
# Check bridge queue depth
curl http://localhost:3006/queue

# View bridge logs
docker logs remarkable-bridge -f

# Check CouchDB health
curl https://obsidian.jasonfagerberg.duckdns.org/
```
