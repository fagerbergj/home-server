# Minecraft Server

Uses the [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) image.
Running **NeoForge 1.21.1** with mods.

## Mods

Mod jars go in `./mods/`. The server loads them on startup.

Required mods — download the **NeoForge 1.21.1** version of each from CurseForge:

| Mod | CurseForge Page | Notes |
|-----|----------------|-------|
| Ars Nouveau | https://www.curseforge.com/minecraft/mc-mods/ars-nouveau | Main mod |
| GeckoLib | https://www.curseforge.com/minecraft/mc-mods/geckolib | Required dependency |
| Patchouli | https://www.curseforge.com/minecraft/mc-mods/patchouli | Required dependency |

After adding or removing mods, restart the server:
```bash
docker compose restart minecraft
```

## Client Setup (for friends)

Everyone needs the same mods installed on their client:

1. Install the [CurseForge launcher](https://www.curseforge.com/download/app)
2. Create a new profile: **NeoForge 1.21.1**
3. Add the same three mods above to the profile
4. Launch from that profile and connect to the server

Anyone without the mods will be kicked on join.

## Start

```bash
docker compose up -d
```

Check logs to see when it's ready:
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

| Variable | Value | Notes |
|----------|-------|-------|
| `VERSION` | `1.21.1` | Must match clients exactly |
| `TYPE` | `NEOFORGE` | Mod loader |
| `MEMORY` | `4G` | JVM heap size — adjust based on available RAM |
| `MAX_PLAYERS` | `10` | |
| `ENABLE_AUTOPAUSE` | `TRUE` | Pauses server when empty, saves CPU/RAM |

Full list of options: https://docker-minecraft-server.readthedocs.io

## Memory Tuning

With 16GB total RAM shared across OS + Plex + Immich, 4G is a reasonable default. Modded servers use more memory than vanilla — if you add more mods and see lag, bump to `6G`.

## Console Access

```bash
docker attach minecraft
```

Detach without stopping: `Ctrl+P` then `Ctrl+Q`

## Updating

When updating NeoForge or mods, back up the world first:
```bash
tar -czf world-backup-$(date +%F).tar.gz ./data/world
```

Then pull and restart:
```bash
docker compose pull
docker compose up -d
```
