# Minecraft — Setup

## 1. Start the server

```bash
docker compose up -d
```

Check logs to confirm it's ready:
```bash
docker compose logs -f minecraft
```

You'll see `Done! For help, type "help"` when it's accepting connections.

## 2. Add mods

Download the **NeoForge 1.21.1** version of each mod from CurseForge and place the jars in `./mods/`:

| Mod | CurseForge Page |
|-----|----------------|
| Ars Nouveau | https://www.curseforge.com/minecraft/mc-mods/ars-nouveau |
| Curios API *(required by Ars Nouveau)* | https://www.curseforge.com/minecraft/mc-mods/curios/download/7642217 |
| GeckoLib | https://www.curseforge.com/minecraft/mc-mods/geckolib |
| Patchouli | https://www.curseforge.com/minecraft/mc-mods/patchouli |

Then restart:
```bash
docker compose restart minecraft
```

## 3. Client setup (for friends)

Everyone needs the same mods installed on their client:

1. Install the [CurseForge launcher](https://www.curseforge.com/download/app)
2. Create a new profile: **NeoForge 1.21.1**
3. Add the same four mods to the profile
4. Launch from that profile and connect to the server

Anyone without the mods will be kicked on join.

## Verify

1. Launch Minecraft with the NeoForge 1.21.1 profile in CurseForge
2. Add a server with `192.168.50.186:25565` and connect — you should spawn in a world with Ars Nouveau available
3. Run `/mods` in chat to confirm all four mods are loaded
