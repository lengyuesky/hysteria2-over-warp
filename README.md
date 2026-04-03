# warp

## Overview

This repository builds a Debian 13.4 slim container image with Cloudflare WARP. The container joins a Docker macvlan network, requests IPv4 DHCP on `eth0`, removes the Docker-injected IPv4 from that interface while restoring the DHCPv4 address and route, waits for IPv6 autoconfiguration readiness, and starts `warp-svc`.

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

## Deploy

1. Create the external `warp_macvlan` network on the host.
2. Pull and start the container:

```bash
docker compose pull
docker compose up -d
```

3. Verify addressing inside the container, including whether IPv6 was automatically assigned by your network and whether campus portal routes select the DHCPv4 source address:

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp sh -lc 'ip route get 10.9.1.3'
docker exec -it warp ip -6 addr show dev eth0
```

4. Verify that only the DHCPv4 address remains on `eth0`, the campus portal route uses that DHCP source address, and IPv6 is still present. In the confirmed working state, the Docker/macvlan IPv4 has been removed, `ip route get 10.9.1.3` selects the DHCPv4 source, and the portal address is reachable from the container.

5. Register and connect WARP for the first time:

```bash
docker exec -it warp warp-cli register
docker exec -it warp warp-cli connect
docker exec -it warp warp-cli status
```

If `eth0` ever shows both a Docker-managed IPv4 and a DHCPv4 lease, fix the network contract first. The container should not keep two competing IPv4 sources on the same interface.
