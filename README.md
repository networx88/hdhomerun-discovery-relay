# HDHomeRun discovery across UniFi VLANs and Site Magic

A small Python discovery relay for native HDHomeRun apps across a Layer 3 boundary. Run it on the gateway at the **client's site**, where the client's discovery broadcast can be received. A client on the HDHomeRun's own subnet does not need it.

The relay receives UDP 65001 discovery requests, queries one configured HDHomeRun by unicast, validates the reply, and returns it to the client with the HDHomeRun source address. Once discovered, clients stream directly from the HDHomeRun. No video proxy or transcoding is involved.

Custom service tested on a UDM and UDM Pro running UniFi OS 5.1.33 with Python 3.9. It is not an official Ubiquiti or SiliconDust feature. Normal reboot startup is configured through systemd; an actual reboot test was not performed during the initial installation. Firmware upgrades may require reapplication.

## Requirements

- Root SSH access to the client-side gateway.
- Python 3, systemd, and iptables. No third-party Python packages.
- Routed access from the gateway and client subnet to the HDHomeRun, including a working return route.
- Non-overlapping routed client/tuner site networks, or separately configured NAT. This relay does not solve overlapping subnets for direct playback.
- A stable HDHomeRun address, preferably a DHCP reservation.

## Setup

1. Copy this folder to a staging directory on the gateway, such as `/data/hdhr-recovery`.
2. Copy `config.example` to a new file and edit its example addresses and interface names. Identify bridge addresses with `ip -4 addr`; do not assume VLAN names map to the examples.
3. From the staging folder, run as root:

```sh
sh install.sh /data/hdhr-recovery/config.example
```

The supplied example places clients on `192.168.50.0/24`, gateway `192.168.50.1`, interface `br0`, with a remote HDHomeRun at `192.168.20.254`. Replace those values with your actual network.

`GATEWAY` must be a local address on the client subnet, with a valid route and return route to the tuner. Site Magic must share the required subnets. A different remote site needs a relay at that site's client network too.

## Firewall behavior

The installer creates custom OS iptables chains, not UniFi UI policies:

- `HDHRD_INPUT`: local discovery requests, only on each configured interface/from its subnet, UDP destination 65001.
- `HDHRD_OUTPUT`: relay queries to the configured HDHomeRun and discovery replies to local clients.
- `HDHRD_FORWARD`: local bridge (`br+`) and Site Magic (`wgsts+`) ingress to the one HDHomeRun address, TCP 80/5004/65001 and UDP 65001, plus established/related return traffic.

No tuner WAN/Internet ingress permit or port forward is created. These rules allow any client arriving through the configured internal/Site Magic interfaces to reach those tuner ports. Existing unrelated firewall policies are preserved.

A systemd timer checks once per minute and restores these explicit rules if UniFi rebuilds the firewall. Stop the timer when intentionally removing the custom rules.

## More than one local client VLAN

The main listener reads `/data/hdhr-discovery/config`. Additional listeners use the provided `hdhr-discovery@.service` template.

For example, create `/data/hdhr-discovery/other.conf`:

```sh
INTERFACE=br2
NETWORK=192.168.60.0/24
GATEWAY=192.168.60.1
UPSTREAM=192.168.50.1
TUNER=192.168.20.254
```

`UPSTREAM` selects the local source address used for the unicast tuner query. Add the additional listener to the main configuration:

```sh
LISTEN_NETWORKS="br0:192.168.50.0/24 br2:192.168.60.0/24"
```

Then apply the discovery rules and enable that listener:

```sh
sh /data/hdhr-discovery/firewall.sh start
systemctl enable --now hdhr-discovery@other.service
```

Clients on the tuner subnet already have native discovery and do not need a relay listener.

## Verify

```sh
systemctl status hdhr-discovery.service --no-pager
systemctl is-enabled hdhr-discovery.service hdhr-discovery-firewall.timer
journalctl -u hdhr-discovery.service -n 30 --no-pager
iptables -nvL HDHRD_INPUT
iptables -nvL HDHRD_OUTPUT
iptables -nvL HDHRD_FORWARD
```

Open `http://YOUR_HDHomeRun_IP/discover.json` from a client, then restart the native app and play a channel. The relay logs successful discovery responses with client addresses. Additional listener logs use `journalctl -u hdhr-discovery@other.service`.

Discovery success does not guarantee codec support. Fire TV may handle HEVC/AC-4 and MPEG-2/AC-3 channels differently; try Stereo/PCM settings if audio passthrough causes trouble. Also check VPN routing on the playback device itself.

## Reapply after an upgrade

Keep this folder and your edited configuration outside the gateway. Copy it back to a staging folder and run the same installer command. Program/configuration files are stored in `/data/hdhr-discovery`, and systemd links are recreated in `/etc/systemd/system`.

Existing extra VLAN `.conf` files are preserved, but after firmware replacement you may need to re-enable their template instances with `systemctl enable --now hdhr-discovery@NAME.service`.

## Stop and rollback

```sh
systemctl disable --now hdhr-discovery-firewall.timer
# Stop/disable every extra instance you added, for example:
systemctl disable --now hdhr-discovery@other.service
systemctl disable --now hdhr-discovery.service
sh /data/hdhr-discovery/firewall.sh stop
```

This removes the custom HDHRD rules/chains and leaves the files for recovery. Unrelated UniFi policies remain in place.

## References

- [SiliconDust diagnostic CLI](https://info.hdhomerun.com/info/hdhomerun_config)
- [SiliconDust discovery protocol/library](https://github.com/Silicondust/libhdhomerun)
- [UniFi firewall zones](https://help.ui.com/hc/en-us/articles/115003173168-Zone-Based-Firewalls-in-UniFi)

## License

Apache License 2.0. See [LICENSE](LICENSE).
