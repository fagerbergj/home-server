# LLM — Setup

## 1. Start services

```bash
docker compose up -d
```

## 2. Pull models

```bash
docker exec ollama ollama pull qwen3.5:35b
```

## 3. Create model variants

Two variants from the same weights — one tuned for coding (large context, thinking on), one for chat (small context, no thinking). Qwen3.5 35B is a hybrid SSM architecture so VRAM stays flat (~26 GiB) regardless of context size.

```bash
docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM qwen3.5:35b
PARAMETER num_ctx 131072
SYSTEM /think
EOF
ollama create qwen35-coding -f /tmp/Modelfile'

docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM qwen3.5:35b
PARAMETER num_ctx 8192
SYSTEM /no_think
EOF
ollama create qwen35-chat -f /tmp/Modelfile'
```

## 4. Set up Open WebUI

Open `http://192.168.50.186:3000` in your browser.

1. Create your admin account (first account gets admin)
2. Set the default model to `qwen35-chat` in **Admin Panel > Settings > Interface**
3. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them `https://llm.jasonfagerberg.duckdns.org` and their credentials — they can change their password after logging in

## Verify

1. Open `http://192.168.50.186:3000`, confirm `qwen35-chat` is the default, and send a test message — you should get a response within a few seconds
2. Check GPU is being used:
   ```bash
   docker exec -it ollama ollama ps
   ```
   You should see the model listed with `100% GPU`
3. Verify the API is reachable over the tailnet — from any tailnet-enrolled device:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://jason-server:11434/api/tags
   ```
   You should get `200`. From a non-tailnet device on the public internet the request should fail outright — that's the access boundary working.
4. Verify OpenCode integration — follow [opencode_setup.md](opencode_setup.md) to configure it with `qwen35-coding`, then confirm you can chat from a project
