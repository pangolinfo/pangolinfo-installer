# Pangolinfo Installer

> 🌐 [English](./README.en.md)

跨平台一键安装脚本 — 把 **Pangolinfo MCP** (17 个 Amazon 电商数据工具) 和 **Skills** SOP 装到你的 AI 助手里,覆盖 7 个客户端。

| | |
|---|---|
| **支持的客户端** | Claude Code · Cursor · Cline (VS Code) · Windsurf · Codex · Hermes · OpenClaw |
| **MCP 版本** | 自动跟随 [pangolinfo-mcp/releases/latest](https://github.com/pangolinfo/pangolinfo-mcp/releases/latest) |
| **运行时要求** | Node.js 18+ (MCP server 启动需要) |
| **License** | MIT |

---

## 安装

### macOS / Linux

```bash
curl -fsSL https://install.pangolinfo.com/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://install.pangolinfo.com/install.ps1 | iex
```

> 默认会启动交互式菜单,依次让你选 AI 助手 → 安装范围 → 输入或注册 API Key。

> **如果 `install.pangolinfo.com` 域名暂时无法访问**,可用 GitHub raw 直链:
> - sh: `curl -fsSL https://raw.githubusercontent.com/pangolinfo/pangolinfo-installer/main/install.sh | sh`
> - ps1: `irm https://raw.githubusercontent.com/pangolinfo/pangolinfo-installer/main/install.ps1 | iex`

---

## 一行命令(跳过菜单)

```bash
# 只装 MCP (推荐 — 周一上线的主要场景)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxxxxxxx

# 同时装 MCP + Skills
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=claude-code --scope=both --api-key=pgl_xxxxxxxx

# 锁定 MCP 版本 (默认跟 /latest/)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxx --mcp-version=v0.1.2

# CI / 脚本化 (缺参数直接报错)
curl -fsSL https://install.pangolinfo.com/install.sh | sh -s -- \
  --agent=cursor --scope=mcp --api-key=pgl_xxx --non-interactive
```

PowerShell:

```powershell
# 只装 MCP
irm https://install.pangolinfo.com/install.ps1 | iex
# (脚本运行后菜单引导)
```

参数全表:

| 参数 (sh) | PS1 等价 | 取值 | 说明 |
|---|---|---|---|
| `--agent=X` | `-Agent X` | claude-code, cursor, cline, windsurf, codex, hermes, openclaw, web | AI 客户端 |
| `--scope=X` | `-Scope X` | skills, mcp, both | 装哪部分 (默认 both) |
| `--api-key=X` | `-ApiKey X` | pgl_xxx | 已有的 API Key (没有时脚本会引导注册) |
| `--api-base=URL` | `-ApiBase URL` | URL | 覆盖默认 API base |
| `--scrape-base=URL` | `-ScrapeBase URL` | URL | 覆盖默认 scrape base |
| `--mcp-version=X` | `-McpVersion X` | latest, v0.1.2, ... | 锁 MCP 版本 (默认 latest) |
| `--non-interactive` | `-NonInteractive` | — | 缺参数直接报错,不弹菜单 |
| `--dry-run` | `-DryRun` | — | 只打印操作不执行 |
| `--lang=X` | `-Lang X` | zh, en | 界面语言 (默认按系统检测) |
| `--help` / `-h` | `-Help` | — | 完整帮助 |

---

## MCP server 怎么装

`--scope=mcp` 或 `--scope=both` 触发 MCP 安装。流程:

1. 从 `github.com/pangolinfo/pangolinfo-mcp/releases/latest/download/server.mjs` 下载单文件 ESM bundle (~800 KB,零依赖)
2. 下载 `server.mjs.sha256` 并用本地 `sha256sum` / `Get-FileHash` 校验完整性
3. 装到:
   - **macOS / Linux**: `~/.local/lib/pangolinfo-mcp/server.mjs`
   - **Windows**: `%LOCALAPPDATA%\pangolinfo-mcp\server.mjs`
4. 按你的 AI 客户端,写入对应的 MCP 配置文件 (见下表)
5. 提示重启客户端

**前置环境**: MCP server 需要 `node` 在 PATH 里 (Node.js 18+)。脚本不强制装 node — 没装时只 warn,让你自己安装:
- macOS: `brew install node`
- Linux: `apt install nodejs` 或 [nvm](https://github.com/nvm-sh/nvm)
- Windows: <https://nodejs.org/>

---

## 支持的 AI 客户端 · 安装位置

| Agent | Skills 位置 | MCP 配置 |
|---|---|---|
| `claude-code` | `~/.claude/skills/pangolinfo/` | `~/.claude/settings.json` (优先用 `claude mcp add --scope user`) |
| `cursor` | `<cwd>/.cursor/rules/pangolinfo-*.mdc` (项目级) | `~/.cursor/mcp.json` |
| `cline` | `~/Documents/Cline/Rules/pangolinfo/` | VS Code 扩展 `globalStorage` + 独立 CLI 双路径 |
| `windsurf` | 追加到 `~/.codeium/windsurf/global_rules.md` (带 marker 幂等) | `~/.codeium/windsurf/mcp_config.json` |
| `codex` | `~/.codex/skills/` + `~/.agents/skills/` (cross-tool 双写) | `~/.codex/config.toml` |
| `hermes` | `~/.hermes/skills/pangolinfo/` | `~/.hermes/config.yaml` |
| `openclaw` | `~/.openclaw/skills/pangolinfo/` | `~/.openclaw/openclaw.json` |
| `web` | `~/Downloads/pangolinfo-skills.zip` (手动上传) | **不支持 MCP**(仅 Skills) |

---

## API Key 获取

选 `--scope=mcp` 或 `both` 时,脚本会问你是否已有 API Key:

- **已有** → 输入并自动校验(终端输入隐藏)
- **没有** → 全程在终端注册:
  1. 输入邮箱
  2. 收验证码(脚本调 `extapi.pangolinfo.com` 后端发送)
  3. 输入验证码 + 密码
  4. 脚本自动注册并取 permanent token
  5. 写入 `~/.pangolinfo/config.json` (权限 `chmod 600` / Windows ACL 收紧)

也可在 <https://extapi.pangolinfo.com> 网页注册后用 `--api-key=pgl_xxx` 传入。

---

## 验证安装

装完重启 AI 客户端,问它:

> 列出 pangolinfo MCP 的所有工具

应该看到 17 个。然后:

> 用 pangolinfo_capabilities 工具 (mode=summary) 给我一份工具清单

这是免费本地调用,确认装好。再试个付费工具:

> 用 search_amazon 搜 "wireless mouse",拿前 5 个 ASIN

预期: 扣 0.75 积点,返回 ~300 KB 结构化数据。

---

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 用户取消 |
| 2 | 参数错误 |
| 10 | Agent 目录不存在(你可能没装该 Agent) |
| 20 | 网络错误(MCP 下载失败 / SHA256 不匹配) |
| 30 | 后端 API 错误(注册失败、Key 无效) |
| 40 | 文件系统错误(权限、磁盘满) |

---

## 卸载

目前 v0.1 没有自动卸载,手动:

```bash
# macOS / Linux
rm -rf ~/.local/lib/pangolinfo-mcp ~/.pangolinfo
# 然后从 AI 客户端的 mcp 配置文件里删 'pangolinfo' 那一段
```

```powershell
# Windows
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\pangolinfo-mcp", "$env:USERPROFILE\.pangolinfo"
```

`--uninstall` 自动卸载支持计划在 v0.2 加。

---

## 开发

```bash
git clone https://github.com/pangolinfo/pangolinfo-installer.git
cd pangolinfo-installer
# sh 端语法检查
sh -n install.sh
# PowerShell 端语法检查
pwsh -c "[System.Management.Automation.Language.Parser]::ParseFile('install.ps1', [ref]$null, [ref]$null)"
# dry-run 测一遍
./install.sh --agent=cursor --scope=mcp --api-key=pgl_dummy --non-interactive --dry-run
```

跑真测前建议用 `HOME=/tmp/fakehome ./install.sh ...` 隔离,避免污染你自己的客户端配置。

---

## 相关项目

- [pangolinfo-mcp](https://github.com/pangolinfo/pangolinfo-mcp) — MCP server 源码与 release
- [pangolinfo-skills](https://github.com/pangolinfo/pangolinfo-skills) — Skills SOP 知识库 *(单独仓库,待发布)*
- [API 文档](https://docs.pangolinfo.com) — 后端 scrape API 文档

---

## 支持

- 🐛 Bug: <https://github.com/pangolinfo/pangolinfo-installer/issues>
- 📧 email: <support@pangolinfo.com>
- 🌐 主页: <https://pangolinfo.com>

---

## License

[MIT](./LICENSE)
