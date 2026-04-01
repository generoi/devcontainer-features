# Devcontainer Features

Shared devcontainer features for Genero projects.

## codespace-network

Configures Codespace networking for DDEV WordPress projects. Supports GitHub port forwarding and Cloudflare named tunnels.

### Usage

GitHub port forwarding (single-site):

```json
"features": {
  "ghcr.io/generoi/devcontainer-features/codespace-network:1": {
    "mode": "github",
    "ddevDomain": "myproject.ddev.site"
  }
}
```

Cloudflare tunnel (multisite):

```json
"features": {
  "ghcr.io/generoi/devcontainer-features/codespace-network:1": {
    "mode": "cloudflare",
    "ddevDomain": "myproject.ddev.site",
    "hosts": "main=myproject.cs.genero-dev.com,fi=fi-myproject.cs.genero-dev.com",
    "ddevHosts": "fi=fi.myproject.ddev.site"
  }
}
```

### Scripts

The feature installs scripts to `/usr/local/share/codespace-network/`:

| Script | When to call | Purpose |
|--------|-------------|---------|
| `cs-network-setup.sh` | `postCreateCommand` (before `ddev start`) | Configure DDEV fqdns, /etc/hosts, start tunnel |
| `cs-network-setup.sh --db-replace` | `postCreateCommand` (after DB import) | Run wp search-replace |
| `cs-network-start.sh` | `postStartCommand` | Restore /etc/hosts, restart tunnel, ensure DDEV running |
| `cs-network-urls.sh` | GitHub Actions workflow | Output preview URLs as JSON |

### Required secrets (Cloudflare mode)

Set as GitHub org-level Codespace secrets:

| Secret | Value |
|--------|-------|
| `CLOUDFLARE_TUNNEL_ID` | Tunnel UUID from `cloudflared tunnel create` |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | Base64-encoded tunnel credentials JSON |
