# LLM — Setup

## 1. Generate the env file

```bash
./generate-env.sh
```

This sets the API key used to protect the external Ollama endpoint.

## 2. Start services

```bash
docker compose up -d
```

## 3. Pull a model

```bash
docker exec -it ollama ollama pull qwen3:8b
```

## 4. Set up Open WebUI

Open `http://<server-ip>:3000` in your browser.

1. Create your admin account (first account gets admin)
2. For each family/friend: **Admin Panel > Users > Add User**
   - Set their name, email, and a temporary password
   - Send them `https://llm.jasonfagerberg.asuscomm.com` and their credentials — they can change their password after logging in

## Verify

1. Open `http://<server-ip>:3000`, select `qwen3:8b`, and send a test message — you should get a response within a few seconds
2. Check GPU is being used:
   ```bash
   docker exec -it ollama ollama ps
   ```
   You should see the model listed with `100% GPU`
3. Verify API key auth is working via OpenCode — follow [opencode_setup.md](opencode_setup.md) to configure it, then confirm you can chat with `qwen3:8b` from a project
4. Confirm auth is actually enforced — a request without the key should be rejected:
   ```bash
   curl https://llm-api.jasonfagerberg.asuscomm.com/v1/models
   ```
   You should get a `401 Unauthorized` response
