# Gaming stack (`gaming`)

> Compose project `~/docker/gaming` · network `server-net` (+ `host` for Playit) · last verified 2026-09-25.
> **In one line:** Minecraft (Paper) and Terraria servers, reachable from the internet through Playit.gg tunnels, with automatic Minecraft backups.

## Containers

| Container | Image | Ports | Memory cap | Data lives in | Notes |
|---|---|---|---|---|---|
| minecraft | `itzg/minecraft-server:latest` | 25565 (game), 25575 (RCON) | 5 GiB | `/srv/games/minecraft/data → /data` | `TYPE=PAPER`, `USE_AIKAR_FLAGS`, `INIT_MEMORY=1G`, `MAX_MEMORY=4G`, `ENABLE_RCON`; healthy. Moved from `/mnt/tank/minecraft` on 2026-09-24. |
| mc-backup | `itzg/mc-backup:latest` | — | 512 MiB | reads `/srv/games/minecraft` (ro), writes `/mnt/tank/backups/minecraft` | Daily, keeps 7 (9 archives present). Its `/data` is the *parent* of the server's data dir, so archives contain an extra `data/` level. |
| terraria | `brammys/terraria:latest` | 7777 tcp+udp | 2 GiB | `/srv/games/terraria/Worlds`, `/srv/games/terraria/configs` | World last saved 2026-09-14. **Backup cron is broken** (see below). |
| playit | `ghcr.io/playit-cloud/playit-agent:latest` | host network | none | — | `SECRET_KEY` written literally in compose. **A second agent also runs on the host** (`playit.service`). |

## Who can reach it

- **Internet:** Minecraft and Terraria, through Playit. Nothing else in this stack should be tunnelled; check the Playit dashboard that RCON (25575) is not.
- **LAN / tailnet:** all four published ports, including RCON.

Access control today:

| Server | Who can join | Recommended |
|---|---|---|
| Minecraft | Anyone with a real Minecraft account (`online-mode=true`), **no whitelist**, no ops | `ENABLE_WHITELIST=true`, `ENFORCE_WHITELIST=true`, `WHITELIST=<names>` in compose, recreate |
| Terraria | **Anyone**, no server password | Add `password=<YOUR_SECRET>` to `serverconfig.txt` |

## Backups

| What | How | Where | State |
|---|---|---|---|
| Minecraft world | mc-backup: RCON `save-off` → `save-all` → tar → `save-on`, so backups are consistent without stopping the server | `/mnt/tank/backups/minecraft` | Working |
| Terraria world | Root cron `0 4 * * *` tar | `/mnt/tank/backups/terraria` | **Broken since 2026-09-24**: the cron still archives `/mnt/tank/terraria`, which no longer exists. Fix: change its `-C` to `/srv/games/terraria`. Last good archive: `terraria_20260924.tar.gz` |

Both backup folders are inside the same VM, so they don't protect against losing the VM. See [the roadmap](../roadmap/ROADMAP.md).

Restoring: [runbooks/disaster-recovery.md §3](../runbooks/disaster-recovery.md#3-per-service-data-recovery).

## Why Minecraft is tuned this way (5 GiB cap, `-Xms1G -Xmx4G`)

JVM flags (Aikar's, injected by `USE_AIKAR_FLAGS=true`):

```
-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4
-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90
-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32
-XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Xmx4G -Xms1G
```

- **`-Xmx4G` under a 5 GiB cap:** Java uses memory beyond the heap (metaspace, code cache, GC tables, thread stacks, network buffers), typically 15–25 % extra. The 1 GiB of headroom stops the container limit from killing the server in the middle of a save.
- **`-Xms1G`, not 4G:** `AlwaysPreTouch` claims the starting heap immediately. Starting at 1 GiB avoids pinning 4 GiB of a 12 GiB VM while the server is idle.
- **G1 tuning:** targets 200 ms pauses with a large young generation, because most game objects (chunks, entities) die young.
- **Observed:** ~920 MiB at idle.
- **Terraria's 2 GiB cap** is generous (it uses ~50 MiB); it mainly guards against leaks.
