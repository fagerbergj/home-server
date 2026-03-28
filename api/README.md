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
| Traefik dashboard | `http://192.168.50.186:8091/dashboard/` (LAN only) |
| Authentik admin | `http://192.168.50.186:9000` (LAN only) |

## Auth

All routes under `/api/v1/` require authentication via Authentik. Browsers are redirected to the Authentik login page. After login, identity headers (`X-authentik-username`, `X-authentik-groups`, etc.) are forwarded to the backend service — services do not implement auth themselves.

Public routes (e.g., `/api/v1/<service>/openapi.json`) omit the `authentik@file` middleware in their router labels.

## Registered Services

| Path prefix | Service | Container |
|-------------|---------|-----------|
| `/api/v1/documents` | document-pipeline | `document-pipeline` |
| `/docs` | Swagger UI | `swagger-ui` |

## Adding a New Service

See [setup.md](setup.md#adding-a-new-service).

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
