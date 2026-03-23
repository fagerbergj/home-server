# Monitoring

Runs a [Netdata](https://www.netdata.cloud/) container to expose real‑time system metrics.

## Quick Start

```bash
cd ~/workspace/home-server/monitoring
# Start the container in the background
# The compose file pulls the latest image on startup
# and mounts the config directories.
docker compose up -d
```

The container will be available on port **19999**. If you want to access it from outside your LAN, add an entry in Nginx Proxy Manager with the following table:

| Service | Domain | Port |
|---------|--------|------|
| Netdata | `monitoring.jasonfagerberg.duckdns.org` | `19999` |

You can then reach the UI at the URLs shown below.

## Access

- **Local**: `http://192.168.50.186:19999` (internal view)
- **Netdata Cloud**: `https://app.netdata.cloud/spaces/jf-fagerberg-space/rooms/all-nodes/overview`

If the container stops, restart it with:
```bash
docker compose restart netdata
```

## Configuration

The following volumes expose host data to the container:

```
./config:/etc/netdata
./lib:/var/lib/netdata
./cache:/var/cache/netdata
/etc/passwd:/host/etc/passwd:ro
/etc/group:/host/etc/group:ro
/etc/localtime:/host/etc/localtime:ro
/proc:/host/proc:ro
/sys:/host/sys:ro
/etc/os-release:/host/etc/os-release:ro
var/run/docker.sock:/var/run/docker.sock:ro
```

Place any custom Netdata configuration files under `./config` – the container will copy them on start.

## Updating

Pull the latest image and recreate the container:
```bash
docker compose pull
docker compose up -d
```

Ensure you keep the container running; Netdata stores its runtime data in `./lib` and `./cache`.

---

For any questions or troubleshooting, see the [Docker‑Compose](./docker-compose.yml) file and the Netdata documentation.