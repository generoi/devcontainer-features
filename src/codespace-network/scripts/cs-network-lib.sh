#!/bin/bash
# Shared functions for Codespace networking.
# Sourced by the other cs-network-*.sh scripts.

INSTALL_DIR="/usr/local/share/codespace-network"
CONFIG_FILE="$INSTALL_DIR/config.env"
MARKER_FILE="/tmp/cs-network-db-replaced"

# Load config written by install.sh
cs_net_load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found. Is the codespace-network feature installed?" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

# Parse key=value pairs from a comma-separated string.
# Usage: cs_net_parse_pairs "main=foo.com,vet=bar.com"
# Sets associative array CS_NET_PARSED.
cs_net_parse_pairs() {
  local input="$1"
  declare -gA CS_NET_PARSED
  CS_NET_PARSED=()
  [ -z "$input" ] && return
  IFS=',' read -ra pairs <<< "$input"
  for pair in "${pairs[@]}"; do
    local key="${pair%%=*}"
    local value="${pair#*=}"
    CS_NET_PARSED[$key]="$value"
  done
}

# Get all target hostnames (the public-facing URLs).
# For github mode, computes from $CODESPACE_NAME.
# For cloudflare mode, reads from CS_NET_HOSTS config.
# Sets associative array CS_NET_TARGET_HOSTS.
cs_net_resolve_hosts() {
  declare -gA CS_NET_TARGET_HOSTS
  CS_NET_TARGET_HOSTS=()

  if [ "$CS_NET_MODE" = "github" ]; then
    local fwd_domain="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
    # DDEV in Codespaces uses port 8080 (HTTP) since the router is disabled.
    # GitHub Codespace port forwarding adds HTTPS on top.
    CS_NET_TARGET_HOSTS[main]="${CODESPACE_NAME}-8080.${fwd_domain}"
  else
    cs_net_parse_pairs "$CS_NET_HOSTS"
    for key in "${!CS_NET_PARSED[@]}"; do
      CS_NET_TARGET_HOSTS[$key]="${CS_NET_PARSED[$key]}"
    done
  fi
}

# Get DDEV source hostnames for DB search-replace.
# Main site uses CS_NET_DDEV_DOMAIN, subsites from CS_NET_DDEV_HOSTS.
# Sets associative array CS_NET_SOURCE_HOSTS.
cs_net_resolve_source_hosts() {
  declare -gA CS_NET_SOURCE_HOSTS
  CS_NET_SOURCE_HOSTS=()
  CS_NET_SOURCE_HOSTS[main]="$CS_NET_DDEV_DOMAIN"

  if [ -n "$CS_NET_DDEV_HOSTS" ]; then
    cs_net_parse_pairs "$CS_NET_DDEV_HOSTS"
    for key in "${!CS_NET_PARSED[@]}"; do
      CS_NET_SOURCE_HOSTS[$key]="${CS_NET_PARSED[$key]}"
    done
  fi
}

# Add hostnames to /etc/hosts → 127.0.0.1 (idempotent).
cs_net_ensure_hosts_file() {
  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    local host="${CS_NET_TARGET_HOSTS[$key]}"
    if ! grep -q "$host" /etc/hosts 2>/dev/null; then
      echo "127.0.0.1 ${host}" | sudo tee -a /etc/hosts >/dev/null
    fi
  done
}

# Configure DDEV additional-fqdns with all target hostnames.
cs_net_ddev_fqdns() {
  local fqdns=""
  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    if [ -n "$fqdns" ]; then
      fqdns="${fqdns},${CS_NET_TARGET_HOSTS[$key]}"
    else
      fqdns="${CS_NET_TARGET_HOSTS[$key]}"
    fi
  done
  if [ -n "$fqdns" ]; then
    ddev config --additional-fqdns="$fqdns"
  fi
}

# Run wp search-replace for each source → target host pair.
cs_net_db_replace() {
  cs_net_resolve_source_hosts

  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    local source="${CS_NET_SOURCE_HOSTS[$key]:-}"
    local target="${CS_NET_TARGET_HOSTS[$key]}"
    if [ -n "$source" ] && [ "$source" != "$target" ]; then
      echo "  Replacing $source → $target"
      ddev wp search-replace "$source" "$target" --all-tables --skip-columns=guid 2>/dev/null || true
    fi
  done
  ddev wp cache flush 2>/dev/null || true

  # Write marker with config hash to avoid re-running on wake
  cs_net_write_marker
}

# Write marker file with a hash of the current config + resolved hosts.
cs_net_write_marker() {
  local hash_input="$CS_NET_MODE:$CS_NET_DDEV_DOMAIN:$CS_NET_HOSTS:$CS_NET_DDEV_HOSTS"
  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    hash_input="${hash_input}:${key}=${CS_NET_TARGET_HOSTS[$key]}"
  done
  echo "$hash_input" | md5sum | cut -d' ' -f1 > "$MARKER_FILE"
}

# Check if DB search-replace is needed (marker missing or hash changed).
cs_net_needs_db_replace() {
  [ ! -f "$MARKER_FILE" ] && return 0

  local hash_input="$CS_NET_MODE:$CS_NET_DDEV_DOMAIN:$CS_NET_HOSTS:$CS_NET_DDEV_HOSTS"
  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    hash_input="${hash_input}:${key}=${CS_NET_TARGET_HOSTS[$key]}"
  done
  local current_hash
  current_hash=$(echo "$hash_input" | md5sum | cut -d' ' -f1)
  local stored_hash
  stored_hash=$(cat "$MARKER_FILE" 2>/dev/null)

  [ "$current_hash" != "$stored_hash" ]
}

# Start or restart cloudflared tunnel.
cs_net_start_tunnel() {
  local tunnel_id="${CLOUDFLARE_TUNNEL_ID:?Missing CLOUDFLARE_TUNNEL_ID secret}"
  local creds_b64="${CLOUDFLARE_TUNNEL_CREDENTIALS:?Missing CLOUDFLARE_TUNNEL_CREDENTIALS secret}"

  # Write credentials
  mkdir -p ~/.cloudflared
  echo "$creds_b64" | base64 -d > ~/.cloudflared/"${tunnel_id}".json

  # Build ingress rules
  local ingress=""
  for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
    local host="${CS_NET_TARGET_HOSTS[$key]}"
    ingress="${ingress}  - hostname: \"${host}\"
    service: https://127.0.0.1:443
    originRequest:
      noTLSVerify: true
"
  done

  cat > ~/.cloudflared/config.yml <<EOF
tunnel: ${tunnel_id}
credentials-file: ${HOME}/.cloudflared/${tunnel_id}.json
ingress:
${ingress}  - service: http_status:404
EOF

  # Kill existing tunnel if running
  pkill -f "cloudflared.*tunnel.*run" 2>/dev/null || true
  sleep 1

  # Start tunnel in background
  nohup cloudflared tunnel run "$tunnel_id" > /tmp/cloudflared.log 2>&1 &
  echo "Cloudflare tunnel started (PID: $!)"
}
