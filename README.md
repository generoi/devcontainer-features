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

### Modes

**`github`** — Uses GitHub's built-in Codespace port forwarding. The preview URL is `https://{codespace-name}-80.app.github.dev`. An `/etc/hosts` entry routes this to `127.0.0.1` inside the Codespace so curl, Playwright, and e2e tests bypass GitHub's port-forwarding interstitial page. Good for simple single-site projects.

**`cloudflare`** — Uses a named Cloudflare Tunnel with stable hostnames under `*.cs.genero-dev.com`. Required for multisite (multiple domains) and useful for any project wanting stable preview URLs. DB search-replace only runs once on creation — not on every wake.

### One-time org setup (Cloudflare mode)

These steps are done once for the entire GitHub org. All projects share the same tunnel and wildcard DNS.

#### 1. Install cloudflared and authenticate

```bash
brew install cloudflared
cloudflared tunnel login
```

This opens a browser to authenticate with Cloudflare. You need a Cloudflare account (free tier) with the domain added as a zone:
- Go to Cloudflare dashboard → **Add a site** → enter `genero-dev.com`
- You do NOT need to change nameservers — the zone just needs to exist so the tunnel login can authorize against it
- The dashboard will show a "nameservers missing" warning — that's fine

#### 2. Create the tunnel

```bash
cloudflared tunnel create genero-cs
```

This outputs a tunnel UUID (e.g. `ab399c52-...`) and creates a credentials file at `~/.cloudflared/<uuid>.json`.

#### 3. Add wildcard DNS (Route53)

Add a CNAME record in Route53:

| Name | Type | Value |
|------|------|-------|
| `*.cs.genero-dev.com` | CNAME | `<tunnel-uuid>.cfargotunnel.com` |

#### 4. Add GitHub org secrets

Add these as **org-level Codespace secrets** at `https://github.com/organizations/generoi/settings/codespaces`:

| Secret | Value | How to get it |
|--------|-------|---------------|
| `CLOUDFLARE_TUNNEL_ID` | Tunnel UUID | Shown by `cloudflared tunnel create`, or `cloudflared tunnel list` |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | Base64-encoded credentials JSON | `base64 -i ~/.cloudflared/<uuid>.json \| tr -d '\n'` |

#### 5. Make the GHCR package accessible

The devcontainer feature is published to `ghcr.io/generoi/devcontainer-features/codespace-network`. Codespaces need to pull it during container build. Set the package visibility to **internal** (visible to org members) at the package settings page.

### Per-project setup

1. Add the feature to `.devcontainer/devcontainer.json` (see Usage above)
2. Call `cs-network-setup.sh` from your `setup.sh` (before `ddev start` and after DB import)
3. Set `postStartCommand` to `cs-network-start.sh`
4. Update `claude.yml` to use `cs-network-urls.sh` for preview URLs

### Wake behavior

- **GitHub mode:** `/etc/hosts` is restored on every start (~2s)
- **Cloudflare mode:** `/etc/hosts` restored + `cloudflared` restarted (~5s). No DB search-replace needed — URLs are stable.
- Visiting a tunnel URL does **not** wake a sleeping Codespace. The `@claude` workflow wakes via `gh codespace ssh`.
