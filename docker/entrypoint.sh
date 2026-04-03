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

request_ipv4() {
  dhclient -4 -v eth0
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

  log "waiting for ipv6 autoconfiguration readiness"
  wait_for_ipv6_link_local

  log "starting warp-svc"
  start_warp &

  log "container ready"
  tail -f /dev/null
}

main "$@"
