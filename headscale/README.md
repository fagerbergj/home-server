# Headscale

[Headscale](https://github.com/juanfont/headscale), an open-source Tailscale control server, on trial
beside Tailscale. If Collie works over it, Tailscale gets decommissioned.

## Access

- Control URL (what clients log in to): `https://headscale.jasonfagerberg.duckdns.org`, a public NPM
  proxy host to `http://headscale:8080` with **Websockets Support** on (the Tailscale control protocol
  upgrades over it). Clients have to reach it from anywhere, so it is public; it only speaks the control
  protocol, and node registration needs an admin command.
- Admin: `docker exec headscale headscale <cmd>` on the media box.
- MagicDNS names: `<host>.hs.internal`.

## Enrolling a device

```bash
docker exec headscale headscale users create jason        # once
```

- **Phone (Tailscale app):** Settings → Accounts → Add account → ⋯ → Use custom coordination server,
  enter the control URL. The app shows a page with a `headscale nodes register` command; run it here
  with `--user jason`. Switching back to the Tailscale account in the app is the rollback.
- **jaison:** the `headscale-client` service in `jaison/docker-compose.yml`, a second client in userspace
  mode so the host's tailscaled keeps running. Its log prints the registration URL.

## Trial limits

- No policy file: every enrolled node reaches every other node.
- DNS goes to 1.1.1.1, not AdGuard, while a device is on Headscale.
- Relays are Tailscale's public DERP servers; they see only encrypted packets. The embedded DERP
  (`derp.server.enabled`) removes that dependency but needs UDP 3478 forwarded.
- Headscale issues no HTTPS certificates, so `tailscale serve` HTTPS is unavailable.
