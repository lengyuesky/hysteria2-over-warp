# warp

## Overview

This repository builds a Debian 13.4 slim container image with Cloudflare WARP and Hysteria 2. The container joins a Docker macvlan network, requests IPv4 DHCP on `eth0`, removes the Docker-injected IPv4 from that interface while restoring the DHCPv4 address and route, runs a user-provided campus login script after DHCP is ready, waits 30 seconds, auto-connects WARP when the client has already been registered, and then starts a Hysteria 2 server.

The default Hysteria 2 server behavior is:

- password auth from `HY2_PASSWORD`
- self-signed certificate generation when no certificate is mounted
- default SNI-related hostname value `bing.com`
- startup continues even if WARP has not been registered yet, but in that case the shared egress may not be WARP yet

## Build and publish

Push to `main` to publish the image to GHCR:

- `ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- `ghcr.io/lengyuesky/hysteria2-over-warp:sha-<shortsha>`

## Host network prerequisites

Your LAN must provide all of the following on the macvlan-attached segment:

- IPv4 DHCP
- Automatic IPv6 configuration for the container network segment (DHCPv6 or RA/SLAAC)
- Layer 2 connectivity for a separate container MAC address

Before `docker compose up`, create an external `warp_macvlan` network on the host. Compose only attaches the container to that network; the container-side IPv4 address must come from `dhclient -4`, not from Docker IPAM. That external network must also preserve IPv6 support for the attached segment, because the current entrypoint still waits for IPv6 link-local readiness and then checks for an IPv6 default route before the optional DHCPv6 request.

Example external macvlan network creation command:

```bash
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  -o parent=eth0 \
  warp_macvlan
```

Do not configure the project so that `eth0` keeps both a Docker-managed IPv4 and a DHCPv4 lease at the same time. That dual-IPv4 state can make routes such as `10.9.1.3` pick the wrong source address. The current entrypoint explicitly removes Docker's injected IPv4 after DHCP succeeds and restores the DHCPv4 address and route so that `eth0` ends up with only the DHCP lease.

## Compose configuration

The compose file now expects these local paths and settings:

- `./config/scripts/campus-login.sh`: your campus login script
- `./config/hysteria/`: optional custom Hysteria config and certificate directory
- `HY2_PASSWORD`: required Hysteria 2 password
- `HY2_SNI`: defaults to `bing.com`
- `WARP_CONNECT_DELAY`: defaults to `30`

If `./config/hysteria/config.yaml` exists, the container uses it directly. Otherwise it generates a default server config. If `server.crt` and `server.key` are missing, the container generates a self-signed certificate automatically.

## Deploy

1. Create the external `warp_macvlan` network on the host.
2. Prepare your campus login script and Hysteria password:

```bash
mkdir -p config/scripts config/hysteria
chmod +x config/scripts/campus-login.sh
```

3. Set `HY2_PASSWORD` in `docker-compose.yml` to a real strong password.
4. Pull and start the container:

```bash
docker compose pull
docker compose up -d
```

## Runtime flow

The startup flow is:

1. get DHCPv4 on `eth0`
2. remove Docker IPv4 and restore the DHCP route
3. run the campus login script
4. wait for IPv6 readiness
5. start `warp-svc`
6. wait 30 seconds and auto-connect WARP if already registered
7. start Hysteria 2

The campus login script is a strong prerequisite. If it is configured but missing, not executable, or exits non-zero, the container fails fast.

## First-time WARP registration

The container does not automate the first registration. Run this once after the container is up:

```bash
docker exec -it warp warp-cli --accept-tos registration new
docker exec -it warp warp-cli --accept-tos connect
docker exec -it warp warp-cli --accept-tos status
```

After that initial registration, subsequent container starts wait 30 seconds and attempt automatic WARP connection.

## Verify

Verify addressing inside the container, including whether IPv6 was automatically assigned by your network and whether campus portal routes select the DHCPv4 source address:

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp sh -lc 'ip route get 10.9.1.3'
docker exec -it warp ip -6 addr show dev eth0
docker exec -it warp warp-cli --accept-tos status
docker exec -it warp sh -lc 'ss -lunp | grep 8443 || true'
```

Expected state:

- `eth0` keeps only the DHCPv4 address
- `ip route get 10.9.1.3` selects the DHCPv4 source address
- IPv6 is still present
- the campus login script has already run
- if WARP was previously registered, the container auto-connects after 30 seconds
- Hysteria 2 is listening on UDP `8443`

In a macvlan deployment, clients normally connect to the container's own DHCP-assigned LAN IP on UDP `8443`. The `ports` mapping is only a compatibility fallback and should not be treated as the primary access path.

## Notes

- If WARP has not been registered yet, Hysteria 2 still starts, but the shared egress may not be WARP yet.
- If `eth0` ever shows both a Docker-managed IPv4 and a DHCPv4 lease, fix the network contract first. The container should not keep two competing IPv4 sources on the same interface.
- If you do not want the auto-generated self-signed certificate to change after rebuilds, persist `./config/hysteria/`.
