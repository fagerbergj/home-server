# Langfuse

Self-hosted [Langfuse](https://langfuse.com) v4 — LLM observability and eval
datasets built from quack's real production traces.

## Access

Tailnet-only, like Grafana: `http://jason-server:3008`

Credentials live in `.env`. The org, project, user, and API keys are
auto-provisioned on first boot from the `LANGFUSE_INIT_*` vars; those vars are
ignored on every later start, so changing them does nothing once the Postgres
volume exists.

## How traces get here

quack exports OTLP to `otel-collector` (unchanged), and the collector fans the
traces out to both Tempo and Langfuse — see `monitoring/otel-collector/config.yaml`.
The two are not redundant: Tempo backs Grafana for whole-system tracing, Langfuse
reads the GenAI semantic-convention attributes for prompt/cost/eval work.

`otel-collector` joins the `langfuse_default` network to reach `langfuse-web`
directly, and its `Authorization` header comes from `monitoring/.env` so the
project key stays out of git.

## Storage split

| Service | Location | Why |
|---|---|---|
| postgres, redis | `./data/` (root NVMe) | Small, and OLTP random writes are the worst case for the HDD array. |
| clickhouse, minio | `/mnt/media/databases/langfuse/` | Bulk trace storage; columnar/object access tolerates spinning disks. |

## Ports

`3008` (web) is the only externally-reachable one. ClickHouse's native port is
remapped to `9002` and MinIO's S3 port to `9091` because Authentik owns `9000`
and Prometheus owns `9090`.

## Updating

```bash
docker compose pull && docker compose up -d
```
