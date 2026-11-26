# Vaultwarden

Self-hosted Bitwarden-compatible password manager. Uses the official Bitwarden apps/extensions pointed at your own server.

Accessible at: https://passwords.jasonfagerberg.duckdns.org

## Notes

- **Signups:** set `SIGNUPS_ALLOWED=false` after creating your account to prevent others from registering.
- **Storage:** data lives in `./data/` (SQLite by default).
- **Backups:** **copy `./data/` off-box regularly — it holds your entire vault.**

## Backup

The vault database is at `./data/db.sqlite3`. Include this in any backup routine.
