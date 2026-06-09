# Games Server

Next.js games launcher service running at [games.jasonfagerberg.duckdns.org](https://games.jasonfagerberg.duckdns.org).

Currently hosts **Kings Corner** - a browser-based card game.

## Deploy

1. Clone this repository to your server
2. Run Docker Compose:
   ```bash
   docker compose up -d
   ```

The service will start on port 80 and be available at your DDNS address.

## Update

To update to the latest version:

```bash
docker compose pull
docker compose up -d
```

## Development

This project is a Next.js application. See the main [games repo](https://github.com/your-username/games) for development details.
