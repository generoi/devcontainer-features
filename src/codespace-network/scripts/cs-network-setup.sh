#!/bin/bash
set -eu

# Called from postCreateCommand (setup.sh).
#
# Without flags: configures DDEV additional-fqdns, /etc/hosts, starts tunnel.
#   Call BEFORE ddev start.
#
# With --db-replace: runs wp search-replace for each host pair.
#   Call AFTER DB import.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cs-network-lib.sh
source "$SCRIPT_DIR/cs-network-lib.sh"

cs_net_load_config
cs_net_resolve_hosts

if [ "${1:-}" = "--db-replace" ]; then
  echo "=== Codespace Network: DB search-replace ==="
  cs_net_db_replace
  exit 0
fi

echo "=== Codespace Network: setup ($CS_NET_MODE mode) ==="

# Configure DDEV to accept the target hostnames
cs_net_ddev_fqdns

# Add /etc/hosts entries for local tool access
cs_net_ensure_hosts_file

# In Codespaces, DDEV maps HTTPS to port 8443 instead of 443.
# Add a docker-compose override to also expose 443 so that
# https://{fqdn} works from inside the Codespace via /etc/hosts.
if [ -n "${CODESPACES:-}" ] && [ -d .ddev ]; then
  cat > .ddev/docker-compose.codespaces.yaml <<'DDEV_YAML'
#ddev-generated
# Expose HTTPS on standard port 443 for internal Codespace access.
# DDEV's router is disabled in Codespaces, so 443 is unmapped by default.
services:
  web:
    ports:
      - "443:443"
DDEV_YAML
fi

# Start tunnel if in cloudflare mode
if [ "$CS_NET_MODE" = "cloudflare" ]; then
  cs_net_start_tunnel
fi

echo "=== Codespace Network: setup complete ==="
