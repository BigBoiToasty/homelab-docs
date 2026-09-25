#!/usr/bin/env bash
#
# audit-homelab.sh — read-only snapshot of the Debian Docker VM, emitted as
# redacted Markdown that is safe to paste into an AI prompt or use as the
# source for the homelab docs.
#
# Usage:
#   bash audit-homelab.sh > /path/outside/repo/audit.md
#   bash audit-homelab.sh --show-hosts > audit.md   # keep real domains/IPs/users
#
# Environment overrides:
#   PROXY_CONF_DIR   nginx conf.d to parse     (default: ~/docker/reverse-proxy/conf.d)
#   DOCKER_ROOT      compose stacks root       (default: ~/docker)
#   DATA_ROOT        bulk data mount           (default: /mnt/tank)
#   PROXY_CONTAINER  nginx container name      (default: nginx-proxy)
#   CMD_TIMEOUT      per-command timeout, sec  (default: 20)
#
# Safety model:
#   * Never opens .env files, token files, certificates, keys, or script bodies.
#   * Compose definitions are read through an allowlist: environment VALUES,
#     commands, entrypoints, healthchecks and labels are never emitted.
#   * systemd ExecStart lines are never printed (they can carry tokens).
#   * ALL stdout passes through one redaction filter, fail-closed: if the
#     filter fails, nothing is printed.
#   * Host masking is ON by default: domains, public/tailnet/link-local IPs,
#     MACs, UUIDs, e-mail addresses and human usernames are replaced.
#   * If stdout is a file it is chmod 600, and a warning is printed when that
#     file would be tracked by git.
#
# The script only reads state; it changes nothing on the system.

set -uo pipefail

readonly SCRIPT_NAME=${0##*/}
readonly PROXY_CONF_DIR=${PROXY_CONF_DIR:-$HOME/docker/reverse-proxy/conf.d}
readonly DOCKER_ROOT=${DOCKER_ROOT:-$HOME/docker}
readonly DATA_ROOT=${DATA_ROOT:-/mnt/tank}
readonly PROXY_CONTAINER=${PROXY_CONTAINER:-nginx-proxy}
readonly CMD_TIMEOUT=${CMD_TIMEOUT:-20}

MASK_HOSTS=1
WARNINGS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
t()    { timeout --kill-after=5 "$CMD_TIMEOUT" "$@"; }
tl()   { timeout --kill-after=5 120 "$@"; }   # for slow commands (du, certbot)

usage() {
  sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'
}

h2()   { printf '\n## %s\n\n' "$*"; }
h3()   { printf '\n### %s\n\n' "$*"; }
note() { printf '> %s\n\n' "$*"; }

warn() {
  WARNINGS+=("$*")
  printf '> ⚠️ %s\n\n' "$*"
}

# block "Title" cmd [args...] — run a command, print its combined output in a
# fenced block, and record a warning on non-zero exit or timeout.
block() {
  local title=$1; shift
  local out rc cmd_label=$1
  [[ $cmd_label == t || $cmd_label == tl ]] && cmd_label=$2

  out=$("$@" 2>&1); rc=$?
  [[ -n $title ]] && h3 "$title"
  [[ -z $out ]] && out='(no output)'
  printf '```text\n%s\n```\n\n' "$out"

  if (( rc == 124 || rc == 137 )); then
    warn "\`$cmd_label\` timed out (${title:-untitled})"
  elif (( rc != 0 )); then
    warn "\`$cmd_label\` exited with status $rc (${title:-untitled})"
  fi
}

# Escape a value for use inside a Markdown table cell.
cell() { local s=${1//|/\\|}; printf '%s' "${s:--}"; }

docker_ok() { have docker && t docker info >/dev/null 2>&1; }

unit_exists() { systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .; }

# ---------------------------------------------------------------------------
# Redaction filter — the single choke point for everything on stdout.
# Runs on the whole document at once so multi-line PEM blocks are caught.
# ---------------------------------------------------------------------------

read -r -d '' REDACT_PL <<'PERL' || true
BEGIN {
  @domains = grep { length } split ' ', ($ENV{MASK_DOMAINS} // '');
  @users   = grep { length } split ' ', ($ENV{MASK_USERS} // '');
  $mask    = $ENV{MASK_HOSTS} // 1;
}

# Certificates and private keys (any PEM block).
s/-----BEGIN [A-Z0-9 ]+-----.*?-----END [A-Z0-9 ]+-----/[REDACTED PEM BLOCK]/gs;

# Raw env-file style lines (KEY=value at line start) are dropped entirely.
s/^[ \t]*(?:export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=[^\n]*$/[REDACTED ENV LINE]/gm;

# key=value / key: value pairs whose key looks sensitive
# (covers DASHBOARD_PASSWORD, *_SECRET, *_TOKEN, API keys, DSNs, conn strings).
s/([\w.-]*?(?:password|passwd|passphrase|pwd|secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key|service[_-]?key|anon[_-]?key|credential|auth[_-]?key|salt|dsn|database[_-]?url|db[_-]?url|conn(?:ection)?[_-]?string)[\w.-]*["']?[ \t]*[:=][ \t]*)("[^"\n]*"|'[^'\n]*'|[^\s,;&"']+)/$1\[REDACTED\]/gi;

# CLI flags carrying secrets: --token X, --password=X, ...
s/(--?(?:token|password|passwd|pass|secret|api-?key|auth-?key|credentials?)(?:=|[ \t]+))\S+/$1\[REDACTED\]/gi;

# Credentials embedded in URIs: scheme://user:pass@host
s{(\b[a-z][a-z0-9+.-]*://)[^\s/:@]+:[^\s@/]+@}{$1\[REDACTED\]@}gi;

# Authorization headers and bearer/basic tokens.
s/(authorization["']?[ \t]*[:=][ \t]*["']?)[^"'\n]+/$1\[REDACTED\]/gi;
s/\b(bearer|basic)([ \t]+)(?=[A-Za-z0-9._~+\/=-]*[0-9=])[A-Za-z0-9._~+\/=-]{8,}/$1$2\[REDACTED\]/gi;

# JWTs and base64-encoded JSON blobs (cloudflared tunnel tokens look like this).
s/\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*/[REDACTED_JWT]/g;
s/\beyJ[A-Za-z0-9+\/=_-]{30,}/[REDACTED_TOKEN]/g;

# Well-known key prefixes.
s/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|glpat-[\w-]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abposr]-[\w-]{10,}|AKIA[0-9A-Z]{16}|tskey-[\w-]+|AIza[\w-]{30,})/[REDACTED_KEY]/g;

# Image digests are public identifiers: shorten, don't redact.
s/\bsha256:([0-9a-f]{12})[0-9a-f]{52}\b/sha256:$1…/g;

# Any remaining long mixed alphanumeric string (likely a key). Path segments
# are exempt so filesystem paths stay readable.
s/(?<![\w\/.-])(?=[A-Za-z0-9+_-]*\d)(?=[A-Za-z0-9+_-]*[A-Za-z])[A-Za-z0-9+_-]{40,}={0,2}(?![\w\/.-])/[REDACTED_LONG_STRING]/g;

# E-mail addresses (always).
s/\b[\w.+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/[EMAIL]/g;

if ($mask) {
  my $i = 0;
  for my $d (@domains) {
    $i++;
    my $repl = $i == 1 ? 'example.com' : "example$i.com";
    s/\b\Q$d\E\b/$repl/gi;
    (my $label = $d) =~ s/\..*//;
    s/\b\Q$label\E\b/example$i/gi if length $label > 3;
  }
  $i = 0;
  for my $u (@users) {
    $i++;
    s/\b\Q$u\E\b/user$i/g;
  }

  # Identifiers: UUIDs (tunnel/connector IDs), MAC addresses.
  s/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/[UUID]/gi;
  s/\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/[MAC]/gi;

  # IPv6: global (public), tailnet ULA, other ULA, link-local (embeds the MAC).
  s/(?<![\w:])fd7a:115c:a1e0(?::[0-9a-f]{0,4}){1,6}(?![\w:])/[TAILNET_IP]/gi;
  s/(?<![\w:])f[cd][0-9a-f]{2}(?::[0-9a-f]{0,4}){2,7}(?![\w:])/[PRIVATE_IPV6]/gi;
  s/(?<![\w:])fe80:(?::[0-9a-f]{0,4}){1,7}(?:%\w+)?(?![\w:])/[LINK_LOCAL]/gi;
  s/(?<![\w:])[23][0-9a-f]{3}(?::[0-9a-f]{0,4}){2,7}(?![\w:])/[PUBLIC_IPV6]/gi;

  # IPv4: keep RFC1918/loopback/docker, mask tailnet (CGNAT) and public.
  s{(?<![\w.:])((\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3})(?![\d.])}{
    my ($ip, $a, $b) = ($1, $2, $3);
    ($a == 10 || $a == 127 || $a == 0 || ($a == 172 && $b >= 16 && $b <= 31)
      || ($a == 192 && $b == 168) || ($a == 169 && $b == 254) || $a >= 224) ? $ip
    : ($a == 100 && $b >= 64 && $b <= 127) ? '[TAILNET_IP]'
    : '[PUBLIC_IP]'
  }ge;
}
PERL

redact() {
  MASK_HOSTS=$MASK_HOSTS MASK_DOMAINS=${MASK_DOMAINS:-} MASK_USERS=${MASK_USERS:-} \
    perl -0777 -pe "$REDACT_PL"
}

# Registrable domains (last two labels) seen in nginx server_name directives.
collect_domains() {
  [[ -d $PROXY_CONF_DIR ]] || return 0
  cat "$PROXY_CONF_DIR"/*.conf 2>/dev/null \
    | sed -n 's/#.*//; s/^[[:space:]]*server_name[[:space:]]\{1,\}\([^;]*\);.*/\1/p' \
    | tr ' \t' '\n\n' \
    | sed 's/^\*\.//; s/^\.//' \
    | grep -E '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' \
    | grep -vE '^[0-9.]+$' \
    | awk -F. '{ print $(NF-1) "." $NF }' \
    | sort -u | tr '\n' ' '
}

# Human login accounts (UID 1000-65533).
collect_users() {
  awk -F: '$3 >= 1000 && $3 < 65534 { printf "%s ", $1 }' /etc/passwd
}

# ---------------------------------------------------------------------------
# 1. System overview
# ---------------------------------------------------------------------------

cpu_busy_pct() {
  local s1 s2
  s1=$(awk '/^cpu /{ print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }' /proc/stat)
  sleep 1
  s2=$(awk '/^cpu /{ print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }' /proc/stat)
  awk -v a="$s1" -v b="$s2" 'BEGIN {
    split(a, x, " "); split(b, y, " ")
    dt = y[1] - x[1]; di = y[2] - x[2]
    if (dt > 0) printf "%.1f%%", 100 * (dt - di) / dt; else print "n/a"
  }'
}

key_versions() {
  printf 'Docker Engine:   %s\n' "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo n/a)"
  printf 'Docker Compose:  %s\n' "$(docker compose version --short 2>/dev/null || echo n/a)"
  printf 'NVIDIA driver:   %s\n' "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo n/a)"
  printf 'NVIDIA toolkit:  %s\n' "$(dpkg-query -W -f='${Version}' nvidia-container-toolkit 2>/dev/null || echo n/a)"
  printf 'Tailscale:       %s\n' "$(tailscale version 2>/dev/null | head -n1 || echo n/a)"
  printf 'cloudflared:     %s\n' "$(cloudflared --version 2>/dev/null | awk '{print $3}' || echo n/a)"
  printf 'certbot:         %s\n' "$(certbot --version 2>/dev/null | awk '{print $2}' || echo n/a)"
  printf 'OpenSSH:         %s\n' "$(ssh -V 2>&1 | cut -d, -f1)"
  printf 'Pending apt upgrades (from local cache): %s\n' \
    "$(apt list --upgradable 2>/dev/null | grep -c '/' || true)"
  printf 'unattended-upgrades installed: %s\n' \
    "$(dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q 'install ok installed' && echo yes || echo no)"
}

section_system() {
  h2 "1. System Overview"

  local distro kernel up load cpu_model cores virt mem_line swap_line
  distro=$( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-unknown}" )
  kernel=$(uname -r)
  up=$(uptime -p 2>/dev/null || uptime)
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  cpu_model=$(awk -F': ' '/^model name/{ print $2; exit }' /proc/cpuinfo)
  cores=$(nproc 2>/dev/null || echo '?')
  virt=$(systemd-detect-virt 2>/dev/null || echo 'none/unknown')
  mem_line=$(free -h | awk '/^Mem:/{ printf "%s used / %s total (%s available)", $3, $2, $7 }')
  swap_line=$(free -h | awk '/^Swap:/{ printf "%s used / %s total", $3, $2 }')

  printf '| Item | Value |\n|---|---|\n'
  printf '| Hostname | %s |\n'        "$(cell "$(hostname)")"
  printf '| Distribution | %s |\n'    "$(cell "$distro")"
  printf '| Kernel | %s |\n'          "$(cell "$kernel")"
  printf '| Virtualization | %s |\n'  "$(cell "$virt")"
  printf '| Uptime | %s |\n'          "$(cell "$up")"
  printf '| CPU | %s × %s vCPU |\n'   "$(cell "$cpu_model")" "$cores"
  printf '| CPU busy (1 s sample) | %s |\n' "$(cpu_busy_pct)"
  printf '| Load average (1/5/15) | %s |\n' "$load"
  printf '| Memory | %s |\n'          "$(cell "$mem_line")"
  printf '| Swap | %s |\n'            "$(cell "$swap_line")"
  printf '\n'

  block "Key component versions" key_versions
  block "Memory and swap" free -h
  # comm (not args) so command-line secrets are never captured.
  block "Top processes by memory" \
    bash -c 'ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n 16'
  block "Top processes by CPU" \
    bash -c 'ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu | head -n 11'

  if have nvidia-smi; then
    block "GPU" t nvidia-smi \
      --query-gpu=name,driver_version,memory.used,memory.total,utilization.gpu,temperature.gpu \
      --format=csv
    block "GPU processes" t nvidia-smi \
      --query-compute-apps=pid,process_name,used_memory --format=csv
  fi
}

# ---------------------------------------------------------------------------
# System services
# ---------------------------------------------------------------------------

# One row per unit. Pass full unit names (foo.service, foo.timer).
service_rows() {
  local u state sub enabled since
  for u in "$@"; do
    if ! unit_exists "$u"; then
      printf '| %s | not installed | - | - | - |\n' "$u"
      continue
    fi
    state=$(systemctl show -p ActiveState --value "$u" 2>/dev/null)
    sub=$(systemctl show -p SubState --value "$u" 2>/dev/null)
    enabled=$(systemctl is-enabled "$u" 2>/dev/null)
    since=$(systemctl show -p ActiveEnterTimestamp --value "$u" 2>/dev/null)
    printf '| %s | %s | %s | %s | %s |\n' "$u" "${state:--}" "${sub:--}" "${enabled:--}" "$(cell "$since")"
  done
}

section_services() {
  h2 "2. System Services"

  h3 "Core services (expected active)"
  printf '| Unit | Active | Sub-state | Enabled | Active since |\n|---|---|---|---|---|\n'
  local core=(docker.service containerd.service cloudflared.service cron.service
              certbot.timer snap.certbot.renew.timer tailscaled.service ssh.service
              qemu-guest-agent.service)
  service_rows "${core[@]}"
  printf '\n'

  local u down=()
  for u in "${core[@]}"; do
    unit_exists "$u" || continue
    [[ $(systemctl is-active "$u" 2>/dev/null) == active ]] || down+=("$u")
  done
  if (( ${#down[@]} )); then
    warn "Core units not active: ${down[*]}"
  else
    note "All installed core units are active."
  fi

  h3 "Other services of interest"
  printf '| Unit | Active | Sub-state | Enabled | Active since |\n|---|---|---|---|---|\n'
  service_rows nginx.service playit.service fail2ban.service x11vnc.service display-manager.service \
               avahi-daemon.service rpcbind.service nvidia-persistenced.service \
               unattended-upgrades.service cloudflared-update.timer
  printf '\n'
}

# ---------------------------------------------------------------------------
# Proxmox / guest environment
# ---------------------------------------------------------------------------

guest_environment() {
  local virt vendor product agent_active agent_enabled channel balloon
  virt=$(systemd-detect-virt 2>/dev/null || echo none)
  vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)
  product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
  agent_active=$(systemctl is-active qemu-guest-agent 2>/dev/null)
  agent_enabled=$(systemctl is-enabled qemu-guest-agent 2>/dev/null)
  if [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
    channel="present (Proxmox has agent: 1)"
  else
    channel="absent (Proxmox VM option 'QEMU Guest Agent' is off)"
  fi
  lsmod 2>/dev/null | grep -q '^virtio_balloon' && balloon=loaded || balloon="not loaded"

  printf '| Item | Value |\n|---|---|\n'
  printf '| Hypervisor type | %s |\n'              "$(cell "$virt")"
  printf '| Machine (DMI) | %s / %s |\n'          "$(cell "$vendor")" "$(cell "$product")"
  printf '| vCPU model | %s |\n'                   "$(cell "$(awk -F': ' '/^model name/{ print $2; exit }' /proc/cpuinfo)")"
  printf '| qemu-guest-agent service | %s / %s |\n' "${agent_active:-not installed}" "${agent_enabled:--}"
  printf '| Guest agent virtio channel | %s |\n'   "$channel"
  printf '| Memory balloon driver | %s |\n'        "$balloon"
  printf '| Disk transport | %s |\n' \
    "$(cell "$(lsblk -dno NAME,TRAN,MODEL -e 7,11 2>/dev/null | awk '{ $1 = $1; printf "%s%s", sep, $0; sep = "; " }')")"
  printf '\n'

  if [[ $virt == kvm && $vendor == QEMU ]]; then
    note "Running as a KVM/QEMU guest, consistent with a Proxmox VE virtual machine."
  fi
  if [[ $agent_active != active || $channel == absent* ]]; then
    warn "QEMU guest agent is not fully working (service: ${agent_active:-missing}; channel: ${channel%% *}). Proxmox backups will be crash-consistent, and the host cannot read guest IPs. Fix both sides: \`qm set <vmid> --agent 1\` on the host (needs a VM stop/start), then \`systemctl enable --now qemu-guest-agent\` in the guest."
  fi
}

section_guest() {
  h2 "3. Proxmox Guest Environment"
  guest_environment
}

# ---------------------------------------------------------------------------
# 4. Storage
# ---------------------------------------------------------------------------

# Filesystem backing each key path (Docker root, data mounts, stack dirs).
key_mounts() {
  local p paths=(/ /var/lib/docker /srv /docker "$DOCKER_ROOT")
  shopt -s nullglob
  paths+=(/mnt/*/)
  shopt -u nullglob
  printf '| Path | Mount point | Device | FS | Size | Used | Avail | Use%% |\n|---|---|---|---|---|---|---|---|\n'
  for p in "${paths[@]}"; do
    [[ -e $p ]] || continue
    [[ $p == / ]] || p=${p%/}
    df -h --output=target,source,fstype,size,used,avail,pcent "$p" 2>/dev/null | tail -n +2 \
      | awk -v p="$p" '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s |\n", p, $1, $2, $3, $4, $5, $6, $7 }'
  done
  printf '\n'
}

# Which filesystem each container's persistent data lands on.
container_data_locations() {
  printf '| Container | Host path (bind or volume) | Type | Lives on mount | Device |\n|---|---|---|---|---|\n'
  local name type src mnt dev
  # shellcheck disable=SC2046
  t docker inspect --format '{{.Name}}{{range .Mounts}}	{{.Type}}|{{.Source}}{{end}}' $(t docker ps -q) 2>/dev/null \
  | while IFS=$'\t' read -r name rest; do
      name=${name#/}
      IFS=$'\t' read -r -a mounts <<<"$rest"
      for m in "${mounts[@]}"; do
        type=${m%%|*}; src=${m#*|}
        case $src in /etc/localtime|/var/run/docker.sock|/|'') continue ;; esac
        read -r mnt dev < <(df --output=target,source "$src" 2>/dev/null | tail -n1)
        printf '| %s | %s | %s | %s | %s |\n' "$name" "$(cell "$src")" "$type" "${mnt:-?}" "${dev:-?}"
      done
    done | sort
  printf '\n'
}

section_storage() {
  h2 "4. Storage"

  block "Filesystems (df -hT)" \
    df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs
  h3 "Key mount points (Docker root, data disks, stack directories)"
  key_mounts
  block "Block devices" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT -e 7
  block "Persistent mounts (/etc/fstab, comments stripped)" \
    bash -c "grep -vE '^[[:space:]]*(#|\$)' /etc/fstab | sed -E 's/^(UUID|PARTUUID|LABEL)=[^[:space:]]+/<by-\\1>/'"
  block "Network and non-root data mounts" \
    findmnt -rn -t nfs,nfs4,cifs,smb3,zfs,ext4,xfs,btrfs -o TARGET,SOURCE,FSTYPE,OPTIONS

  if have zpool; then
    block "ZFS pools" t zpool list
    block "ZFS pool health" t zpool status -x
    block "ZFS datasets" t zfs list -o name,used,avail,refer,compressratio,mountpoint
  else
    note "ZFS tools are not installed in this guest. The pools (fastpool / hddpool) live on the Proxmox host; run \`zpool list\` and \`zfs list\` there for pool-level data."
  fi

  local dirs=()
  shopt -s nullglob
  [[ -d $DOCKER_ROOT ]] && dirs+=("$DOCKER_ROOT"/*/)
  [[ -d $DATA_ROOT ]]   && dirs+=("$DATA_ROOT"/*/)
  [[ -d /docker ]]      && dirs+=(/docker/*/)
  [[ -d /srv ]]         && dirs+=(/srv/*/)
  shopt -u nullglob
  if (( ${#dirs[@]} )); then
    block "Directory sizes (stacks, data, /docker, /srv)" \
      bash -c 'timeout 120 du -xsh "$@" 2>/dev/null | sort -rh' _ "${dirs[@]}"
  fi

  if docker_ok; then
    h3 "Where container data lives (each bind mount / volume → filesystem)"
    note "Use this to see which disk holds each stack's persistent state (e.g. Immich library vs. its Postgres, Supabase volumes)."
    container_data_locations
  fi

  if [[ -d $DOCKER_ROOT ]]; then
    block "Stack layout under $DOCKER_ROOT (compose, scripts, configs; names only)" \
      bash -c 'find "$1" -maxdepth 3 \( -name ".git" -o -name "node_modules" -o -name "volumes" -o -name "data" -o -name "db" \) -prune -o \
                 -type f \( -name "*compose*.y*ml" -o -name "*.sh" -o -name "Dockerfile" -o -name "*.conf" -o -name "*.toml" -o -name "*.yml" -o -name "*.yaml" \) \
                 -printf "%P\n" 2>/dev/null | sort' _ "$DOCKER_ROOT"
  fi
}

# ---------------------------------------------------------------------------
# 5. Container audit
# ---------------------------------------------------------------------------

# Compose service definitions through an allowlist (no env values, commands,
# entrypoints, healthchecks, labels or secrets).
read -r -d '' COMPOSE_JQ <<'JQ' || true
def human: (tonumber? // null) as $n
  | if $n == null then tostring
    elif $n >= 1073741824 then "\(($n / 1073741824 * 10 | floor) / 10) GiB"
    else "\($n / 1048576 | floor) MiB" end;
def esc: tostring | gsub("\\|"; "\\|");
.services | to_entries[] | .key as $svc | .value as $s |
[
  $svc,
  ($s.container_name // "-"),
  ($s.image // ("build: " + (($s.build.context // "?") | tostring))),
  ([ $s.ports[]? | "\(.host_ip // "0.0.0.0"):\(.published // "-")→\(.target)/\(.protocol // "tcp")" ] | join("<br>")),
  (if $s.network_mode then "mode: " + $s.network_mode
   else ([ ($s.networks // {}) | keys[] ] | join(", ")) end),
  ([ ($s.depends_on // {}) | keys[] ] | join(", ")),
  ($s.restart // "-"),
  (($s.deploy.resources.limits.memory // $s.mem_limit // "-") | human),
  ([ (if $s.privileged then "privileged" else empty end),
     ($s.cap_add[]? | "cap:" + .),
     ($s.devices[]? | "dev:" + ((.source // .) | tostring)),
     (if ($s.deploy.resources.reservations.devices // $s.gpus) then "gpu" else empty end),
     (if $s.env_file then "env_file" else empty end) ] | join(", ")),
  (($s.environment // {}) | keys | length | tostring)
] | map(if . == "" then "-" else esc end) | "| " + join(" | ") + " |"
JQ

compose_definitions() {
  have jq || { warn "jq not installed; compose definitions skipped."; return; }
  local projects name files json args f
  projects=$(t docker compose ls -a --format json 2>/dev/null | jq -r '.[] | "\(.Name)\t\(.ConfigFiles)"')
  [[ -z $projects ]] && { note "No compose projects found."; return; }

  while IFS=$'\t' read -r name files; do
    h3 "Compose project \`$name\`"
    printf 'Files: `%s`\n\n' "$files"
    args=()
    IFS=',' read -r -a f <<<"$files"
    for files in "${f[@]}"; do args+=(-f "$files"); done

    if ! json=$(t docker compose -p "$name" "${args[@]}" config --format json 2>/dev/null); then
      warn "could not render compose config for \`$name\`."
      continue
    fi
    printf '| Service | Container | Image | Published ports | Networks | Depends on | Restart | Mem limit | Extras | Env vars |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|\n'
    jq -r "$COMPOSE_JQ" <<<"$json"
    printf '\n'

    # Variable NAMES only, so the docs can list the config surface.
    jq -r '.services | to_entries[] | select((.value.environment // {}) | length > 0)
           | "- `\(.key)` env keys: " + ((.value.environment | keys) | join(", "))' <<<"$json"
    local ext
    ext=$(jq -r '[(.networks // {}) | to_entries[] | select(.value.external) | .value.name // .key] | join(", ")' <<<"$json")
    [[ -n $ext ]] && printf -- '- External networks: %s\n' "$ext"
    printf '\n'
  done <<<"$projects"
}

runtime_wiring() {
  printf '| Container | Network mode / networks | GPU | Mounts (source → target) |\n'
  printf '|---|---|---|---|\n'
  # shellcheck disable=SC2046  # word-splitting of container IDs is intended
  t docker inspect --format \
    '{{.Name}}	{{.HostConfig.NetworkMode}}	{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}	{{if .HostConfig.DeviceRequests}}yes{{else}}-{{end}}	{{range .Mounts}}{{.Type}}:{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}} → {{.Destination}}{{if not .RW}} (ro){{end}};;{{end}}' \
    $(t docker ps -aq) 2>/dev/null \
  | awk -F'\t' -v ids="$(t docker ps -a --no-trunc --format '{{.ID}}={{.Names}}' | tr '\n' ' ')" '
    BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); name[kv[1]] = kv[2] } }
    {
      if ($2 ~ /^container:/) { id = substr($2, 11); if (id in name) $2 = "container:" name[id] }
      sub(/^\//, "", $1); gsub(/\|/, "\\|")
      m = $5; sub(/;;$/, "", m); gsub(/;;/, "<br>", m); if (m == "") m = "-"
      n = $3; sub(/ +$/, "", n)
      if (n == "" || n == $2) n = $2; else if ($2 != "default" && $2 !~ /_default$/ && index(n, $2) == 0) n = $2 " (" n ")"
      printf "| %s | %s | %s | %s |\n", $1, n, $4, m }' \
  | sort
  printf '\n'
}

section_docker() {
  h2 "5. Container Audit"

  if ! have docker; then warn "Docker CLI not found; container audit skipped."; return; fi
  if ! docker_ok; then warn "Docker daemon unreachable (not running, or no permission); container audit skipped."; return; fi

  block "Engine summary" t docker info --format \
    'Server version: {{.ServerVersion}}
Storage driver:  {{.Driver}}
Docker root:     {{.DockerRootDir}}
Containers:      {{.Containers}} total, {{.ContainersRunning}} running, {{.ContainersPaused}} paused, {{.ContainersStopped}} stopped
Images:          {{.Images}}
Logging driver:  {{.LoggingDriver}}
Cgroup driver:   {{.CgroupDriver}}
Runtimes:        {{range $k, $v := .Runtimes}}{{$k}} {{end}}
Default runtime: {{.DefaultRuntime}}'

  if [[ -r /etc/docker/daemon.json ]]; then
    block "Daemon config (/etc/docker/daemon.json)" cat /etc/docker/daemon.json
  else
    note "No /etc/docker/daemon.json: default json-file logging with **no log rotation**."
  fi

  block "Containers (running and stopped)" t docker ps -a \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

  h3 "Container health, restart policy and memory limits"
  printf '| Container | Restart policy | Restarts | Health | OOM-killed | Memory limit | Log driver / max-size |\n'
  printf '|---|---|---|---|---|---|---|\n'
  # shellcheck disable=SC2046
  t docker inspect --format \
    '{{.Name}}	{{.HostConfig.RestartPolicy.Name}}	{{.RestartCount}}	{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}	{{.State.OOMKilled}}	{{.HostConfig.Memory}}	{{.HostConfig.LogConfig.Type}} / {{index .HostConfig.LogConfig.Config "max-size"}}' \
    $(t docker ps -aq) 2>/dev/null \
  | awk -F'\t' '
      function human(b) {
        if (b == 0) return "unlimited"
        if (b >= 1073741824) return sprintf("%.1f GiB", b / 1073741824)
        return sprintf("%d MiB", b / 1048576)
      }
      { sub(/^\//, "", $1); sub(/ \/ (<no value>)?$/, " / none", $7); gsub(/\|/, "\\|")
        printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, ($2 == "" ? "no" : $2), $3, $4, $5, human($6), $7 }' \
  | sort
  printf '\n'

  h3 "Runtime wiring: networks, GPU and mounts"
  runtime_wiring

  block "Live resource usage" t docker stats --no-stream \
    --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}'

  if t docker compose version >/dev/null 2>&1; then
    block "Compose projects" t docker compose ls -a
    compose_definitions
  fi

  block "Images" t docker images \
    --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
  block "Docker disk usage" t docker system df
  block "Named volumes" t docker volume ls --format 'table {{.Name}}\t{{.Driver}}'

  h3 "Docker networks"
  printf '| Network | Driver | Scope | Subnet(s) | Attached containers |\n'
  printf '|---|---|---|---|---|\n'
  local net
  while IFS= read -r net; do
    [[ -z $net ]] && continue
    t docker network inspect --format \
      '{{.Name}}	{{.Driver}}	{{.Scope}}	{{range .IPAM.Config}}{{.Subnet}} {{end}}	{{range .Containers}}{{.Name}} {{end}}' \
      "$net" 2>/dev/null
  done < <(t docker network ls -q) \
  | awk -F'\t' '{ gsub(/\|/, "\\|"); for (i = 1; i <= 5; i++) { sub(/ +$/, "", $i); if ($i == "") $i = "-" }
                 printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5 }' \
  | sort
  printf '\n'

  h3 "Environment files (contents never read)"
  local envs stack_dirs=()
  [[ -d $DOCKER_ROOT ]] && stack_dirs+=("$DOCKER_ROOT")
  if have jq; then
    while IFS= read -r f; do
      [[ -n $f ]] && stack_dirs+=("${f%/*}")
    done < <(t docker compose ls -a --format json 2>/dev/null | jq -r '.[].ConfigFiles' | tr ',' '\n')
  fi
  (( ${#stack_dirs[@]} )) || { note "No stack directories found."; return; }
  envs=$(find "${stack_dirs[@]}" -maxdepth 4 -type f \( -name '.env' -o -name '*.env' -o -name '.env.*' \) \
           -printf '%p\t%s bytes\t%m\n' 2>/dev/null | sort -u)
  if [[ -n $envs ]]; then
    printf '| File | Size | Mode |\n|---|---|---|\n'
    awk -F'\t' '{ printf "| %s | %s | %s |\n", $1, $2, $3 }' <<<"$envs"
    printf '\n'
    note "Values intentionally omitted. Modes wider than 600 let other local users read secrets."
  else
    note "No .env files found."
  fi
}

# ---------------------------------------------------------------------------
# 6. Networking and reverse proxy
# ---------------------------------------------------------------------------

# Emits one Markdown table row per nginx `server { }` block.
parse_nginx_conf() {
  awk '
    function flush() {
      gsub(/\|/, "\\|", names); gsub(/\|/, "\\|", listens); gsub(/\|/, "\\|", routes)
      printf "| %s | %s | %s | %s |\n", file, (names ? names : "-"), (listens ? listens : "-"), (routes ? routes : "-")
    }
    function directive(line, key,    v) {
      v = line
      sub("^[ \t]*" key "[ \t]+", "", v); sub(/[ \t]*;.*$/, "", v)
      return v
    }
    FNR == 1 { file = FILENAME; sub(/.*\//, "", file) }
    {
      line = $0; sub(/#.*/, "", line)
      if (!in_srv && line ~ /^[ \t]*server[ \t]*\{/) {
        in_srv = 1; depth = 0; names = ""; listens = ""; routes = ""; loc = ""
      }
      if (!in_srv) next

      if (line ~ /^[ \t]*server_name[ \t]/) names   = names   (names   ? " " : "")    directive(line, "server_name")
      if (line ~ /^[ \t]*listen[ \t]/)      listens = listens (listens ? ", " : "")   directive(line, "listen")
      if (line ~ /^[ \t]*location[ \t]/) {
        loc = line; sub(/^[ \t]*location[ \t]+/, "", loc); sub(/[ \t]*\{.*$/, "", loc)
      }
      if (line ~ /^[ \t]*proxy_pass[ \t]/)
        routes = routes (routes ? "<br>" : "") (loc ? loc : "/") " → " directive(line, "proxy_pass")
      if (line ~ /^[ \t]*return[ \t]+30[1278]/)
        routes = routes (routes ? "<br>" : "") (loc ? loc : "*") " → redirect " directive(line, "return")

      opens = gsub(/\{/, "{", line); closes = gsub(/\}/, "}", line)
      depth += opens - closes
      if (closes > 0 && depth <= 1) loc = ""
      if (closes > 0 && depth <= 0) { flush(); in_srv = 0 }
    }
  ' "$@"
}

# Compact listening-socket table: one row per port/owner, docker-proxy
# resolved to the container behind it, ephemeral client sockets collapsed.
listening_table() {
  printf '| Port | Proto | Owner | Bound to |\n|---|---|---|---|\n'
  awk -F'\t' '
    FNR == NR {
      m = split($2, ps, ", ")
      for (j = 1; j <= m; j++) if (ps[j] ~ /->/) {
        hp = ps[j]; sub(/->.*/, "", hp); sub(/.*:/, "", hp)
        cp = ps[j]; sub(/.*->/, "", cp)
        pr = cp; sub(/.*\//, "", pr); sub(/\/.*/, "", cp)
        owner[pr SUBSEP hp] = $1 ":" cp
      }
      next
    }
    {
      split($0, s, " "); proto = s[1]; addr = s[5]
      port = addr; sub(/.*:/, "", port)
      host = addr; sub(/:[^:]*$/, "", host)
      proc = "?"
      if (match($0, /users:\(\("[^"]+"/)) proc = substr($0, RSTART + 9, RLENGTH - 10)

      if (host ~ /^(224\.|\[ff)/) next                          # multicast (mDNS)
      if (proto == "udp" && port + 0 >= 32768 && proc != "docker-proxy") { eph[proc]++; next }

      if (host ~ /^(0\.0\.0\.0|\*|\[::\])$/)  bnd = "all interfaces"
      else if (host ~ /^(127\.|\[::1\])/)      bnd = "localhost only"
      else if (host ~ /^(100\.|\[fd7a:)/)      bnd = "tailnet only"
      else                                     bnd = host

      what = proc
      if (proc == "docker-proxy" && ((proto SUBSEP port) in owner)) what = "container " owner[proto SUBSEP port]

      k = port SUBSEP proto SUBSEP what
      if (!(k in seen)) { seen[k] = bnd; order[++nk] = k }
      else if (index(seen[k], bnd) == 0) seen[k] = seen[k] ", " bnd
    }
    END {
      for (i = 1; i <= nk; i++) {
        split(order[i], a, SUBSEP)
        printf "| %s | %s | %s | %s |\n", a[1], a[2], a[3], seen[order[i]]
      }
      for (p in eph) printf "| 32768+ | udp | %s ×%d | ephemeral client sockets |\n", p, eph[p]
    }
  ' <(t docker ps --format '{{.Names}}	{{.Ports}}' 2>/dev/null) <(ss -Htulpn 2>/dev/null) \
  | sort -t'|' -k2,2n -k3,3
  printf '\n'
}

tailscale_summary() {
  local js
  js=$(t tailscale status --json 2>/dev/null) || { echo "tailscale status unavailable"; return 1; }
  # Allowlist only: no tailnet name, user, DNS suffix, peer names or keys.
  jq -r '
    "Backend state:   \(.BackendState)",
    "Version:         \(.Version)",
    "Self online:     \(.Self.Online)",
    "Tailscale IPs:   \((.TailscaleIPs // []) | join(", "))",
    "Peers:           \((.Peer // {}) | length) total, \([(.Peer // {})[] | select(.Online)] | length) online",
    "Exit node used:  \(if ([(.Peer // {})[] | select(.ExitNode)] | length) > 0 then "yes" else "no" end)",
    "Offers exit node: \(.Self.ExitNodeOption // false)",
    "Health warnings: \(if ((.Health // []) | length) == 0 then "none" else (.Health | join("; ")) end)"
  ' <<<"$js"
  printf 'Serve/Funnel:    %s\n' "$(t tailscale serve status 2>&1 | head -n 5 | tr '\n' ' ')"
}

firewall_summary() {
  if have ufw; then ufw status verbose 2>&1; echo; fi
  if have iptables; then
    printf 'iptables INPUT policy: %s\n' "$(iptables -S INPUT 2>/dev/null | awk '/^-P/{ print $3 }')"
    printf 'iptables INPUT rules:  %s\n' "$(iptables -S INPUT 2>/dev/null | grep -c '^-A' || true)"
    printf 'DOCKER-USER rules:\n'
    iptables -S DOCKER-USER 2>/dev/null | sed 's/^/  /'
  fi
  if have nft; then
    printf 'nftables tables: %s\n' "$(nft list tables 2>/dev/null | tr '\n' ' ')"
  fi
}

certbot_summary() {
  tl certbot certificates 2>/dev/null \
    | grep -E 'Certificate Name|Domains|Expiry Date' \
    | sed 's/^[[:space:]]*//'
}

cloudflared_ready() {
  local addr found=0
  while IFS= read -r addr; do
    [[ -z $addr ]] && continue
    found=1
    printf '%s/ready -> ' "$addr"
    t curl -fsS --max-time 3 "http://$addr/ready" 2>&1 || true
    printf '\n'
  done < <(ss -Htlnp 2>/dev/null | awk '/"cloudflared"/{ print $4 }' | sed 's/^\*:/127.0.0.1:/')
  (( found )) || echo 'No cloudflared metrics listener found (start it with --metrics to enable /ready).'
}

section_cloudflared() {
  h3 "Cloudflare Tunnel (cloudflared)"
  if ! have cloudflared && ! unit_exists 'cloudflared*'; then
    note "cloudflared is not installed on this VM."
    return
  fi

  local cf_ver cf_state cf_since cf_restarts cf_exec cf_mode
  cf_ver=$(t cloudflared --version 2>/dev/null | head -n1)
  cf_state=$(systemctl is-active cloudflared 2>/dev/null)
  cf_since=$(systemctl show -p ActiveEnterTimestamp --value cloudflared 2>/dev/null)
  cf_restarts=$(systemctl show -p NRestarts --value cloudflared 2>/dev/null)
  # ExecStart usually carries the tunnel token: only classify it, never print it.
  cf_exec=$(systemctl show -p ExecStart --value cloudflared 2>/dev/null)
  case $cf_exec in
    *--token-file*) cf_mode="remotely managed (token file)" ;;
    *--token*)      cf_mode="remotely managed (token on command line: consider --token-file)" ;;
    *--config*|*config.y*ml*) cf_mode="locally managed (config file)" ;;
    '')             cf_mode="unknown (no systemd unit)" ;;
    *)              cf_mode="default config lookup" ;;
  esac

  printf '| Item | Value |\n|---|---|\n'
  printf '| Version | %s |\n'        "$(cell "$cf_ver")"
  printf '| Service state | %s |\n'  "$(cell "$cf_state")"
  printf '| Active since | %s |\n'   "$(cell "$cf_since")"
  printf '| Restarts (systemd) | %s |\n' "$(cell "$cf_restarts")"
  printf '| Tunnel mode | %s |\n'    "$(cell "$cf_mode")"
  printf '| Ingress rules | %s |\n'  "$( [[ $cf_mode == remotely* ]] && echo 'managed in the Cloudflare dashboard (not visible locally)' || echo 'see config file below')"
  printf '\n'

  [[ $cf_state == active ]] || warn "cloudflared service is \`${cf_state:-unknown}\`."

  local cfg
  for cfg in /etc/cloudflared/config.yml /etc/cloudflared/config.yaml "$HOME/.cloudflared/config.yml"; do
    if [[ -r $cfg ]]; then
      block "Ingress rules ($cfg — hostname/service lines only)" \
        grep -E '^[[:space:]-]*(hostname|service|path):' "$cfg"
      break
    fi
  done

  block "Tunnel readiness (metrics endpoint)" cloudflared_ready
  if have journalctl; then
    block "cloudflared errors/reconnects in the last 24 h (count by message)" \
      bash -c 'journalctl -u cloudflared --since "24 hours ago" --no-pager -o cat 2>/dev/null \
               | grep -E " (ERR|WRN) " | sed -E "s/^[^ ]+ (ERR|WRN) /\1 /; s/ (connIndex|event|ip|connection)=.*//" \
               | sort | uniq -c | sort -rn | head -n 10'
  fi
}

section_network() {
  h2 "6. Networking & Reverse Proxy"

  h3 "Listening ports (from ss -tulpn, de-duplicated)"
  (( EUID == 0 )) || note "Not running as root: process owners may be missing."
  listening_table

  block "Network interfaces (container veths omitted)" \
    bash -c 'ip -brief address | grep -v "^veth"'
  block "Routes" ip route

  h3 "Reverse proxy virtual hosts"
  local confs=()
  if [[ -d $PROXY_CONF_DIR ]]; then
    shopt -s nullglob
    confs=("$PROXY_CONF_DIR"/*.conf)
    shopt -u nullglob
  fi
  if (( ${#confs[@]} )); then
    note "Parsed from \`$PROXY_CONF_DIR\` (${#confs[@]} files). Certificate paths and headers are not extracted."
    printf '| File | server_name | listen | location → upstream |\n|---|---|---|---|\n'
    parse_nginx_conf "${confs[@]}"
    printf '\n'
  else
    warn "No .conf files found in \`$PROXY_CONF_DIR\`."
  fi

  if docker_ok && t docker ps --format '{{.Names}}' | grep -qx "$PROXY_CONTAINER"; then
    block "nginx config test (\`$PROXY_CONTAINER\`)" t docker exec "$PROXY_CONTAINER" nginx -t
  fi

  if have certbot; then
    block "TLS certificates (certbot: names, domains, expiry only)" certbot_summary
  fi

  if have tailscale && have jq; then
    block "Tailscale (allowlisted fields only)" tailscale_summary
  fi

  block "Firewall" firewall_summary

  section_cloudflared
}

# ---------------------------------------------------------------------------
# 7. Security posture
# ---------------------------------------------------------------------------

ssh_posture() {
  sshd -T 2>/dev/null | grep -iE '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|x11forwarding|allowusers|allowgroups|maxauthtries) '
  local f n
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [[ -f $f ]] || continue
    n=$(grep -cvE '^[[:space:]]*(#|$)' "$f" || true)
    printf 'authorized_keys %s: %s key(s)\n' "$f" "$n"
  done
  compgen -G '/root/.ssh/authorized_keys' >/dev/null || echo 'authorized_keys /root/.ssh: none'
}

security_checks() {
  local vnc sock
  vnc=$(ss -Htlnp 2>/dev/null | awk '/"x11vnc"|"websockify"|"Xvnc"/{ print $4, $6 }' | sed -E 's/,pid=[0-9]+,fd=[0-9]+//g')
  printf 'Remote desktop listeners:\n%s\n\n' "${vnc:-  none}"
  if pgrep -x x11vnc >/dev/null; then
    if tr '\0' ' ' < "/proc/$(pgrep -xo x11vnc)/cmdline" 2>/dev/null | grep -q -- '-nopw'; then
      echo 'x11vnc: running WITHOUT a password (-nopw)'
    else
      echo 'x11vnc: running (password option present)'
    fi
  fi
  if docker_ok; then
    # shellcheck disable=SC2046
    sock=$(t docker inspect --format '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}' $(t docker ps -q) 2>/dev/null \
           | awk '/docker\.sock/{ sub(/^\//, "", $1); printf "%s ", $1 }')
    printf 'Containers with the Docker socket mounted: %s\n' "${sock:-none}"
    # shellcheck disable=SC2046
    printf 'Privileged containers: %s\n' "$(t docker inspect --format '{{.Name}} {{.HostConfig.Privileged}}' $(t docker ps -q) 2>/dev/null \
           | awk '$2 == "true" { sub(/^\//, "", $1); printf "%s ", $1 }')"
  fi
  printf 'Sudo/admin group members: %s\n' "$(getent group sudo | cut -d: -f4)"
  printf 'Root password set: %s\n' "$(passwd -S root 2>/dev/null | awk '{ print ($2 == "P" ? "yes" : "no/locked") }')"
}

section_security() {
  h2 "7. Security Posture"
  block "SSH daemon (effective settings)" ssh_posture
  block "Exposure checks" security_checks
}

# ---------------------------------------------------------------------------
# 8. Automation: timers, cron, custom units, scripts
# ---------------------------------------------------------------------------

custom_units() {
  printf '| Unit | Description | Active | Enabled |\n|---|---|---|---|\n'
  local f u
  for f in /etc/systemd/system/*.service /etc/systemd/system/*.timer; do
    [[ -f $f && ! -L $f ]] || continue
    u=${f##*/}
    printf '| %s | %s | %s | %s |\n' "$u" \
      "$(cell "$(systemctl show -p Description --value "$u" 2>/dev/null)")" \
      "$(systemctl is-active "$u" 2>/dev/null)" "$(systemctl is-enabled "$u" 2>/dev/null)"
  done
  printf '\n'
}

cron_jobs() {
  local u f
  for u in root $(collect_users); do
    if crontab -l -u "$u" >/dev/null 2>&1; then
      printf '# crontab (%s)\n' "$u"
      crontab -l -u "$u" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)'
    fi
  done
  for f in /etc/cron.d/*; do
    [[ -f $f ]] || continue
    printf '# %s\n' "$f"
    grep -vE '^[[:space:]]*(#|$)' "$f"
  done
}

scripts_inventory() {
  local d
  for d in /usr/local/bin /usr/local/sbin /root/scripts /root/bin "$DOCKER_ROOT"; do
    [[ -d $d ]] || continue
    find "$d" -maxdepth 1 -type f \( -perm -u+x -o -name '*.sh' \) \
      -printf '%p\t%s bytes\tmodified %TY-%Tm-%Td\n' 2>/dev/null
  done | sort
}

section_automation() {
  h2 "8. Automation & Scheduled Jobs"
  block "systemd timers" systemctl list-timers --all --no-pager
  h3 "Locally defined systemd units (/etc/systemd/system; ExecStart hidden)"
  custom_units
  block "Cron jobs (redacted)" cron_jobs
  block "Custom scripts (names only; contents not read)" scripts_inventory
}

# ---------------------------------------------------------------------------
# 9. Stability signals
# ---------------------------------------------------------------------------

oom_events() {
  local n
  n=$(journalctl -k -b --no-pager -o cat 2>/dev/null | grep -ciE 'out of memory|oom-kill|killed process' || true)
  printf 'Kernel OOM events this boot: %s\n' "$n"
  journalctl -k -b --no-pager -o short-iso 2>/dev/null \
    | grep -iE 'killed process' | tail -n 8 \
    | sed -E 's/(Killed process [0-9]+ \([^)]+\)).*/\1/' || true
}

section_stability() {
  h2 "9. Stability Signals"
  block "OOM kills" oom_events
  block "Failed systemd units" systemctl --failed --no-pager --no-legend
  block "Error-level journal messages this boot (top 15 by message)" \
    bash -c 'journalctl -b -p err --no-pager -o cat 2>/dev/null \
             | sed -E "s/[0-9]+/N/g" | sort | uniq -c | sort -rn | head -n 15'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

section_footer() {
  h2 "Audit Notes"
  printf -- '- Generated by `%s` at %s.\n' "$SCRIPT_NAME" "$(date -Is)"
  printf -- '- Scope: this Docker VM only. Proxmox host state (ZFS pools, VM config, vzdump jobs) must be collected on the host.\n'
  printf -- '- Redaction: PEM blocks, env-style lines, password/secret/token/API-key values, URI credentials, auth headers, JWTs, long key-like strings and e-mail addresses are replaced.\n'
  printf -- '- Never opened: `.env` files, token files, certificates, keys, script bodies. Compose files are read through an allowlist (no env values, commands or healthchecks).\n'
  if (( MASK_HOSTS )); then
    printf -- '- Host masking ON: domains → `example.com`, public/tailnet/link-local IPs, MACs, UUIDs and human usernames replaced. Private LAN and Docker subnets kept.\n'
  else
    printf -- '- Host masking OFF (`--show-hosts`): real domains, IPs and usernames are present. Do not share this file.\n'
  fi
  if (( ${#WARNINGS[@]} )); then
    printf -- '- %d warning(s) during collection:\n' "${#WARNINGS[@]}"
    local w
    for w in "${WARNINGS[@]}"; do printf -- '  - %s\n' "$w"; done
  else
    printf -- '- All collection steps completed without errors.\n'
  fi
}

main() {
  printf '# Homelab Audit — %s\n\n' "$(hostname)"
  printf '_Generated %s · read-only snapshot · secrets redacted_\n' "$(date '+%Y-%m-%d %H:%M %Z')"

  section_system
  section_services
  section_guest
  section_storage
  section_docker
  section_network
  section_security
  section_automation
  section_stability
  section_footer
}

# Protect the report file and warn if it would land in git.
guard_output() {
  local out
  out=$(readlink -f /proc/$$/fd/1 2>/dev/null) || return 0
  [[ -f $out ]] || return 0
  chmod 600 "$out" 2>/dev/null || true
  if git -C "${out%/*}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && ! git -C "${out%/*}" check-ignore -q "$out"; then
    log "WARNING: $out is inside a git repo and NOT ignored — do not commit it."
  fi
}

while (( $# )); do
  case $1 in
    --show-hosts) MASK_HOSTS=0 ;;
    -h|--help)    usage; exit 0 ;;
    *)            log "unknown option: $1"; usage >&2; exit 2 ;;
  esac
  shift
done

for dep in perl awk sed timeout ss; do
  have "$dep" || { log "required command not found: $dep"; exit 1; }
done

if (( MASK_HOSTS )); then
  MASK_DOMAINS=$(collect_domains)
  MASK_USERS=$(collect_users)
fi

trap 'log "interrupted"; exit 130' INT TERM

[[ -t 1 ]] && log "tip: redirect to a file outside the repo, e.g. bash $SCRIPT_NAME > ~/audit.md"
guard_output
log "collecting (takes ~30 s)..."

main | redact
status=("${PIPESTATUS[@]}")

if (( status[1] != 0 )); then
  log "redaction filter failed (exit ${status[1]}); output suppressed."
  exit 1
fi
log "done."
