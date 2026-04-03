# WARP Debian macvlan Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Debian 13.4 slim image with Cloudflare WARP, container-managed DHCPv4/DHCPv6 over macvlan, a Compose deployment that pulls `ghcr.io/lengyuesky/hysteria2-over-warp:latest`, and a GitHub Actions workflow that publishes `latest` and `sha-<shortsha>` tags on `main` pushes.

**Architecture:** The implementation uses a small shell-based entrypoint instead of systemd. The image installs WARP plus the minimum runtime packages, the entrypoint brings up D-Bus, requests IPv4/IPv6 leases on `eth0`, then starts `warp-svc`. Compose consumes the published GHCR image and only provides runtime privileges and macvlan attachment, while GitHub Actions is responsible for building and publishing the image.

**Tech Stack:** Debian 13.4 slim, shell entrypoint, Cloudflare WARP Linux package, Docker Compose, Docker Buildx, GitHub Actions, GHCR

---

## File Structure

- Create: `Dockerfile` — builds the runtime image from `debian:13.4-slim`, installs runtime dependencies and WARP, copies the entrypoint.
- Create: `docker/entrypoint.sh` — starts D-Bus, acquires DHCPv4/DHCPv6 on `eth0`, starts `warp-svc`, and keeps the container in the foreground.
- Create: `docker-compose.yml` — runs `ghcr.io/lengyuesky/hysteria2-over-warp:latest` with `NET_ADMIN`, `/dev/net/tun`, and an external macvlan network.
- Create: `.github/workflows/build-image.yml` — builds and pushes `latest` and `sha-<shortsha>` tags to GHCR on `main` pushes.
- Create: `.dockerignore` — avoids sending git metadata and local editor files into Docker build context.
- Create: `README.md` — documents required host-side macvlan setup, GHCR image usage, and first-run `warp-cli` steps.

### Task 1: Create Docker build inputs

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`
- Test: local Docker build command using the repository root as context

- [ ] **Step 1: Write the failing build attempt command in your notes and confirm the files do not exist yet**

```bash
ls -la Dockerfile .dockerignore
```

Expected: `ls` reports both files are missing.

- [ ] **Step 2: Create `.dockerignore` with the exact contents below**

```dockerignore
.git
.github
.claude
.docs
worktrees
.worktrees
*.log
```

- [ ] **Step 3: Create `Dockerfile` with the exact contents below**

```dockerfile
FROM debian:13.4-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        iproute2 \
        iputils-ping \
        isc-dhcp-client \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ trixie main" \
        > /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends cloudflare-warp \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

- [ ] **Step 4: Run the Docker build to verify the image build now fails for the expected next reason**

Run: `docker build -t warp:test .`
Expected: FAIL with `COPY failed` / `failed to compute cache key` because `docker/entrypoint.sh` does not exist yet.

- [ ] **Step 5: Commit the initial build inputs**

```bash
git add .dockerignore Dockerfile
git commit -m "build: scaffold warp image inputs"
```

### Task 2: Add the runtime entrypoint

**Files:**
- Create: `docker/entrypoint.sh`
- Modify: `Dockerfile`
- Test: local Docker build command using the repository root as context

- [ ] **Step 1: Create the failing runtime script path check**

```bash
ls -la docker/entrypoint.sh
```

Expected: `ls` reports `docker/entrypoint.sh` is missing.

- [ ] **Step 2: Create `docker/entrypoint.sh` with the exact contents below**

```sh
#!/bin/sh
set -eu

log() {
  printf '%s %s\n' "[entrypoint]" "$*"
}

cleanup_dhcp_state() {
  rm -f /run/dhclient.pid \
        /run/dhclient6.pid \
        /var/lib/dhcp/dhclient.leases \
        /var/lib/dhcp/dhclient6.leases
}

start_dbus() {
  mkdir -p /run/dbus
  dbus-daemon --system --fork
}

wait_for_eth0() {
  i=0
  while [ ! -d /sys/class/net/eth0 ]; do
    i=$((i + 1))
    if [ "$i" -ge 20 ]; then
      log "eth0 not found"
      exit 1
    fi
    sleep 1
  done
}

request_ipv4() {
  dhclient -4 -v eth0
}

request_ipv6() {
  dhclient -6 -v eth0
}

start_warp() {
  warp-svc
}

main() {
  log "starting dbus"
  start_dbus

  log "waiting for eth0"
  wait_for_eth0

  log "cleaning dhcp state"
  cleanup_dhcp_state

  log "requesting ipv4 lease"
  request_ipv4

  log "requesting ipv6 lease"
  request_ipv6

  log "starting warp-svc"
  start_warp &

  log "container ready"
  tail -f /dev/null
}

main "$@"
```

- [ ] **Step 3: Modify `Dockerfile` to create the DHCP state directory before copying the entrypoint**

Replace the first `RUN apt-get update ...` block with this exact block:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        iproute2 \
        iputils-ping \
        isc-dhcp-client \
        procps \
    && mkdir -p /var/lib/dhcp \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 4: Run the Docker build to verify the image build passes**

Run: `docker build -t warp:test .`
Expected: PASS and prints a final `Successfully tagged warp:test` or BuildKit success message.

- [ ] **Step 5: Commit the runtime entrypoint**

```bash
git add Dockerfile docker/entrypoint.sh
git commit -m "feat: add warp container entrypoint"
```

### Task 3: Add Compose deployment that uses GHCR

**Files:**
- Create: `docker-compose.yml`
- Test: Compose config rendering

- [ ] **Step 1: Confirm the compose file is absent before creating it**

```bash
ls -la docker-compose.yml
```

Expected: `ls` reports `docker-compose.yml` is missing.

- [ ] **Step 2: Create `docker-compose.yml` with the exact contents below**

```yaml
services:
  warp:
    image: ghcr.io/lengyuesky/hysteria2-over-warp:latest
    container_name: warp
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    stdin_open: true
    tty: true
    networks:
      - warp_macvlan

networks:
  warp_macvlan:
    external: true
    name: warp_macvlan
```

- [ ] **Step 3: Render the Compose configuration to verify the file is valid YAML**

Run: `docker compose config`
Expected: PASS and prints the normalized Compose configuration with a `warp` service and the external `warp_macvlan` network.

- [ ] **Step 4: Add a deployment note to your implementation notes before commit**

```text
docker-compose.yml already targets ghcr.io/lengyuesky/hysteria2-over-warp:latest; verify the GHCR package is readable by the deployment environment before first pull.
```

Expected: You have explicitly captured the only deployment prerequisite tied to the image reference in this file.

- [ ] **Step 5: Commit the Compose deployment file**

```bash
git add docker-compose.yml
git commit -m "deploy: add ghcr compose deployment"
```

### Task 4: Add GitHub Actions image publishing workflow

**Files:**
- Create: `.github/workflows/build-image.yml`
- Test: workflow YAML inspection and tag logic review

- [ ] **Step 1: Confirm the workflow file path is absent before creating it**

```bash
ls -la .github/workflows/build-image.yml
```

Expected: `ls` reports the workflow file is missing.

- [ ] **Step 2: Create `.github/workflows/build-image.yml` with the exact contents below**

```yaml
name: Build and publish image

on:
  push:
    branches:
      - main

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=raw,value=latest
            type=sha,format=short,prefix=sha-

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

- [ ] **Step 3: Validate the workflow structure with a targeted file read**

Run: `python - <<'PY'
from pathlib import Path
text = Path('.github/workflows/build-image.yml').read_text()
for needle in ['branches:', 'main', 'ghcr.io/${{ github.repository }}', 'type=raw,value=latest', 'type=sha,format=short,prefix=sha-']:
    assert needle in text, needle
print('workflow-check-ok')
PY`
Expected: PASS and prints `workflow-check-ok`.

- [ ] **Step 4: Verify the published image reference matches the Compose convention**

Run: `python - <<'PY'
from pathlib import Path
compose = Path('docker-compose.yml').read_text()
workflow = Path('.github/workflows/build-image.yml').read_text()
assert 'ghcr.io/lengyuesky/hysteria2-over-warp:latest' in compose
assert 'ghcr.io/${{ github.repository }}' in workflow
print('image-reference-check-ok')
PY`
Expected: PASS and prints `image-reference-check-ok`.

- [ ] **Step 5: Commit the CI workflow**

```bash
git add .github/workflows/build-image.yml
git commit -m "ci: publish warp image to ghcr"
```

### Task 5: Add operator documentation

**Files:**
- Create: `README.md`
- Test: markdown content inspection

- [ ] **Step 1: Confirm the README is absent before creating it**

```bash
ls -la README.md
```

Expected: `ls` reports `README.md` is missing.

- [ ] **Step 2: Create `README.md` with the exact contents below**

````markdown
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
````

- [ ] **Step 3: Verify the README contains the required operator commands**

Run: `python - <<'PY'
from pathlib import Path
text = Path('README.md').read_text()
for needle in ['docker network create -d macvlan', 'docker compose pull', 'warp-cli register', 'warp-cli connect', 'warp-cli status']:
    assert needle in text, needle
print('readme-check-ok')
PY`
Expected: PASS and prints `readme-check-ok`.

- [ ] **Step 4: Verify the documentation reflects the strict DHCPv6 requirement**

Run: `python - <<'PY'
from pathlib import Path
text = Path('README.md').read_text()
assert 'IPv6 DHCPv6' in text
assert 'Docker must have IPv6 enabled' in text
print('dhcpv6-doc-check-ok')
PY`
Expected: PASS and prints `dhcpv6-doc-check-ok`.

- [ ] **Step 5: Commit the operator documentation**

```bash
git add README.md
git commit -m "docs: add warp deployment guide"
```

### Task 6: End-to-end verification

**Files:**
- Test: Docker build, Compose config, and operator verification commands

- [ ] **Step 1: Verify the compose file already references the concrete GHCR image path**

Run: `python - <<'PY'
from pathlib import Path
text = Path('docker-compose.yml').read_text()
assert 'ghcr.io/lengyuesky/hysteria2-over-warp:latest' in text
print('compose-image-check-ok')
PY`
Expected: PASS and prints `compose-image-check-ok`.

- [ ] **Step 2: Build the image locally one final time to verify the repository still builds**

Run: `docker build -t warp:final .`
Expected: PASS and prints a final success message.

- [ ] **Step 3: Render the Compose configuration with the concrete GHCR image reference**

Run: `docker compose config`
Expected: PASS and shows `image: ghcr.io/lengyuesky/hysteria2-over-warp:latest` in the rendered output.

- [ ] **Step 4: Push the branch to `main` and verify the workflow publishes both image tags in GHCR**

Run: `gh run list --workflow "Build and publish image" --limit 1`
Expected: PASS and shows the latest run triggered from `main`.

- [ ] **Step 5: Start the deployment and verify runtime networking and WARP state**

Run: `docker compose pull && docker compose up -d && docker exec warp ip -4 addr show dev eth0 && docker exec warp ip -6 addr show dev eth0 && docker exec warp warp-cli status`
Expected: PASS for compose operations, visible IPv4 lease on `eth0`, visible IPv6 lease on `eth0`, and a valid WARP status output (connected after manual registration/connect).
