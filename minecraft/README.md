# Minecraft Server

Uses the [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) image.

## Start

```bash
docker compose up -d
```

The server will download the latest Minecraft version on first run. Check logs to see when it's ready:
```bash
docker compose logs -f minecraft
```

You'll see `Done! For help, type "help"` when it's ready to accept connections.

## Connect

From Minecraft, add a server with your server's local IP and default port:
```
<server-ip>:25565
```

## Configuration

Key settings in `docker-compose.yml`:

| Variable | Default | Notes |
|----------|---------|-------|
| `VERSION` | `LATEST` | Pin to a specific version e.g. `1.21.1` |
| `TYPE` | `VANILLA` | Change to `PAPER` for better performance with plugins |
| `MEMORY` | `4G` | JVM heap size — adjust based on available RAM |
| `MAX_PLAYERS` | `10` | |
| `ENABLE_AUTOPAUSE` | `TRUE` | Pauses server when empty, saves CPU/RAM |

Full list of options: https://docker-minecraft-server.readthedocs.io

## Switching to Paper (recommended for performance)

Paper is a drop-in Vanilla replacement with significantly better performance. Change in `docker-compose.yml`:
```yaml
- TYPE=PAPER
```

## Memory Tuning

With 16GB total RAM shared across OS + Plex + Immich, 4G is a reasonable default. If Plex is idle and you want a bigger world, you can bump to `6G`. If all services are running hot, drop to `2G`.

## Console Access

```bash
docker attach minecraft
```

Detach without stopping: `Ctrl+P` then `Ctrl+Q`

## Updating

```bash
docker compose pull
docker compose up -d
```

## Backups

World data is in `./data/world`. Back this up before updating.
```bash
tar -czf world-backup-$(date +%F).tar.gz ./data/world
```
