#!/bin/sh
# Re-adds the IPv6 listener that nginx:alpine's own
# 10-listen-on-ipv6-by-default.sh would add. That script skips any
# default.conf that differs from the packaged one, and ours does (CORS), so
# without this the trust root would listen on IPv4 only on an IPv6 host.
# Same rule as the stock script: only when the host has IPv6, because
# `listen [::]:80` makes nginx fail to start where it does not.
set -e
CONF="${ATLASENT_NGINX_CONF:-/etc/nginx/conf.d/default.conf}"
IF_INET6="${ATLASENT_IF_INET6:-/proc/net/if_inet6}"

[ -f "$IF_INET6" ] || { echo "$0: ipv6 not available, IPv4 only"; exit 0; }
grep -q "listen  \[::\]:80;" "$CONF" && { echo "$0: IPv6 listen already enabled"; exit 0; }
sed -i -E 's,listen       80;,listen       80;\n    listen  [::]:80;,' "$CONF"
grep -q "listen  \[::\]:80;" "$CONF" || { echo "$0: could not enable IPv6 listen" >&2; exit 1; }
echo "$0: enabled listen on IPv6"
