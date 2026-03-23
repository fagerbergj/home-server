# Vaultwarden — Setup

## 1. Start the container

```bash
cd ~/workspace/home-server/passwords
docker compose up -d
```

## 2. Configure NPM proxy host

In Nginx Proxy Manager, create a new proxy host:

- **Domain**: `passwords.jasonfagerberg.duckdns.org`
- **Scheme**: `http`
- **Forward Hostname**: `<server-ip>`
- **Forward Port**: `8888`
- **SSL**: Let's Encrypt, force SSL
- **WebSockets**: on

## 3. Create your account

Go to `https://passwords.jasonfagerberg.duckdns.org` and register your account.

## 4. Disable signups

Once your account is created, set `SIGNUPS_ALLOWED=false` in the compose file (already set) and restart:

```bash
docker compose restart vaultwarden
```

## 5. Import from Bitwarden

1. Export from bitwarden.com → **Tools** → **Export Vault** → JSON format
2. In your Vaultwarden instance → **Tools** → **Import Data** → select **Bitwarden (json)**
3. Re-add TOTP seeds and file attachments manually (not included in export)

## 6. Point Bitwarden clients at your server

In the Bitwarden app/extension:
- Click the region selector (the globe icon or "Log in" screen)
- Select **Self-hosted**
- Enter: `https://passwords.jasonfagerberg.duckdns.org`
- Log in with your Vaultwarden account
