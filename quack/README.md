# quack — GitHub PR-review bot

[quack](https://github.com/fagerbergj/quack) reviews GitHub pull requests: mention
`@quack` on a PR, open a PR (auto-review), or apply the `quack-auto-review` label,
and it clones the repo, reads the diff, and posts an inline review.

Built from source; reuses `llm-swap` + `qdrant` (from `../llm/`) and brings its own
Postgres. Ingress: **NPM → Traefik (`api` entrypoint) → quack** on `api_gateway`.
The `/api/v1/github/webhook` path is **public** (GitHub HMAC-signs it); the UI + rest
of the API are behind **Authentik**.

## Deploy (on the server)

1. **Clone the build source** (the compose builds from it):
   ```bash
   git clone https://github.com/fagerbergj/quack ~/workspace/agent-researcher
   ```
2. **Place the GitHub App private key** on the server, e.g. `~/.quack/quack-jason.private-key.pem`.
3. **Fill secrets** in the root `../.env`:
   - `QUACK_GITHUB_APP_CLIENT_ID` — from the App (github.com/settings/apps/quack-jason).
   - `QUACK_GITHUB_APP_PRIVATE_KEY_PATH` — absolute path to the `.pem` from step 2.
   - `QUACK_EXA_API_KEY` — Exa search key.
   - Then `./generate-env.sh` to generate `QUACK_DB_PASSWORD` + `QUACK_GITHUB_APP_WEBHOOK_SECRET`.
4. **Build + start:**
   ```bash
   cd quack && docker compose build && docker compose up -d
   docker logs quack | grep "github extension enabled"   # confirm the App loaded
   ```
5. **NPM** (admin UI, :81): add a Proxy Host `quack.jasonfagerberg.duckdns.org` →
   forward to the Traefik `api` entrypoint (`:8090`), TLS via the DuckDNS wildcard cert —
   same as the existing `api.` / `documents.` hosts.
6. **GitHub App** (github.com/settings/apps/quack-jason):
   - **Webhook URL** = `https://quack.jasonfagerberg.duckdns.org/api/v1/github/webhook`
   - **Webhook secret** = the `QUACK_GITHUB_APP_WEBHOOK_SECRET` from `../.env` (must match).
   - **Install** the App on the repos to review (e.g. `fagerbergj/quack`, `fagerbergj/games`).

## Verify

```bash
# Public webhook route reachable + signature check active (bad sig ⇒ 401):
curl -s -o /dev/null -w '%{http_code}\n' -XPOST \
  https://quack.jasonfagerberg.duckdns.org/api/v1/github/webhook -d '{}'   # → 401
```
Then `@quack review this PR` on an installed repo — the App's *Recent Deliveries* should
show `202`, and quack posts a review. UI: `https://quack.jasonfagerberg.duckdns.org/`
(Authentik login).

## Config

`quack.yaml` is a copy of the upstream `config/quack.yaml` with two server edits: `web_fetch`
→ `kind: direct` (no crawl4ai here) and `extensions.github` enabled. Models are set in
`docker-compose.yml` (35b main, `qwen3-coder-next` for coding, gemma judge, vl image, omni media).

**If large-PR reviews stall** (models can't co-reside → swap thrash), fall back to a single
review model: set `QUACK_ORCH_MODEL`/`QUACK_RESEARCHER_MODEL`/`QUACK_CODER_MODEL=qwen3-coder-next`
and `QUACK_JUDGE_MODEL=` (empty) in `docker-compose.yml`, then recreate.
