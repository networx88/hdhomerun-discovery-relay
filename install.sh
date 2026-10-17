#!/bin/sh
# Run on the client-side UniFi gateway as root, after editing config.example.
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config=${1:?Usage: sh install.sh /path/to/edited-config}
test -r "$config"
command -v python3 >/dev/null
command -v iptables >/dev/null
# Keep the input configuration outside the destination before replacing files.
config_text=$(cat "$config")
systemctl stop hdhr-discovery-firewall.timer 2>/dev/null || true
systemctl stop hdhr-discovery.service 2>/dev/null || true
dest=/data/hdhr-discovery
mkdir -p "$dest"
chmod 700 "$dest"
cp "$src/hdhr-discovery-relay.py" "$dest/relay.py"
cp "$src/hdhr-discovery-firewall.sh" "$dest/firewall.sh"
cp "$src/hdhr-discovery.service" "$src/hdhr-discovery@.service" "$src/hdhr-discovery-firewall.service" "$src/hdhr-discovery-firewall.timer" "$dest/"
printf '%s\n' "$config_text" > "$dest/config"
chmod 600 "$dest/config"
chmod 700 "$dest/firewall.sh"
python3 -m py_compile "$dest/relay.py"
sh -n "$dest/firewall.sh"
for name in hdhr-discovery.service hdhr-discovery@.service hdhr-discovery-firewall.service hdhr-discovery-firewall.timer; do
  ln -sfn "$dest/$name" "/etc/systemd/system/$name"
done
systemctl daemon-reload
systemctl enable --now hdhr-discovery.service hdhr-discovery-firewall.timer
systemctl is-active hdhr-discovery.service hdhr-discovery-firewall.timer
systemctl is-enabled hdhr-discovery.service hdhr-discovery-firewall.timer
