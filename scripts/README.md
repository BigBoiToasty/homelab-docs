# Scripts

Helper scripts for the homelab. Run them on VM 100 as root.

| Script | What it does | Changes anything? |
|---|---|---|
| [`audit-homelab.sh`](audit-homelab.sh) | Takes a full, redacted snapshot of the VM as Markdown, used to keep these docs accurate | No, read-only |
| [`add-site.sh`](add-site.sh) | Adds a new `https://<name>.example.com` site to the `nginx-proxy` container using the wildcard certificate | Yes: writes one nginx config file and reloads nginx (rolls back if the config is invalid) |

Related (installed on the VM, not in this repo): `/usr/local/bin/vnc-tailscale.sh` starts/stops the VNC desktop bound to the Tailscale IP ([maintenance runbook](../runbooks/maintenance.md#vnc-desktop-tailscale-only)); `/usr/local/bin/tailscale-watchdog.sh` restarts Tailscale if it hangs (cron, every 5 min).

## `audit-homelab.sh`

```bash
bash audit-homelab.sh > ~/audit.md                # normal (masked)
bash audit-homelab.sh --show-hosts > ~/audit.md   # real domains/IPs/usernames. Never share this one
```

**What the report covers:**

1. System overview: OS, CPU, RAM/swap, top processes, GPU, key versions, pending updates.
2. System services: docker, containerd, cloudflared, cron, certbot timers, tailscaled, ssh, qemu-guest-agent, and others.
3. Proxmox guest environment: hypervisor, guest agent service **and** its virtio channel, balloon driver, disks.
4. Storage: `df`, key mount points, which disk each container's data lives on, folder sizes, stack file layout.
5. Containers: status, health, restarts, memory limits, log settings, networks, mounts, compose definitions (allowlisted), images, volumes, `.env` file list (names only).
6. Networking: listening ports mapped to containers, interfaces, routes, nginx sites, certificates, Tailscale, firewall, Cloudflare Tunnel health.
7. Security: SSH settings, remote-desktop exposure, Docker socket mounts.
8. Automation: timers, cron jobs, custom systemd units, scripts.
9. Stability: OOM kills, failed units, kernel errors.

**Safety:**

- Never opens `.env` files, token files, certificates, keys or script contents.
- Compose files are read through an allowlist (image, ports, mounts, networks, limits, env var *names*).
- All output passes one redaction filter (passwords, tokens, API keys, JWTs, private keys, URL credentials, e-mails). If the filter fails, nothing is printed.
- Masking is on by default: domain → `example.com`; public, Tailscale and link-local IPs, MACs, UUIDs and login names are replaced.
- The report file is `chmod 600`, and the script warns if it would be saved inside a git repo. Report names (`audit.md`, `audit-*.md`, `*.audit.md`, `audits/`) are gitignored.
- It sees only the VM. Proxmox host facts (ZFS pools, `qm config 100`, backup jobs) must be checked on the host.

**Before committing doc changes**, check nothing identifying slipped in:

```bash
grep -rnE '<your-domain-label>|<your-username>|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' --include=*.md ~/homelab-docs
```

## `add-site.sh`

```bash
bash add-site.sh <name> <host-port> [--max-body 100M] [--domain example.com] [--dry-run]
```

It checks the name is free and the port is actually listening, writes `~/docker/reverse-proxy/conf.d/<name>.conf`, validates it with `nginx -t` (deleting it again if invalid), and reloads nginx. It does **not** create the DNS record; the step-by-step guide is in the [maintenance runbook](../runbooks/maintenance.md#add-a-new-website-tailnet-only).
