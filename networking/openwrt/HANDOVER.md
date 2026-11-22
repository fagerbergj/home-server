# OpenWrt migration — session handover (2026-11-22)

For the next session continuing this work. Full runbook: [`README.md`](README.md);
inventories + decisions: [`inventory.md`](inventory.md). Nothing here takes
the live network down; the old ASUS network is running until cutover.

## Where things stand

- Step 0 (config dump) **done**: `dumps/nvram-20261122-171043.txt` (complete,
  2533 vars). Untracked like `.env` — they hold the Wi-Fi PSK; never commit.
- `.env` filled from the dump — **except** `OPENWRT_ROOT_PASS` (still
  `change-me`) and `WAN_IF`/`LAN_IF` (guesses until the bench session).
- Scripts pass `sh -n` / `bash -n`; never executed against real hardware yet.
- Physical work in flight: upstairs AP mount + PoE run, jaison wire, ISP
  landing at the router-PC spot.

## Working with the ASUS (until cutover)

- SSH: `jf_fagerberg@192.168.50.1` port **56765**. Interactive-only shell
  (Broadcom debug shell): it rejects `sh -c`, so remote commands **and**
  `ssh-copy-id` key installs silently fail. Password entry only.
- Re-dump config: `./scripts/asus-dump.sh` → enter password → at the router
  prompt type `nvram show`, wait for it to stop, `exit`.
- `nvram show` ending in `size: 78160 bytes (52912 left)` is the normal
  partition footer, not a truncation.
- Never edit a shell script while it is running — bash parses the file
  lazily and the run corrupts (this happened once).

## Decisions (don't relitigate without new facts)

- WAN stays **DHCP** — the dump proved the ASUS never ran PPPoE.
- APs broadcast both `69 Carmel 2GHz` (WPA2-PSK) and `69 Carmel 5GHz`
  (WPA2/WPA3-mixed, PMF capable); PSK is in the dump only.
- Everything hardwired through the Omada switch; jaison's reservation moves
  to wired `b0:82:e2:31:7b:14` (NIC `lan2g5`; `lan10g` = `...7b:13` spare).
- Public 80/443/25565 become explicit DNAT rules (the ASUS had no Virtual
  Server entries — those ports ride on UPnP today). No UPnP day one.
- LAN IPv6 off day one. ASUS DDNS (`asuscomm.com`) is abandoned; DuckDNS
  container is authoritative.

## Bench session — next action, was blocked here

Blocked on: jaison's `lan10g`/`lan2g5` are admin-down (needs sudo) and
`OPENWRT_ROOT_PASS` is unset.

1. Set `OPENWRT_ROOT_PASS` in `.env` (keep it 0600).
2. Jumper cable: router PC ↔ jaison. On jaison: `sudo ip link set lan2g5 up`
   (or `lan10g`) — the linked one is confirmed via
   `cat /sys/class/net/<if>/carrier`.
3. `sudo ip addr add 192.168.1.100/24 dev <if>` → reach the OpenWrt default
   `192.168.1.1` → copy `networking/openwrt/` to the router (scp or USB) →
   `sh scripts/openwrt-clone.sh`. It fail-closes if
   `network.device[0]` isn't `br-lan` — inspect `/etc/config/network` by
   hand if so.
4. Identify the router's physical WAN vs LAN port: unplug/replug the jumper
   and watch which router interface flaps (`ip -o link`). Set `WAN_IF` /
   `LAN_IF` in `.env` to match reality, re-run clone (idempotent).
5. Flip jaison's static to `192.168.50.50/24` and verify: lease from
   `.2–.254`, `ssh root@192.168.50.1`,
   `uci get dhcp.lan.dhcp_option` = `3,192.168.50.186`,
   `iptables -t nat -S PREROUTING | grep DNAT` shows 80/443/25565.
6. Remove the static, unplug the jumper. jaison's port goes back to its
   permanent switch run at cutover.

## Remaining before cutover

- Bench session above.
- Both APs: the two `69 Carmel` networks + PSK. Downstairs EAP772 tonight
  (~30 s of its clients bouncing to the ASUS — fine); upstairs NWA50AX PRO
  configured but **unpowered until cutover**.
- Label the jaison + ISP cables at both ends.
- Cutover + verify: README steps 4–6. Rollback = ISP line back into the ASUS.
