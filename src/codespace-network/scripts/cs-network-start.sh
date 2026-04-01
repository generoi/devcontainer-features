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

echo "=== Codespace Network: start ($CS_NET_MODE mode) ==="

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
