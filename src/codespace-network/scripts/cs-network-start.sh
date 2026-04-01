#!/bin/bash
set -eu

# Called from postStartCommand. Runs on every Codespace start, including
# wakes from shutdown. Restores ephemeral state that doesn't survive
# container restarts.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cs-network-lib.sh
source "$SCRIPT_DIR/cs-network-lib.sh"

cs_net_load_config
cs_net_resolve_hosts

# Source Codespace secrets if not already in env
SECRETS_ENV="/workspaces/.codespaces/shared/.env"
if [ -f "$SECRETS_ENV" ]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# || ! "$line" =~ = ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ [[:space:]] || "$key" =~ ^- ]] && continue
    export "$key=$value"
  done < "$SECRETS_ENV"
fi

echo "=== Codespace Network: start ($CS_NET_MODE mode) ==="

# cd to project directory (postStartCommand may run from /home/vscode)
if [ -n "${CS_NET_DDEV_DOMAIN:-}" ]; then
  PROJECT_DIR=$(find /workspaces -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
  if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/.ddev" ]; then
    cd "$PROJECT_DIR"
  fi
fi

# Restore /etc/hosts entries (Docker regenerates /etc/hosts on restart)
cs_net_ensure_hosts_file

# Restart tunnel if cloudflare mode and not running
if [ "$CS_NET_MODE" = "cloudflare" ]; then
  if ! pgrep -f "cloudflared.*tunnel.*run" >/dev/null 2>&1; then
    echo "Restarting cloudflared tunnel..."
    cs_net_start_tunnel
  fi
fi

# Ensure DDEV is running
if ! ddev describe >/dev/null 2>&1; then
  echo "Starting DDEV..."
  ddev start
fi

# Check if DB search-replace is needed (shouldn't be with stable URLs,
# but handles edge cases like config changes between rebuilds)
if cs_net_needs_db_replace; then
  echo "Config changed, running DB search-replace..."
  cs_net_db_replace
fi

echo "=== Codespace Network: ready ==="
