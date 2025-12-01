# Hardened Minecraft Server

A security-first Docker deployment for Minecraft Java Edition with defense-in-depth architecture.

## Quick Start

```bash
chmod +x minecraft-control.sh
sudo ./minecraft-control.sh start
```

## Server Control

```bash
./server.sh start     # Start server
./server.sh stop      # Stop server
./server.sh restart   # Restart server
./server.sh status    # View status & stats
./server.sh logs      # Follow live logs
./server.sh backup    # Backup world data
./server.sh rebuild   # Rebuild from scratch
```

## Client Mode Configuration

Edit `Dockerfile` before building:

**Legitimate Clients Only** (secure, default)
```properties
online-mode=true
```

**Cracked Clients Allowed** (requires IP firewall)
```properties
online-mode=false
```

When using cracked mode, you **must** implement IP whitelisting:

```bash
sudo ufw allow from 1.2.3.4 to any port 25565
sudo ufw allow from 5.6.7.8 to any port 25565
sudo ufw enable
```

## Player Management

```bash
# Add to whitelist
docker exec -it minecraft-server sh
whitelist add PlayerName
whitelist reload
exit

# Grant operator status
op PlayerName
```

## Security Architecture

### MITRE ATT&CK Mitigations

**M1048 - Application Isolation**  
Containerized deployment with isolated network namespace and restricted IPC.

**M1026 - Privileged Account Management**  
Non-root execution (UID 25565), no Docker group access required for operation.

**M1038 - Execution Prevention**  
Read-only root filesystem with noexec tmpfs mounts prevents malware persistence.

**M1050 - Exploit Protection**  
All Linux capabilities dropped, no-new-privileges flag enabled, proper signal handling.

**M1051 - Update Software**  
Minimal base image from Chainguard with rapid security patching cycle.

**M1030 - Network Segmentation**  
Isolated bridge network with inter-container communication disabled.

**M1040 - Behavior Prevention**  
CPU and memory limits prevent resource hijacking and cryptomining attacks.

**M1022 - Restrict Permissions**  
Strict file ownership, read-only plugin directory, minimal write access.

### Techniques Blocked

| TTP | Technique | Mitigation |
|-----|-----------|------------|
| T1190 | Exploit Public-Facing Application | IP firewall + regular updates |
| T1059 | Command and Scripting Interpreter | Read-only filesystem + noexec |
| T1610 | Deploy Container | Capability drop + non-root |
| T1068 | Privilege Escalation | No-new-privileges + cap_drop ALL |
| T1611 | Escape to Host | Non-root + no socket mount |
| T1222 | File Permissions Modification | Read-only root filesystem |
| T1496 | Resource Hijacking | CPU/memory limits |
| T1499 | Endpoint Denial of Service | Resource limits + health checks |
| T1562 | Impair Defenses | Centralized logging + monitoring |
| T1195 | Supply Chain Compromise | Pinned versions + hash verification |

### Minecraft-Specific Protections

**CVE-2021-44228 (Log4Shell)**  
JVM flag `-Dlog4j2.formatMsgNoLookups=true` blocks exploitation attempts.

**RCON Exploitation**  
RCON disabled by default. If needed, localhost binding only with strong passwords required.

**UUID Spoofing**  
Mitigated via `online-mode=true` or IP whitelisting when using cracked clients.

**Command Block Exploits**  
Command blocks disabled preventing command injection and world corruption attacks.

**Plugin Backdoors**  
No plugins installed by default. Plugin directory mounted read-only in production.

## Resource Configuration

Default allocation (edit `docker-compose.yml`):
- CPU: 2-4 cores
- RAM: 2-4 GB
- Storage: Persistent volumes at `/opt/minecraft/`

## Backup Strategy

Automated backups recommended via cron:

```bash
0 3 * * * /path/to/minecraft-control.sh backup
```

Backups stored in `/opt/minecraft/backups/` with timestamp naming.

## Monitoring

View real-time metrics:
```bash
docker stats minecraft-server
```

Access logs:
```bash
tail -f /opt/minecraft/logs/latest.log
```

## Threat Model

This deployment assumes:
- VPS hosts other production workloads requiring isolation
- Attackers may exploit Minecraft vulnerabilities to pivot to host
- Players may use cracked clients (optional configuration)
- IP-based access control is acceptable for your use case
- DDoS and resource exhaustion are realistic threats

Primary security objective: **Prevent container escape and host compromise.**

## Compliance

Implements controls from:
- CIS Docker Benchmark v1.6
- OWASP Docker Security
- NIST Container Security Guidelines
- MITRE ATT&CK Framework

## Troubleshooting

**Server won't start**
```bash
docker-compose logs minecraft
```

**Permission errors**
```bash
sudo chown -R 25565:25565 /opt/minecraft
```

**Port already in use**
```bash
sudo lsof -i :25565
```

**Out of memory**  
Increase memory limit in `docker-compose.yml` under `deploy.resources.limits.memory`

## License

Minecraft is property of Mojang/Microsoft. This deployment configuration is provided as-is for educational and personal use.
