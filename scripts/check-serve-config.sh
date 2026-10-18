#!/usr/bin/env bash
# Builds the real image and asserts what a browser verifier depends on:
#   - only the published trust-root paths are served, byte for byte, and
#     repository internals (CLAUDE.md, workflows, scripts) are not;
#   - the verifier keys JSON is served with Access-Control-Allow-Origin: *
#     and application/json, with the exact bytes in the repo;
#   - a CORS preflight is answered 204 with the same header;
#   - no Allow-Credentials header is ever sent;
#   - a write method is refused.
# --self-test runs the same assertions against the STOCK nginx:alpine config
# and must FAIL, proving the checks can detect a missing CORS config.
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-}"
tag="atlasent-keys-serve-check:$$"
name="atlasent-keys-serve-check-$$"
port="${PORT:-18080}"
url="http://127.0.0.1:${port}"
path="/.well-known/atlasent-verifier-keys.json"

cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; docker rmi -f "$tag" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if [ "$mode" = "--self-test" ]; then
  # Stock nginx, same content, no custom config.
  printf 'FROM nginx:alpine\nCOPY . /usr/share/nginx/html\n' | docker build -q -t "$tag" -f - . >/dev/null
else
  docker build -q -t "$tag" . >/dev/null
fi
docker run -d --name "$name" -p "127.0.0.1:${port}:80" "$tag" >/dev/null
for _ in $(seq 1 30); do curl -sf -o /dev/null "$url$path" && break; sleep 0.5; done

fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }

get_h="$(curl -s -D - -o /tmp/serve-check-body.$$ -H 'Origin: https://verify.atlasent.io' "$url$path")"
pre_h="$(curl -s -D - -o /dev/null -X OPTIONS -H 'Origin: https://verify.atlasent.io' -H 'Access-Control-Request-Method: GET' "$url$path")"
post_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -d x "$url$path")"

check "GET 200"                          "grep -qiE '^HTTP/[0-9.]+ 200' <<<\"\$get_h\""
check "GET Access-Control-Allow-Origin *" "grep -qiE '^access-control-allow-origin: \\*' <<<\"\$get_h\""
check "GET content-type application/json" "grep -qiE '^content-type: application/json' <<<\"\$get_h\""
check "GET body is the repo file"         "cmp -s /tmp/serve-check-body.$$ .${path}"
check "preflight 204"                     "grep -qiE '^HTTP/[0-9.]+ 204' <<<\"\$pre_h\""
check "preflight Allow-Origin *"          "grep -qiE '^access-control-allow-origin: \\*' <<<\"\$pre_h\""
check "never Allow-Credentials"           "! grep -qi '^access-control-allow-credentials' <<<\"\$get_h\$pre_h\""
check "POST refused (403/405)"            "[ \"$post_code\" = 403 ] || [ \"$post_code\" = 405 ]"
rm -f /tmp/serve-check-body.$$

# What is published, and only that. Every published path must be served with
# the repo's exact bytes; repository internals and the stock welcome page must
# not be served at all.
for pub in /cosign.pub /.well-known/atlasent-trust-root.json /.well-known/atlasent-trust-root.json.bundle \
           /schemas/trust-root/v1/atlasent-verifier-keys.schema.json /docs/permit-signing-keys.json; do
  check "serves $pub with the repo's bytes" "curl -sf '$url$pub' | cmp -s - .$pub"
done
for internal in /50x.html /index.html /CLAUDE.md /Dockerfile /RENAME_PROPOSAL.md /README.md /nginx/default.conf \
                /scripts/check-serve-config.sh /.github/workflows/publish-trust-root.yml; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$url$internal")"
  check "does not serve $internal (got $code)" "[ \"$code\" = 404 ]"
done
check "no stock nginx welcome page at /" "! curl -s '$url/' | grep -qi 'welcome to nginx'"

# IPv6 listener: the stock entrypoint skips a modified default.conf, so our
# own entrypoint script must add it when the host has IPv6 and leave the
# config alone when it does not. Both branches are exercised in a throwaway
# container (the "IPv6 available" marker is simulated). Only nginx's
# "syntax is ok" line is asserted: nginx -t also opens sockets, which fails
# for [::]:80 on a runner without IPv6 even though the config is valid.
v6_on="$(docker run --rm --entrypoint sh -e ATLASENT_IF_INET6=/etc/hostname "$tag" -c \
  '/docker-entrypoint.d/11-atlasent-listen-on-ipv6.sh >/dev/null 2>&1 || exit 9; grep -c "listen  \[::\]:80;" /etc/nginx/conf.d/default.conf; nginx -t 2>&1 | grep -q "syntax is ok" && echo parse-ok' 2>/dev/null || true)"
v6_off="$(docker run --rm --entrypoint sh -e ATLASENT_IF_INET6=/nonexistent "$tag" -c \
  '/docker-entrypoint.d/11-atlasent-listen-on-ipv6.sh >/dev/null 2>&1 || exit 9; grep -c "listen  \[::\]:80;" /etc/nginx/conf.d/default.conf || true' 2>/dev/null || true)"
v6_expected="$(printf '1\nparse-ok')"
check "IPv6 host: listen [::]:80 added once, config parses" '[ "$v6_on" = "$v6_expected" ]'
check "IPv4-only host: config left without an IPv6 listener" "[ \"\$v6_off\" = 0 ]"

if [ "$mode" = "--self-test" ]; then
  if [ "$fail" = 1 ]; then echo "self-test ok: the checks reject the stock config"; exit 0; fi
  echo "self-test FAILED: the checks passed against stock nginx, so they prove nothing"; exit 1
fi
exit "$fail"
