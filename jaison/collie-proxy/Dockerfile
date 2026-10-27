FROM caddy:2-builder AS build
RUN xcaddy build --with github.com/caddy-dns/duckdns

FROM caddy:2
COPY --from=build /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
