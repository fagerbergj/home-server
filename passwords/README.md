# Vaultwarden

Self-hosted Bitwarden-compatible password manager. Uses the official Bitwarden apps/extensions pointed at your own server.

Accessible at: https://passwords.jasonfagerberg.duckdns.org

## Notes

- `SIGNUPS_ALLOWED=false` — set after creating your account to prevent others from registering
- Data stored in `./data/` (SQLite by default)
- **Back up `./data/` regularly** — this is your entire vault

## Backup

The vault database is at `./data/db.sqlite3`. Include this in any backup routine.
