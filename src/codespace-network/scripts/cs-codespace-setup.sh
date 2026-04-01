#!/bin/bash
set -eu

# Full Codespace setup for DDEV WordPress projects.
# Called as postCreateCommand. Handles everything:
#   - Secrets, Docker, DDEV
#   - Networking (delegates to cs-network-setup.sh)
#   - Auth (Composer, FontAwesome npm)
#   - Tool installation (Playwright, Claude CLI)
#   - Dependencies & build
#   - Production DB snapshot import + URL search-replace
#
# Usage: cs-codespace-setup.sh [repo]
#   repo: GitHub repo (e.g. "generoi/btbtransformers").
#   Defaults to the repo option in devcontainer-feature.json, then $GITHUB_REPOSITORY.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cs-network-lib.sh
source "$SCRIPT_DIR/cs-network-lib.sh"
cs_net_load_config

# Log all output for debugging (viewable via: cat /tmp/codespace-setup.log)
exec > >(tee -a /tmp/codespace-setup.log) 2>&1
echo "=== Codespace setup started at $(date -u) ==="

REPO="${1:-${CS_NET_REPO:-${GITHUB_REPOSITORY:-}}}"

# --- Docker ---
while ! docker info >/dev/null 2>&1; do sleep 1; done

# --- Codespace secrets ---
# Secrets live in a shared .env file but aren't always exported into
# postCreateCommand. Source single-line KEY=VALUE pairs, preserving
# values that contain '=' (e.g. base64 keys). Skip multiline values.
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

# --- DDEV ---
export DDEV_NO_INSTRUMENTATION=true
ddev poweroff 2>/dev/null || true

# --- Networking ---
"$SCRIPT_DIR/cs-network-setup.sh"

# --- Git submodules ---
# Rewrite SSH to HTTPS for Codespace environments (no SSH keys)
git config --global url."https://github.com/".insteadOf "git@github.com:"
git submodule update --init --recursive --force 2>/dev/null || true

ddev start

# --- Auth ---
if [ -n "${PACKAGIST_GITHUB_TOKEN:-}" ]; then
  ddev composer config --global github-oauth.github.com "$PACKAGIST_GITHUB_TOKEN"
fi

if [ -n "${NPM_FONTAWESOME_AUTH_TOKEN:-}" ]; then
  ddev exec bash -c "cat >> ~/.npmrc <<NPMRC
@fortawesome:registry=https://npm.fontawesome.com/
//npm.fontawesome.com/:_authToken=${NPM_FONTAWESOME_AUTH_TOKEN}
NPMRC"
fi

# --- Tools ---
npx -y playwright install --with-deps chromium
curl -fsSL https://claude.ai/install.sh | bash

# --- Dependencies & build ---
ddev composer install
ddev npm install
ddev npm run build

# --- Production snapshot ---
if [ -n "${DB_ARTIFACT_KEY:-}" ] && [ -n "$REPO" ]; then
  echo "Downloading production snapshot from $REPO..."
  GH_TOKEN="${GITHUB_TOKEN:-}" gh run download -n production-snapshot -D /tmp/snapshot -R "$REPO" 2>/dev/null || true

  if [ -f /tmp/snapshot/production-snapshot.tar.gz.enc ]; then
    openssl enc -d -aes-256-cbc -pbkdf2 \
      -in /tmp/snapshot/production-snapshot.tar.gz.enc \
      -out /tmp/production-snapshot.tar.gz \
      -pass "pass:${DB_ARTIFACT_KEY}"

    tar xzf /tmp/production-snapshot.tar.gz

    ddev import-db --file=.github/fixtures/sanitized-db.sql.gz

    # Replace DDEV URLs with Codespace/tunnel URLs
    "$SCRIPT_DIR/cs-network-setup.sh" --db-replace

    rm -rf /tmp/snapshot /tmp/production-snapshot.tar.gz .github/fixtures/sanitized-db.sql.gz
  fi
fi

echo "=== Codespace setup complete at $(date -u) ==="
