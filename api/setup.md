# API Gateway — Setup

## Prerequisites

- `api` stack started first (creates the `api_gateway` Docker network)
- NPM proxy host for `api.jasonfagerberg.duckdns.org` configured (step 3)

---

## 1. Add env vars to root `.env`

```bash
# API Gateway (Traefik)
TRAEFIK_DASHBOARD_CREDENTIALS=admin:$$apr1$$...   # see below
AUTHENTIK_SECRET_KEY=                             # openssl rand -base64 36
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

## 3. Add NPM proxy host

In Nginx Proxy Manager (`http://192.168.50.186:81`), add a new proxy host:

| Field | Value |
|-------|-------|
| Domain | `api.jasonfagerberg.duckdns.org` |
| Scheme | `http` |
| Forward Hostname | `192.168.50.186` |
| Forward Port | `8090` |
| WebSockets Support | on |
| SSL Certificate | `*.jasonfagerberg.duckdns.org` (existing wildcard) |
| Force SSL | on |

---

## 4. Start Authentik

```bash
docker compose -f api/docker-compose.yml up -d authentik-postgres authentik-redis
# Wait for healthy (30–60s)
docker compose -f api/docker-compose.yml up -d authentik-server authentik-worker
```

---

## 5. Initial Authentik setup

Temporarily expose port 9000 — edit `api/docker-compose.yml` and uncomment the `ports` block on `authentik-server`, then:

```bash
docker compose -f api/docker-compose.yml up -d authentik-server
```

Visit `http://192.168.50.186:9000/if/flow/initial-setup/` and set the admin password.

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

### Remove the temporary port

Re-comment the `ports` block in `api/docker-compose.yml`, then:

```bash
docker compose -f api/docker-compose.yml up -d authentik-server
```

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
