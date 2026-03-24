# Nextcloud — Setup

## 1. Generate secrets

```bash
cd ~/workspace/home-server/files
bash generate-env.sh
```

## 2. Start the containers

```bash
docker compose up -d
```

## 3. Configure NPM proxy host

| Field | Value |
|-------|-------|
| Domain | `files.jasonfagerberg.duckdns.org` |
| Scheme | `http` |
| Forward Host | `192.168.50.186` |
| Forward Port | `8090` |
| SSL | `*.jasonfagerberg.duckdns.org`, force SSL |
| WebSockets | Yes |

## 4. Complete setup wizard

Open `https://files.jasonfagerberg.duckdns.org` and create your admin account.

## 5. Configure AI Assistant (Ollama)

1. Go to **Apps** → search for **Assistant** → install it
2. Go to **Apps** → search for **OpenAI API integration** → install it
3. Go to **Administration Settings** → **AI** → **OpenAI API**
4. Set:
   - **API endpoint**: `http://192.168.50.186:11434/v1`
   - **API key**: `ollama` (any non-empty string)
   - **Default model**: `gpt-oss-20b-64k`

## 6. Install desktop/mobile sync clients

- Desktop: [nextcloud.com/install](https://nextcloud.com/install) → Desktop client
- Point it at `https://files.jasonfagerberg.duckdns.org`
