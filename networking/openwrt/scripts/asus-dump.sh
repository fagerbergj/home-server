#!/usr/bin/env bash
# Dump the ASUS RT-AX58U's nvram through an INTERACTIVE ssh session and print
# the settings that must be carried to OpenWrt.
#
# Interactive by necessity: this firmware's login shell is a Broadcom debug
# shell that rejects `sh -c`, so remote commands and authorized_keys writes
# fail silently — nothing works but typed keystrokes. SSH is enabled at
# Administration > System (this router: port 56765, user jf_fagerberg).
#
# Usage: ./asus-dump.sh
#   1. enter the router password when asked
#   2. at the router prompt type:  nvram show     (wait for it to stop)
#   3. then type:                  exit
#
# The capture contains secrets (Wi-Fi PSK, PPPoE password): files are written
# 0600 under dumps/, which is gitignored.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p dumps && chmod 700 dumps
raw="dumps/nvram-$(date +%Y%m%d-%H%M%S).raw"
out="${raw%.raw}.txt"

echo "SSH prompt coming — then at the router prompt: 'nvram show', wait, then 'exit'."
ssh -tt -p "${SSH_PORT:-56765}" "${SSH_USER:-jf_fagerberg}@${SSH_HOST:-192.168.50.1}" | tee "$raw" || true
chmod 600 "$raw"

# Interactive capture duplicates lines (tty echo); keep clean key=value lines.
tr -d '\r' < "$raw" | grep -E '^[A-Za-z0-9_]+=' | sort -u > "$out"
chmod 600 "$out"
echo "raw capture: $raw"
echo "cleaned dump: $out ($(wc -l < "$out") variables)"
[ "$(wc -l < "$out")" -gt 500 ] || echo "WARNING: under 500 vars — nvram show probably did not complete; re-run." >&2

rpt() {
  printf '\n=== %s ===\n' "$1"
  matches=$(grep -E "$2" "$out" | sort)
  [ -n "$matches" ] && echo "$matches" || echo '(none found — confirm in the router UI)'
}

rpt "Wi-Fi: SSIDs" '^(wl[01]?_(ssid|mssid)|wps_)'
rpt "Wi-Fi: PSK + security" '(wpa_psk|auth_mode|crypto|mfp)'
rpt "Wi-Fi: band / channel / width" '^(wl[01]?_(band|channel|ctrl_sb|bw|bwcls|txpower|distance|wmm|band_steering|smartconnect))'
rpt "Guest / IoT networks (expect none)" 'guest'
rpt "LAN + DHCP server" '^(lan_ipaddr|lan_netmask|lan_gateway|lan_domain|dhcp_(start|end|lease|dns[12]?_x?|enable)|manual_dhcp|staticmap)'
rpt "WAN + PPPoE" '^(wan_(proto|dns[12]_x?|ipaddr|netmask|gateway|mtu|enable)|ppp_(username|passwd|idle|mtu)|auto_connect)'
rpt "Port forwards (Virtual Server)" '^virtualserver'
rpt "UPnP / NAT acceleration" '^(upnp|nat_accel|hwnat|natpmp)'
rpt "DDNS (expect off — container handles it)" '^ddns_'
rpt "VPN servers (expect none)" '(openvpn|ipsec|l2tp|instant_guard|^vpn)'
rpt "Static routes / DHCP option extras" '^(staticroute|dhcp_option)'
rpt "IPv6" '^(ipv6|dhcpv6)'
rpt "Time / hostname" '^(time_zone|hostname|ntp)'

cat <<'EOF'

Next steps:
  1. Fill networking/openwrt/inventory.md from the sections above.
  2. Copy PPPOE_USER/PPPOE_PASS, staticmap_* and virtualserver_* into
     networking/openwrt/.env for openwrt-clone.sh.
  3. Never commit dumps/.
EOF
