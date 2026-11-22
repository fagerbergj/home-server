# Migration inventory

Three inventories for the OpenWrt move: hardware, how the servers connect,
and the ASUS settings that must be carried over. Full details of the servers
live in [`../../hardware.md`](../../hardware.md) and
[`../../jaison/README.md`](../../jaison/README.md); this file is the network view.

## 1. Hardware

| Device | Model | Role after cutover | Network | PoE |
|---|---|---|---|---|
| Router PC | custom-build x86-64, 2× NIC, OpenWrt installed (specs TBD) | Gateway, PPPoE, DHCP, firewall, port forwards | WAN: ISP line → `eth0`; LAN: → switch on `eth1` | — |
| Switch | TP-Link Omada **SG3218XP-M2** | Distribution: all wired devices | 12× 2.5G PoE+ (30 W), 4× 2.5G PoE++ (90 W), 2× 10G SFP+, 240 W budget | source |
| AP upstairs | TP-Link Omada **NWA50AX PRO** (Wi-Fi 6, ceiling) | Broadcast the cloned SSID + PSK, bridge into LAN | MAC `80:EA:0B:5D:E0:FA` — new, needs mounting + PoE run | powered by switch |
| AP downstairs | TP-Link **EAP772-Outdoor** (Wi-Fi 7 BE11000) | Broadcast the cloned SSID + PSK, bridge into LAN | MAC `A8:29:48:CF:D0:40` — already mounted + PoE-fed | powered by switch |
| jason-server | Threadripper 1950X box ([hardware.md](../../hardware.md)) | Services host; Headscale + AdGuard + NPM | Intel GbE wired → switch; reservation `192.168.50.186` | — |
| jaison | Threadripper 7960X box ([jaison/README.md](../../jaison/README.md)) | AI box | wired → switch (new run); NICs present: `lan10g` `b0:82:e2:31:7b:13` (10G) + `lan2g5` `b0:82:e2:31:7b:14` (2.5G), both currently unplugged; reservation `192.168.50.202` moves to the wired MAC in use | — |
| RT-AX58U | ASUS (current router) | Retired — shelf spare | — | — |

Notes:

- The EAP772's sticker still lists default SSIDs `TP-Link_{2.4,5,6}GHz_CFD04x` —
  confirm what it actually broadcasts today from the step-0 dump before
  reconfiguring it.
- Both APs are PoE: one cable each into any PoE port does data + power.
- The switch is managed (Omada); factory defaults are a flat L2 bridge, which
  is all the clone needs. Controller adoption can happen after the move.
- jaison gets wired: reserve `b0:82:e2:31:7b:14` (`lan2g5`) — or `b0:82:e2:31:7b:13`
  (`lan10g`) if you'd rather use that port; either negotiates 2.5G into the
  switch's RJ45. Same `.202`, so the AdGuard rewrite and every
  `192.168.50.202` config keep working untouched. Verify which NIC actually
  gets cabled before filling `.env`.

## 2. Server connectivity to OpenWrt

| Server | Path to WAN | IP source | What must be true on cutover day |
|---|---|---|---|
| jason-server | OpenWrt `eth1` → switch → its onboard GbE | DHCP reservation `.186` (MAC from dump) | OpenWrt up; it needs no renew to keep working — same subnet, same gateway |
| jaison | OpenWrt `eth1` → switch → its NIC (new run) | DHCP reservation `.202` (wired MAC) | new cable terminated + reservation uses the wired MAC |
| Headscale bootstrap | runs in Docker on jason-server; clients reach `headscale.jasonfagerberg.duckdns.org` over WAN + AdGuard DNS | — | WAN dials PPPoE and DNS resolves; then tailnet heals itself, no router involvement |

## 3. ASUS settings to carry over

Source of truth: `dumps/nvram-20261122-171043.txt` (RT-AX58U, firmware
3.0.0.4.388_25278, dumped 2026-11-22). Secrets — Wi-Fi PSK, PPPoE — live
only in `dumps/`, never in tracked files.

| Setting | Actual value | Where it lands on OpenWrt |
|---|---|---|
| SSID 2.4 GHz | `69 Carmel 2GHz` | APs (both must broadcast both SSIDs) |
| SSID 5 GHz | `69 Carmel 5GHz` | APs |
| Security 2.4 | WPA2-PSK, AES, PMF off | AP — match exactly or clients won't join |
| Security 5 | WPA2/WPA3-Personal mixed (psk2sae), AES, PMF capable, 160 MHz | AP |
| Wi-Fi PSK | single PSK for both bands — in dump (`wl*_wpa_psk`) | APs |
| Guest / IoT networks | none | n/a |
| LAN IP / mask | `192.168.50.1` / 255.255.255.0 | `network.lan` static |
| DHCP pool | `.2` – `.254`, lease 24 h | `dhcp.lan.start=2 limit=252 leasetime=24h` |
| DHCP reservations | `a8:5e:45:a7:e5:fc`→`.186` (jason-server); `9c:c7:d3:d0:20:6a`→`.202` (jaison Wi-Fi) | OpenWrt hosts — jaison's gets swapped to wired `b0:82:e2:31:7b:14` |
| DNS to clients | `192.168.50.186` only | `dhcp.lan.dhcp_option` |
| WAN protocol | **DHCP (`wan_proto=dhcp` on `eth4`)** — not PPPoE, see §4 | `network.wan.proto` (`.env` `WAN_TYPE`) |
| Port forwards (Virtual Server) | **none configured** — see §4 | explicit redirects added anyway |
| UPnP | **on** — this is how 80/443/25565 are currently open; verified listening on the WAN IP | disabled day one; explicit DNAT replaces it |
| DDNS | ASUS DDNS → `jasonfagerberg.asuscomm.com` | dies with the router, nobody uses it — DuckDNS container is authoritative |
| VPN servers | none (`vpnc_*`/`openvpn` empty) | n/a |
| Static routes | none | n/a |
| IPv6 | router had a WAN v6 address (Verizon); LAN v6 unused | off day one, revisit later |
| Timezone | `EST5DST` | `.env` `TIMEZONE=America/New_York` |

## 4. Findings that change the plan

1. **The internet is DHCP, not PPPoE.** `wan_proto=dhcp`, no PPPoE
   credentials anywhere in nvram. WAN IP `73.123.8.244` is Verizon public
   space; any PPPoE session rides on the ISP ONT. **Decided 2026-11-22:
   keep DHCP on the OpenWrt box** (`WAN_TYPE=dhcp`); revisit PPPoE only if
   the ONT is ever bridged.
2. **There are no Virtual Server rules.** Public 80/443/25565 are open via
   **UPnP** (confirmed listening from WAN; 3000 is closed — the Games
   forward in `networking/setup.md` was never/wrongly added). UPnP on stock
   Docker hosts is fragile; the clone writes explicit DNAT rules for
   80/443/25565 and skips UPnP.
3. Two SSIDs (`2GHz`/`5GHz` variants), not one — the APs must broadcast
   both names or half the devices won't auto-connect.
