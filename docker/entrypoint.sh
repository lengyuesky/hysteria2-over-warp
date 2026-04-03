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
