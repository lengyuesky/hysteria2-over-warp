#!/bin/sh
set -eu

log() {
  printf '%s %s\n' "[entrypoint]" "$*"
}

set_defaults() {
  : "${CAMPUS_LOGIN_SCRIPT:=}"
  : "${WARP_AUTO_CONNECT:=true}"
  : "${WARP_CONNECT_DELAY:=30}"
  : "${HY2_CONFIG_FILE:=/config/hysteria/config.yaml}"
  : "${HY2_RUNTIME_CONFIG_FILE:=/var/lib/hysteria/config.yaml}"
  : "${HY2_TEMPLATE_FILE:=/usr/local/share/hysteria/config.yaml.template}"
  : "${HY2_PORT:=8443}"
  : "${HY2_SNI:=bing.com}"
  : "${HY2_CERT_FILE:=/config/hysteria/server.crt}"
  : "${HY2_KEY_FILE:=/config/hysteria/server.key}"
  : "${HY2_PASSWORD:=}"
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

get_dhcp_router() {
  awk '/^lease \{/ { in_lease = 1; next }
       in_lease && /^  option routers / { gsub(/;/, "", $3); router = $3 }
       /^}/ { in_lease = 0 }
       END { if (router) print router }' /var/lib/dhcp/dhclient.leases
}

get_dhcp_prefix_len() {
  awk '/^lease \{/ { in_lease = 1; next }
       in_lease && /^  option subnet-mask / {
         gsub(/;/, "", $3)
         split($3, octets, ".")
         bits = 0
         for (i = 1; i <= 4; i++) {
           n = octets[i] + 0
           while (n > 0) {
             bits += n % 2
             n = int(n / 2)
           }
         }
         prefix = bits
       }
       /^}/ { in_lease = 0 }
       END { if (prefix) print prefix }' /var/lib/dhcp/dhclient.leases
}

cleanup_docker_ipv4() {
  dhcp_ipv4="$1"

  ip -4 -o addr show dev eth0 scope global | awk '/inet / {print $4}' | while read -r addr; do
    if [ -n "$addr" ] && [ "${addr%/*}" != "$dhcp_ipv4" ]; then
      ip addr del "$addr" dev eth0
    fi
  done
}

restore_dhcp_ipv4() {
  dhcp_ipv4="$1"
  dhcp_prefix_len="$2"
  dhcp_router="$3"

  if ! ip -4 -o addr show dev eth0 scope global | awk '/inet / {print $4}' | grep -q "^${dhcp_ipv4}/"; then
    ip addr add "$dhcp_ipv4/$dhcp_prefix_len" dev eth0
  fi

  if [ -n "$dhcp_router" ]; then
    ip route replace default via "$dhcp_router" dev eth0
  fi
}

run_campus_login_script() {
  if [ -z "$CAMPUS_LOGIN_SCRIPT" ]; then
    log "no campus login script configured; skipping"
    return
  fi

  if [ ! -e "$CAMPUS_LOGIN_SCRIPT" ]; then
    log "campus login script not found: $CAMPUS_LOGIN_SCRIPT"
    exit 1
  fi

  if [ ! -x "$CAMPUS_LOGIN_SCRIPT" ]; then
    log "campus login script is not executable: $CAMPUS_LOGIN_SCRIPT"
    exit 1
  fi

  log "running campus login script: $CAMPUS_LOGIN_SCRIPT"
  if ! "$CAMPUS_LOGIN_SCRIPT"; then
    log "campus login script failed"
    exit 1
  fi
}

request_ipv6() {
  if ! dhclient -6 -v eth0; then
    log "dhcpv6 request failed; continuing with automatic ipv6 state"
  fi
}

start_warp() {
  log "launching warp-svc"
  warp-svc &
  WARP_SVC_PID=$!
}

warp_cli() {
  warp-cli --accept-tos "$@"
}

is_true() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_warp_registered() {
  warp_cli registration show >/tmp/warp-registration.log 2>&1
}

auto_connect_warp() {
  if ! is_true "$WARP_AUTO_CONNECT"; then
    log "warp auto connect disabled"
    return
  fi

  if [ "$WARP_CONNECT_DELAY" -gt 0 ] 2>/dev/null; then
    log "waiting $WARP_CONNECT_DELAY seconds before warp auto connect"
    sleep "$WARP_CONNECT_DELAY"
  fi

  if is_warp_registered; then
    log "connecting warp"
    warp_cli connect
  else
    log "warp registration missing; skipping auto connect"
  fi
}

require_hy2_password() {
  if [ -z "$HY2_PASSWORD" ] || [ "$HY2_PASSWORD" = "change-this-password" ]; then
    log "HY2_PASSWORD must be set to a non-placeholder value"
    exit 1
  fi
}

prepare_hysteria_cert() {
  if [ -f "$HY2_CERT_FILE" ] && [ -f "$HY2_KEY_FILE" ]; then
    log "using existing hysteria certificate and key"
    return
  fi

  if [ -e "$HY2_CERT_FILE" ] || [ -e "$HY2_KEY_FILE" ]; then
    log "partial hysteria certificate or key detected"
    exit 1
  fi

  mkdir -p "$(dirname "$HY2_CERT_FILE")" "$(dirname "$HY2_KEY_FILE")"

  log "generating self-signed hysteria certificate"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "$HY2_KEY_FILE" \
    -out "$HY2_CERT_FILE" \
    -subj "/CN=$HY2_SNI" \
    -addext "subjectAltName=DNS:$HY2_SNI" >/dev/null 2>&1
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

render_default_hysteria_config() {
  if [ ! -f "$HY2_TEMPLATE_FILE" ]; then
    log "hysteria config template not found: $HY2_TEMPLATE_FILE"
    exit 1
  fi

  mkdir -p "$(dirname "$HY2_RUNTIME_CONFIG_FILE")"

  sed \
    -e "s|\${HY2_PORT}|$(escape_sed_replacement "$HY2_PORT")|g" \
    -e "s|\${HY2_CERT_FILE}|$(escape_sed_replacement "$HY2_CERT_FILE")|g" \
    -e "s|\${HY2_KEY_FILE}|$(escape_sed_replacement "$HY2_KEY_FILE")|g" \
    -e "s|\${HY2_PASSWORD}|$(escape_sed_replacement "$HY2_PASSWORD")|g" \
    "$HY2_TEMPLATE_FILE" > "$HY2_RUNTIME_CONFIG_FILE"
}

select_hysteria_config() {
  if [ -f "$HY2_CONFIG_FILE" ]; then
    FINAL_HY2_CONFIG_FILE="$HY2_CONFIG_FILE"
    log "using custom hysteria config: $FINAL_HY2_CONFIG_FILE"
    return
  fi

  require_hy2_password
  render_default_hysteria_config
  FINAL_HY2_CONFIG_FILE="$HY2_RUNTIME_CONFIG_FILE"
  log "using generated hysteria config: $FINAL_HY2_CONFIG_FILE"
}

start_hysteria() {
  log "starting hysteria"
  hysteria server -c "$FINAL_HY2_CONFIG_FILE" &
  HYSTERIA_PID=$!
}

cleanup_children() {
  status=$?
  trap - EXIT INT TERM

  if [ -n "${HYSTERIA_PID:-}" ] && kill -0 "$HYSTERIA_PID" 2>/dev/null; then
    kill "$HYSTERIA_PID" 2>/dev/null || true
  fi

  if [ -n "${WARP_SVC_PID:-}" ] && kill -0 "$WARP_SVC_PID" 2>/dev/null; then
    kill "$WARP_SVC_PID" 2>/dev/null || true
  fi

  wait_for_exit "${HYSTERIA_PID:-}"
  wait_for_exit "${WARP_SVC_PID:-}"

  exit "$status"
}

wait_for_exit() {
  pid="$1"

  if [ -z "$pid" ]; then
    return
  fi

  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
  done
}

monitor_services() {
  while :; do
    if ! kill -0 "$WARP_SVC_PID" 2>/dev/null; then
      log "warp-svc exited"
      exit 1
    fi

    if ! kill -0 "$HYSTERIA_PID" 2>/dev/null; then
      log "hysteria exited"
      exit 1
    fi

    sleep 1
  done
}

main() {
  set_defaults
  trap cleanup_children EXIT INT TERM

  log "starting dbus"
  start_dbus

  log "waiting for eth0"
  wait_for_eth0

  log "cleaning dhcp state"
  cleanup_dhcp_state

  log "requesting ipv4 lease"
  request_ipv4

  dhcp_ipv4="$(get_dhcp_ipv4)"
  dhcp_router="$(get_dhcp_router)"
  dhcp_prefix_len="$(get_dhcp_prefix_len)"
  if [ -z "$dhcp_ipv4" ] || [ -z "$dhcp_prefix_len" ]; then
    log "failed to determine dhcp ipv4 lease details"
    exit 1
  fi

  log "removing docker-provided ipv4 addresses"
  cleanup_docker_ipv4 "$dhcp_ipv4"

  log "restoring dhcp ipv4 address and route"
  restore_dhcp_ipv4 "$dhcp_ipv4" "$dhcp_prefix_len" "$dhcp_router"

  log "waiting for ipv6 autoconfiguration readiness"
  wait_for_ipv6_link_local

  log "waiting for ipv6 default route readiness"
  wait_for_ipv6_default_route

  log "requesting optional dhcpv6 lease"
  request_ipv6

  log "running optional campus login stage"
  run_campus_login_script

  log "starting warp-svc"
  start_warp

  log "running warp auto connect stage"
  auto_connect_warp

  log "preparing hysteria certificate"
  prepare_hysteria_cert

  log "selecting hysteria config"
  select_hysteria_config

  log "starting hysteria service"
  start_hysteria

  log "container ready"
  monitor_services
}

main "$@"
