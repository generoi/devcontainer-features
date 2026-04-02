# Devcontainer Features

Shared devcontainer features for Genero projects.

## codespace-network

Configures Codespace networking for DDEV WordPress projects. Handles DDEV setup, production data import, Cloudflare Tunnel, `/etc/hosts`, and DB search-replace.

### Quick Start

```json
{
  "features": {
    "ghcr.io/generoi/devcontainer-features/codespace-network:1": {
      "mode": "cloudflare",
      "ddevDomain": "myproject.ddev.site",
      "hosts": "main=myproject.genero-dev.app",
      "repo": "generoi/myproject"
    }
  },
  "postCreateCommand": "/usr/local/share/codespace-network/cs-codespace-setup.sh",
  "postStartCommand": "/usr/local/share/codespace-network/cs-network-start.sh"
}
```

### Modes

**`cloudflare`** (recommended) — Stable preview URLs via Cloudflare Tunnel (e.g. `myproject.genero-dev.app`). Works with multisite. Auto-starts via Cloudflare Worker. Protected by Cloudflare Access (`@genero.fi` emails).

**`github`** — GitHub port forwarding (`{codespace}-80.app.github.dev`). Simpler but URL changes per Codespace, has GitHub interstitial page.

### Feature Options

| Option | Description |
|--------|-------------|
| `mode` | `cloudflare` or `github` |
| `ddevDomain` | Project's DDEV domain (e.g. `myproject.ddev.site`) |
| `hosts` | Comma-separated `key=hostname` pairs (e.g. `main=myproject.genero-dev.app`) |
| `ddevHosts` | For multisite: `key=ddev-hostname` pairs for subsites |
| `repo` | GitHub repo for production snapshots (e.g. `generoi/myproject`) |

### What it does

**On creation** (`postCreateCommand` → `cs-codespace-setup.sh`):
1. Sources Codespace secrets
2. Configures DDEV additional-fqdns and `/etc/hosts`
3. Creates `docker-compose.codespaces.yaml` (port 443 mapping)
4. Starts Cloudflare tunnel (cloudflare mode)
5. Starts DDEV
6. Configures auth (Composer, FontAwesome npm)
7. Installs Playwright + Claude CLI
8. Runs `composer install`, `npm install`, `npm run build`
9. Downloads and imports production DB snapshot
10. Runs URL search-replace

**On wake** (`postStartCommand` → `cs-network-start.sh`):
1. Restores `/etc/hosts` (lost on container restart)
2. Restarts Cloudflare tunnel
3. Ensures DDEV is running

### Commands

| Command | Description |
|---------|-------------|
| `import-production` | Re-import latest production data into running Codespace |

### WP Login

The sanitized production DB has one user: **admin** / **admin**

## Secrets

### Codespace secrets (org level)

Set at `https://github.com/organizations/generoi/settings/codespaces`:

| Secret | Purpose |
|--------|---------|
| `DB_ARTIFACT_KEY` | Decrypt production snapshot |
| `PACKAGIST_GITHUB_TOKEN` | Composer auth for private packages |
| `NPM_FONTAWESOME_AUTH_TOKEN` | npm auth for FontAwesome Pro |
| `CLOUDFLARE_TUNNEL_ID` | Cloudflare tunnel UUID |
| `CLOUDFLARE_TUNNEL_CREDENTIALS` | Base64-encoded tunnel credentials JSON |
| `CLOUDINARY_CLOUD_NAME` | Screenshot uploads |
| `CLOUDINARY_UPLOAD_PRESET` | Screenshot uploads |

### Actions secrets (repo level)

| Secret | Purpose |
|--------|---------|
| `CODESPACE_TOKEN` | [Fine-grained PAT](#codespace_token-pat) for Codespace lifecycle |
| `DB_ARTIFACT_KEY` | Same key as Codespace secret |

### `CODESPACE_TOKEN` PAT

Fine-grained PAT from the `genero-claudebot` machine user.

**Repository permissions:**
- Contents: Read and write
- Codespaces: Read and write
- Codespaces lifecycle admin: Read and write
- Codespaces metadata: Read
- Issues: Read and write
- Pull requests: Read and write

**Organization permissions:**
- Organization codespaces: Read and write

## Cloudflare Setup

### Tunnel

Created once, shared by all projects:

```bash
brew install cloudflared
cloudflared tunnel login    # authenticates with Cloudflare
cloudflared tunnel create genero-cs
```

Credentials stored as org Codespace secrets (see above).

### DNS (Cloudflare)

Domain `genero-dev.app` with nameservers on Cloudflare.

| Record | Type | Value | Proxy |
|--------|------|-------|-------|
| `*` | CNAME | `<tunnel-uuid>.cfargotunnel.com` | Proxied (orange) |

### Auto-start Worker

A Cloudflare Worker at `*.genero-dev.app/*` intercepts requests when the tunnel is down, starts the Codespace via GitHub API, and shows a "Starting..." page.

See `gcf-github-chat-bot/cloudflare-worker/` for the worker code.

### Access Control (Zero Trust)

Codespace previews are protected by [Cloudflare Access](https://one.dash.cloudflare.com/access/apps):

- **Application:** `Codespace Previews` at `*.genero-dev.app`
- **Policy:** Allow emails ending in `@genero.fi`
- **Login:** One-time PIN (email code)
- **Session:** 30 days
- **Team domain:** `genero-dev.cloudflareaccess.com`

## Production Data Sync

The `Manage: Sync Production` workflow pulls the latest DB + uploads from production, sanitizes it, and uploads as an encrypted GitHub Actions artifact.

```bash
gh workflow run sync-production.yml -R generoi/myproject
```

The Codespace imports this automatically during setup. To re-import: run `import-production`.

### What's sanitized

See `config/wp-cli/db-export-clean.php` in each project:
- Deletes all users → creates `admin` / `admin`
- Blanks API keys, auth salts, license keys
- Truncates email logs, form submissions, order data, comments

## Codespace Management

| Action | How |
|--------|-----|
| **Create/rebuild** | GitHub Actions → `Manage: Codespace` → rebuild |
| **Auto-start** | Visit `myproject.genero-dev.app` (Cloudflare Worker) |
| **Stop** | GitHub Actions → `Manage: Codespace` → stop |
| **Refresh data** | Google Chat `/gh` → 🔄 Refresh Data |

## GHCR Package

The feature is published to `ghcr.io/generoi/devcontainer-features/codespace-network`. Visibility must be **public** for Codespaces to pull it during container build.

Package settings: `https://github.com/orgs/generoi/packages/container/devcontainer-features%2Fcodespace-network/settings`
