#!/usr/bin/env bash
#
# add-site.sh — publish a local service at https://<name>.<domain> through the
# nginx-proxy container, using the existing wildcard certificate.
#
# Usage:
#   bash add-site.sh <name> <host-port> [--max-body 100M] [--domain example.com] [--dry-run]
#
# Examples:
#   bash add-site.sh jellyfin 8096
#   bash add-site.sh photos 2283 --max-body 50000M --dry-run
#
# What it does:
#   1. Checks the name is free and something is listening on <host-port>.
#   2. Writes ~/docker/reverse-proxy/conf.d/<name>.conf (80 → 443 redirect,
#      TLS with the wildcard cert, websocket-friendly proxy to
#      host.docker.internal:<host-port>).
#   3. Runs `nginx -t` inside nginx-proxy; on failure the new file is removed.
#   4. Reloads nginx.
#
# What it does NOT do: create the DNS record. Afterwards, in Cloudflare DNS,
# add an A record <name> → the server's Tailscale IP (DNS only, grey cloud)
# to keep the site tailnet-only, like the existing sites. To make a site
# public instead, add it as a Cloudflare Tunnel hostname, not a port-forward.

set -euo pipefail

readonly CONF_DIR=${PROXY_CONF_DIR:-$HOME/docker/reverse-proxy/conf.d}
readonly PROXY_CONTAINER=${PROXY_CONTAINER:-nginx-proxy}

die()   { printf 'add-site: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; }

name='' port='' max_body=100M domain='' dry_run=0
while (( $# )); do
  case $1 in
    --max-body) max_body=${2:?}; shift ;;
    --domain)   domain=${2:?}; shift ;;
    --dry-run)  dry_run=1 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          if [[ -z $name ]]; then name=$1; elif [[ -z $port ]]; then port=$1; else die "unexpected argument: $1"; fi ;;
  esac
  shift
done

[[ -n $name && -n $port ]] || { usage >&2; exit 2; }
[[ $name =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "name must be lowercase letters, digits and dashes: $name"
[[ $port =~ ^[0-9]+$ ]] && (( port > 0 && port < 65536 )) || die "invalid port: $port"
[[ $max_body =~ ^[0-9]+[kKmMgG]?$ ]] || die "invalid --max-body: $max_body"
[[ -d $CONF_DIR ]] || die "proxy config dir not found: $CONF_DIR"

# Domain: taken from the existing vhosts unless given.
if [[ -z $domain ]]; then
  domain=$(sed -n 's/^[[:space:]]*server_name[[:space:]]\{1,\}[^.;[:space:]]*\.\([^;[:space:]]*\);.*/\1/p' "$CONF_DIR"/*.conf 2>/dev/null \
           | sort | uniq -c | sort -rn | awk 'NR == 1 { print $2 }')
  [[ -n $domain ]] || die "could not detect the domain; pass --domain"
fi

conf="$CONF_DIR/$name.conf"
[[ ! -e $conf ]] || die "$conf already exists"
if grep -qsE "server_name[[:space:]]+([^;]*[[:space:]])?$name\.$domain[[:space:];]" "$CONF_DIR"/*.conf; then
  die "$name.$domain is already served by another file in $CONF_DIR"
fi

cert_dir="/etc/letsencrypt/live/$domain"
[[ -r $cert_dir/fullchain.pem ]] || die "wildcard certificate not found at $cert_dir"

if ! ss -Htln | awk '{ print $4 }' | grep -qE "[:.]$port\$"; then
  die "nothing is listening on port $port; start the service first"
fi

render() {
  cat <<EOF
# Added by add-site.sh on $(date +%F): $name → host port $port
server {
    listen 80;
    server_name $name.$domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $name.$domain;

    ssl_certificate $cert_dir/fullchain.pem;
    ssl_certificate_key $cert_dir/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size $max_body;

    location / {
        proxy_pass http://host.docker.internal:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
}

if (( dry_run )); then
  render
  exit 0
fi

docker ps --format '{{.Names}}' | grep -qx "$PROXY_CONTAINER" || die "$PROXY_CONTAINER is not running"

render > "$conf"
if ! docker exec "$PROXY_CONTAINER" nginx -t >/dev/null 2>&1; then
  rm -f "$conf"
  docker exec "$PROXY_CONTAINER" nginx -t >&2 || true
  die "nginx rejected the new config; nothing was changed"
fi
docker exec "$PROXY_CONTAINER" nginx -s reload

printf 'Added https://%s.%s → host port %s (%s)\n' "$name" "$domain" "$port" "$conf"
printf 'Next: in Cloudflare DNS add an A record "%s" → this server'"'"'s Tailscale IP (DNS only).\n' "$name"
