# Pangolinfo Installer - Agent path table (PowerShell)
# Mirrors lib/agents.sh §3 of CONTRACT-installer.md
# See INSTALLER-COMPAT-REPORT.md for the path/config-shape audit driving these values.
#
# Dot-sourced by install.ps1. Defines $AgentTable and helper functions.
#
# Path table: each agent → @{ DisplayName; SkillsDir; McpConfig; Notes; DistDir }
# SkillsDir may carry a special prefix:
#   "PROJECT:<subpath>" → write under current working directory (project scope)
#   "APPEND:<file>"     → append to a single file (e.g. global_rules.md)

$script:AgentTable = @{
    'claude-code' = @{
        DisplayName = 'Claude Code'
        SkillsDir   = "$env:USERPROFILE\.claude\skills\pangolinfo"
        # B1: 不直接写 ~/.claude.json — 用 settings.json 的 mcpServers 键，或 claude mcp add
        McpConfig   = "$env:USERPROFILE\.claude\settings.json"
        Notes       = 'Official Anthropic CLI'
        DistDir     = 'claude-code'
    }
    'cursor' = @{
        DisplayName = 'Cursor'
        # B2: Cursor rules 是项目级的，写到当前 cwd 的 .cursor/rules/
        SkillsDir   = 'PROJECT:.cursor\rules'
        McpConfig   = "$env:USERPROFILE\.cursor\mcp.json"
        Notes       = 'AI IDE (project-level rules)'
        DistDir     = 'cursor'
    }
    'cline' = @{
        DisplayName = 'Cline (VS Code)'
        # B4: Cline 全局 rules 真实路径
        SkillsDir   = "$env:USERPROFILE\Documents\Cline\Rules\pangolinfo"
        # S1: VS Code 扩展用户的 MCP 路径不同 — install-mcp-cline 函数会探测并加写一份
        McpConfig   = "$env:USERPROFILE\.cline\data\settings\cline_mcp_settings.json"
        Notes       = 'VS Code extension or standalone CLI'
        DistDir     = 'cline'
    }
    'windsurf' = @{
        DisplayName = 'Windsurf'
        # B5: Windsurf 用户规则要写到 global_rules.md 单文件追加
        SkillsDir   = "APPEND:$env:USERPROFILE\.codeium\windsurf\global_rules.md"
        McpConfig   = "$env:USERPROFILE\.codeium\windsurf\mcp_config.json"
        Notes       = 'Codeium AI IDE'
        DistDir     = 'windsurf'
    }
    'hermes' = @{
        DisplayName = 'Hermes'
        SkillsDir   = "$env:USERPROFILE\.hermes\skills\pangolinfo"
        McpConfig   = "$env:USERPROFILE\.hermes\config.yaml"
        Notes       = 'Nous Research local agent (YAML key: mcp_servers)'
        DistDir     = 'hermes'
    }
    'codex' = @{
        DisplayName = 'Codex / OpenCode'
        SkillsDir   = "$env:USERPROFILE\.codex\skills\pangolinfo"
        McpConfig   = "$env:USERPROFILE\.codex\config.toml"
        Notes       = 'OpenAI Codex CLI'
        DistDir     = 'codex'
    }
    'openclaw' = @{
        DisplayName = 'OpenClaw'
        # S3: skills 子路径修正 — workspace/ 是 SOUL.md 身份目录，不是 skills
        SkillsDir   = "$env:USERPROFILE\.openclaw\skills\pangolinfo"
        McpConfig   = "$env:USERPROFILE\.openclaw\openclaw.json"
        Notes       = 'Open-source agent framework'
        DistDir     = 'openclaw'
    }
    'web' = @{
        DisplayName = 'Claude.ai / ChatGPT (web)'
        SkillsDir   = "$env:USERPROFILE\Downloads\pangolinfo-skills.zip"
        McpConfig   = 'none'
        Notes       = 'Web app — manual upload required'
        DistDir     = 'claude-code'
    }
}

$script:AgentOrder = @(
    'claude-code', 'cursor', 'cline', 'windsurf',
    'hermes', 'codex', 'openclaw', 'web'
)

function Get-AgentInfo {
    param([string]$Name)
    if ($script:AgentTable.ContainsKey($Name)) {
        return $script:AgentTable[$Name]
    }
    return $null
}

# 探测 VS Code 扩展版 Cline 的 globalStorage 路径（S1）
# 返回路径字符串 或 $null
function Find-ClineVsCodeExtDir {
    $extId = 'saoudrizwan.claude-dev'
    $candidates = @(
        (Join-Path $env:APPDATA "Code\User\globalStorage\$extId"),
        (Join-Path $env:USERPROFILE "AppData\Roaming\Code\User\globalStorage\$extId"),
        (Join-Path $env:USERPROFILE "Library/Application Support/Code/User/globalStorage/$extId"),
        (Join-Path $env:USERPROFILE ".config/Code/User/globalStorage/$extId")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Test-AgentInstalled {
    param([string]$Name)
    switch ($Name) {
        'claude-code' { return (Test-Path (Join-Path $env:USERPROFILE '.claude')) }
        'cursor'      { return (Test-Path (Join-Path $env:USERPROFILE '.cursor')) }
        'cline'       {
            $vsCode = Find-ClineVsCodeExtDir
            if ($null -ne $vsCode) { return $true }
            return (Test-Path (Join-Path $env:USERPROFILE '.cline'))
        }
        'windsurf'    { return (Test-Path (Join-Path $env:USERPROFILE '.codeium\windsurf')) }
        'hermes'      { return (Test-Path (Join-Path $env:USERPROFILE '.hermes')) }
        'codex'       { return (Test-Path (Join-Path $env:USERPROFILE '.codex')) }
        'openclaw'    { return (Test-Path (Join-Path $env:USERPROFILE '.openclaw')) }
        'web'         { return $false }
        default       { return $false }
    }
}
