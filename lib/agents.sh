#!/bin/sh
# Pangolinfo Installer - Agent path table (POSIX sh)
# See CONTRACT-installer.md §3 + INSTALLER-COMPAT-REPORT.md
#
# 这是被 install.sh source 进去的纯数据文件。新增 Agent 时改这里即可。
#
# 用法：agent_paths <agent-name>  → 在 stdout 打印 4 行：
#   line 1: display name
#   line 2: skills install dir (absolute path with $HOME expanded)
#           特殊值 "PROJECT:<subpath>" 表示要写到当前 cwd 下的项目内子路径
#           特殊值 "APPEND:<file>" 表示要追加写入单个文件（如 global_rules.md）
#   line 3: mcp config file (absolute path) 或 "none" 表示该 Agent 不支持 MCP
#           特殊值 "CMD:claude-mcp-add" 表示要 shell-out 调 `claude mcp add`
#   line 4: notes (free text)
#
# 各 agent 的路径已对照 2026-05 官方文档核实，详见 INSTALLER-COMPAT-REPORT.md

agent_paths() {
  case "$1" in
    claude-code)
      echo "Claude Code"
      echo "$HOME/.claude/skills/pangolinfo"
      # B1: 不直接写 ~/.claude.json (扁平 mcpServers 不被识别)
      # 改用 user-scope settings.json 或 shell-out 调 claude mcp add
      echo "$HOME/.claude/settings.json"
      echo "Official Anthropic CLI"
      ;;
    cursor)
      echo "Cursor"
      # B2: Cursor rules 是项目级的 — 写到当前 cwd 的 .cursor/rules/
      # 同时改为 .mdc 单文件（见 B3，由 install_skills_cursor 处理）
      echo "PROJECT:.cursor/rules"
      echo "$HOME/.cursor/mcp.json"
      echo "AI IDE (project-level rules)"
      ;;
    cline)
      echo "Cline (VS Code)"
      # B4: Cline 全局 rules 真实路径
      echo "$HOME/Documents/Cline/Rules/pangolinfo"
      # S1: VS Code 扩展用户的 MCP 路径不同 — install_mcp_cline 函数会探测
      echo "$HOME/.cline/data/settings/cline_mcp_settings.json"
      echo "VS Code extension or standalone CLI"
      ;;
    windsurf)
      echo "Windsurf"
      # B5: Windsurf 用户规则要写到 global_rules.md 单文件（追加）
      # memories/ 是 Cascade 自动记忆区，不是用户规则
      echo "APPEND:$HOME/.codeium/windsurf/global_rules.md"
      echo "$HOME/.codeium/windsurf/mcp_config.json"
      echo "Codeium AI IDE"
      ;;
    hermes)
      echo "Hermes"
      echo "$HOME/.hermes/skills/pangolinfo"
      echo "$HOME/.hermes/config.yaml"
      echo "Nous Research local agent (YAML key: mcp_servers)"
      ;;
    codex)
      echo "Codex / OpenCode"
      # 同时写两份：旧路径 + 新 cross-tool convention
      echo "$HOME/.codex/skills/pangolinfo"
      echo "$HOME/.codex/config.toml"
      echo "OpenAI Codex CLI"
      ;;
    openclaw)
      echo "OpenClaw"
      # S3: skills 子路径修正 — workspace/ 是 SOUL.md 身份目录，不是 skills
      echo "$HOME/.openclaw/skills/pangolinfo"
      echo "$HOME/.openclaw/openclaw.json"
      echo "Open-source agent framework"
      ;;
    web)
      echo "Claude.ai / ChatGPT (web)"
      echo "$HOME/Downloads/pangolinfo-skills.zip"
      echo "none"
      echo "Web app — manual upload required"
      ;;
    *)
      return 1
      ;;
  esac
}

# Skills 目录格式：返回 dist 子目录名（用于决定从 pangolinfo-skills/dist/<which>/ 拷贝什么）
agent_dist_dir() {
  case "$1" in
    claude-code) echo "claude-code" ;;
    cursor)      echo "cursor" ;;
    cline)       echo "cline" ;;
    windsurf)    echo "windsurf" ;;
    hermes)      echo "hermes" ;;
    codex)       echo "codex" ;;
    openclaw)    echo "openclaw" ;;
    web)         echo "claude-code" ;;  # web 端用 SKILL.md 标准格式打包
    *)           return 1 ;;
  esac
}

# 已知 Agent 列表（用于菜单显示）
ALL_AGENTS="claude-code cursor cline windsurf hermes codex openclaw web"

# 检测某 agent 是否已装：返回 0 = 已装，1 = 未装/无法判定
# 检测信号：检查 agent 安装时生成的根目录是否存在
agent_is_installed() {
  case "$1" in
    claude-code) [ -d "$HOME/.claude" ] ;;
    cursor)      [ -d "$HOME/.cursor" ] ;;
    cline)
      # 探测两种安装模式：VS Code 扩展 或 独立 CLI
      [ -d "$HOME/.cline" ] || _cline_vscode_ext_dir >/dev/null
      ;;
    windsurf)    [ -d "$HOME/.codeium/windsurf" ] ;;
    hermes)      [ -d "$HOME/.hermes" ] ;;
    codex)       [ -d "$HOME/.codex" ] ;;
    openclaw)    [ -d "$HOME/.openclaw" ] ;;
    web)         return 1 ;;  # 网页端永远"未检测到"（用户自己选）
    *)           return 1 ;;
  esac
}

# 探测 VS Code 扩展版 Cline 的 globalStorage 路径（S1）
# 各平台 VS Code 的 globalStorage 目录不同
# 返回 0 + 路径 stdout；返回 1 = 没找到
_cline_vscode_ext_dir() {
  ext_id="saoudrizwan.claude-dev"
  # macOS
  p1="$HOME/Library/Application Support/Code/User/globalStorage/$ext_id"
  # Linux
  p2="$HOME/.config/Code/User/globalStorage/$ext_id"
  # Windows (在 git-bash / WSL 下可能用 %APPDATA% 也可能是 /c/Users/...)
  p3="${APPDATA:-$HOME/AppData/Roaming}/Code/User/globalStorage/$ext_id"
  for p in "$p1" "$p2" "$p3"; do
    if [ -d "$p" ]; then echo "$p"; return 0; fi
  done
  return 1
}
