# Minecraft Server

Runs [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) with **NeoForge 1.21.1** and mods.

## Connect

Local:
```
<server-ip>:25565
```

External (via DDNS):
```
jasonfagerberg.asuscomm.com:25565
```

## Mods

Mod jars go in `./mods/`. The server loads them on startup.

| Mod | CurseForge Page | Notes |
|-----|----------------|-------|
| Ars Nouveau | https://www.curseforge.com/minecraft/mc-mods/ars-nouveau | Main mod |
| GeckoLib | https://www.curseforge.com/minecraft/mc-mods/geckolib | Required dependency |
| Patchouli | https://www.curseforge.com/minecraft/mc-mods/patchouli | Required dependency |

After adding or removing mods, restart the server:
```bash
docker compose restart minecraft
```

## Configuration

Key settings in `docker-compose.yml`:

| Variable | Value | Notes |
|----------|-------|-------|
| `VERSION` | `1.21.1` | Must match clients exactly |
| `TYPE` | `NEOFORGE` | Mod loader |
| `MEMORY` | `4G` | JVM heap size — adjust based on available RAM |
| `MAX_PLAYERS` | `10` | |
| `ENABLE_AUTOPAUSE` | `TRUE` | Pauses server when empty, saves CPU/RAM |

Full list of options: https://docker-minecraft-server.readthedocs.io

With 16GB total RAM shared across OS + Plex + Immich, 4G is a reasonable default. If you add more mods and see lag, bump to `6G`.

## Console Access

```bash
docker attach minecraft
```

Detach without stopping: `Ctrl+P` then `Ctrl+Q`

## Logs

```bash
docker compose logs -f minecraft
```

You'll see `Done! For help, type "help"` when it's ready to accept connections.

## Updating

Always back up the world before updating NeoForge or mods:

```bash
tar -czf world-backup-$(date +%F).tar.gz ./data/world
```

Then pull and restart:
```bash
docker compose pull
docker compose up -d
```
