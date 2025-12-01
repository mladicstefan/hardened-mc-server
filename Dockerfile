FROM cgr.dev/chainguard/jre:latest-dev AS base

USER root

RUN apk update && apk add --no-cache \
    curl \
    dumb-init \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

RUN addgroup -g 25565 -S minecraft \
    && adduser -S minecraft -u 25565 -G minecraft

FROM base AS builder

WORKDIR /build

ARG MC_VERSION=1.21.4

RUN curl -o server.jar \
    "https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"

RUN echo "eula=true" > eula.txt

RUN cat > server.properties << 'EOF'
server-ip=0.0.0.0
server-port=25565
max-players=20
online-mode=false
white-list=true
enforce-whitelist=true
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
snooper-enabled=false
function-permission-level=2
text-filtering-config=
EOF

FROM cgr.dev/chainguard/jre:latest AS production

WORKDIR /minecraft

ENV JAVA_OPTS="-Xmx2G -Xms1G \
    -XX:+UseG1GC \
    -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch \
    -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 \
    -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem \
    -XX:MaxTenuringThreshold=1 \
    -Dlog4j2.formatMsgNoLookups=true"

COPY --from=base /usr/bin/dumb-init /usr/bin/dumb-init

COPY --from=builder --chown=minecraft:minecraft /build/server.jar /minecraft/
COPY --from=builder --chown=minecraft:minecraft /build/eula.txt /minecraft/
COPY --from=builder --chown=minecraft:minecraft /build/server.properties /minecraft/

RUN mkdir -p /minecraft/world /minecraft/logs \
    && chown -R minecraft:minecraft /minecraft

USER minecraft

EXPOSE 25565

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "java.*server.jar" || exit 1

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["sh", "-c", "java $JAVA_OPTS -jar server.jar nogui"]

LABEL org.opencontainers.image.title="Hardened Minecraft Server" \
      org.opencontainers.image.description="Security-hardened Minecraft Java Edition server" \
      minecraft.version="1.21.4"
