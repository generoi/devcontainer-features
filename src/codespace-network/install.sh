#!/bin/bash
set -eu

INSTALL_DIR="/usr/local/share/codespace-network"
mkdir -p "$INSTALL_DIR"

# Write config from feature options
cat > "$INSTALL_DIR/config.env" <<EOF
CS_NET_MODE="${MODE:-github}"
CS_NET_DDEV_DOMAIN="${DDEVDOMAIN:-}"
CS_NET_HOSTS="${HOSTS:-}"
CS_NET_DDEV_HOSTS="${DDEVHOSTS:-}"
CS_NET_REPO="${REPO:-}"
EOF

# Copy scripts
cp -r scripts/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh

# Add convenience commands to PATH
cat > /usr/local/bin/import-production <<'SCRIPT'
#!/bin/bash
set -eu
source /usr/local/share/codespace-network/config.env
exec /usr/local/share/codespace-network/cs-import-production.sh "${CS_NET_REPO:-$GITHUB_REPOSITORY}"
SCRIPT
chmod +x /usr/local/bin/import-production

# Install cloudflared for tunnel mode
if [ "${MODE:-github}" = "cloudflare" ]; then
  ARCH=$(dpkg --print-architecture)
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    -o /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi
