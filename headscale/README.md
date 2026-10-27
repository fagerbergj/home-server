# Headscale

[Headscale](https://github.com/juanfont/headscale), an open-source Tailscale control server. It runs the tailnet: every device uses the open-source Tailscale client logged in here instead of Tailscale's hosted service. Setup and enrollment steps live in [networking/setup.md](../networking/setup.md), Phase 7.

## Access

- Control URL (what clients log in to): `https://headscale.jasonfagerberg.duckdns.org`, a public NPM proxy host to `http://headscale:8080` with **Websockets Support** on (the Tailscale control protocol upgrades over it). Clients have to reach it from anywhere, so it is public; it only speaks the control protocol, and adding a node needs an admin command or a pre-auth key.
- Admin: `docker exec headscale headscale <cmd>` on the media box.
- MagicDNS names: `<host>.hs.internal`; short names resolve too.

## Nodes

| Node | IP | Notes |
|---|---|---|
| jaison | 100.64.0.1 | Collie behind Caddy on this IP |
| jason-server | 100.64.0.6 | advertises `192.168.50.0/24`; tailnet-only services bind this IP |

## Config notes

- DNS: AdGuard on the media box (`100.64.0.6`) is the global nameserver; `extra_records` maps `collie.jasonfagerberg.duckdns.org` to jaison.
- No policy file: every enrolled node reaches every other node. Add one before enrolling a device that isn't mine.
- Relays are Tailscale's public DERP servers; they see only encrypted packets. The embedded DERP (`derp.server.enabled`) removes that dependency but needs UDP 3478 forwarded.
- Headscale issues no HTTPS certificates, so `tailscale serve` HTTPS is unavailable; services that need TLS bring their own (Collie uses Caddy with a DuckDNS DNS-01 cert).
