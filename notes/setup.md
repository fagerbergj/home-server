# Notes — Setup

reMarkable cloud replacement + OCR pipeline + Open WebUI knowledge base.

## 1. Pull the OCR model into Ollama

```bash
cd ~/workspace/home-server/llm
docker compose exec ollama ollama pull glm-ocr
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

## 4. Set up Open WebUI knowledge collection

1. In Open WebUI → **Workspace → Knowledge** → create a new collection called `remarkable`
2. Copy the collection ID from the URL
3. In Open WebUI → **Settings → Account → API Keys** → create an API key
4. Add to `.env`:
   ```bash
   export OPENWEBUI_API_KEY=sk-...
   export OPENWEBUI_KNOWLEDGE_ID=<id from URL>
   ```

## 5. Start the stack

```bash
cd ~/workspace/home-server/notes
docker compose up -d
```

## 6. Configure NPM proxy host

In Nginx Proxy Manager, add a proxy host:

**reMarkable cloud:**
- Domain: `remarkable.jasonfagerberg.duckdns.org`
- Forward Host: `192.168.50.186`, Port: `3005`
- WebSockets: on, Force SSL: on

## 7. Connect your reMarkable tablet

1. Install [rmfakecloud-proxy](https://github.com/ddvk/rmfakecloud-proxy) on your tablet (requires enabling developer mode)
2. In the proxy config, set the server URL to `https://remarkable.jasonfagerberg.duckdns.org`
3. Visit `https://remarkable.jasonfagerberg.duckdns.org` — log in and generate a one-time code
4. On the tablet, enter the code to register

## 8. Configure the webhook integration

In the rmfakecloud web UI, add a webhook integration pointing to the bridge:

- URL: `http://document-pipeline:8000/webhook`
- Type: Webhook

On the tablet, tap the **Share** icon on any notebook — the integration will appear as a send target. Tapping it sends the note image to the bridge, which OCRs it via Ollama and uploads it to the Open WebUI knowledge collection.

## 9. Query your notes in Open WebUI

In any Open WebUI chat, click the knowledge icon and select the `remarkable` collection. You can now ask questions or request summaries across all your notes using any Ollama model.

## Monitoring

```bash
# View bridge logs
docker logs document-pipeline -f
```
