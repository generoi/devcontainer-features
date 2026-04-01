#!/bin/bash
set -eu

# Re-import the latest production snapshot inside a running Codespace.
# Usage: cs-import-production.sh [repo]
#   repo: GitHub repo (e.g. "generoi/btbtransformers"). Defaults to $GITHUB_REPOSITORY.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO="${1:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
  echo "Error: Pass the repo as an argument or set GITHUB_REPOSITORY." >&2
  exit 1
fi

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

if [ -z "${DB_ARTIFACT_KEY:-}" ]; then
  echo "Error: DB_ARTIFACT_KEY is not set. Add it as a Codespace secret." >&2
  exit 1
fi

echo "Downloading production snapshot from $REPO..."
rm -rf /tmp/snapshot
GH_TOKEN="${GITHUB_TOKEN:-}" gh run download -n production-snapshot -D /tmp/snapshot -R "$REPO"

echo "Decrypting..."
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in /tmp/snapshot/production-snapshot.tar.gz.enc \
  -out /tmp/production-snapshot.tar.gz \
  -pass "pass:${DB_ARTIFACT_KEY}"

echo "Extracting DB and uploads..."
tar xzf /tmp/production-snapshot.tar.gz

echo "Importing database..."
ddev import-db --file=.github/fixtures/sanitized-db.sql.gz

# Replace DDEV URLs with Codespace/tunnel URLs
"$SCRIPT_DIR/cs-network-setup.sh" --db-replace

# Cleanup temp files (keep extracted SVGs in web/app/uploads/)
rm -rf /tmp/snapshot /tmp/production-snapshot.tar.gz .github/fixtures/sanitized-db.sql.gz

echo "Done! Production DB and SVGs imported."
