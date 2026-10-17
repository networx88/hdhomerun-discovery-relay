#!/bin/sh
set -eu
. /data/hdhr-discovery/config
ipt() { /usr/sbin/iptables -w 5 "$@"; }
add() { ipt -C "$@" 2>/dev/null || ipt -A "$@"; }
if [ "${1:-}" = stop ]; then
  for pair in 'INPUT HDHRD_INPUT' 'OUTPUT HDHRD_OUTPUT' 'FORWARD HDHRD_FORWARD'; do
    set -- $pair
    while ipt -C "$1" -j "$2" 2>/dev/null; do ipt -D "$1" -j "$2"; done
    if ipt -S "$2" >/dev/null 2>&1; then ipt -F "$2"; ipt -X "$2"; fi
  done
  exit 0
fi
for chain in HDHRD_INPUT HDHRD_OUTPUT HDHRD_FORWARD; do
  ipt -S "$chain" >/dev/null 2>&1 || ipt -N "$chain"
done
for listener in $LISTEN_NETWORKS; do
  iface=${listener%%:*}; net=${listener#*:}
  add HDHRD_INPUT -i "$iface" -s "$net" -p udp --dport 65001 -m comment --comment 'HDHR local discovery to relay' -j ACCEPT
  add HDHRD_OUTPUT -o "$iface" -s "$TUNER" -d "$net" -p udp --sport 65001 -m comment --comment 'HDHR discovery reply to local client' -j ACCEPT
done
add HDHRD_OUTPUT -s "$GATEWAY" -d "$TUNER" -p udp --dport 65001 -m comment --comment 'HDHR relay query to tuner' -j ACCEPT
for ingress in $CLIENT_INTERFACES; do
  add HDHRD_FORWARD -i "$ingress" -d "$TUNER" -p tcp -m multiport --dports 80,5004,65001 -m comment --comment 'HDHR internal or Site Magic client HTTP stream control' -j ACCEPT
  add HDHRD_FORWARD -i "$ingress" -d "$TUNER" -p udp --dport 65001 -m comment --comment 'HDHR internal or Site Magic client discovery' -j ACCEPT
  add HDHRD_FORWARD -o "$ingress" -s "$TUNER" -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment 'HDHR explicit tuner return traffic' -j ACCEPT
done
for pair in 'INPUT HDHRD_INPUT' 'OUTPUT HDHRD_OUTPUT' 'FORWARD HDHRD_FORWARD'; do
  set -- $pair
  ipt -C "$1" -j "$2" 2>/dev/null || ipt -I "$1" 1 -j "$2"
done
