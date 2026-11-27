#!/bin/sh
# Clone the production ASUS RT-AX58U config onto this OpenWrt router PC in one
# pass: PPPoE WAN, LAN 192.168.50.1/24, DHCP + reservations, AdGuard DNS,
# port forwards. Run it from the console or a laptop wired directly to the
# LAN port — networking restarts mid-script. Idempotent: safe to re-run.
#
# Copy the whole openwrt/ directory to a USB stick, put .env beside this
# script (see .env.example), then on the router:
#   sh /mnt/sda1/openwrt-clone.sh
#
# Wi-Fi is intentionally absent: the two external APs broadcast the same
# SSID/PSK bridged into br-lan; this box has no radio to configure.
set -eu

cd "$(dirname "$0")"
# .env is untracked by design and only exists on the router USB stick at runtime.
# shellcheck source=/dev/null
[ -f .env ] && . ./.env

: "${WAN_IF:?set WAN_IF in .env}"
: "${LAN_IF:?set LAN_IF in .env}"
: "${WAN_TYPE:=dhcp}"   # dhcp = today's reality per the ASUS dump; pppoe if the ONT is bridged
: "${LAN_IP:=192.168.50.1}"
: "${LAN_NETMASK:=255.255.255.0}"
: "${DNS_SERVER:=192.168.50.186}"
: "${DHCP_START:=100}"
: "${DHCP_END:=200}"
: "${DHCP_LEASE:=24h}"
: "${TIMEZONE:=America/Chicago}"
: "${FORWARD_TO:=192.168.50.186}"
: "${PORT_FORWARDS:=80:80:tcp 443:443:tcp 25565:25565:tcp}"
: "${RESERVATIONS:?set RESERVATIONS (mac,ip,name triples) in .env}"
: "${OPENWRT_ROOT_PASS:?set OPENWRT_ROOT_PASS in .env}"

command -v uci >/dev/null 2>&1 || { echo "no uci — run this ON the OpenWrt router" >&2; exit 1; }
if [ "$WAN_TYPE" = pppoe ]; then
  pppoe_mod=$(opkg list-installed 2>/dev/null | grep -c 'ppp-mod-pppoe') || pppoe_mod=0
  [ "$pppoe_mod" -ge 1 ] || echo "WARNING: ppp-mod-pppoe not installed; WAN will not come up. opkg install ppp-mod-pppoe." >&2
fi

# Default x86 images define br-lan as device[0]; anything else means a
# customized config that must be edited by hand instead.
[ "$(uci -q get network.@device[0].name)" = "br-lan" ] || {
  echo "unexpected /etc/config/network layout (device[0] is not br-lan) — configure manually" >&2; exit 1; }

# --- WAN toward the ISP ---
uci set network.wan.device="$WAN_IF"
uci set network.wan.peerdns='1'
uci -q delete network.wan.ipaddr
uci -q delete network.wan.netmask
uci -q delete network.wan.gateway
if [ "$WAN_TYPE" = pppoe ]; then
  : "${PPPOE_USER:?set PPPOE_USER in .env}"
  : "${PPPOE_PASS:?set PPPOE_PASS in .env}"
  uci set network.wan.proto='pppoe'
  uci set network.wan.username="$PPPOE_USER"
  uci set network.wan.password="$PPPOE_PASS"
else
  uci set network.wan.proto='dhcp'
  uci -q delete network.wan.username
  uci -q delete network.wan.password
fi

# --- LAN: same subnet and gateway as the ASUS ---
uci set network.@device[0].ports="$LAN_IF"
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask="$LAN_NETMASK"
uci -q delete network.lan.gateway
# Static clone: no DHCP/prefix from WAN, and no RA/DHCPv6 — PPPoE here has no
# IPv6, and half-configured RA gives clients a broken v6 default route.
uci set network.lan.delegate='0'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.ra_management='0'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'

# --- DHCP: pool, single DNS = AdGuard Home, reservations from the ASUS dump ---
uci set dhcp.lan.start="$DHCP_START"
uci set dhcp.lan.limit="$((DHCP_END - DHCP_START))"
uci set dhcp.lan.leasetime="$DHCP_LEASE"
# One DNS server only: a second public server leaks blocked domains past AdGuard.
uci set dhcp.lan.dhcp_option="3,$DNS_SERVER"
for h in $(uci show dhcp 2>/dev/null | sed -n 's/^\(dhcp\.host\[[0-9]*\]\)\.mac=.*/\1/p'); do uci -q delete "$h"; done
for r in $RESERVATIONS; do
  mac=${r%%,*}; rest=${r#*,}; ip=${rest%%,*}; name=${rest#*,}
  h=$(uci add dhcp host)
  uci set dhcp.$h.mac="$mac"
  uci set dhcp.$h.ip="$ip"
  uci set dhcp.$h.name="$name"
done

# --- Firewall: rebuild the WAN->LAN port forwards on the dump's list ---
for r in $(uci show firewall 2>/dev/null | sed -n 's/^\(firewall\.redirect\[[0-9]*\]\)\.target=.*/\1/p'); do uci -q delete "$r"; done
for f in $PORT_FORWARDS; do
  ext=${f%%:*}; rest=${f#*:}; int=${rest%%:*}; proto=${rest#*:}
  r=$(uci add firewall redirect)
  uci set firewall.$r.name="fwd-$ext"
  uci set firewall.$r.src='wan'
  uci set firewall.$r.dest='lan'
  uci set firewall.$r.proto="$proto"
  uci set firewall.$r.src_dport="$ext"
  uci set firewall.$r.target='DNAT'
  uci set firewall.$r.dest_ip="$FORWARD_TO"
  uci set firewall.$r.dest_port="$int"
done
# PPPoE payload must fit under the 1492 link MTU or TLS to the servers stalls.
wanzone=$(uci show firewall | sed -n "s/^\(firewall\.@zone\[[0-9]*\]\)\.name='wan'\$/\1/p" | head -n 1)
[ -n "$wanzone" ] && uci set "firewall.$wanzone.tcp_mss_clamp=1452"

# --- System + login ---
uci set system.@system[0].timezone="$TIMEZONE"
printf 'root:%s\n' "$OPENWRT_ROOT_PASS" | chpasswd

uci commit
echo "config committed. Restarting network + firewall — this drops your session."
/etc/init.d/network restart
/etc/init.d/firewall restart >/dev/null 2>&1

cat <<EOF

Done. Verify:
  ifstatus wan | grep -A2 ipv4_address      # PPPoE learned a public IP
  uci get dhcp.lan.dhcp_option              # 3,$DNS_SERVER
  iptables -t nat -S PREROUTING | grep DNAT # port forwards live
From a LAN client: DHCP lease in 192.168.50.$DHCP_START-$DHCP_END, ssh root@$LAN_IP.
EOF
