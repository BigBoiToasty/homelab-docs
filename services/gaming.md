# Gaming stack (`gaming`)

> Compose project `~/docker/gaming` · network `server-net` (+ `host` for Playit) · last verified 2026-09-26.
> **In one line:** Minecraft (Paper) and Terraria servers, reachable from the internet through Playit.gg tunnels, with automatic Minecraft backups.

## Containers

| Container | Image | Ports | Memory cap | Data lives in | Notes |
|---|---|---|---|---|---|
| minecraft | `itzg/minecraft-server:latest` | 25565 (game), 25575 (RCON) | 5 GiB | `/srv/games/minecraft/data → /data` | `TYPE=PAPER`, `USE_AIKAR_FLAGS`, `INIT_MEMORY=1G`, `MAX_MEMORY=4G`, `ENABLE_RCON`; healthy. Everything (server files **and** `world/`) is inside `data/`; nothing else lives in `/srv/games/minecraft`. |
| mc-backup | `itzg/mc-backup:latest` | — | 512 MiB | reads `/srv/games/minecraft/data` (ro), writes `/mnt/tank/backups/minecraft` | Every 24 h, prunes archives older than 7 days. Reads the same folder as the server (fixed 2026-09-26). |
| terraria | `brammys/terraria:latest` | 7777 tcp+udp | 2 GiB | `/srv/games/terraria/Worlds`, `/srv/games/terraria/configs` | Backed up nightly by cron. |
| playit | `ghcr.io/playit-cloud/playit-agent:latest` | host network | none | — | `SECRET_KEY` written literally in compose. The only Playit agent since 2026-10-04; the duplicate host service is disabled ([why](../architecture/networking-and-security.md#24-game-traffic-via-playitgg)). |

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
| Minecraft world | mc-backup: RCON `save-off` → `save-all` → tar → `save-on`, so backups are consistent without stopping the server | `/mnt/tank/backups/minecraft` | Working. Verified 2026-09-26: newest archive has `world/level.dat` and all 59 region files |
| Terraria world | Root cron `0 4 * * *` tar of `/srv/games/terraria` | `/mnt/tank/backups/terraria` | Working (archives on 2026-09-25 and 09-26) |

Both backup folders are inside the same VM, so they don't protect against losing the VM. See [the roadmap](../roadmap/ROADMAP.md).

Restoring: [runbooks/disaster-recovery.md §3](../runbooks/disaster-recovery.md#3-per-service-data-recovery).

## The Sep 24–26 world mix-up (what happened, and how to avoid it)

- **2026-09-24, 13:31:** the server files were moved into a new `/srv/games/minecraft/data/` folder, and the compose volume was changed to match. The `world/` folder was left behind one level up. Minecraft found no world at 13:32 and **quietly generated a new one**. Players joined a different map.
- `mc-backup` still read the parent folder, so its archives held both worlds and nothing looked broken.
- **2026-09-26:** the original world (last saved 2026-09-24 13:18) was copied into `data/world`, and the server loaded it. `mc-backup` now reads `data/`. The old top-level files were archived and then deleted.
- **Safety copies** in `/mnt/tank/backups/minecraft-restore-2026-09-26/`: `original-world.tar.gz` and `old-toplevel-files-before-sep24.tar.gz`. They can be deleted once nobody needs them.

**When moving a game server's folder:** stop the server, copy the **whole** folder (check that `world/` or the `.wld` file came along), change the server's **and** the backup's paths together, start it, then check the log. It should say it is loading the existing world, and the world size should match.

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
