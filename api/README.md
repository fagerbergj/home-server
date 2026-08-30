# API Gateway

Traefik-based API gateway at `api.jasonfagerberg.duckdns.org`. Path-based routing to services, centralized auth via Authentik (OAuth2/OIDC), public OpenAPI docs via Swagger UI.

## Architecture

```
Internet
  └── :443 ──► NPM (wildcard cert) ──► api.jasonfagerberg.duckdns.org
                                              └── Traefik :8090
                                                    ├── /docs              → Swagger UI (public)
                                                    ├── /outpost.*         → Authentik embedded outpost
                                                    └── /api/v1/...        → registered services (auth required)
```

Services register their own routes via Docker labels on the `api_gateway` shared network. Moving an endpoint to a different service = relabel, no public URL changes.

## Access

| Interface | URL |
|-----------|-----|
| API base | `https://api.jasonfagerberg.duckdns.org` |
| OpenAPI docs | `https://api.jasonfagerberg.duckdns.org/docs` |
| Authentik | `https://auth.jasonfagerberg.duckdns.org` |
| Traefik dashboard | `http://jason-server:8091/dashboard/` (tailnet only) |
| Authentik admin (break-glass) | `http://jason-server:9000` (tailnet only) |

## Auth

All routes under `/api/v1/` require authentication via Authentik. Browsers are redirected to the Authentik login page. After login, identity headers (`X-authentik-username`, `X-authentik-groups`, etc.) are forwarded to the backend service — services do not implement auth themselves.

Public routes (e.g., `/api/v1/<service>/openapi.json`) omit the `authentik@file` middleware in their router labels.

## Registered Services

| Path prefix | Service | Container |
|-------------|---------|-----------|
| `/docs` | Swagger UI | `swagger-ui` |

## Internal Backends

Some services in this stack are **not** routed through the public gateway — they
have no Traefik labels and are reachable only by other containers on the
`api_gateway` / `default` networks, by container name. They carry no auth of
their own; isolation is the network boundary (no NPM proxy host, no Traefik
router points at them).

| Container | Internal address | Purpose |
|-----------|------------------|---------|
| `searxng` | `http://searxng:8080` | keyless metasearch — JSON web-search backend |
| `browserless` | `http://browserless:3000` | keyless headless Chromium — JS page render |

**SearXNG** serves `/search?q=...&format=json` to internal consumers (e.g. Quack's
`web_search` tool). It needs no API key, and callers need no auth. JSON output is
enabled and the bot-detection limiter is disabled in `searxng/settings.yml` so
server-to-server queries aren't rate-limited. Setup and caveats: [setup.md](setup.md#searxng-internal-search-backend).

**Browserless** renders pages a plain HTTP GET can't read (SPAs, JS-built content):
`POST /content` with `{"url": "..."}` returns the rendered HTML. SearXNG finds URLs,
browserless reads them. Keyless (no `TOKEN` set) and internal-only — but it fetches
arbitrary URLs server-side, so the caller must guard against SSRF. Setup and caveats:
[setup.md](setup.md#browserless-internal-headless-chromium-render-backend).

## Adding a New Service

See [setup.md](setup.md#adding-a-new-service).

## Adding a UI for a Service

UIs live alongside their API service in the same `docker-compose.yml` and route through the same Traefik instance. Each UI gets its own subdomain covered by the existing `*.jasonfagerberg.duckdns.org` wildcard cert.

### 1. Add an NPM proxy host

In Nginx Proxy Manager, add a new proxy host pointing to the same Traefik port:

| Field | Value |
|-------|-------|
| Domain | `<service>.jasonfagerberg.duckdns.org` |
| Scheme | `http` |
| Forward Hostname | `192.168.50.186` |
| Forward Port | `8090` |
| WebSockets Support | on |
| SSL Certificate | `*.jasonfagerberg.duckdns.org` (existing wildcard) |
| Force SSL | on |

### 2. Add Traefik labels to the UI container

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.services.<name>-ui.loadbalancer.server.port=<port>"
  - "traefik.http.routers.<name>-ui.rule=Host(`<service>.jasonfagerberg.duckdns.org`)"
  - "traefik.http.routers.<name>-ui.entrypoints=api"
  - "traefik.http.routers.<name>-ui.middlewares=authentik@file"
```

Join the `api_gateway` network (same as the API service).

### 3. Add a Proxy Provider in Authentik for the new subdomain

The existing `api-gateway` Proxy Provider only covers `api.jasonfagerberg.duckdns.org`. Each UI subdomain needs its own provider:

1. **Admin → Providers → Create → Proxy Provider**
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Mode: **Forward auth (single application)**
   - External host: `https://<service>.jasonfagerberg.duckdns.org`
2. **Applications → Create** — link to the new provider
3. **Outposts → authentik Embedded Outpost → Edit** — add the new application

Users share the same Authentik session across all subdomains; Authentik just needs a provider registered for each one.

## Future RBAC

When ready, resource+verb scopes (`documents:read`, `documents:write`, etc.) can be enforced by:
- **Option A** — Authentik Proxy Provider policy (path-pattern scope requirements)
- **Option B** — OPA as a second `forwardAuth` middleware in Traefik

Neither option requires changes to service code.

## Updating

```bash
docker compose -f api/docker-compose.yml pull
docker compose -f api/docker-compose.yml up -d
```

Authentik: pin to a specific minor version (`2024.12`) and update deliberately — DB schema changes between major versions.
