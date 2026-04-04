FROM debian:13.4-slim

ARG TARGETARCH
ARG HYSTERIA_VERSION=app/v2.8.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        iproute2 \
        iputils-ping \
        isc-dhcp-client \
        openssl \
        procps \
    && mkdir -p /var/lib/dhcp /var/lib/hysteria /usr/local/share/hysteria /config/hysteria /etc/dhcp/dhclient-exit-hooks.d \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p --mode=0755 /usr/share/keyrings \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ trixie main" \
        > /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends cloudflare-warp \
    && rm -rf /var/lib/apt/lists/*

RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "$arch" in \
        amd64) hy2_asset="hysteria-linux-amd64"; hy2_sha256="97059a4c3802699c7ecff979133092be3d5f8a62907a939a82e90e7f8668f5a0" ;; \
        arm64) hy2_asset="hysteria-linux-arm64"; hy2_sha256="6814ebeaa0ebbf089548d1b5f236bc63bb4bb796fa2a0e52fe5de522e511cf64" ;; \
        *) echo "unsupported TARGETARCH: $arch" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/${hy2_asset}" \
        -o /usr/local/bin/hysteria \
    && printf '%s  %s\n' "$hy2_sha256" /usr/local/bin/hysteria | sha256sum -c - \
    && chmod +x /usr/local/bin/hysteria

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/dhclient-ipv6-exit-hook.sh /etc/dhcp/dhclient-exit-hooks.d/cleanup-ipv6-default-route
COPY docker/hysteria-server.yaml.template /usr/local/share/hysteria/config.yaml.template
RUN chmod +x /usr/local/bin/entrypoint.sh /etc/dhcp/dhclient-exit-hooks.d/cleanup-ipv6-default-route

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
