FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gnupg \
    iproute2 \
    iptables \
    lsb-release \
    openssl \
  && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends cloudflare-warp \
  && arch="$(dpkg --print-architecture)" \
  && case "$arch" in \
      amd64) hy2_arch='amd64' ;; \
      arm64) hy2_arch='arm64' ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
  && curl -fsSL "https://download.hysteria.network/app/latest/hysteria-linux-${hy2_arch}" -o /usr/local/bin/hysteria \
  && chmod +x /usr/local/bin/hysteria \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh
COPY scripts /app/scripts
COPY config /app/config

RUN chmod +x /app/entrypoint.sh /app/scripts/*.sh

ENTRYPOINT ["/app/entrypoint.sh"]
