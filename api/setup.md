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
proxy_http_version 1.1;
proxy_buffering off;
proxy_cache off;
proxy_read_timeout 600s;
proxy_send_timeout 600s;
chunked_transfer_encoding on;
```

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

## Moving a Route to a Different Service

1. Remove the Traefik labels from the old service's `docker-compose.yml`
2. Add them to the new service
3. `docker compose up -d` both services

The public URL (`/api/v1/<resource>`) does not change.
