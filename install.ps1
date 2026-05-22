# Pangolinfo Installer · Windows PowerShell
# Spec: CONTRACT-installer.md, CONTRACT-i18n.md
# Requires: PowerShell 5.1+
#
# Quick start:
#   irm install.pangolinfo.com/install.ps1 | iex
#   irm install.pangolinfo.com/install.ps1 | iex; Install-Pangolinfo -Agent claude-code -Scope both

[CmdletBinding()]
param(
    [string]$Agent           = '',
    [ValidateSet('', 'skills', 'mcp', 'both')]
    [string]$Scope           = '',
    [string]$ApiKey          = '',
    [string]$ApiBase         = 'https://extapi.pangolinfo.com',
    [string]$ScrapeBase      = 'https://scrapeapi.pangolinfo.com',
    [switch]$NonInteractive,
    [switch]$DryRun,
    [string]$SkillsVersion   = 'latest',
    [string]$McpVersion      = 'latest',
    [ValidateSet('', 'zh', 'en')]
    [string]$Lang            = '',
    [switch]$Help
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:InstallerVersion = '0.1.0'
$script:GitHubUrl        = 'https://github.com/pangolinfo'
$script:ConfigDir        = Join-Path $env:USERPROFILE '.pangolinfo'
$script:ConfigFile       = Join-Path $script:ConfigDir 'config.json'
$script:McpInstallDir    = Join-Path $env:LOCALAPPDATA 'pangolinfo-mcp'

# MCP server 二进制从 GitHub Release 拉。
# /latest/ 自动跟随最新 release;客户可用 -McpVersion v0.1.2 锁版本。
# 单文件 ESM bundle (~800 KB),零运行时依赖,只需 node 18+ 在 PATH。
$script:McpReleaseBase   = 'https://github.com/pangolinfo/pangolinfo-mcp/releases'

# ---------------------------------------------------------------------------
# i18n: language detection
# ---------------------------------------------------------------------------
function Get-Lang {
    param([string]$Explicit)
    if ($Explicit -eq 'zh' -or $Explicit -eq 'en') { return $Explicit }
    if ($env:PANGOLINFO_LANG -eq 'zh' -or $env:PANGOLINFO_LANG -eq 'en') {
        return $env:PANGOLINFO_LANG
    }
    try {
        $culture = (Get-Culture).Name
        if ($culture -like 'zh*') { return 'zh' }
        if ($culture)             { return 'en' }
    } catch {}
    return 'zh'
}

$script:Lang = Get-Lang -Explicit $Lang

# ---------------------------------------------------------------------------
# i18n: dictionary (keys MUST mirror install.sh)
# ---------------------------------------------------------------------------
$script:Translations = @{
    zh = @{
        # Banner (Phase 1)
        banner_title              = 'Pangolinfo MCP Server 部署'
        banner_intro              = '欢迎使用 Pangolinfo MCP 安装程序。该脚本会把 Amazon 实时抓取能力集成到你的本地 AI 环境。'
        banner_desc_header        = '此安装程序将：'
        banner_desc_skills        = '在你 AI 客户端的配置中注册 pangolinfo-mcp 服务'
        banner_desc_mcp           = '部署 Skills 知识包到你的 AI 助手'
        banner_desc_apikey        = '安全建立运行时凭据与计费上下文'

        # Help
        help_usage_header         = '用法：'
        help_options_header       = '参数：'
        help_examples_header      = '示例：'
        help_exitcodes_header     = '退出码：'
        help_opt_agent            = '你的 AI 助手'
        help_opt_scope            = '安装范围 skills|mcp|both（默认 both）'
        help_opt_apikey           = '已有的 Pangolinfo API Key'
        help_opt_apibase          = '覆盖默认 API base URL'
        help_opt_scrapebase       = '覆盖默认 scrape base URL'
        help_opt_noninteractive   = '缺参数直接报错，不弹菜单'
        help_opt_skillsver        = '锁定 Skills 版本（默认 latest）'
        help_opt_mcpver           = '锁定 MCP 版本（默认 latest）'
        help_opt_dryrun           = '只打印操作不执行'
        help_opt_lang             = '界面语言 zh|en（默认按系统检测）'
        help_opt_help             = '显示本帮助'
        help_ex_interactive       = '# 快速开始（交互式菜单）'
        help_ex_preset            = '# 预设参数'
        help_ex_headless          = '# 无人值守（CI / 脚本化）'
        help_exit_table           = "   0 成功 | 1 用户取消 | 2 参数错误 | 10 Agent 目录不存在`n  20 网络错误 | 30 后端 API 错误 | 40 文件系统错误"

        # Prompts / menus
        prompt_continue           = '是否按标准方式继续安装？(Y/n)'
        info_cancelled            = '已取消。'
        menu_choose_agent         = '你在用哪个 AI 助手？'
        prompt_enter_agent_num    = '请输入序号 [1-8]:'
        prompt_enter_agent_num_default = '请输入序号 [1-8, 默认'
        label_detected            = '已检测到'
        info_agent_autodetect_summary = '已嗅探到本机已装 AI 助手数量：'
        info_agent_autodetect_none = '未嗅探到已装的 AI 助手——请手动选。'
        menu_choose_scope         = '你想安装哪些组件？'
        menu_scope_skills         = '仅 Skills            (只装方法论，轻量)'
        menu_scope_mcp            = '仅 MCP               (只装 API 工具，给开发者)'
        menu_scope_both           = '两者都装 (推荐)        (体验最完整)'
        prompt_enter_scope_num    = '请输入序号 [1-3, 默认 3]:'
        error_invalid_selection   = '无效的选项：'
        error_unknown_agent       = '未识别的 Agent：'
        error_unknown_agent_hint  = '运行 -Help 查看有效值。'
        error_unknown_option      = '未识别的参数：'
        error_agent_required_ni   = '-Agent 参数在 -NonInteractive 模式下必填'
        error_scope_required_ni   = '-Scope 参数在 -NonInteractive 模式下必填'
        error_invalid_scope       = '无效的安装范围'
        error_invalid_scope_hint  = '可选值：skills|mcp|both'
        warn_web_no_mcp           = 'Web 端不支持 MCP，已降级为 scope=skills。'

        # Scope preset (from landing-page generated command)
        info_scope_preset         = '安装范围已由落地页指定：'
        info_scope_mcp_only_hint  = '你只装 MCP 工具，不含方法论 SOP。如需 Skills，请从 pangolinfo.com/skills 重新生成命令。'

        # API key flow
        info_scope_skills_no_key  = '安装范围=skills，无需 API Key。'
        info_validating_key       = '正在校验你提供的 API Key...'
        info_dryrun_validate_key  = '[dry-run] 会通过 GET 校验 Key'
        ok_key_valid              = 'API Key 可用。'
        error_key_invalid_provided= '你提供的 API Key 无效。'
        error_key_required_ni     = '缺少 API Key（使用 -ApiKey pgl_...）'
        prompt_has_key            = '你已经有 Pangolinfo API Key 吗？[y/N]'
        prompt_arrow              = '>'
        prompt_paste_key          = '粘贴你的 API Key（输入不显示）'
        error_empty_key           = 'Key 为空，请重试。'
        info_dryrun_validate      = '[dry-run] 会校验该 Key'
        info_validating           = '正在校验...'
        error_key_invalid_retry   = "Key 无效。按 r 重试，按 n 注册新账号。"
        info_register_intro       = '接下来在终端里注册 Pangolinfo 账号。'
        prompt_email              = '邮箱：'
        error_bad_email           = '邮箱格式不正确。'
        info_dryrun_send_code     = '[dry-run] 会向以下邮箱发验证码：'
        info_sending_code         = '正在发送验证码到'
        error_send_code_failed    = '发送验证码失败。常见原因：'
        error_send_code_reason_rate = '频率限制（每邮箱 1 次/分钟，每 IP 5 次/小时）'
        error_send_code_reason_net  = '网络问题'
        ok_code_sent              = '验证码已发送，请检查收件箱（也看一下垃圾邮件）。'
        prompt_code               = '验证码（6 位数字）：'
        prompt_password           = '密码（8-20 位，需含字母和数字，输入不显示）'
        error_weak_password       = '密码不符合要求。需 8-20 位，必须包含字母和数字。'
        info_dryrun_register      = '[dry-run] 会调用 /user/reg 与 /user/permanent-token'
        info_creating_account     = '正在创建账号...'
        error_register_failed     = '注册失败。请检查验证码或联系客服。'
        ok_account_created        = '账号已创建。'
        info_fetching_perm_key    = '正在获取永久 API Key...'
        error_perm_key_failed     = '获取永久 Key 失败（已拿到会话）。请联系客服。'
        ok_key_obtained           = 'API Key 获取成功。'

        # Phase 2: Activation (API Key guidance)
        phase2_title              = '🚀 服务状态：已安装（等待激活）'
        phase2_step1              = '第 1 步：激活你的 API Key'
        phase2_step1_intro        = '开启实时抓取能力需要一个有效的 API Key。'
        phase2_existing_label     = '已有账号？'
        phase2_existing_hint      = '到开发者控制台复制你的 Key：'
        phase2_new_label          = '新用户？'
        phase2_new_hint           = '立刻注册赠送 60 测试积分（也可以直接在终端完成注册）：'
        dashboard_url             = 'https://tool.pangolinfo.com/#/zh/menu/dataAPI/keys'
        signup_url                = 'https://tool.pangolinfo.com/?sourceTag=mcp'

        # Config
        info_dryrun_write_config  = '[dry-run] 会写入配置文件（仅当前用户可读）：'
        error_cannot_create_dir   = '无法创建目录：'
        warn_chmod_failed         = '无法收紧文件权限：'
        ok_config_saved           = '配置已保存到'

        # Phase 3: Security & Data Transparency
        phase3_title              = '✅ 鉴权已激活'
        phase3_security_header    = '安全与存储说明：'
        phase3_security_local     = '本地存储：你的 Key 保存在本地 AI 客户端的配置文件中，权限已收紧为仅当前用户可读。'
        phase3_security_https     = '加密传输：所有数据传输强制走 HTTPS。'
        phase3_security_privacy   = '隐私：Pangolinfo 是无状态数据提供方，不会记录你 AI 的对话历史或 prompt 上下文。'
        phase3_warning            = '警告：此配置文件包含敏感凭据。请勿提交到公开版本控制系统。'

        # Skills install
        info_scope_mcp_skip_skills= '安装范围=mcp，跳过 Skills。'
        info_installing_skills    = '正在安装 Skills...'
        label_source              = '来源：'
        label_target              = '目标：'
        info_dryrun_copy_skills   = '[dry-run] 会把 Skills 拷贝到：'
        error_skills_src_missing  = '找不到 Skills 源目录：'
        error_skills_src_hint     = "请先在 pangolinfo-skills/ 里跑 'npm run build'（开发模式）"
        info_backed_up            = '已备份原目录 →'
        ok_packaged_skills        = '已打包 Skills →'
        info_web_next_header      = 'Web 端后续步骤：'
        info_web_step1            = '在浏览器中打开 Claude.ai 或 ChatGPT'
        info_web_step2            = '创建 Project（Claude）或自定义 GPT（OpenAI）'
        info_web_step3            = '把 ZIP 上传为知识库：'
        info_web_step4            = "添加自定义指令：'请根据附带知识库中的 SKILL.md 调用 Pangolinfo 技能'"
        error_parent_missing      = '父目录不存在：'
        error_agent_not_installed_prefix = 'Agent'
        error_agent_not_installed_suffix = '可能还没装。请先初始化它再跑本安装程序。'
        error_copy_failed         = '拷贝 Skills 失败'
        ok_skills_installed       = 'Skills 已安装到'

        # MCP install
        info_scope_skills_skip_mcp= '安装范围=skills，跳过 MCP。'
        info_web_skip_mcp         = 'Web 端不支持 MCP，跳过。'
        info_installing_mcp       = '正在安装 MCP 服务...'
        info_dryrun_install_mcp   = '[dry-run] 会安装 MCP 到：'
        info_dryrun_register_mcp  = '[dry-run] 会在以下配置中注册：'
        info_downloading_mcp      = '正在从 GitHub Release 下载 MCP server (~800 KB)...'
        info_verifying_sha256     = '正在校验 SHA256...'
        ok_sha256_verified        = 'SHA256 校验通过。'
        warn_sha256_skipped       = '未找到 SHA256 校验工具，跳过完整性校验（不影响功能）。'
        error_mcp_download_failed = '下载 MCP server 失败：'
        error_mcp_download_hint   = '请检查网络连接是否能访问 github.com，或重试。'
        error_sha256_mismatch     = 'SHA256 校验失败——下载的文件可能被破坏或篡改，已删除。'
        ok_mcp_binary_at          = 'MCP server 已安装：'
        warn_no_mcp_config        = '该 Agent 没有 MCP 注册文件：'
        ok_mcp_created_config     = '已创建配置并写入 pangolinfo：'
        ok_mcp_registered         = '已在以下配置中注册 pangolinfo：'
        warn_no_jq                = '无法安全合并到现有配置：'
        warn_add_manually         = '请在 "mcpServers" 下手动添加：'
        warn_node_missing         = '未检测到 node。MCP server 启动需要 Node.js 18+。安装方式见 README.md 的《前置环境》段。'

        # Per-agent install messages (v0.1 兼容性适配)
        info_codex_dual_path      = '同时写入新版 cross-tool 路径：'
        info_cursor_project_scope = 'Cursor rules 是项目级——已写到：'
        ok_cursor_mdc_written     = '已写入 .mdc 规则文件数：'
        info_cursor_global_hint   = '如需全局生效，请把上面的 .mdc 内容粘贴到 Cursor → Settings → User Rules。'
        info_cline_global_loaded  = 'Cline 启动时会自动加载 ~/Documents/Cline/Rules/ 下所有规则。'
        ok_windsurf_appended      = '已追加 Pangolinfo 段到：'
        info_using_claude_cli     = '检测到 claude CLI——使用 ''claude mcp add'' 注册'
        warn_claude_cli_failed    = 'claude mcp add 失败，回退到写 settings.json'
        info_cline_vscode_detected = '检测到 VS Code 扩展版 Cline，写入：'
        info_mcp_already_registered = '配置中已存在 pangolinfo 节点，跳过：'
        info_mcp_manual_overwrite = '如需更新请手动编辑或删掉旧节点重跑。'

        # Done
        done_success              = '✓ Pangolinfo 安装成功！'
        done_agent_label          = 'Agent：'
        done_scope_label          = '安装范围：'
        done_try_header           = '在你的 AI 助手里试试这些：'
        done_try_1                = '用 Pangolinfo 查询 ASIN B0XXXXXXXX 的 Buy Box 价格'
        done_try_2                = '帮我做一份蓝牙耳机的 Amazon 选品报告'
        done_star_prompt          = '觉得好用？在 GitHub 给我们点个 Star：'
        done_small_team           = '我们是一支小团队，你的 Star 对我们意义重大。🙏'
    }
    en = @{
        # Banner (Phase 1)
        banner_title              = 'Pangolinfo MCP Server Deployment'
        banner_intro              = 'Welcome to the Pangolinfo MCP Installer. This script will integrate Amazon real-time scraping capabilities into your local AI environment.'
        banner_desc_header        = 'The installer will:'
        banner_desc_skills        = "Detect and configure the pangolinfo-mcp server within your AI client's config"
        banner_desc_mcp           = 'Deploy Skills knowledge packs to your AI agent'
        banner_desc_apikey        = 'Set up the secure runtime for data execution'

        # Help
        help_usage_header         = 'USAGE:'
        help_options_header       = 'PARAMETERS:'
        help_examples_header      = 'EXAMPLES:'
        help_exitcodes_header     = 'EXIT CODES:'
        help_opt_agent            = 'Your AI agent'
        help_opt_scope            = 'skills | mcp | both                  [default: both]'
        help_opt_apikey           = 'Existing Pangolinfo API key'
        help_opt_apibase          = 'Override default API base URL'
        help_opt_scrapebase       = 'Override default scrape API base URL'
        help_opt_noninteractive   = 'Fail instead of prompting for missing args'
        help_opt_skillsver        = 'Pin Skills version (default: latest)'
        help_opt_mcpver           = 'Pin MCP server version (default: latest)'
        help_opt_dryrun           = 'Print actions without executing'
        help_opt_lang             = 'UI language zh|en (default: auto-detect)'
        help_opt_help             = 'Show this help'
        help_ex_interactive       = '# Quick start (interactive menu)'
        help_ex_preset            = '# Pre-configured'
        help_ex_headless          = '# Headless (CI / scripted)'
        help_exit_table           = "   0 success | 1 user-cancel | 2 bad args | 10 agent dir missing`n  20 network error | 30 backend API error | 40 filesystem error"

        # Prompts / menus
        prompt_continue           = 'Proceed with standard installation? (Y/n)'
        info_cancelled            = 'Cancelled.'
        menu_choose_agent         = 'Which AI agent do you use?'
        prompt_enter_agent_num    = 'Enter number [1-8]:'
        prompt_enter_agent_num_default = 'Enter number [1-8, default'
        label_detected            = 'detected'
        info_agent_autodetect_summary = 'Detected installed AI agents:'
        info_agent_autodetect_none = 'No AI agents auto-detected — please pick manually.'
        menu_choose_scope         = 'What do you want to install?'
        menu_scope_skills         = 'Skills only       (methodology only, lightweight)'
        menu_scope_mcp            = 'MCP only          (API tools only, for developers)'
        menu_scope_both           = 'Both (recommended)  (best experience)'
        prompt_enter_scope_num    = 'Enter number [1-3, default 3]:'
        error_invalid_selection   = 'Invalid selection:'
        error_unknown_agent       = 'Unknown agent:'
        error_unknown_agent_hint  = 'Run -Help for valid values.'
        error_unknown_option      = 'Unknown option:'
        error_agent_required_ni   = '-Agent is required in -NonInteractive mode'
        error_scope_required_ni   = '-Scope is required in -NonInteractive mode'
        error_invalid_scope       = 'Invalid scope'
        error_invalid_scope_hint  = 'Use skills|mcp|both.'
        warn_web_no_mcp           = 'Web agent does not support MCP. Falling back to scope=skills.'

        # Scope preset (from landing-page generated command)
        info_scope_preset         = 'Install scope (from landing page):'
        info_scope_mcp_only_hint  = 'MCP-only install — methodology SOPs not included. For Skills, generate command from pangolinfo.com/skills.'

        # API key flow
        info_scope_skills_no_key  = 'Scope=skills, no API key required.'
        info_validating_key       = 'Validating provided API key...'
        info_dryrun_validate_key  = '[dry-run] would validate key via GET'
        ok_key_valid              = 'API key valid.'
        error_key_invalid_provided= 'Provided API key is invalid.'
        error_key_required_ni     = 'API key required (-ApiKey pgl_...)'
        prompt_has_key            = 'Do you have a Pangolinfo API key? [y/N]'
        prompt_arrow              = '>'
        prompt_paste_key          = 'Paste your API key (input hidden)'
        error_empty_key           = 'Empty key, try again.'
        info_dryrun_validate      = '[dry-run] would validate key'
        info_validating           = 'Validating...'
        error_key_invalid_retry   = "Key invalid. Press 'r' to retry, 'n' to register a new account."
        info_register_intro       = "Let's register a Pangolinfo account — fully in terminal."
        prompt_email              = 'Email:'
        error_bad_email           = 'Invalid email format.'
        info_dryrun_send_code     = '[dry-run] would POST /email/code/send to'
        info_sending_code         = 'Sending verification code to'
        error_send_code_failed    = 'Failed to send code. Possible reasons:'
        error_send_code_reason_rate = 'Rate limit (1/min per email, 5/hour per IP)'
        error_send_code_reason_net  = 'Network issue'
        ok_code_sent              = 'Code sent. Check your inbox (and spam folder).'
        prompt_code               = 'Verification code (6 digits):'
        prompt_password           = 'Password (8-20 chars, must include letter+number, hidden)'
        error_weak_password       = 'Password too weak. Need 8-20 chars with both letters and digits.'
        info_dryrun_register      = '[dry-run] would POST /user/reg and GET /user/permanent-token'
        info_creating_account     = 'Creating account...'
        error_register_failed     = 'Registration failed. Check your code or contact support.'
        ok_account_created        = 'Account created.'
        info_fetching_perm_key    = 'Fetching your permanent API key...'
        error_perm_key_failed     = 'Got session but failed to fetch permanent token. Contact support.'
        ok_key_obtained           = 'API key obtained.'

        # Phase 2: Activation (API Key guidance)
        phase2_title              = '🚀 Server Status: Installed (Awaiting Authentication)'
        phase2_step1              = 'Step 1: Activate Your API Key'
        phase2_step1_intro        = 'To enable live scraping, you need a valid API Key.'
        phase2_existing_label     = 'Existing Users:'
        phase2_existing_hint      = 'Copy your key from the Developer Dashboard:'
        phase2_new_label          = 'New Users:'
        phase2_new_hint           = 'Register now to receive 60 Complimentary Testing Credits (or finish registration here in terminal):'
        dashboard_url             = 'https://tool.pangolinfo.com/#/en/menu/dataAPI/keys'
        signup_url                = 'https://tool.pangolinfo.com/?sourceTag=mcp'

        # Config
        info_dryrun_write_config  = '[dry-run] would write config (ACL: user-only):'
        error_cannot_create_dir   = 'Cannot create'
        warn_chmod_failed         = 'Could not tighten ACL on'
        ok_config_saved           = 'Config saved to'

        # Phase 3: Security & Data Transparency
        phase3_title              = '✅ Authentication Active'
        phase3_security_header    = 'Security & Storage Note:'
        phase3_security_local     = "Local Storage: Your Key is stored locally in your AI client's config. We've already restricted permissions to current user only."
        phase3_security_https     = 'Encryption: All data transmission is strictly over HTTPS.'
        phase3_security_privacy   = "Privacy: Pangolinfo is a stateless data provider. We do not log or store your AI's conversation history or prompt context."
        phase3_warning            = 'Warning: Treat this configuration as a sensitive credential. Do not commit your config files to public version control.'

        # Skills install
        info_scope_mcp_skip_skills= 'Scope=mcp, skipping Skills.'
        info_installing_skills    = 'Installing Skills...'
        label_source              = 'source:'
        label_target              = 'target:'
        info_dryrun_copy_skills   = '[dry-run] would copy Skills to'
        error_skills_src_missing  = 'Skills source not found:'
        error_skills_src_hint     = "Run 'npm run build' in pangolinfo-skills/ first (dev mode)"
        info_backed_up            = 'Backed up existing →'
        ok_packaged_skills        = 'Packaged Skills →'
        info_web_next_header      = 'Next steps for web:'
        info_web_step1            = 'Open Claude.ai or ChatGPT in your browser'
        info_web_step2            = 'Create a Project (Claude) or custom GPT (OpenAI)'
        info_web_step3            = 'Upload as Knowledge Base:'
        info_web_step4            = "Add Custom Instructions: 'Use the SKILL.md files in the attached knowledge base to invoke Pangolinfo skills.'"
        error_parent_missing      = 'Parent directory does not exist:'
        error_agent_not_installed_prefix = 'Is'
        error_agent_not_installed_suffix = 'installed? Initialize it once before running this installer.'
        error_copy_failed         = 'Failed to copy Skills'
        ok_skills_installed       = 'Skills installed to'

        # MCP install
        info_scope_skills_skip_mcp= 'Scope=skills, skipping MCP.'
        info_web_skip_mcp         = 'Web agent does not support MCP — skipping.'
        info_installing_mcp       = 'Installing MCP server...'
        info_dryrun_install_mcp   = '[dry-run] would install MCP to'
        info_dryrun_register_mcp  = '[dry-run] would register in'
        info_downloading_mcp      = 'Downloading MCP server from GitHub Release (~800 KB)...'
        info_verifying_sha256     = 'Verifying SHA256...'
        ok_sha256_verified        = 'SHA256 verified.'
        warn_sha256_skipped       = 'SHA256 tool not available — skipping integrity check (functional).'
        error_mcp_download_failed = 'Failed to download MCP server:'
        error_mcp_download_hint   = 'Check network access to github.com and retry.'
        error_sha256_mismatch     = 'SHA256 mismatch — downloaded file may be corrupted or tampered with; removed.'
        ok_mcp_binary_at          = 'MCP server binary at'
        warn_no_mcp_config        = 'Agent has no MCP registration file:'
        ok_mcp_created_config     = 'Created config with pangolinfo entry:'
        ok_mcp_registered         = 'Registered pangolinfo in'
        warn_no_jq                = 'Cannot safely merge into existing config:'
        warn_add_manually         = 'Please add manually under "mcpServers":'
        warn_node_missing         = 'node not found in PATH. MCP server requires Node.js 18+. See README.md > Prerequisites for install instructions.'

        # Per-agent install messages (v0.1 compat adaptation)
        info_codex_dual_path      = 'Also wrote to new cross-tool path:'
        info_cursor_project_scope = 'Cursor rules are project-scoped — wrote to:'
        ok_cursor_mdc_written     = '.mdc rule files written:'
        info_cursor_global_hint   = 'For global scope, paste the .mdc content into Cursor → Settings → User Rules.'
        info_cline_global_loaded  = 'Cline auto-loads all rules from ~/Documents/Cline/Rules/ on startup.'
        ok_windsurf_appended      = 'Appended Pangolinfo section to:'
        info_using_claude_cli     = "Detected claude CLI - using 'claude mcp add'"
        warn_claude_cli_failed    = 'claude mcp add failed; falling back to settings.json'
        info_cline_vscode_detected = 'Detected Cline VS Code extension; writing to:'
        info_mcp_already_registered = 'pangolinfo entry already exists, skipping:'
        info_mcp_manual_overwrite = 'Edit manually or remove the old entry and re-run to update.'

        # Done
        done_success              = '✓ Pangolinfo installed successfully!'
        done_agent_label          = 'Agent:'
        done_scope_label          = 'Scope:'
        done_try_header           = 'Try this in your AI agent:'
        done_try_1                = 'Use Pangolinfo to get the buybox price for ASIN B0XXXXXXXX'
        done_try_2                = 'Help me research Amazon niches for bluetooth earphones'
        done_star_prompt          = 'Enjoyed it? Star us on GitHub:'
        done_small_team           = "We're a small team. Your star really helps. 🙏"
    }
}

function t {
    param([string]$Key)
    $tbl = $script:Translations[$script:Lang]
    if ($null -ne $tbl[$Key]) { return $tbl[$Key] }
    # 兜底：英文不存在时回退中文，反之亦然
    $fallback = if ($script:Lang -eq 'en') { 'zh' } else { 'en' }
    return $script:Translations[$fallback][$Key]
}

# Source agent table
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsLib = Join-Path $ScriptDir 'lib\agents.ps1'
if (Test-Path $AgentsLib) {
    . $AgentsLib
} else {
    Write-Host "ERROR: lib\agents.ps1 not found." -ForegroundColor Red
    Write-Host "When using 'irm | iex', download the full installer instead." -ForegroundColor Red
    exit 2
}

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
$script:SelectedAgent = $Agent
$script:SelectedScope = $Scope
$script:ResolvedKey   = $ApiKey
$script:McpVersion    = $McpVersion

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
function Write-Info  { Write-Host "› $args" -ForegroundColor DarkGray }
function Write-OK    { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Err   { Write-Host "✗ $args" -ForegroundColor Red }
function Stop-Fatal  { param([string]$Msg, [int]$Code = 1); Write-Err $Msg; exit $Code }

function Read-Prompt {
    param([string]$Message)
    Write-Host -NoNewline "$Message "
    return Read-Host
}

function Read-Secret {
    param([string]$Message)
    $secure = Read-Host -Prompt $Message -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Show-Help {
    @"
$(t 'banner_title') v$($script:InstallerVersion)

$(t 'help_usage_header')
  irm install.pangolinfo.com/install.ps1 | iex
  .\install.ps1 -Agent claude-code -Scope both [-ApiKey pgl_...] [-DryRun]

$(t 'help_options_header')
  -Agent           claude-code | cursor | cline | windsurf
                   hermes | codex | openclaw | web
                   $(t 'help_opt_agent')
  -Scope           $(t 'help_opt_scope')
  -ApiKey          $(t 'help_opt_apikey')
  -ApiBase         $(t 'help_opt_apibase')
  -ScrapeBase      $(t 'help_opt_scrapebase')
  -NonInteractive  $(t 'help_opt_noninteractive')
  -SkillsVersion   $(t 'help_opt_skillsver')
  -McpVersion      $(t 'help_opt_mcpver')
  -DryRun          $(t 'help_opt_dryrun')
  -Lang            $(t 'help_opt_lang')
  -Help            $(t 'help_opt_help')

$(t 'help_exitcodes_header')
$(t 'help_exit_table')
"@ | Write-Host
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
function Show-Banner {
    Write-Host ''
    Write-Host ("[$(t 'banner_title') v$($script:InstallerVersion)]") -ForegroundColor White
    Write-Host (t 'banner_intro') -ForegroundColor DarkGray
    Write-Host $script:GitHubUrl -ForegroundColor DarkGray
    Write-Host ''
    Write-Host (t 'banner_desc_header') -ForegroundColor White
    Write-Host ("  " + [char]0x2022 + " " + (t 'banner_desc_skills'))
    Write-Host ("  " + [char]0x2022 + " " + (t 'banner_desc_mcp'))
    Write-Host ("  " + [char]0x2022 + " " + (t 'banner_desc_apikey'))
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Agent selection
# ---------------------------------------------------------------------------
function Select-Agent {
    if ($script:SelectedAgent) {
        if (-not (Get-AgentInfo $script:SelectedAgent)) {
            Stop-Fatal "$(t 'error_unknown_agent') $($script:SelectedAgent). $(t 'error_unknown_agent_hint')" 2
        }
        return
    }
    if ($NonInteractive) { Stop-Fatal (t 'error_agent_required_ni') 2 }

    # 自动嗅探已装 agent
    $defaultIdx = $null
    $detectedCount = 0
    $i = 1
    foreach ($name in $script:AgentOrder) {
        if (Test-AgentInstalled $name) {
            $detectedCount++
            if (-not $defaultIdx) { $defaultIdx = $i }
        }
        $i++
    }
    if ($detectedCount -gt 0) {
        Write-Info "$(t 'info_agent_autodetect_summary') $detectedCount"
    } else {
        Write-Info (t 'info_agent_autodetect_none')
    }
    Write-Host ''

    Write-Host (t 'menu_choose_agent') -ForegroundColor White
    $i = 1
    foreach ($name in $script:AgentOrder) {
        $info = Get-AgentInfo $name
        if (Test-AgentInstalled $name) {
            $line = ("  {0}) {1,-25} ({2})" -f $i, $info.DisplayName, $name)
            Write-Host -NoNewline $line
            Write-Host (" ● $(t 'label_detected')") -ForegroundColor Green
        } else {
            Write-Host ("  {0}) {1,-25} ({2})" -f $i, $info.DisplayName, $name)
        }
        $i++
    }
    Write-Host ''

    if ($defaultIdx) {
        $reply = Read-Prompt "$(t 'prompt_enter_agent_num_default') $($defaultIdx)]:"
        if (-not $reply) { $reply = "$defaultIdx" }
    } else {
        $reply = Read-Prompt (t 'prompt_enter_agent_num')
    }

    $idx = [int]::Parse($reply) - 1
    if ($idx -lt 0 -or $idx -ge $script:AgentOrder.Count) {
        Stop-Fatal "$(t 'error_invalid_selection') $reply" 2
    }
    $script:SelectedAgent = $script:AgentOrder[$idx]
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Scope selection
# ---------------------------------------------------------------------------
function Select-Scope {
    if ($script:SelectedAgent -eq 'web') {
        if ($script:SelectedScope -and $script:SelectedScope -ne 'skills') {
            Write-Warn (t 'warn_web_no_mcp')
        }
        $script:SelectedScope = 'skills'
        return
    }

    if ($script:SelectedScope) {
        # Scope 由命令行参数已指定（典型场景：从落地页生成的命令）
        Write-Info "$(t 'info_scope_preset') $($script:SelectedScope)"
        if ($script:SelectedScope -eq 'mcp') {
            Write-Info (t 'info_scope_mcp_only_hint')
        }
        return
    }
    if ($NonInteractive) { Stop-Fatal (t 'error_scope_required_ni') 2 }

    Write-Host (t 'menu_choose_scope') -ForegroundColor White
    Write-Host ("  1) 📘 " + (t 'menu_scope_skills'))
    Write-Host ("  2) 🧰 " + (t 'menu_scope_mcp'))
    Write-Host ("  3) ✨ " + (t 'menu_scope_both'))
    Write-Host ''
    $reply = Read-Prompt (t 'prompt_enter_scope_num')

    $script:SelectedScope = switch ($reply) {
        '1'     { 'skills' }
        '2'     { 'mcp' }
        '3'     { 'both' }
        ''      { 'both' }
        default { Stop-Fatal "$(t 'error_invalid_selection') $reply" 2 }
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Backend API helpers
# ---------------------------------------------------------------------------
function Invoke-BackendSendCode {
    param([string]$Email)
    $body = @{ type = 'regist'; to = $Email } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "$ApiBase/email/code/send" -Method Post `
            -Body $body -ContentType 'application/json' | Out-Null
        return $true
    } catch { return $false }
}

function Invoke-BackendRegister {
    param([string]$Email, [string]$Password, [string]$Code)
    # 注意 Email / Password 是后端 DTO 的大写字段名
    $body = @{
        Email    = $Email
        Password = $Password
        code     = $Code
        source   = 'cli-installer'
    } | ConvertTo-Json -Compress
    try {
        $resp = Invoke-RestMethod -Uri "$ApiBase/user/reg" -Method Post `
            -Body $body -ContentType 'application/json'
        return $resp.data
    } catch { return $null }
}

function Invoke-BackendGetPermanentToken {
    param([string]$SessionToken)
    try {
        $resp = Invoke-RestMethod -Uri "$ApiBase/user/permanent-token" -Method Get `
            -Headers @{ Authorization = "Bearer $SessionToken" }
        return $resp.data
    } catch { return $null }
}

function Test-BackendKey {
    param([string]$Key)
    try {
        Invoke-RestMethod -Uri "$ApiBase/user/permanent-token" -Method Get `
            -Headers @{ Authorization = "Bearer $Key" } | Out-Null
        return $true
    } catch { return $false }
}

function Test-EmailFormat {
    param([string]$Email)
    return $Email -match '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
}

function Test-StrongPassword {
    param([string]$Password)
    if ($Password.Length -lt 8 -or $Password.Length -gt 20) { return $false }
    if ($Password -notmatch '[A-Za-z]') { return $false }
    if ($Password -notmatch '[0-9]')    { return $false }
    return $true
}

# ---------------------------------------------------------------------------
# API Key flow
# ---------------------------------------------------------------------------
function Initialize-ApiKey {
    if ($script:SelectedScope -eq 'skills') {
        Write-Info (t 'info_scope_skills_no_key')
        return
    }

    if ($script:ResolvedKey) {
        Write-Info (t 'info_validating_key')
        if ($DryRun) {
            Write-OK "$(t 'info_dryrun_validate_key') $ApiBase/user/permanent-token"
            return
        }
        if (Test-BackendKey $script:ResolvedKey) {
            Write-OK (t 'ok_key_valid')
            return
        }
        Write-Err (t 'error_key_invalid_provided')
        if ($NonInteractive) { exit 30 }
        $script:ResolvedKey = ''
    }

    if ($NonInteractive) { Stop-Fatal (t 'error_key_required_ni') 2 }

    # --- Phase 2 引导 ---
    Write-Host ''
    Write-Host (t 'phase2_title') -ForegroundColor White
    Write-Host ''
    Write-Host (t 'phase2_step1') -ForegroundColor White
    Write-Host ("  " + (t 'phase2_step1_intro'))
    Write-Host ''
    Write-Host ("  " + [char]0x2022 + " ") -NoNewline -ForegroundColor Green
    Write-Host ("$(t 'phase2_existing_label') $(t 'phase2_existing_hint')")
    Write-Host ("    " + (t 'dashboard_url')) -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("  " + [char]0x2022 + " ") -NoNewline -ForegroundColor Green
    Write-Host ("$(t 'phase2_new_label') $(t 'phase2_new_hint')")
    Write-Host ("    " + (t 'signup_url')) -ForegroundColor Cyan
    Write-Host ''

    Write-Host (t 'prompt_has_key') -ForegroundColor White
    $reply = Read-Prompt (t 'prompt_arrow')
    if ($reply -match '^[Yy]') {
        Read-ExistingKey
    } else {
        Register-NewAccount
    }
}

function Read-ExistingKey {
    while ($true) {
        $key = Read-Secret (t 'prompt_paste_key')
        if (-not $key) { Write-Err (t 'error_empty_key'); continue }
        if ($DryRun) {
            Write-OK (t 'info_dryrun_validate')
            $script:ResolvedKey = $key
            return
        }
        Write-Info (t 'info_validating')
        if (Test-BackendKey $key) {
            Write-OK (t 'ok_key_valid')
            $script:ResolvedKey = $key
            return
        }
        Write-Err (t 'error_key_invalid_retry')
        $r = Read-Prompt (t 'prompt_arrow')
        if ($r -match '^[Nn]') { Register-NewAccount; return }
    }
}

function Register-NewAccount {
    Write-Host ''
    Write-Info (t 'info_register_intro')
    Write-Host ''

    # 1. 邮箱
    do {
        $email = Read-Prompt (t 'prompt_email')
        if (-not (Test-EmailFormat $email)) { Write-Err (t 'error_bad_email') }
    } while (-not (Test-EmailFormat $email))

    # 2. 发码
    if ($DryRun) {
        Write-OK "$(t 'info_dryrun_send_code') $email"
    } else {
        Write-Info "$(t 'info_sending_code') $email..."
        if (-not (Invoke-BackendSendCode $email)) {
            Write-Err (t 'error_send_code_failed')
            Write-Err "  • $(t 'error_send_code_reason_rate')"
            Write-Err "  • $(t 'error_send_code_reason_net')"
            exit 30
        }
        Write-OK (t 'ok_code_sent')
    }

    # 3. 验证码+密码
    $code = Read-Prompt (t 'prompt_code')
    do {
        $password = Read-Secret (t 'prompt_password')
        if (-not (Test-StrongPassword $password)) {
            Write-Err (t 'error_weak_password')
        }
    } while (-not (Test-StrongPassword $password))

    # 4. 注册
    if ($DryRun) {
        Write-OK (t 'info_dryrun_register')
        $script:ResolvedKey = 'pgl_dryrun_fake_key'
        return
    }

    Write-Info (t 'info_creating_account')
    $sessionToken = Invoke-BackendRegister $email $password $code
    if (-not $sessionToken) {
        Write-Err (t 'error_register_failed')
        exit 30
    }
    Write-OK (t 'ok_account_created')

    Write-Info (t 'info_fetching_perm_key')
    $permKey = Invoke-BackendGetPermanentToken $sessionToken
    if (-not $permKey) {
        Write-Err (t 'error_perm_key_failed')
        exit 30
    }
    Write-OK (t 'ok_key_obtained')
    $script:ResolvedKey = $permKey
}

# ---------------------------------------------------------------------------
# Save config
# ---------------------------------------------------------------------------
function Save-Config {
    if (-not $script:ResolvedKey) { return }
    if ($DryRun) {
        Write-OK "$(t 'info_dryrun_write_config') $script:ConfigFile"
        Write-Phase3Security
        return
    }

    if (-not (Test-Path $script:ConfigDir)) {
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    }
    $cfg = @{
        api_key      = $script:ResolvedKey
        api_base     = $ApiBase
        scrape_base  = $ScrapeBase
    } | ConvertTo-Json
    Set-Content -Path $script:ConfigFile -Value $cfg -Encoding UTF8

    # 收紧 ACL：仅当前用户可读写
    try {
        $acl = Get-Acl $script:ConfigFile
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -Path $script:ConfigFile -AclObject $acl
    } catch {
        Write-Warn "$(t 'warn_chmod_failed') $script:ConfigFile"
    }
    Write-OK "$(t 'ok_config_saved') $script:ConfigFile"
    Write-Phase3Security
}

function Write-Phase3Security {
    Write-Host ''
    Write-Host (t 'phase3_title') -ForegroundColor White
    Write-Host ''
    Write-Host ("  " + (t 'phase3_security_header')) -ForegroundColor DarkGray
    Write-Host ("  " + [char]0x2022 + " " + (t 'phase3_security_local'))
    Write-Host ("  " + [char]0x2022 + " " + (t 'phase3_security_https'))
    Write-Host ("  " + [char]0x2022 + " " + (t 'phase3_security_privacy'))
    Write-Host ''
    Write-Host ("  " + [char]0x26A0 + "  " + (t 'phase3_warning')) -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Install Skills
# ---------------------------------------------------------------------------
function Install-Skills {
    if ($script:SelectedScope -eq 'mcp') { Write-Info (t 'info_scope_mcp_skip_skills'); return }

    $info = Get-AgentInfo $script:SelectedAgent
    $skillsDir = $info.SkillsDir
    $distName  = $info.DistDir

    Write-Info (t 'info_installing_skills')
    Write-Host "  ↓ $(t 'label_source') dist\$distName\"
    Write-Host "  → $(t 'label_target') $skillsDir"

    if ($DryRun) {
        Write-OK "$(t 'info_dryrun_copy_skills') $skillsDir"
        return
    }

    $localSrc = Join-Path $ScriptDir "..\pangolinfo-skills\dist\$distName"
    if (-not (Test-Path $localSrc)) {
        Write-Err "$(t 'error_skills_src_missing') $localSrc"
        Write-Err (t 'error_skills_src_hint')
        exit 20
    }

    # 按 agent 分发（每家 agent 的 skill 加载机制不同）
    switch ($script:SelectedAgent) {
        'web'      { Install-Skills-Web      $localSrc $skillsDir }
        'cursor'   { Install-Skills-Cursor   $localSrc $skillsDir }
        'cline'    { Install-Skills-Cline    $localSrc $skillsDir }
        'windsurf' { Install-Skills-Windsurf $localSrc $skillsDir }
        'codex'    { Install-Skills-Codex    $localSrc $skillsDir }
        default    { Install-Skills-Dir      $localSrc $skillsDir }
    }
}

# 标准目录拷贝（claude-code / hermes / openclaw 用）
function Install-Skills-Dir {
    param([string]$Src, [string]$Dest)
    $parent = Split-Path -Parent $Dest
    if (-not (Test-Path $parent)) {
        Write-Err "$(t 'error_parent_missing') $parent"
        Write-Err "$(t 'error_agent_not_installed_prefix') $script:SelectedAgent $(t 'error_agent_not_installed_suffix')"
        exit 10
    }
    if (Test-Path $Dest) {
        $backup = "$Dest.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Move-Item $Dest $backup
        Write-Info "$(t 'info_backed_up') $backup"
    }
    Copy-Item -Recurse $Src $Dest
    Write-OK "$(t 'ok_skills_installed') $Dest"
}

# Web: 打包 ZIP 让用户上传
function Install-Skills-Web {
    param([string]$Src, [string]$ZipTarget)
    $zipParent = Split-Path -Parent $ZipTarget
    if (-not (Test-Path $zipParent)) {
        New-Item -ItemType Directory -Path $zipParent -Force | Out-Null
    }
    if (Test-Path $ZipTarget) {
        $backup = "$ZipTarget.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Move-Item $ZipTarget $backup
        Write-Info "$(t 'info_backed_up') $backup"
    }
    Compress-Archive -Path "$Src\*" -DestinationPath $ZipTarget
    Write-OK "$(t 'ok_packaged_skills') $ZipTarget"
    Write-Host ''
    Write-Info (t 'info_web_next_header')
    Write-Info "  1. $(t 'info_web_step1')"
    Write-Info "  2. $(t 'info_web_step2')"
    Write-Info "  3. $(t 'info_web_step3') $ZipTarget"
    Write-Info "  4. $(t 'info_web_step4')"
}

# Codex: 同时写 ~/.codex/skills/ 和 ~/.agents/skills/ (向前兼容)
function Install-Skills-Codex {
    param([string]$Src, [string]$Primary)
    Install-Skills-Dir $Src $Primary

    # 新 cross-tool convention: ~/.agents/skills/
    $agentsDir = Join-Path $env:USERPROFILE '.agents\skills\pangolinfo'
    $parent = Split-Path -Parent $agentsDir
    if (-not (Test-Path $parent)) {
        try { New-Item -ItemType Directory -Path $parent -Force | Out-Null } catch {}
    }
    if (Test-Path $parent) {
        if (Test-Path $agentsDir) {
            $backup = "$agentsDir.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
            Move-Item $agentsDir $backup
            Write-Info "$(t 'info_backed_up') $backup"
        }
        try {
            Copy-Item -Recurse $Src $agentsDir
            Write-Info "$(t 'info_codex_dual_path') $agentsDir"
        } catch { }
    }
}

# Cursor (B2+B3): 把每个 skill 编译成 .cursor/rules/pangolinfo-<name>.mdc 单文件
# $SkillsDirSpec 形如 "PROJECT:.cursor\rules"
function Install-Skills-Cursor {
    param([string]$Src, [string]$SkillsDirSpec)
    $subpath = $SkillsDirSpec -replace '^PROJECT:', ''
    $targetDir = Join-Path (Get-Location) $subpath
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Write-Info "$(t 'info_cursor_project_scope') $targetDir"

    $count = 0
    Get-ChildItem -Path $Src -Directory | ForEach-Object {
        $skillName = $_.Name
        $skillMd = Join-Path $_.FullName 'SKILL.md'
        if (-not (Test-Path $skillMd)) { return }
        $targetMdc = Join-Path $targetDir "pangolinfo-$skillName.mdc"

        # 抽 description (兼容 inline + YAML pipe 多行)
        $desc = ''
        $inPipe = $false
        foreach ($line in (Get-Content $skillMd)) {
            if ($line -match '^description:\s*\|') { $inPipe = $true; continue }
            if ($inPipe) {
                if ($line -match '^\s+(.+)$') {
                    $desc = $matches[1]
                    break
                } else { $inPipe = $false }
            }
            if ($line -match '^description:\s+(.+)$') {
                $desc = $matches[1]
                break
            }
        }
        if ([string]::IsNullOrEmpty($desc)) {
            $desc = "Pangolinfo MCP skill: $skillName"
        }
        $desc = $desc -replace '"', '\"'

        # 剥 frontmatter，只保留正文
        $content = Get-Content $skillMd
        $dashCount = 0
        $bodyStart = -1
        for ($i = 0; $i -lt $content.Length; $i++) {
            if ($content[$i] -eq '---') {
                $dashCount++
                if ($dashCount -eq 2) {
                    $bodyStart = $i + 1
                    break
                }
            }
        }
        $body = if ($bodyStart -ge 0) { $content[$bodyStart..($content.Length - 1)] } else { $content }

        $mdc = @(
            '---',
            "description: `"$desc`"",
            'globs: ["**/*"]',
            'alwaysApply: false',
            '---',
            ''
        ) + $body
        Set-Content -Path $targetMdc -Value $mdc -Encoding UTF8
        $count++
    }
    Write-OK "$(t 'ok_cursor_mdc_written') $count → $targetDir"
    Write-Info (t 'info_cursor_global_hint')
}

# Cline (B4): 写到 ~/Documents/Cline/Rules/pangolinfo/
function Install-Skills-Cline {
    param([string]$Src, [string]$Dest)
    $parent = Split-Path -Parent $Dest
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path $Dest) {
        $backup = "$Dest.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Move-Item $Dest $backup
        Write-Info "$(t 'info_backed_up') $backup"
    }
    Copy-Item -Recurse $Src $Dest
    Write-OK "$(t 'ok_skills_installed') $Dest"
    Write-Info (t 'info_cline_global_loaded')
}

# Windsurf (B5): 追加 pangolinfo 段到 global_rules.md
# $SkillsDirSpec 形如 "APPEND:C:\Users\...\global_rules.md"
function Install-Skills-Windsurf {
    param([string]$Src, [string]$SkillsDirSpec)
    $targetFile = $SkillsDirSpec -replace '^APPEND:', ''
    $parent = Split-Path -Parent $targetFile
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path $targetFile) {
        $backup = "$targetFile.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Copy-Item $targetFile $backup
        Write-Info "$(t 'info_backed_up') $backup"

        # 若已有 BEGIN PANGOLINFO 段，删除旧段
        $existing = Get-Content $targetFile
        $cleaned = @()
        $skip = $false
        foreach ($line in $existing) {
            if ($line -match '<!-- BEGIN PANGOLINFO -->') { $skip = $true; continue }
            if ($line -match '<!-- END PANGOLINFO -->') { $skip = $false; continue }
            if (-not $skip) { $cleaned += $line }
        }
        Set-Content -Path $targetFile -Value $cleaned -Encoding UTF8
    }

    # 追加新段
    $lines = @(
        '',
        '<!-- BEGIN PANGOLINFO -->',
        '<!-- Auto-added by pangolinfo installer. Do not edit between markers. -->',
        ''
    )
    Get-ChildItem -Path $Src -Directory | ForEach-Object {
        $skillName = $_.Name
        $skillMd = Join-Path $_.FullName 'SKILL.md'
        if (-not (Test-Path $skillMd)) { return }
        $lines += "## Pangolinfo Skill: $skillName"
        $lines += ''
        # 剥 frontmatter，留正文
        $content = Get-Content $skillMd
        $dashCount = 0
        $bodyStart = -1
        for ($i = 0; $i -lt $content.Length; $i++) {
            if ($content[$i] -eq '---') {
                $dashCount++
                if ($dashCount -eq 2) {
                    $bodyStart = $i + 1
                    break
                }
            }
        }
        if ($bodyStart -ge 0) {
            $lines += $content[$bodyStart..($content.Length - 1)]
        }
        $lines += ''
        $lines += '---'
        $lines += ''
    }
    $lines += '<!-- END PANGOLINFO -->'
    Add-Content -Path $targetFile -Value $lines -Encoding UTF8
    Write-OK "$(t 'ok_windsurf_appended') $targetFile"
}

# ---------------------------------------------------------------------------
# Install MCP + register
# ---------------------------------------------------------------------------
function Install-Mcp {
    if ($script:SelectedScope -eq 'skills') { Write-Info (t 'info_scope_skills_skip_mcp'); return }
    if ($script:SelectedAgent -eq 'web')    { Write-Info (t 'info_web_skip_mcp'); return }

    # 非阻断式 node 检查 — MCP server 启动需要 node 18+
    # 见 README.md "前置环境" / Prerequisites
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warn (t 'warn_node_missing')
    }

    $info = Get-AgentInfo $script:SelectedAgent
    $mcpConfig = $info.McpConfig

    Write-Info (t 'info_installing_mcp')
    if ($DryRun) {
        Write-OK "$(t 'info_dryrun_install_mcp') $script:McpInstallDir"
        Write-OK "$(t 'info_dryrun_register_mcp') $mcpConfig"
        return
    }

    # 从 GitHub Release 下载 server.mjs (单文件零依赖 ~800 KB)
    # $script:McpVersion 来自脚本顶层 param (default 'latest');函数 scope 看不到顶层非 $script: 变量。
    $mcpVer = $script:McpVersion
    if (-not $mcpVer -or $mcpVer -eq 'latest') {
        $mcpUrl = "$script:McpReleaseBase/latest/download/server.mjs"
        $shaUrl = "$script:McpReleaseBase/latest/download/server.mjs.sha256"
    } else {
        $mcpUrl = "$script:McpReleaseBase/download/$mcpVer/server.mjs"
        $shaUrl = "$script:McpReleaseBase/download/$mcpVer/server.mjs.sha256"
    }

    if (-not (Test-Path $script:McpInstallDir)) {
        New-Item -ItemType Directory -Path $script:McpInstallDir -Force | Out-Null
    }
    $serverDest = Join-Path $script:McpInstallDir 'server.mjs'
    $shaDest    = Join-Path $script:McpInstallDir 'server.mjs.sha256'

    Write-Info (t 'info_downloading_mcp')
    try {
        # Invoke-WebRequest 自动跟随 redirect。-UseBasicParsing 避免在 PS 5 上需要 IE 引擎。
        Invoke-WebRequest -Uri $mcpUrl -OutFile $serverDest -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Err "$(t 'error_mcp_download_failed') $mcpUrl"
        Write-Err (t 'error_mcp_download_hint')
        if (Test-Path $serverDest) { Remove-Item $serverDest -Force -ErrorAction SilentlyContinue }
        exit 20
    }

    # SHA256 校验 — PowerShell 自带 Get-FileHash,不依赖外部工具
    Write-Info (t 'info_verifying_sha256')
    try {
        Invoke-WebRequest -Uri $shaUrl -OutFile $shaDest -UseBasicParsing -ErrorAction Stop
        # .sha256 文件首段是 hex hash
        $expected = (Get-Content $shaDest -Raw).Trim().Split(' ')[0].ToLowerInvariant()
        $actual   = (Get-FileHash -Path $serverDest -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -ne $actual) {
            Write-Err (t 'error_sha256_mismatch')
            Remove-Item $serverDest -Force -ErrorAction SilentlyContinue
            Remove-Item $shaDest    -Force -ErrorAction SilentlyContinue
            exit 20
        }
        Write-OK (t 'ok_sha256_verified')
        Remove-Item $shaDest -Force -ErrorAction SilentlyContinue
    } catch {
        # 拉取 .sha256 失败不阻塞 — 主文件下载成功就放行,只 warn
        Write-Warn (t 'warn_sha256_skipped')
    }

    Write-OK "$(t 'ok_mcp_binary_at') $serverDest"

    if ($mcpConfig -eq 'none') {
        Write-Warn "$(t 'warn_no_mcp_config') $script:SelectedAgent"
        return
    }

    # 按 agent 分发
    switch ($script:SelectedAgent) {
        'claude-code' { Register-ClaudeCodeMcp }
        'cline'       { Register-ClineMcp $mcpConfig }
        'hermes'      { Register-HermesYaml $mcpConfig }
        'openclaw'    { Register-OpenClawJson $mcpConfig }
        'codex'       { Register-CodexToml $mcpConfig }
        default       { Register-McpJson $mcpConfig }
    }
}

# B1: Claude Code 优选 claude mcp add，备选写 settings.json
function Register-ClaudeCodeMcp {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -ne $claudeCmd) {
        Write-Info (t 'info_using_claude_cli')
        $serverPath = Join-Path $script:McpInstallDir 'server.mjs'
        try {
            & claude mcp add --scope user pangolinfo `
                --command node `
                --args $serverPath `
                --env "PANGOLINFO_API_KEY=$script:ApiKey" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-OK "$(t 'ok_mcp_registered') (via 'claude mcp add')"
                return
            }
        } catch {}
        Write-Warn (t 'warn_claude_cli_failed')
    }
    # 备选：写 ~/.claude/settings.json
    $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
    $parent = Split-Path -Parent $settings
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Register-McpJson $settings
}

# S1: Cline MCP 双路径（VS Code 扩展 + 独立 CLI）
function Register-ClineMcp {
    param([string]$Primary)
    $wroteAny = $false
    $vsCodePath = Find-ClineVsCodeExtDir
    if ($null -ne $vsCodePath) {
        $vsCodeMcp = Join-Path $vsCodePath 'settings\cline_mcp_settings.json'
        Write-Info "$(t 'info_cline_vscode_detected') $vsCodeMcp"
        Register-McpJson $vsCodeMcp
        $wroteAny = $true
    }
    # 兜底：如果独立 CLI 的目录已存在，也写一份
    $cliParent = Split-Path -Parent $Primary
    if (Test-Path $cliParent) {
        Register-McpJson $Primary
        $wroteAny = $true
    }
    # 两个都没写到 → 至少建独立 CLI 路径写一份，避免 silent skip
    if (-not $wroteAny) {
        if (-not (Test-Path $cliParent)) {
            New-Item -ItemType Directory -Path $cliParent -Force | Out-Null
        }
        Register-McpJson $Primary
    }
}

# Codex TOML
function Register-CodexToml {
    param([string]$ConfigPath)
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $serverPath = (Join-Path $script:McpInstallDir 'server.mjs').Replace('\', '/')
    $tomlBlock = @"

# === Pangolinfo MCP server (auto-added by installer) ===
[mcp_servers.pangolinfo]
command = "node"
args = ["$serverPath"]

[mcp_servers.pangolinfo.env]
PANGOLINFO_API_KEY = "$script:ApiKey"
"@

    if (-not (Test-Path $ConfigPath)) {
        Set-Content -Path $ConfigPath -Value $tomlBlock -Encoding UTF8
        Write-OK "$(t 'ok_mcp_created_config') $ConfigPath"
        return
    }

    if (Select-String -Path $ConfigPath -Pattern '^\[mcp_servers\.pangolinfo\]' -Quiet) {
        Write-Info "$(t 'info_mcp_already_registered') $ConfigPath"
        Write-Info (t 'info_mcp_manual_overwrite')
        return
    }

    $backup = "$ConfigPath.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
    Copy-Item $ConfigPath $backup
    Add-Content -Path $ConfigPath -Value $tomlBlock -Encoding UTF8
    Write-OK "$(t 'ok_mcp_registered') $ConfigPath"
    Write-Info "$(t 'info_backed_up') $backup"
}

function Register-McpJson {
    param([string]$ConfigPath)
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $newEntry = [PSCustomObject]@{
        command = 'node'
        args    = @("$script:McpInstallDir\server.mjs")
        env     = [PSCustomObject]@{ PANGOLINFO_API_KEY = $script:ResolvedKey }
    }

    if (-not (Test-Path $ConfigPath)) {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{ pangolinfo = $newEntry }
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-OK "$(t 'ok_mcp_created_config') $ConfigPath"
        return
    }

    # 已存在 → 合并
    try {
        $existing = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if (-not $existing.mcpServers) {
            $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $existing.mcpServers | Add-Member -NotePropertyName pangolinfo -NotePropertyValue $newEntry -Force
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-OK "$(t 'ok_mcp_registered') $ConfigPath"
    } catch {
        Write-Warn "$(t 'warn_no_jq') $ConfigPath"
        Write-Warn (t 'warn_add_manually')
        Write-Host (@{ pangolinfo = $newEntry } | ConvertTo-Json -Depth 10)
    }
}

# ---------------------------------------------------------------------------
# Hermes YAML 自动写入（避免依赖 yq；手拼 YAML 字符串）
# ---------------------------------------------------------------------------
function Register-HermesYaml {
    param([string]$ConfigPath)
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $serverPath = $script:McpInstallDir + "\server.mjs"
    # PowerShell here-string 拼 YAML
    $yamlBlock = @"

# === Pangolinfo MCP server (auto-added by installer) ===
mcp_servers:
  pangolinfo:
    command: node
    args:
      - "$serverPath"
    env:
      PANGOLINFO_API_KEY: "$script:ResolvedKey"
"@

    if (-not (Test-Path $ConfigPath)) {
        Set-Content -Path $ConfigPath -Value $yamlBlock -Encoding UTF8
        Write-OK "$(t 'ok_mcp_created_config') $ConfigPath"
        return
    }

    $content = Get-Content $ConfigPath -Raw
    if ($content -match '(?m)^mcp_servers:') {
        # 已有 mcp_servers 节点，在该节点行后追加 pangolinfo 子节点
        $childBlock = @"
  pangolinfo:
    command: node
    args:
      - "$serverPath"
    env:
      PANGOLINFO_API_KEY: "$script:ResolvedKey"
"@
        $newContent = $content -replace '(?m)(^mcp_servers:\s*)$', "`$1`n$childBlock"
        Set-Content -Path $ConfigPath -Value $newContent -Encoding UTF8
        Write-OK "$(t 'ok_mcp_registered') $ConfigPath"
    } else {
        # 没 mcp_servers 节点——文件末尾追加
        $backup = "$ConfigPath.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        Copy-Item $ConfigPath $backup
        Add-Content -Path $ConfigPath -Value $yamlBlock -Encoding UTF8
        Write-OK "$(t 'ok_mcp_registered') $ConfigPath"
        Write-Info "$(t 'info_backed_up') $backup"
    }
}

# ---------------------------------------------------------------------------
# OpenClaw 嵌套 JSON 自动写入
# ---------------------------------------------------------------------------
function Register-OpenClawJson {
    param([string]$ConfigPath)
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $serverPath = $script:McpInstallDir + "\server.mjs"

    $mcpEntry = [PSCustomObject]@{
        command = 'node'
        args    = @($serverPath)
        env     = [PSCustomObject]@{ PANGOLINFO_API_KEY = $script:ResolvedKey }
    }

    if (-not (Test-Path $ConfigPath)) {
        $json = [PSCustomObject]@{
            skills     = [PSCustomObject]@{ entries = @('pangolinfo') }
            mcpServers = [PSCustomObject]@{ pangolinfo = $mcpEntry }
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-OK "$(t 'ok_mcp_created_config') $ConfigPath"
        return
    }

    try {
        $existing = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        # skills.entries 追加 pangolinfo（若未含）
        if (-not $existing.skills) {
            $existing | Add-Member -NotePropertyName skills -NotePropertyValue ([PSCustomObject]@{ entries = @() }) -Force
        } elseif (-not $existing.skills.entries) {
            $existing.skills | Add-Member -NotePropertyName entries -NotePropertyValue @() -Force
        }
        if ($existing.skills.entries -notcontains 'pangolinfo') {
            $existing.skills.entries = @($existing.skills.entries) + 'pangolinfo'
        }
        # mcpServers.pangolinfo 设置
        if (-not $existing.mcpServers) {
            $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $existing.mcpServers | Add-Member -NotePropertyName pangolinfo -NotePropertyValue $mcpEntry -Force
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-OK "$(t 'ok_mcp_registered') $ConfigPath"
    } catch {
        Write-Warn "$(t 'warn_no_jq') $ConfigPath"
        Write-Warn (t 'warn_add_manually')
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
function Show-Done {
    $info = Get-AgentInfo $script:SelectedAgent
    Write-Host ''
    Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host (t 'done_success') -ForegroundColor Green
    Write-Host '═══════════════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
    Write-Host "$(t 'done_agent_label') $($info.DisplayName)" -ForegroundColor White
    Write-Host "$(t 'done_scope_label') $script:SelectedScope" -ForegroundColor White
    Write-Host ''
    Write-Host (t 'done_try_header')
    Write-Host ("  › " + (t 'done_try_1'))
    Write-Host ("  › " + (t 'done_try_2'))
    Write-Host ''
    Write-Host '─────────────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  ⭐  $(t 'done_star_prompt')" -ForegroundColor White
    Write-Host "      $script:GitHubUrl" -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  $(t 'done_small_team')" -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-Main {
    if ($Help) { Show-Help; return }

    Show-Banner

    if (-not $NonInteractive -and -not $DryRun) {
        $reply = Read-Prompt (t 'prompt_continue')
        if ($reply -match '^[Nn]') { Write-Info (t 'info_cancelled'); exit 1 }
        Write-Host ''
    }

    Select-Agent
    Select-Scope
    Initialize-ApiKey
    Save-Config
    Install-Skills
    Install-Mcp
    Show-Done
}

Invoke-Main
