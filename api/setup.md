# API Gateway — Setup

## Prerequisites

- `api` stack started first (creates the `api_gateway` Docker network)
- NPM proxy host for `api.jasonfagerberg.duckdns.org` configured (step 3)

---

## 1. Add env vars to root `.env`

```bash
# API Gateway (Traefik)
TRAEFIK_DASHBOARD_CREDENTIALS=admin:$$apr1$$...   # see below
AUTHENTIK_SECRET_KEY=                             # openssl rand -hex 32
AUTHENTIK_ERROR_REPORTING__ENABLED=false
AUTHENTIK_DB_NAME=authentik
AUTHENTIK_DB_USER=authentik
AUTHENTIK_DB_PASSWORD=                            # openssl rand -hex 24

# Email (optional — for Authentik password resets; leave blank to disable)
AUTHENTIK_EMAIL__HOST=
AUTHENTIK_EMAIL__PORT=587
AUTHENTIK_EMAIL__USERNAME=
AUTHENTIK_EMAIL__PASSWORD=
AUTHENTIK_EMAIL__FROM=
```

Generate the Traefik dashboard htpasswd credential:

```bash
echo $(htpasswd -nb admin yourpassword) | sed -e 's/\$/\$\$/g'
```

Paste the result as `TRAEFIK_DASHBOARD_CREDENTIALS`.

---

## 2. Start Traefik and Swagger UI

```bash
docker compose -f api/docker-compose.yml up -d traefik swagger-ui
```

Verify:
- `http://192.168.50.186:8091/dashboard/` → Traefik dashboard visible
- No routes yet (no services registered)

---

## 3. Add NPM proxy hosts

In Nginx Proxy Manager (`http://192.168.50.186:81`), add the following proxy hosts:

| Domain | Scheme | Forward Hostname | Port | WebSockets | SSL Certificate | Force SSL |
|--------|--------|-----------------|------|------------|-----------------|-----------|
| `api.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8090` | on | `*.jasonfagerberg.duckdns.org` | on |
| `auth.jasonfagerberg.duckdns.org` | `http` | `192.168.50.186` | `8090` | on | `*.jasonfagerberg.duckdns.org` | on |

### Streaming / SSE settings

NPM defaults (`proxy_read_timeout 60s`, `proxy_buffering on`) break long-lived
SSE streams: tokens get buffered, and any silence longer than 60s drops the
connection (504 on first request while a model loads, `NS_ERROR_NET_PARTIAL_TRANSFER`
mid-stream when the agent is between tool calls).

For each proxy host that fronts a streaming service, edit it → **Advanced**
tab → paste:

```nginx
proxy_read_timeout 600s;
proxy_send_timeout 600s;
proxy_buffering off;
```

Keep it to these three directives. NPM's validator silently rejects the
proxy host config if you also include `proxy_http_version`, `proxy_cache`,
or `chunked_transfer_encoding` in the Advanced block — which causes the
host to disappear from `/data/nginx/proxy_host/`, so requests fall through
to NPM's default server and clients see `SSL_ERROR_UNRECOGNIZED_NAME_ALERT`.
Those three directives are all NPM defaults already, so dropping them
loses nothing.

Save — NPM regenerates the config and reloads automatically. Verify with:

```bash
docker exec nginx-proxy-manager sh -c 'grep -E "timeout|buffering" /data/nginx/proxy_host/*.conf'
```

Traefik's defaults are streaming-friendly (no response-header timeout, no
buffering), so no Traefik-side tweaks are needed.

---

## 4. Start Authentik

Fix permissions on the data directories (created by root, Authentik runs as UID 1000):

```bash
sudo chown -R 1000:1000 api/data/
```

```bash
docker compose -f api/docker-compose.yml up -d authentik-postgres authentik-redis
# Wait for healthy (30–60s)
docker compose -f api/docker-compose.yml up -d authentik-server authentik-worker
```

---

## 5. Initial Authentik setup

Visit `https://auth.jasonfagerberg.duckdns.org/if/flow/initial-setup/` and set the admin password.

### Create the Proxy Provider

1. **Admin Interface → Providers → Create → Proxy Provider**
   - Name: `api-gateway`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Mode: **Forward auth (single application)**
   - External host: `https://api.jasonfagerberg.duckdns.org`

### Create the Application

2. **Applications → Create**
   - Name: `API Gateway`
   - Slug: `api-gateway`
   - Provider: `api-gateway`

### Configure the Outpost

3. **Outposts → Create**
   - Type: Proxy
   - Applications: `API Gateway`

   The embedded outpost activates inside `authentik-server` — no separate container needed.

---

## 6. Verify end-to-end

1. Visit `https://api.jasonfagerberg.duckdns.org/docs` → Swagger UI (public, no login)
2. Visit `https://api.jasonfagerberg.duckdns.org/api/v1/documents` → redirected to Authentik login
3. Log in → request proceeds, service receives `X-authentik-username` header

---

## Adding a New Service

1. Add the `api_gateway` external network to the service's `docker-compose.yml`:

```yaml
networks:
  default:
  api_gateway:
    external: true
    name: api_gateway
```

2. Add Traefik labels to the service container:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.services.<name>.loadbalancer.server.port=<port>"

  # Protected route
  - "traefik.http.routers.<name>.rule=Host(`api.jasonfagerberg.duckdns.org`) && PathPrefix(`/api/v1/<resource>`)"
  - "traefik.http.routers.<name>.entrypoints=api"
  - "traefik.http.routers.<name>.service=<name>"
  - "traefik.http.routers.<name>.middlewares=authentik@file"

  # Public: OpenAPI spec
  - "traefik.http.routers.<name>-spec.rule=Host(`api.jasonfagerberg.duckdns.org`) && Path(`/api/v1/<resource>/openapi.json`)"
  - "traefik.http.routers.<name>-spec.entrypoints=api"
  - "traefik.http.routers.<name>-spec.service=<name>"
```

3. Restart the service: `docker compose up -d <service>`

4. Add its OpenAPI spec to Swagger UI — update `URLS` in `api/docker-compose.yml`:

```yaml
URLS: '[{"url": "https://api.jasonfagerberg.duckdns.org/api/v1/<resource>/openapi.json", "name": "<Name>"}]'
```

Then: `docker compose -f api/docker-compose.yml up -d swagger-ui`

---

## SearXNG (internal search backend)

Keyless metasearch backend that other services query over the internal network.
No Traefik route, no NPM host — it is never exposed publicly. Config lives in
`api/searxng/settings.yml` (JSON output enabled, limiter disabled).

### 1. Add the secret to root `.env`

```bash
# SearXNG internal search backend (api/searxng)
export SEARXNG_SECRET=    # openssl rand -hex 32
```

SearXNG overrides `server.secret_key` from this env var at load time, so the
committed `settings.yml` keeps only a placeholder — the real secret never
enters git.

### 2. Start it

```bash
docker compose -f api/docker-compose.yml up -d searxng
```

### 3. Verify

```bash
# Healthcheck convention (also wired into the container healthcheck):
docker exec searxng wget -qO- http://localhost:8080/healthz          # -> OK

# JSON API, from any container on the api_gateway network:
docker run --rm --network api_gateway curlimages/curl:latest \
  -s 'http://searxng:8080/search?q=dublin&format=json' | head -c 400
```

Both should return data (the second a JSON object with a `results` array).

### Consumer wiring

Point the consumer (Quack's `web_search`) at the internal URL — no auth, no key:

```
http://searxng:8080/search          # ?q=<query>&format=json
```

### Caveats for automated querying

- **JSON is opt-in.** `?format=json` returns HTTP 403 unless `json` is in
  `search.formats` (it is, in `settings.yml`). Removing it re-blocks the API.
- **Limiter is off.** Required for server-to-server use — with it on, SearXNG's
  bot detection rate-limits/403s non-browser clients. It stays off *because*
  the instance is internal-only; do not add a public route without
  reconsidering this (turning the limiter back on then needs a valkey/redis
  sidecar via `valkey.url`).
- **No SearXNG API key exists.** SearXNG has no native key/token auth on
  `/search`; access control here is purely the network boundary. If the
  consumer must present a credential, terminate it at a proxy in front of
  SearXNG — don't expect SearXNG to check one.
- **Upstream engines self-throttle.** Individual engines (Google, etc.) may
  CAPTCHA or 429 under heavy automated load; SearXNG suspends a failing engine
  briefly (`suspended_times`) and answers from the rest. For steady high volume,
  prune `settings.yml` to a few resilient engines (e.g. duckduckgo, brave,
  wikipedia, startpage).

---

## Browserless (internal headless-Chromium render backend)

Headless Chromium that renders a URL server-side and returns the resulting HTML,
for pages a plain GET can't read (SPAs / client-rendered content). Keyless and
internal-only — no Traefik route, no NPM host. No config file or secret: it is
entirely env-driven (see the `browserless` service in `docker-compose.yml`).

### 1. Start it

```bash
docker compose -f api/docker-compose.yml up -d browserless
```

Keyless by default — `TOKEN` is unset, so every request is authorized
(`src/token.ts`: `token === null` → allowed). **Optional:** set `BROWSERLESS_TOKEN`
in root `.env` to require a token; callers then pass `?token=<value>` (e.g.
`POST http://browserless:3000/content?token=...`). An empty value stays keyless.
A token gates *who can drive a browser* but does **not** limit *which URLs are
fetched* — SSRF guarding (below) is still required either way.

### 2. Verify

```bash
# Liveness (also the container healthcheck): returns HTTP 204, empty body.
docker exec browserless wget -qO- http://localhost:3000/active; echo "exit=$?"

# Render a page to HTML, from any container on api_gateway:
docker run --rm --network api_gateway curlimages/curl:latest \
  -sX POST 'http://browserless:3000/content' \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com"}' | head -c 200
```

The second should return the rendered `<html>…</html>` for example.com.

### Consumer wiring

Quack's `fetch` tool, for URLs that need JS rendering — no auth, no key:

```
POST http://browserless:3000/content
Content-Type: application/json
{"url": "<url>"}            # -> rendered HTML
```

Tier it: try a plain HTTP GET + readability first, and only fall back to
browserless when that returns an empty/JS shell — rendering is far heavier.
Other useful endpoints: `/scrape` (structured elements), `/pdf`, `/screenshot`.

### Caveats

- **SSRF — the important one.** Browserless fetches whatever URL it's handed,
  server-side, and it sits on the `api_gateway`/`default` networks, so a
  malicious or redirected URL can reach internal services
  (`http://opensearch:9200`, `http://searxng:8080`, `shared-postgres`, the cloud
  metadata IP `169.254.169.254`, etc.). **The caller must allowlist/deny before
  calling**: reject non-`http(s)` schemes, and resolve+block private/link-local
  ranges (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `::1`,
  `fc00::/7`). Validate *after* DNS resolution and on each redirect hop. This
  belongs in Quack's `fetch` tool — browserless has no built-in SSRF filter.
- **Keyless is only safe because it's internal.** With no `TOKEN`, anyone who can
  reach `:3000` can drive a browser. Setting `BROWSERLESS_TOKEN` closes that off
  (defense-in-depth even internally). Never give it a Traefik route / NPM host
  without a token set.
- **Resource use.** Each render spawns a Chromium tab. `CONCURRENT` caps parallel
  sessions, `QUEUED` caps the backlog, `TIMEOUT` (ms) bounds a single render.
  `shm_size: 2gb` is required — Chromium crashes on Docker's default 64MB
  `/dev/shm`. Tune `CONCURRENT` to the host's memory.
- **Image is `:latest`.** Pin to a version tag if you want reproducible updates
  (matches the deliberate-update note for Authentik above).

---

## Moving a Route to a Different Service

1. Remove the Traefik labels from the old service's `docker-compose.yml`
2. Add them to the new service
3. `docker compose up -d` both services

The public URL (`/api/v1/<resource>`) does not change.
