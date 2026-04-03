# warp

## Overview

This repository builds a Debian 13.4 slim container image with Cloudflare WARP. The container joins a Docker macvlan network, requests IPv4 DHCP and IPv6 DHCPv6 leases on `eth0`, and starts `warp-svc`.

## Build and publish

Push to `main` to publish the image to GHCR:

- `ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- `ghcr.io/lengyuesky/hysteria2-over-warp:sha-<shortsha>`

## Host network prerequisites

Docker must have IPv6 enabled, and your LAN must provide all of the following on the macvlan-attached segment:

- IPv4 DHCP
- IPv6 DHCPv6
- Layer 2 connectivity for a separate container MAC address

Example external macvlan network creation command:

```bash
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  --ipv6 \
  --subnet=2001:db8:10::/64 \
  --gateway=2001:db8:10::1 \
  -o parent=eth0 \
  warp_macvlan
```

## Deploy

1. Pull and start the container:

```bash
docker compose pull
docker compose up -d
```

2. Verify addressing inside the container:

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp ip -6 addr show dev eth0
```

3. Register and connect WARP for the first time:

```bash
docker exec -it warp warp-cli register
docker exec -it warp warp-cli connect
docker exec -it warp warp-cli status
```
