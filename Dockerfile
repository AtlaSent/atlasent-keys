FROM nginx:alpine

# CORS-enabled, read-only server config (see the file's header), plus the
# IPv6 listener the stock entrypoint no longer adds to a modified config.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 nginx/11-atlasent-listen-on-ipv6.sh /docker-entrypoint.d/11-atlasent-listen-on-ipv6.sh
# Serve ONLY the published trust-root material, never the whole repository:
# a file committed for maintainers (CLAUDE.md, workflows, scripts, a stray
# .html) must not become content on the origin verifiers are told to trust.
# Add a path here only when it is meant to be fetched from keys.atlasent.io;
# scripts/check-serve-config.sh asserts both directions. The stock nginx
# welcome page is removed so the bare host does not pose as a server default.
RUN rm -f /usr/share/nginx/html/index.html
COPY .well-known /usr/share/nginx/html/.well-known
COPY cosign.pub /usr/share/nginx/html/cosign.pub
COPY schemas /usr/share/nginx/html/schemas
COPY docs /usr/share/nginx/html/docs

EXPOSE 80
