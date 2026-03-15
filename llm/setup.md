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
