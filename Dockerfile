FROM nginx:alpine

# CORS-enabled, read-only server config (see the file's header), plus the
# IPv6 listener the stock entrypoint no longer adds to a modified config.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 nginx/11-atlasent-listen-on-ipv6.sh /docker-entrypoint.d/11-atlasent-listen-on-ipv6.sh
COPY . /usr/share/nginx/html

EXPOSE 80
