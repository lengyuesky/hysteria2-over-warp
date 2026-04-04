#!/bin/sh

if [ "${reason:-}" != "BOUND6" ] && [ "${reason:-}" != "RENEW6" ] && [ "${reason:-}" != "REBIND6" ] && [ "${reason:-}" != "REBOOT6" ]; then
  return 0
fi

if [ "${interface:-}" != "eth0" ]; then
  return 0
fi

ip -6 route show default dev "$interface" | while read -r _ _ gateway _; do
  if [ -n "$gateway" ] && [ "${gateway#fe80:}" = "$gateway" ]; then
    ip -6 route del default via "$gateway" dev "$interface"
  fi
done
