# syntax=docker/dockerfile:1

FROM cgr.dev/chainguard/wolfi-base:latest AS base

USER root
RUN apk update && apk add --no-cache curl dumb-init && rm -rf /var/cache/apk/*

RUN addgroup -g 25565 minecraft && adduser -u 25565 -G minecraft -D minecraft

# /minecraft must be owned by 25565 in the final image. When the (empty) data
# volume is first mounted, Docker copies this directory's ownership onto it.
RUN mkdir -p /minecraft && chown 25565:25565 /minecraft && chmod 750 /minecraft


FROM base AS builder

RUN apk add --no-cache jq unzip

WORKDIR /build

ARG MC_VERSION=26.3
ARG LEVEL_SEED=""
ARG TARGETARCH

RUN set -eu; \
    VERSION_URL="$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json \
      | jq -r --arg v "$MC_VERSION" '.versions[] | select(.id == $v) | .url')"; \
    if [ -z "$VERSION_URL" ]; then echo "Minecraft version $MC_VERSION not found in manifest" >&2; exit 1; fi; \
    curl -fsSL "$VERSION_URL" -o version.json; \
    SERVER_URL="$(jq -r '.downloads.server.url' version.json)"; \
    SERVER_SHA1="$(jq -r '.downloads.server.sha1' version.json)"; \
    echo "MC $MC_VERSION requires Java $(jq -r '.javaVersion.majorVersion' version.json)"; \
    curl -fsSL "$SERVER_URL" -o server.jar; \
    echo "$SERVER_SHA1  server.jar" | sha1sum -c -; \
    rm version.json

# Extract JNA's native dispatch library at build time so JNA never has to
# unpack a .so into a writable (noexec) directory at runtime.
RUN set -eu; \
    ARCH="${TARGETARCH:-}"; \
    if [ -z "$ARCH" ]; then \
      case "$(uname -m)" in \
        x86_64) ARCH=amd64 ;; \
        aarch64) ARCH=arm64 ;; \
        *) ARCH="$(uname -m)" ;; \
      esac; \
    fi; \
    case "$ARCH" in \
      amd64) JNA_ARCH=linux-x86-64 ;; \
      arm64) JNA_ARCH=linux-aarch64 ;; \
      *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac; \
    JNA_JAR="$(unzip -Z1 server.jar | grep -E '^META-INF/libraries/net/java/dev/jna/jna/[^/]+/jna-[^/]+\.jar$' | head -n1)"; \
    if [ -z "$JNA_JAR" ]; then echo "JNA jar not found inside server.jar" >&2; exit 1; fi; \
    echo "Using $JNA_JAR ($JNA_ARCH)"; \
    unzip -p server.jar "$JNA_JAR" > /tmp/jna.jar; \
    mkdir -p /build/jna; \
    unzip -p /tmp/jna.jar "com/sun/jna/$JNA_ARCH/libjnidispatch.so" > /build/jna/libjnidispatch.so; \
    rm /tmp/jna.jar; \
    test -s /build/jna/libjnidispatch.so

RUN echo "eula=true" > eula.txt

# Unquoted delimiter so ${LEVEL_SEED} is actually expanded.
RUN cat > server.properties << EOF
level-seed=${LEVEL_SEED}
server-ip=0.0.0.0
server-port=25565
max-players=20
online-mode=false
white-list=false
enforce-whitelist=false
pvp=true
difficulty=hard
gamemode=survival
hardcore=false
enable-command-block=false
spawn-protection=16
allow-nether=true
allow-flight=false
enable-rcon=false
enable-query=false
enable-status=true
max-tick-time=60000
max-world-size=29999984
view-distance=10
simulation-distance=10
spawn-monsters=true
spawn-animals=true
spawn-npcs=true
generate-structures=true
level-type=default
level-name=world
motd=Hardened Minecraft Server
network-compression-threshold=256
op-permission-level=4
player-idle-timeout=0
force-gamemode=false
rate-limit=0
broadcast-console-to-ops=true
broadcast-rcon-to-ops=false
use-native-transport=true
sync-chunk-writes=true
entity-broadcast-range-percentage=100
require-resource-pack=false
resource-pack=
resource-pack-prompt=
prevent-proxy-connections=false
hide-online-players=false
function-permission-level=2
text-filtering-config=
EOF


FROM cgr.dev/chainguard/jre:latest AS production

ARG MC_VERSION=26.3

COPY --from=base /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=base /etc/passwd /etc/passwd
COPY --from=base /etc/group /etc/group

# Writable game directory (becomes the data volume), owned by the server user.
COPY --from=base --chown=25565:25565 /minecraft /minecraft

# Immutable server files: root-owned, outside the data volume, so a rebuild
# actually updates the server version.
COPY --from=builder /build/server.jar /opt/minecraft-server/server.jar
COPY --from=builder /build/eula.txt /build/server.properties /opt/minecraft-server/defaults/
COPY --from=builder /build/jna/libjnidispatch.so /opt/jna/libjnidispatch.so

WORKDIR /minecraft
USER 25565:25565

EXPOSE 25565

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "java.*server.jar" || exit 1

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["java", "-Xmx2G", "-Xms1G", "-XX:+UseG1GC", "-XX:+ParallelRefProcEnabled", "-XX:MaxGCPauseMillis=200", "-XX:+UnlockExperimentalVMOptions", "-XX:+DisableExplicitGC", "-XX:+AlwaysPreTouch", "-XX:G1HeapWastePercent=5", "-XX:G1MixedGCCountTarget=4", "-XX:G1MixedGCLiveThresholdPercent=90", "-XX:G1RSetUpdatingPauseTimePercent=5", "-XX:SurvivorRatio=32", "-XX:+PerfDisableSharedMem", "-XX:MaxTenuringThreshold=1", "-Dlog4j2.formatMsgNoLookups=true", "-Djna.boot.library.path=/opt/jna", "-Djna.nounpack=true", "-jar", "/opt/minecraft-server/server.jar", "nogui"]

LABEL org.opencontainers.image.title="Hardened Minecraft Server" \
      org.opencontainers.image.description="Security-hardened Minecraft Java Edition server" \
      minecraft.version="${MC_VERSION}"
