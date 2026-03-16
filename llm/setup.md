# LLM — Setup

## 1. Generate the env file

```bash
./generate-env.sh
```

This generates the API key used in NPM's nginx config to protect the external Ollama endpoint.

## 2. Start services

```bash
docker compose up -d
```

## 3. Pull models and create nothink variant

```bash
docker exec -it ollama ollama pull qwen3:8b
```

Create a thinking-disabled variant for use with OpenCode and other OpenAI-compatible clients:

```bash
echo -e 'FROM qwen3:8b\nSYSTEM /nothink' > /tmp/Modelfile
docker cp /tmp/Modelfile ollama:/tmp/Modelfile
docker exec ollama ollama create qwen3:8b-nothink -f /tmp/Modelfile
```

## 4. Set up Open WebUI

Open `http://192.168.50.186:3000` in your browser.

1. Create your admin account (first account gets admin)
2. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them `https://llm.jasonfagerberg.duckdns.org` and their credentials — they can change their password after logging in

## Verify

1. Open `http://192.168.50.186:3000`, select `qwen3:8b`, and send a test message — you should get a response within a few seconds
2. Check GPU is being used:
   ```bash
   docker exec -it ollama ollama ps
   ```
   You should see the model listed with `100% GPU`
3. Verify API key auth is working via OpenCode — follow [opencode_setup.md](opencode_setup.md) to configure it, then confirm you can chat with `qwen3:8b-nothink` from a project
4. Confirm auth is enforced at NPM — a request without the key should be rejected:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" https://llm-api.jasonfagerberg.duckdns.org/v1/models
   ```
   You should get `401`
