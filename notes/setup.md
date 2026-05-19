# Notes — Setup

reMarkable cloud replacement. Uploaded notes are forwarded to document-pipeline
for OCR + classification + embedding (handled in the api/ stack, not here).

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

## 6. Configure the webhook integration

In the rmfakecloud web UI, add a webhook integration pointing to document-pipeline:

- URL: `http://document-pipeline:8000/webhook`
- Type: Webhook

On the tablet, tap the **Share** icon on any notebook — the integration will appear as a send target. Tapping it sends the note image to document-pipeline, which runs it through OCR (via llm-swap), classification, and embedding stages.

## 7. Query your notes

document-pipeline writes embedded chunks to Qdrant. Use the document-pipeline UI
at `http://localhost:8000` to search, or attach the Qdrant collection to an
Open WebUI knowledge base for RAG-style chat across your notes.

## Monitoring

```bash
docker logs document-pipeline -f
```
