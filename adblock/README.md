# AdGuard Home

Network-wide DNS ad blocker. Blocks ads and trackers at the DNS level for all devices on the network — no client-side setup required.

Admin UI at: `http://192.168.50.186:3003` (internal only)

## Notes

- DNS runs on port 53. The router's DHCP and WAN DNS both point only at `192.168.50.186`, and Headscale makes it the tailnet's resolver, so every device on either network is filtered.
- Blocklist: HaGeZi's Pro. 1Hosts (Xtra) broke legitimate sites.
- Blocklists and query logs managed via the web UI
