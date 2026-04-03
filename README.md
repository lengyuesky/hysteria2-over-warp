# warp

## Overview

This repository builds a Debian 13.4 slim container image with Cloudflare WARP. The container joins a Docker macvlan network, requests IPv4 DHCP on `eth0`, waits for IPv6 autoconfiguration readiness, and starts `warp-svc`.

## Build and publish

Push to `main` to publish the image to GHCR:

- `ghcr.io/lengyuesky/hysteria2-over-warp:latest`
- `ghcr.io/lengyuesky/hysteria2-over-warp:sha-<shortsha>`

## Host network prerequisites

Docker must have IPv6 enabled, the compose-managed macvlan network must keep `enable_ipv6: true`, and your LAN must provide all of the following on the macvlan-attached segment:

- IPv4 DHCP
- Automatic IPv6 configuration for the container network segment (DHCPv6 or RA/SLAAC)
- Layer 2 connectivity for a separate container MAC address

The values in `docker-compose.yml` are templates. Replace all of the following before deployment:

- `parent: eth0`
- `192.168.10.0/24`
- `192.168.10.1`

Equivalent manual macvlan network creation command:

```bash
docker network create -d macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  -o parent=eth0 \
  warp_macvlan
```

## Deploy

1. Update the template network values in `docker-compose.yml`.
2. Pull and start the container:

```bash
docker compose pull
docker compose up -d
```

3. Verify addressing inside the container, including whether IPv6 was automatically assigned by your network:

```bash
docker exec -it warp ip -4 addr show dev eth0
docker exec -it warp ip -6 addr show dev eth0
```

4. Register and connect WARP for the first time:

```bash
docker exec -it warp warp-cli register
docker exec -it warp warp-cli connect
docker exec -it warp warp-cli status
```

If you use the compose-managed network definition above, do not pre-create an external `warp_macvlan` network with conflicting settings.
