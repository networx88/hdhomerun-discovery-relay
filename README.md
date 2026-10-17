# HDHomeRun discovery across subnets and routed VPNs

A small Python discovery relay for native HDHomeRun apps when clients and the HDHomeRun are on different subnets.

Use it between VLANs at one site, or across a routed VPN such as **Ubiquiti UniFi Site Magic, OpenVPN, or a point-to-point IPsec VPN**. Run the relay on the gateway serving the clients, where it can receive their discovery broadcasts. Devices on the HDHomeRun's own subnet already discover it directly.

The relay receives UDP 65001 discovery requests, queries one configured HDHomeRun by unicast, validates the reply, and returns it to the client with the HDHomeRun source address. Once discovered, clients stream directly from the HDHomeRun. No video proxy or transcoding is involved.

Tested on a UDM and UDM Pro running UniFi OS 5.1.33 with Python 3.9. The installer enables startup at boot. This is a custom service, independent of Ubiquiti and SiliconDust.

## Requirements

- Root SSH access to the client-side gateway.
- Python 3, systemd, and iptables. No third-party Python packages.
- Routed access from the gateway and client subnet to the HDHomeRun, including a working return route.
- A stable HDHomeRun address, preferably a DHCP reservation.

## Setup

1. Copy this folder to a staging directory on the gateway, such as `/data/hdhr-recovery`.
2. Edit the addresses and interface names in `config.example`. Use `ip -4 addr` to identify your local interfaces.
3. From the staging folder, run as root:

```sh
sh install.sh /data/hdhr-recovery/config.example
```

The example uses client subnet `192.168.50.0/24`, gateway `192.168.50.1`, interface `br0`, and HDHomeRun address `192.168.20.254`. The HDHomeRun can be on another local subnet or at a remote site reached through the VPN.

`GATEWAY` is the local address on the client subnet. Ensure clients and the relay can reach the HDHomeRun through local routing or the VPN. With Site Magic, share the required subnets. Each client site crossing a Layer 3 boundary needs its own relay.

## Firewall behavior

The installer creates custom OS iptables chains, not UniFi UI policies:

- `HDHRD_INPUT`: local discovery requests, only on each configured interface/from its subnet, UDP destination 65001.
- `HDHRD_OUTPUT`: relay queries to the configured HDHomeRun and discovery replies to local clients.
- `HDHRD_FORWARD`: local bridge (`br+`) and Site Magic (`wgsts+`) ingress to the one HDHomeRun address, TCP 80/5004/65001 and UDP 65001, plus established/related return traffic.

The supplied firewall defaults allow local bridges and Site Magic interfaces. For OpenVPN or IPsec, adapt `CLIENT_INTERFACES` and the VPN firewall policy to your platform. Route-based VPNs can use their tunnel interface names; policy-based IPsec needs an explicit VPN policy match. Do not substitute an unrestricted WAN interface.

No Internet-facing tuner permit or port forward is created.

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
