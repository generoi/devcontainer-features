#!/bin/bash
set -eu

# Outputs preview URLs as JSON.
# Called from the GitHub Actions workflow to get the preview URL(s).
#
# Output: {"main": "https://...", "vet": "https://...", ...}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cs-network-lib.sh
source "$SCRIPT_DIR/cs-network-lib.sh"

cs_net_load_config
cs_net_resolve_hosts

# Build JSON output
json="{"
first=true
for key in "${!CS_NET_TARGET_HOSTS[@]}"; do
  if [ "$first" = true ]; then first=false; else json+=","; fi
  json+="\"$key\":\"https://${CS_NET_TARGET_HOSTS[$key]}\""
done
json+="}"

echo "$json"
