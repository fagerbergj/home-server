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

## 3. Pull models

```bash
docker exec ollama ollama pull qwen3:4b
docker exec ollama ollama pull gpt-oss:20b
docker exec ollama ollama pull carstenuhlig/omnicoder-9b:latest
```

## 4. Create context-capped model variants

All models default to large context windows that exceed available VRAM — cap them to avoid excessive RAM spill:

```bash
docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM carstenuhlig/omnicoder-9b:latest
PARAMETER num_ctx 131072
EOF
ollama create omnicoder-9b-128k -f /tmp/Modelfile'

docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM gpt-oss:20b
PARAMETER num_ctx 65536
EOF
ollama create gpt-oss-20b-64k -f /tmp/Modelfile'

docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM qwen3:4b
PARAMETER num_ctx 32768
EOF
ollama create qwen3-4b-32k -f /tmp/Modelfile'
```

## 5. Set up Open WebUI

Open `http://192.168.50.186:3000` in your browser.

1. Create your admin account (first account gets admin)
2. Set the default model to `qwen3-4b-32k` in **Admin Panel > Settings > Interface**
3. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them `https://llm.jasonfagerberg.duckdns.org` and their credentials — they can change their password after logging in

## Verify

1. Open `http://192.168.50.186:3000`, confirm `qwen3-4b-32k` is the default, and send a test message — you should get a response within a few seconds
2. Check GPU is being used:
   ```bash
   docker exec -it ollama ollama ps
   ```
   You should see the model listed with `100% GPU`
3. Verify API key auth is working via OpenCode — follow [opencode_setup.md](opencode_setup.md) to configure it with `gpt-oss-20b-64k`, then confirm you can chat from a project
4. Confirm auth is enforced at NPM — a request without the key should be rejected:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" https://llm-api.jasonfagerberg.duckdns.org/v1/models
   ```
   You should get `401`
