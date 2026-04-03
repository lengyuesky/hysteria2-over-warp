#!/bin/sh
set -eu

log() {
  printf '%s %s\n' "[entrypoint]" "$*"
}

enable_ipv4_secondary_promotion() {
  sysctl -w net.ipv4.conf.eth0.promote_secondaries=1 >/dev/null
}

cleanup_dhcp_state() {
  rm -f /run/dhclient.pid \
        /run/dhclient6.pid \
        /var/lib/dhcp/dhclient.leases \
        /var/lib/dhcp/dhclient6.leases
}

start_dbus() {
  mkdir -p /run/dbus

  if [ -f /run/dbus/pid ]; then
    pid="$(cat /run/dbus/pid 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return
    fi
    rm -f /run/dbus/pid
  fi

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

wait_for_ipv6_link_local() {
  i=0
  while ! ip -6 addr show dev eth0 scope link | grep -q 'inet6 fe80:'; do
    i=$((i + 1))
    if [ "$i" -ge 20 ]; then
      log "ipv6 link-local address not ready on eth0"
      exit 1
    fi
    sleep 1
  done
}

wait_for_ipv6_default_route() {
  i=0
  while ! ip -6 route show dev eth0 | grep -q 'default via fe80:'; do
    i=$((i + 1))
    if [ "$i" -ge 20 ]; then
      log "ipv6 default route not ready on eth0"
      return
    fi
    sleep 1
  done
}

request_ipv4() {
  dhclient -4 -v eth0
}

get_dhcp_ipv4() {
  awk '/^lease \{/ { in_lease = 1; next }
       in_lease && /^  fixed-address / { gsub(/;/, "", $2); addr = $2 }
       /^}/ { in_lease = 0 }
       END { if (addr) print addr }' /var/lib/dhcp/dhclient.leases
}

cleanup_docker_ipv4() {
  dhcp_ipv4="$1"

  ip -4 -o addr show dev eth0 scope global | awk '/inet / {print $4}' | while read -r addr; do
    if [ -n "$addr" ] && [ "${addr%/*}" != "$dhcp_ipv4" ]; then
      ip addr del "$addr" dev eth0
    fi
  done
}

request_ipv6() {
  if ! dhclient -6 -v eth0; then
    log "dhcpv6 request failed; continuing with automatic ipv6 state"
  fi
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

  dhcp_ipv4="$(get_dhcp_ipv4)"
  if [ -z "$dhcp_ipv4" ]; then
    log "failed to determine dhcp ipv4 address"
    exit 1
  fi

  log "enabling ipv4 secondary promotion"
  enable_ipv4_secondary_promotion

  log "removing docker-provided ipv4 addresses"
  cleanup_docker_ipv4 "$dhcp_ipv4"

  log "waiting for ipv6 autoconfiguration readiness"
  wait_for_ipv6_link_local

  log "waiting for ipv6 default route readiness"
  wait_for_ipv6_default_route

  log "requesting optional dhcpv6 lease"
  request_ipv6

  log "starting warp-svc"
  start_warp &

  log "container ready"
  tail -f /dev/null
}

main "$@"
