FROM rust:1-bookworm AS builder

WORKDIR /src
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    libsqlite3-dev \
    libsodium-dev \
    pkg-config \
    sqlite3 \
  && rm -rf /var/lib/apt/lists/*

COPY . .
RUN sqlite3 /tmp/sqlx-check.db "create table peer (guid blob primary key not null, id varchar(100) not null, uuid blob not null, pk blob not null, created_at datetime not null default(current_timestamp), user blob, status tinyint, note varchar(300), info text not null) without rowid; create unique index index_peer_id on peer (id); create index index_peer_user on peer (user); create index index_peer_created_at on peer (created_at); create index index_peer_status on peer (status);" \
  && DATABASE_URL=sqlite:///tmp/sqlx-check.db cargo build --release --bins

FROM debian:bookworm-slim

ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.2.0.0
ARG S6_ARCH

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl libsqlite3-0 libsodium23 xz-utils \
  && if [ -z "$S6_ARCH" ]; then \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) S6_ARCH=x86_64 ;; \
      arm64) S6_ARCH=aarch64 ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
  fi \
  && curl -fsSL -o /tmp/s6-overlay-${S6_ARCH}.tar.xz \
    https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz \
  && rm -rf /var/lib/apt/lists/* /tmp/s6-overlay*.tar.xz \
  && ln -s /run /var/run

COPY --from=builder /src/target/release/hbbs /usr/bin/hbbs
COPY --from=builder /src/target/release/hbbr /usr/bin/hbbr
COPY --from=builder /src/target/release/rustdesk-utils /usr/bin/rustdesk-utils
COPY docker/rootfs /
RUN find /etc/s6-overlay/s6-rc.d -type f -exec sed -i 's/\r$//' {} + \
  && sed -i 's/\r$//' /usr/bin/healthcheck.sh \
  && rm -rf /etc/s6-overlay/s6-rc.d/api \
  && rm -f /etc/s6-overlay/s6-rc.d/user/contents.d/api \
  && chmod +x /usr/bin/healthcheck.sh \
  && find /etc/s6-overlay/s6-rc.d -type f \( -name run -o -name up -o -name up.real \) -exec chmod +x {} +

ENV RELAY=relay.example.com
ENV ENCRYPTED_ONLY=0
ENV MUST_LOGIN=N

EXPOSE 21115 21116 21116/udp 21117 21118 21119

HEALTHCHECK --interval=10s --timeout=5s CMD /usr/bin/healthcheck.sh

WORKDIR /app
VOLUME /app/data
VOLUME /data

ENTRYPOINT ["/init"]
