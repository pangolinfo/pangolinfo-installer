# Pangolinfo Installer

> 🌐 [中文](./README.md)

Cross-platform one-line installer that wires **Pangolinfo MCP** (17 Amazon e-commerce data tools) and **Skills** SOPs into your AI assistant — covers 7 clients.

| | |
|---|---|
| **Supported clients** | Claude Code · Cursor · Cline (VS Code) · Windsurf · Codex · Hermes · OpenClaw |
| **MCP version** | Auto-tracks [pangolinfo-mcp/releases/latest](https://github.com/pangolinfo/pangolinfo-mcp/releases/latest) |
| **Runtime** | Node.js 18+ (required by MCP server) |
| **License** | MIT |

---

## Install

### macOS / Linux

```bash
curl -fsSL https://install.pangolinfo.com/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://install.pangolinfo.com/install.ps1 | iex
```

> An interactive menu will walk you through AI client → install scope → API key.

> **If `install.pangolinfo.com` is unavailable**, use the GitHub raw URL:
> - sh: `curl -fsSL https://raw.githubusercontent.com/pangolinfo/pangolinfo-installer/main/install.sh | sh`
> - ps1: `irm https://raw.githubusercontent.com/pangolinfo/pangolinfo-installer/main/install.ps1 | iex`

---

## One-line install (skip the menu)

```bash
# MCP only (recommended for most users)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxxxxxxx

# MCP + Skills
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=claude-code --scope=both --api-key=pgl_xxxxxxxx

# Pin MCP version (default tracks /latest/)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxx --mcp-version=v0.1.2

# CI / scripted (errors out if anything is missing)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxx --non-interactive
```

Full argument table:

| sh flag | PS1 equivalent | Values | Meaning |
|---|---|---|---|
| `--agent=X` | `-Agent X` | claude-code, cursor, cline, windsurf, codex, hermes, openclaw, web | AI client |
| `--scope=X` | `-Scope X` | skills, mcp, both | What to install (defaults to both) |
| `--api-key=X` | `-ApiKey X` | pgl_xxx | Existing API key (script can register one for you if missing) |
| `--api-base=URL` | `-ApiBase URL` | URL | Override default API base |
| `--scrape-base=URL` | `-ScrapeBase URL` | URL | Override default scrape base |
| `--mcp-version=X` | `-McpVersion X` | latest, v0.1.2, ... | Pin MCP version (default latest) |
| `--non-interactive` | `-NonInteractive` | — | Bail on missing args instead of prompting |
| `--dry-run` | `-DryRun` | — | Print actions without executing |
| `--lang=X` | `-Lang X` | zh, en | UI language (auto-detected by default) |
| `--help` / `-h` | `-Help` | — | Full help |

---

## How the MCP server gets installed

`--scope=mcp` or `--scope=both` triggers MCP install:

1. Download single-file ESM bundle (~800 KB, zero deps) from `github.com/pangolinfo/pangolinfo-mcp/releases/latest/download/server.mjs`
2. Download `server.mjs.sha256` and verify with local `sha256sum` / `Get-FileHash`
3. Install to:
   - **macOS / Linux**: `~/.local/lib/pangolinfo-mcp/server.mjs`
   - **Windows**: `%LOCALAPPDATA%\pangolinfo-mcp\server.mjs`
4. Write the appropriate MCP config entry for your AI client (table below)
5. Tell you to restart the client

**Prerequisite**: MCP server needs `node` in PATH (Node.js 18+). The installer doesn't force-install Node — it just warns if missing:
- macOS: `brew install node`
- Linux: `apt install nodejs` or [nvm](https://github.com/nvm-sh/nvm)
- Windows: <https://nodejs.org/>

---

## Supported AI clients · install paths

| Agent | Skills location | MCP config |
|---|---|---|
| `claude-code` | `~/.claude/skills/pangolinfo/` | `~/.claude/settings.json` (prefers `claude mcp add --scope user`) |
| `cursor` | `<cwd>/.cursor/rules/pangolinfo-*.mdc` (project-scoped) | `~/.cursor/mcp.json` |
| `cline` | `~/Documents/Cline/Rules/pangolinfo/` | VS Code ext `globalStorage` + standalone CLI (dual-write) |
| `windsurf` | Appended to `~/.codeium/windsurf/global_rules.md` (idempotent markers) | `~/.codeium/windsurf/mcp_config.json` |
| `codex` | `~/.codex/skills/` + `~/.agents/skills/` (cross-tool dual-write) | `~/.codex/config.toml` |
| `hermes` | `~/.hermes/skills/pangolinfo/` | `~/.hermes/config.yaml` |
| `openclaw` | `~/.openclaw/skills/pangolinfo/` | `~/.openclaw/openclaw.json` |
| `web` | `~/Downloads/pangolinfo-skills.zip` (manual upload) | **MCP not supported** (Skills only) |

---

## Getting an API key

With `--scope=mcp` or `both`, the installer prompts:

- **Have a key** → enter it; the installer validates it
- **No key** → register fully in the terminal:
  1. Email
  2. Receive verification code (installer hits `extapi.pangolinfo.com`)
  3. Code + password
  4. Installer auto-registers and fetches a permanent token
  5. Writes `~/.pangolinfo/config.json` (`chmod 600` / Windows ACL hardened)

You can also register at <https://extapi.pangolinfo.com> and pass `--api-key=pgl_xxx`.

---

## Verify your install

Restart your AI client, then ask:

> List all pangolinfo MCP tools.

You should see 17. Then:

> Use the pangolinfo_capabilities tool with mode "summary".

This is a free local call — confirms the wiring. Try a paid one:

> Search Amazon for "wireless mouse" — top 5 ASINs.

Expected: ~0.75 credits, ~300 KB structured data.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User cancelled |
| 2 | Argument error |
| 10 | Agent directory missing (the agent isn't installed) |
| 20 | Network error (MCP download or SHA256 verification failed) |
| 30 | Backend API error (registration failed / invalid key) |
| 40 | Filesystem error (permissions, disk full) |

---

## Uninstall

v0.1 has no auto-uninstall; do it manually:

```bash
# macOS / Linux
rm -rf ~/.local/lib/pangolinfo-mcp ~/.pangolinfo
# Then remove the 'pangolinfo' entry from your AI client's mcp config file
```

```powershell
# Windows
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\pangolinfo-mcp", "$env:USERPROFILE\.pangolinfo"
```

`--uninstall` auto-cleanup is planned for v0.2.

---

## Development

```bash
git clone https://github.com/pangolinfo/pangolinfo-installer.git
cd pangolinfo-installer
# sh syntax check
sh -n install.sh
# PowerShell syntax check
pwsh -c "[System.Management.Automation.Language.Parser]::ParseFile('install.ps1', [ref]$null, [ref]$null)"
# Dry-run
./install.sh --agent=cursor --scope=mcp --api-key=pgl_dummy --non-interactive --dry-run
```

For real runs use `HOME=/tmp/fakehome ./install.sh ...` so you don't pollute your own AI client configs.

---

## Related projects

- [pangolinfo-mcp](https://github.com/pangolinfo/pangolinfo-mcp) — MCP server source and releases
- [pangolinfo-skills](https://github.com/pangolinfo/pangolinfo-skills) — Skills SOP knowledge base *(separate repo, TBD)*
- [API docs](https://docs.pangolinfo.com) — Backend scrape API reference

---

## Support

- 🐛 Issues: <https://github.com/pangolinfo/pangolinfo-installer/issues>
- 📧 Email: <support@pangolinfo.com>
- 🌐 Homepage: <https://pangolinfo.com>

---

## License

[MIT](./LICENSE)
