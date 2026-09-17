#!/bin/sh
# Pangolinfo Installer · macOS / Linux
# Spec: CONTRACT-installer.md, CONTRACT-i18n.md
# Style: POSIX sh (no bashisms — works under dash/ash/zsh)
#
# Quick start:
#   curl -fsSL install.pangolinfo.com/install.sh | sh
#   curl -fsSL install.pangolinfo.com/install.sh | sh -s -- --agent=claude-code --scope=both
#   curl -fsSL install.pangolinfo.com/install.sh | sh -s -- --lang=en

set -eu

# ---------------------------------------------------------------------------
# Constants & globals
# ---------------------------------------------------------------------------
INSTALLER_VERSION="0.1.0"
DEFAULT_API_BASE="https://extapi.pangolinfo.com"
DEFAULT_SCRAPE_BASE="https://scrapeapi.pangolinfo.com"
GITHUB_URL="https://github.com/pangolinfo"
CONFIG_DIR="${HOME}/.pangolinfo"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# 默认 MCP server 安装到无 sudo 路径
MCP_INSTALL_DIR="${HOME}/.local/lib/pangolinfo-mcp"

# MCP server 二进制从 GitHub Release 拉。
# /latest/ 自动跟随最新 release;客户可用 --mcp-version=v0.1.2 锁版本(对应仓库 tag)。
# 单文件 ESM bundle (~800 KB),零运行时依赖,只需 node 18+ 在 PATH。
MCP_RELEASE_BASE="https://github.com/pangolinfo/pangolinfo-mcp/releases"

# 解析后的参数
ARG_AGENT=""
ARG_SCOPE=""
ARG_API_KEY=""
ARG_API_BASE=""
ARG_SCRAPE_BASE=""
ARG_NON_INTERACTIVE=0
ARG_DRY_RUN=0
ARG_SKILLS_VERSION="latest"
ARG_MCP_VERSION="latest"
ARG_LANG=""

# 运行期状态
SELECTED_AGENT=""
SELECTED_SCOPE=""
API_KEY=""
API_BASE=""
SCRAPE_BASE=""

# ---------------------------------------------------------------------------
# i18n: locale detection
# ---------------------------------------------------------------------------
# 解析语言：--lang= > PANGOLINFO_LANG > $LANG(zh* → zh, 其他 → en) > 默认 zh
detect_lang() {
  for arg in "$@"; do
    case "$arg" in
      --lang=*)
        v="${arg#*=}"
        case "$v" in
          zh|en) echo "$v"; return ;;
          *)     echo "zh"; return ;;
        esac
        ;;
    esac
  done
  if [ -n "${PANGOLINFO_LANG:-}" ]; then
    case "$PANGOLINFO_LANG" in
      zh|en) echo "$PANGOLINFO_LANG"; return ;;
    esac
  fi
  case "${LANG:-}" in
    zh*|ZH*) echo "zh"; return ;;
    "")      echo "zh"; return ;;
    *)       echo "en"; return ;;
  esac
}

LOCALE=$(detect_lang "$@")

# ---------------------------------------------------------------------------
# i18n: dictionary
# ---------------------------------------------------------------------------
# 字典 key 命名：snake_case, 按场景分组（banner_/menu_/error_/info_/done_/help_/prompt_)
# install.sh 与 install.ps1 必须共享同一套 key

# --- Banner (Phase 1: Welcome) ---
T_ZH_banner_title="Pangolinfo MCP Server 部署"
T_EN_banner_title="Pangolinfo MCP Server Deployment"
T_ZH_banner_intro="欢迎使用 Pangolinfo MCP 安装程序。该脚本会把 Amazon 实时抓取能力集成到你的本地 AI 环境。"
T_EN_banner_intro="Welcome to the Pangolinfo MCP Installer. This script will integrate Amazon real-time scraping capabilities into your local AI environment."
T_ZH_banner_desc_header="此安装程序将："
T_EN_banner_desc_header="The installer will:"
T_ZH_banner_desc_skills="在你 AI 客户端的配置中注册 pangolinfo-mcp 服务"
T_EN_banner_desc_skills="Detect and configure the pangolinfo-mcp server within your AI client's config"
T_ZH_banner_desc_mcp="部署 Skills 知识包到你的 AI 助手"
T_EN_banner_desc_mcp="Deploy Skills knowledge packs to your AI agent"
T_ZH_banner_desc_apikey="安全建立运行时凭据与计费上下文"
T_EN_banner_desc_apikey="Set up the secure runtime for data execution"

# --- Help text ---
T_ZH_help_usage_header="用法："
T_EN_help_usage_header="USAGE:"
T_ZH_help_options_header="可选参数："
T_EN_help_options_header="OPTIONS:"
T_ZH_help_examples_header="示例："
T_EN_help_examples_header="EXAMPLES:"
T_ZH_help_exitcodes_header="退出码："
T_EN_help_exitcodes_header="EXIT CODES:"
T_ZH_help_opt_agent="你的 AI 助手"
T_EN_help_opt_agent="Your AI agent"
T_ZH_help_opt_scope="安装范围                                 [默认: both]"
T_EN_help_opt_scope="skills | mcp | both                       [default: both]"
T_ZH_help_opt_apikey="已有的 Pangolinfo API Key"
T_EN_help_opt_apikey="Existing Pangolinfo API key"
T_ZH_help_opt_apibase="覆盖默认 API base URL"
T_EN_help_opt_apibase="Override default API base URL"
T_ZH_help_opt_scrapebase="覆盖默认 scrape base URL"
T_EN_help_opt_scrapebase="Override default Scraper API base URL"
T_ZH_help_opt_noninteractive="缺参数直接报错，不弹菜单"
T_EN_help_opt_noninteractive="Fail instead of prompting for missing args"
T_ZH_help_opt_skillsver="锁定 Skills 版本（默认 latest）"
T_EN_help_opt_skillsver="Pin Skills version (default: latest)"
T_ZH_help_opt_mcpver="锁定 MCP 版本（默认 latest）"
T_EN_help_opt_mcpver="Pin MCP server version (default: latest)"
T_ZH_help_opt_dryrun="只打印操作不执行"
T_EN_help_opt_dryrun="Print actions without executing"
T_ZH_help_opt_lang="界面语言 zh|en（默认按系统检测）"
T_EN_help_opt_lang="UI language zh|en (default: auto-detect)"
T_ZH_help_opt_help="显示本帮助"
T_EN_help_opt_help="Show this help"
T_ZH_help_ex_interactive="# 快速开始（交互式菜单）"
T_EN_help_ex_interactive="# Quick start (interactive menu)"
T_ZH_help_ex_preset="# 预设参数（落地页一键命令）"
T_EN_help_ex_preset="# Pre-configured (one-shot from landing page generator)"
T_ZH_help_ex_headless="# 无人值守（CI / 脚本化）"
T_EN_help_ex_headless="# Headless (CI / scripted)"
T_ZH_help_exit_table="   0 成功 | 1 用户取消 | 2 参数错误 | 10 Agent 目录不存在
  20 网络错误 | 30 后端 API 错误 | 40 文件系统错误"
T_EN_help_exit_table="   0 success | 1 user-cancel | 2 bad args | 10 agent dir missing
  20 network error | 30 backend API error | 40 filesystem error"

# --- Prompts / menus ---
T_ZH_prompt_continue="是否按标准方式继续安装？(Y/n)"
T_EN_prompt_continue="Proceed with standard installation? (Y/n)"
T_ZH_info_cancelled="已取消。"
T_EN_info_cancelled="Cancelled."
T_ZH_menu_choose_agent="你在用哪个 AI 助手？"
T_EN_menu_choose_agent="Which AI agent do you use?"
T_ZH_prompt_enter_agent_num="请输入序号 [1-8]:"
T_EN_prompt_enter_agent_num="Enter number [1-8]:"
T_ZH_prompt_enter_agent_num_default="请输入序号 [1-8, 默认"
T_EN_prompt_enter_agent_num_default="Enter number [1-8, default"
T_ZH_label_detected="已检测到"
T_EN_label_detected="detected"
T_ZH_info_agent_autodetect_summary="已嗅探到本机已装 AI 助手数量："
T_EN_info_agent_autodetect_summary="Detected installed AI agents:"
T_ZH_info_agent_autodetect_none="未嗅探到已装的 AI 助手——请手动选。"
T_EN_info_agent_autodetect_none="No AI agents auto-detected — please pick manually."
T_ZH_menu_choose_scope="你想安装哪些组件？"
T_EN_menu_choose_scope="What do you want to install?"
T_ZH_menu_scope_skills="仅 Skills            (只装方法论，轻量)"
T_EN_menu_scope_skills="Skills only       (methodology only, lightweight)"
T_ZH_menu_scope_mcp="仅 MCP               (只装 API 工具，给开发者)"
T_EN_menu_scope_mcp="MCP only          (API tools only, for developers)"
T_ZH_menu_scope_both="两者都装 (推荐)        (体验最完整)"
T_EN_menu_scope_both="Both (recommended)  (best experience)"
T_ZH_prompt_enter_scope_num="请输入序号 [1-3, 默认 3]:"
T_EN_prompt_enter_scope_num="Enter number [1-3, default 3]:"
T_ZH_error_invalid_selection="无效的选项："
T_EN_error_invalid_selection="Invalid selection:"
T_ZH_error_unknown_agent="未识别的 Agent："
T_EN_error_unknown_agent="Unknown agent:"
T_ZH_error_unknown_agent_hint="运行 --help 查看有效值。"
T_EN_error_unknown_agent_hint="Run --help for valid values."
T_ZH_error_unknown_option="未识别的参数："
T_EN_error_unknown_option="Unknown option:"
T_ZH_error_agent_required_ni="--agent 参数在非交互模式下必填"
T_EN_error_agent_required_ni="--agent is required in non-interactive mode"
T_ZH_error_scope_required_ni="--scope 参数在非交互模式下必填"
T_EN_error_scope_required_ni="--scope is required in non-interactive mode"
T_ZH_error_invalid_scope="无效的安装范围"
T_EN_error_invalid_scope="Invalid scope"
T_ZH_error_invalid_scope_hint="可选值：skills|mcp|both"
T_EN_error_invalid_scope_hint="Use skills|mcp|both."
T_ZH_warn_web_no_mcp="Web 端不支持 MCP，已降级为 scope=skills。"
T_EN_warn_web_no_mcp="Web agent does not support MCP. Falling back to scope=skills."

# --- API key flow (Phase 2: Activation) ---
T_ZH_phase2_title="🚀 服务状态：已安装（等待激活）"
T_EN_phase2_title="🚀 Server Status: Installed (Awaiting Authentication)"
T_ZH_phase2_step1="第 1 步：激活你的 API Key"
T_EN_phase2_step1="Step 1: Activate Your API Key"
T_ZH_phase2_step1_intro="开启实时抓取能力需要一个有效的 API Key。"
T_EN_phase2_step1_intro="To enable live scraping, you need a valid API Key."
T_ZH_phase2_existing_label="已有账号？"
T_EN_phase2_existing_label="Existing Users:"
T_ZH_phase2_existing_hint="到开发者控制台复制你的 Key："
T_EN_phase2_existing_hint="Copy your key from the Developer Dashboard:"
T_ZH_phase2_new_label="新用户？"
T_EN_phase2_new_label="New Users:"
T_ZH_phase2_new_hint="立刻注册赠送 60 测试积分（也可以直接在终端完成注册）："
T_EN_phase2_new_hint="Register now to receive 60 Complimentary Testing Credits (or finish registration here in terminal):"
T_ZH_dashboard_url="https://tool.pangolinfo.com/#/zh/menu/dataAPI/keys"
T_EN_dashboard_url="https://tool.pangolinfo.com/#/en/menu/dataAPI/keys"
T_ZH_signup_url="https://tool.pangolinfo.com/?sourceTag=mcp"
T_EN_signup_url="https://tool.pangolinfo.com/?sourceTag=mcp"

T_ZH_info_scope_skills_no_key="安装范围=skills，无需 API Key。"
T_EN_info_scope_skills_no_key="Scope=skills, no API key required."

# --- Scope preset (from landing-page generated command) ---
T_ZH_info_scope_preset="安装范围已由落地页指定："
T_EN_info_scope_preset="Install scope (from landing page):"
T_ZH_info_scope_mcp_only_hint="你只装 MCP 工具，不含方法论 SOP。如需 Skills，请从 pangolinfo.com/skills 重新生成命令。"
T_EN_info_scope_mcp_only_hint="MCP-only install — methodology SOPs not included. For Skills, generate command from pangolinfo.com/skills."
T_ZH_info_validating_key="正在校验你提供的 API Key..."
T_EN_info_validating_key="Validating provided API key..."
T_ZH_info_dryrun_validate_key="[dry-run] 会通过 GET 校验 Key"
T_EN_info_dryrun_validate_key="[dry-run] would validate key via GET"
T_ZH_ok_key_valid="API Key 可用。"
T_EN_ok_key_valid="API key valid."
T_ZH_error_key_invalid_provided="你提供的 API Key 无效。"
T_EN_error_key_invalid_provided="Provided API key is invalid."
T_ZH_error_key_required_ni="缺少 API Key（使用 --api-key=xxx）"
T_EN_error_key_required_ni="API key required (use --api-key=xxx)"
T_ZH_prompt_has_key="你已经有 Pangolinfo API Key 吗？[y/N]"
T_EN_prompt_has_key="Do you have a Pangolinfo API key? [y/N]"
T_ZH_prompt_arrow=">"
T_EN_prompt_arrow=">"
T_ZH_prompt_paste_key="粘贴你的 API Key（输入不显示）："
T_EN_prompt_paste_key="Paste your API key (input hidden):"
T_ZH_error_empty_key="Key 为空，请重试。"
T_EN_error_empty_key="Empty key, try again."
T_ZH_info_dryrun_validate="[dry-run] 会校验该 Key"
T_EN_info_dryrun_validate="[dry-run] would validate key"
T_ZH_info_validating="正在校验..."
T_EN_info_validating="Validating..."
T_ZH_error_key_invalid_retry="Key 无效。按 r 重试，按 n 注册新账号。"
T_EN_error_key_invalid_retry="Key invalid. Press 'r' to retry, 'n' to register a new account."
T_ZH_info_register_intro="接下来在终端里注册 Pangolinfo 账号。"
T_EN_info_register_intro="Let's register a Pangolinfo account — fully in terminal."
T_ZH_prompt_email="邮箱："
T_EN_prompt_email="Email:"
T_ZH_error_bad_email="邮箱格式不正确。"
T_EN_error_bad_email="Invalid email format."
T_ZH_info_dryrun_send_code="[dry-run] 会向以下邮箱发验证码："
T_EN_info_dryrun_send_code="[dry-run] would POST /email/code/send to"
T_ZH_info_sending_code="正在发送验证码到"
T_EN_info_sending_code="Sending verification code to"
T_ZH_error_send_code_failed="发送验证码失败。常见原因："
T_EN_error_send_code_failed="Failed to send code. Common reasons:"
T_ZH_error_send_code_reason_rate="频率限制（每邮箱 1 次/分钟，每 IP 5 次/小时）"
T_EN_error_send_code_reason_rate="Rate limit (1/min per email, 5/hour per IP)"
T_ZH_error_send_code_reason_net="网络问题"
T_EN_error_send_code_reason_net="Network issue"
T_ZH_ok_code_sent="验证码已发送，请检查收件箱（也看一下垃圾邮件）。"
T_EN_ok_code_sent="Code sent. Check your inbox (and spam folder)."
T_ZH_prompt_code="验证码（6 位数字）："
T_EN_prompt_code="Verification code (6 digits):"
T_ZH_prompt_password="密码（8-20 位，需含字母和数字，输入不显示）："
T_EN_prompt_password="Password (8-20 chars, must include letter+number, hidden):"
T_ZH_error_weak_password="密码不符合要求。需 8-20 位，必须包含字母和数字。"
T_EN_error_weak_password="Password too weak. Need 8-20 chars with both letters and digits."
T_ZH_info_dryrun_register="[dry-run] 会调用 /user/reg 与 /user/permanent-token"
T_EN_info_dryrun_register="[dry-run] would POST /user/reg and GET /user/permanent-token"
T_ZH_info_creating_account="正在创建账号..."
T_EN_info_creating_account="Creating account..."
T_ZH_error_register_failed="注册失败。请检查验证码或联系客服。"
T_EN_error_register_failed="Registration failed. Check your code or contact support."
T_ZH_ok_account_created="账号已创建。"
T_EN_ok_account_created="Account created."
T_ZH_info_fetching_perm_key="正在获取永久 API Key..."
T_EN_info_fetching_perm_key="Fetching your permanent API key..."
T_ZH_error_perm_key_failed="获取永久 Key 失败（已拿到会话）。请联系客服。"
T_EN_error_perm_key_failed="Got session but failed to fetch permanent token. Contact support."
T_ZH_ok_key_obtained="API Key 获取成功。"
T_EN_ok_key_obtained="API key obtained."

# --- Config ---
T_ZH_info_dryrun_write_config="[dry-run] 会写入配置文件（权限 600）："
T_EN_info_dryrun_write_config="[dry-run] would write config with chmod 600:"
T_ZH_error_cannot_create_dir="无法创建目录："
T_EN_error_cannot_create_dir="Cannot create"
T_ZH_warn_chmod_failed="无法设置文件权限 600："
T_EN_warn_chmod_failed="Failed to chmod 600"
T_ZH_ok_config_saved="配置已保存到"
T_EN_ok_config_saved="Config saved to"

# --- Phase 3: Security & Data Transparency ---
T_ZH_phase3_title="✅ 鉴权已激活"
T_EN_phase3_title="✅ Authentication Active"
T_ZH_phase3_security_header="安全与存储说明："
T_EN_phase3_security_header="Security & Storage Note:"
T_ZH_phase3_security_local="本地存储：你的 Key 保存在本地 AI 客户端的配置文件中，权限已收紧为仅当前用户可读。"
T_EN_phase3_security_local="Local Storage: Your Key is stored locally in your AI client's config. We've already restricted permissions to current user only."
T_ZH_phase3_security_https="加密传输：所有数据传输强制走 HTTPS。"
T_EN_phase3_security_https="Encryption: All data transmission is strictly over HTTPS."
T_ZH_phase3_security_privacy="隐私：Pangolinfo 是无状态数据提供方，不会记录你 AI 的对话历史或 prompt 上下文。"
T_EN_phase3_security_privacy="Privacy: Pangolinfo is a stateless data provider. We do not log or store your AI's conversation history or prompt context."
T_ZH_phase3_warning="警告：此配置文件包含敏感凭据。请勿提交到公开版本控制系统。"
T_EN_phase3_warning="Warning: Treat this configuration as a sensitive credential. Do not commit your config files to public version control."

# --- Skills install ---
T_ZH_info_scope_mcp_skip_skills="安装范围=mcp，跳过 Skills。"
T_EN_info_scope_mcp_skip_skills="Scope=mcp, skipping Skills."
T_ZH_info_installing_skills="正在安装 Skills..."
T_EN_info_installing_skills="Installing Skills..."
T_ZH_label_source="来源："
T_EN_label_source="source:"
T_ZH_label_target="目标："
T_EN_label_target="target:"
T_ZH_info_dryrun_copy_skills="[dry-run] 会把 Skills 拷贝到："
T_EN_info_dryrun_copy_skills="[dry-run] would copy Skills to"
T_ZH_error_skills_src_missing="找不到 Skills 源目录："
T_EN_error_skills_src_missing="Skills source not found:"
T_ZH_error_skills_src_hint="请先在 pangolinfo-skills/ 里跑 'npm run build'（开发模式）"
T_EN_error_skills_src_hint="Run 'npm run build' in pangolinfo-skills/ first (dev mode)"
T_ZH_info_backed_up="已备份原目录 →"
T_EN_info_backed_up="Backed up existing →"
T_ZH_ok_packaged_skills="已打包 Skills →"
T_EN_ok_packaged_skills="Packaged Skills →"
T_ZH_info_web_next_header="Web 端后续步骤："
T_EN_info_web_next_header="Next steps for web:"
T_ZH_info_web_step1="在浏览器中打开 Claude.ai 或 ChatGPT"
T_EN_info_web_step1="Open Claude.ai or ChatGPT in your browser"
T_ZH_info_web_step2="创建 Project（Claude）或自定义 GPT（OpenAI）"
T_EN_info_web_step2="Create a Project (Claude) or custom GPT (OpenAI)"
T_ZH_info_web_step3="把 ZIP 上传为知识库："
T_EN_info_web_step3="Upload as Knowledge Base:"
T_ZH_info_web_step4="添加自定义指令：'请根据附带知识库中的 SKILL.md 调用 Pangolinfo 技能'"
T_EN_info_web_step4="Add Custom Instructions: 'Use the SKILL.md files in the attached knowledge base to invoke Pangolinfo skills.'"
T_ZH_error_parent_missing="父目录不存在："
T_EN_error_parent_missing="Parent directory does not exist:"
T_ZH_error_agent_not_installed_prefix="Agent"
T_EN_error_agent_not_installed_prefix="Is"
T_ZH_error_agent_not_installed_suffix="可能还没装。请先初始化它再跑本安装程序。"
T_EN_error_agent_not_installed_suffix="installed? Initialize it once before running this installer."
T_ZH_error_copy_failed="拷贝 Skills 失败"
T_EN_error_copy_failed="Failed to copy Skills"
T_ZH_ok_skills_installed="Skills 已安装到"
T_EN_ok_skills_installed="Skills installed to"

# --- MCP install ---
T_ZH_info_scope_skills_skip_mcp="安装范围=skills，跳过 MCP。"
T_EN_info_scope_skills_skip_mcp="Scope=skills, skipping MCP."
T_ZH_info_web_skip_mcp="Web 端不支持 MCP，跳过。"
T_EN_info_web_skip_mcp="Web agent does not support MCP — skipping."
T_ZH_info_installing_mcp="正在安装 MCP 服务..."
T_EN_info_installing_mcp="Installing MCP server..."
T_ZH_info_dryrun_install_mcp="[dry-run] 会安装 MCP 到："
T_EN_info_dryrun_install_mcp="[dry-run] would install MCP to"
T_ZH_info_dryrun_register_mcp="[dry-run] 会在以下配置中注册："
T_EN_info_dryrun_register_mcp="[dry-run] would register in"
T_ZH_info_downloading_mcp="正在从 GitHub Release 下载 MCP server (~800 KB)..."
T_EN_info_downloading_mcp="Downloading MCP server from GitHub Release (~800 KB)..."
T_ZH_info_verifying_sha256="正在校验 SHA256..."
T_EN_info_verifying_sha256="Verifying SHA256..."
T_ZH_ok_sha256_verified="SHA256 校验通过。"
T_EN_ok_sha256_verified="SHA256 verified."
T_ZH_warn_sha256_skipped="未找到 sha256sum/shasum 工具，跳过完整性校验（不影响功能）。"
T_EN_warn_sha256_skipped="Neither sha256sum nor shasum available — skipping integrity check (functional)."
T_ZH_error_mcp_download_failed="下载 MCP server 失败："
T_EN_error_mcp_download_failed="Failed to download MCP server:"
T_ZH_error_mcp_download_hint="请检查网络连接是否能访问 github.com，或重试。"
T_EN_error_mcp_download_hint="Check network access to github.com and retry."
T_ZH_error_sha256_mismatch="SHA256 校验失败——下载的文件可能被破坏或篡改，已删除。"
T_EN_error_sha256_mismatch="SHA256 mismatch — downloaded file may be corrupted or tampered with; removed."
T_ZH_ok_mcp_binary_at="MCP server 已安装："
T_EN_ok_mcp_binary_at="MCP server binary at"
T_ZH_warn_no_mcp_config="该 Agent 没有 MCP 注册文件："
T_EN_warn_no_mcp_config="Agent has no MCP registration file:"
T_ZH_ok_mcp_created_config="已创建配置并写入 pangolinfo："
T_EN_ok_mcp_created_config="Created config with pangolinfo entry:"
T_ZH_ok_mcp_registered="已在以下配置中注册 pangolinfo："
T_EN_ok_mcp_registered="Registered pangolinfo in"
T_ZH_warn_no_jq="未安装 jq —— 无法安全合并到现有配置："
T_EN_warn_no_jq="jq not found — cannot safely merge into existing config:"
T_ZH_warn_add_manually="请手动添加："
T_EN_warn_add_manually="Please add manually:"
T_ZH_warn_node_missing="未检测到 node。MCP server 启动需要 Node.js 18+。安装方式见 README.md 的《前置环境》段。"
T_EN_warn_node_missing="node not found in PATH. MCP server requires Node.js 18+. See README.md > Prerequisites for install instructions."

# --- Per-agent install messages (v0.1 兼容性适配) ---
T_ZH_info_codex_dual_path="同时写入新版 cross-tool 路径："
T_EN_info_codex_dual_path="Also wrote to new cross-tool path:"
T_ZH_info_cursor_project_scope="Cursor rules 是项目级——已写到："
T_EN_info_cursor_project_scope="Cursor rules are project-scoped — wrote to:"
T_ZH_ok_cursor_mdc_written="已写入 .mdc 规则文件数："
T_EN_ok_cursor_mdc_written=".mdc rule files written:"
T_ZH_info_cursor_global_hint="如需全局生效，请把上面的 .mdc 内容粘贴到 Cursor → Settings → User Rules。"
T_EN_info_cursor_global_hint="For global scope, paste the .mdc content into Cursor → Settings → User Rules."
T_ZH_info_cline_global_loaded="Cline 启动时会自动加载 ~/Documents/Cline/Rules/ 下所有规则。"
T_EN_info_cline_global_loaded="Cline auto-loads all rules from ~/Documents/Cline/Rules/ on startup."
T_ZH_ok_windsurf_appended="已追加 Pangolinfo 段到："
T_EN_ok_windsurf_appended="Appended Pangolinfo section to:"
T_ZH_info_using_claude_cli="检测到 claude CLI——使用 'claude mcp add' 注册"
T_EN_info_using_claude_cli="Detected claude CLI — using 'claude mcp add'"
T_ZH_warn_claude_cli_failed="claude mcp add 失败，回退到写 settings.json"
T_EN_warn_claude_cli_failed="claude mcp add failed; falling back to settings.json"
T_ZH_info_cline_vscode_detected="检测到 VS Code 扩展版 Cline，写入："
T_EN_info_cline_vscode_detected="Detected Cline VS Code extension; writing to:"
T_ZH_info_mcp_already_registered="配置中已存在 pangolinfo 节点，跳过："
T_EN_info_mcp_already_registered="pangolinfo entry already exists, skipping:"
T_ZH_info_mcp_manual_overwrite="如需更新请手动编辑或删掉旧节点重跑。"
T_EN_info_mcp_manual_overwrite="Edit manually or remove the old entry and re-run to update."

# --- Done ---
T_ZH_done_success="✓ Pangolinfo 安装成功！"
T_EN_done_success="✓ Pangolinfo installed successfully!"
T_ZH_done_agent_label="Agent："
T_EN_done_agent_label="Agent:"
T_ZH_done_scope_label="安装范围："
T_EN_done_scope_label="Scope:"
T_ZH_done_try_header="重启你的 AI 客户端，然后试试："
T_EN_done_try_header="Restart your AI client, then run:"
T_ZH_done_try_1="用 Pangolinfo 查询 ASIN B0XXXXXXXX 的 Buy Box 价格"
T_EN_done_try_1="Use Pangolinfo to get the buybox price for ASIN B0XXXXXXXX"
T_ZH_done_try_2="帮我做一份蓝牙耳机的 Amazon 选品报告"
T_EN_done_try_2="Help me research Amazon niches for bluetooth earphones"
T_ZH_done_star_prompt="觉得好用？在 GitHub 给我们点个 Star："
T_EN_done_star_prompt="Enjoyed it? Star us on GitHub:"
T_ZH_done_small_team="我们是一支小团队，你的 Star 对我们意义重大。🙏"
T_EN_done_small_team="We're a small team. Your star really helps. 🙏"

# 翻译查表
t() {
  key="$1"
  case "$LOCALE" in
    en) eval "printf '%s' \"\${T_EN_$key:-}\"" ;;
    *)  eval "printf '%s' \"\${T_ZH_$key:-}\"" ;;
  esac
}

# Source agent path table.
# 两种运行模式:
#   1. 本地 git clone 模式: $0 是 ./install.sh, lib/ 在脚本旁边. 直接 source.
#   2. curl|sh 模式: $0 是 /dev/stdin 或类似, 没有 lib/. 从 install.pangolinfo.com
#      拉同一 main 分支的 lib/agents.sh 到 /tmp 后 source.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/lib/agents.sh" ]; then
  # 本地模式
  . "${SCRIPT_DIR}/lib/agents.sh"
else
  # curl|sh 模式 — 远程拉 lib/agents.sh
  # 允许通过 PANGOLINFO_INSTALLER_BASE 环境变量覆盖,便于测试
  AGENTS_URL="${PANGOLINFO_INSTALLER_BASE:-https://install.pangolinfo.com}/lib/agents.sh"
  AGENTS_TMP="$(mktemp -t pangolinfo-agents.XXXXXX.sh 2>/dev/null || echo "/tmp/pangolinfo-agents-$$.sh")"
  # cleanup on exit
  trap 'rm -f "$AGENTS_TMP"' EXIT INT TERM
  if ! curl -fsSL --max-time 30 "$AGENTS_URL" -o "$AGENTS_TMP" 2>/dev/null; then
    echo "ERROR: failed to download lib/agents.sh from $AGENTS_URL" >&2
    echo "Check your network connection or try cloning the repo and running ./install.sh locally:" >&2
    echo "  git clone https://github.com/pangolinfo/pangolinfo-installer.git" >&2
    echo "  cd pangolinfo-installer && ./install.sh ..." >&2
    exit 20
  fi
  # 简单校验: 应该至少包含 agent_paths 函数定义
  if ! grep -q 'agent_paths' "$AGENTS_TMP" 2>/dev/null; then
    echo "ERROR: downloaded lib/agents.sh looks malformed (no agent_paths function)." >&2
    echo "URL: $AGENTS_URL" >&2
    exit 20
  fi
  . "$AGENTS_TMP"
  SCRIPT_DIR=""  # 标记为远程模式,后续代码不要依赖 SCRIPT_DIR/../pangolinfo-skills 等
fi

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
# Colors — only when stdout is a TTY
if [ -t 1 ]; then
  C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RED='\033[31m'
  C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'
  C_RESET='\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_RESET=''
fi

info()  { printf "%b\n" "${C_DIM}›${C_RESET} $*"; }
ok()    { printf "%b\n" "${C_GREEN}✓${C_RESET} $*"; }
warn()  { printf "%b\n" "${C_YELLOW}⚠${C_RESET} $*" >&2; }
err()   { printf "%b\n" "${C_RED}✗${C_RESET} $*" >&2; }
fatal() { err "$*"; exit "${2:-1}"; }

# 防止 curl|sh 时 stdin 被占用，所有交互输入走 /dev/tty
prompt() {
  printf "%b " "$1"
  REPLY=""
  if [ -t 0 ]; then
    IFS= read -r REPLY || true
  elif [ -r /dev/tty ]; then
    IFS= read -r REPLY < /dev/tty || true
  fi
  printf "%s" "${REPLY:-}"
}

# 关闭回显的输入（密码）
prompt_silent() {
  printf "%b " "$1"
  REPLY=""
  stty -echo 2>/dev/null || true
  if [ -t 0 ]; then
    IFS= read -r REPLY || true
  elif [ -r /dev/tty ]; then
    IFS= read -r REPLY < /dev/tty || true
  fi
  stty echo 2>/dev/null || true
  printf "\n"
  printf "%s" "${REPLY:-}"
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
  cat <<EOF
$(t banner_title) v${INSTALLER_VERSION}

$(t help_usage_header)
  install.sh [OPTIONS]

$(t help_options_header)
  --agent=<name>       claude-code | cursor | cline | windsurf
                       hermes | codex | openclaw | web
                       $(t help_opt_agent)
  --scope=<scope>      $(t help_opt_scope)
  --api-key=<key>      $(t help_opt_apikey)
  --api-base=<url>     $(t help_opt_apibase)
  --scrape-base=<url>  $(t help_opt_scrapebase)
  --non-interactive    $(t help_opt_noninteractive)
  --skills-version=<v> $(t help_opt_skillsver)
  --mcp-version=<v>    $(t help_opt_mcpver)
  --dry-run            $(t help_opt_dryrun)
  --lang=<zh|en>       $(t help_opt_lang)
  -h, --help           $(t help_opt_help)

$(t help_examples_header)
  $(t help_ex_interactive)
  curl -fsSL install.pangolinfo.com/install.sh | sh

  $(t help_ex_preset)
  curl ... | sh -s -- --agent=claude-code --scope=both

  $(t help_ex_headless)
  curl ... | sh -s -- --agent=cursor --scope=mcp \\
                       --api-key=pgl_xxx --non-interactive

$(t help_exitcodes_header)
$(t help_exit_table)
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing (POSIX-compatible --key=value)
# ---------------------------------------------------------------------------
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --agent=*)           ARG_AGENT="${arg#*=}" ;;
      --scope=*)           ARG_SCOPE="${arg#*=}" ;;
      --api-key=*)         ARG_API_KEY="${arg#*=}" ;;
      --api-base=*)        ARG_API_BASE="${arg#*=}" ;;
      --scrape-base=*)     ARG_SCRAPE_BASE="${arg#*=}" ;;
      --skills-version=*)  ARG_SKILLS_VERSION="${arg#*=}" ;;
      --mcp-version=*)     ARG_MCP_VERSION="${arg#*=}" ;;
      --lang=*)            ARG_LANG="${arg#*=}" ;;
      --non-interactive)   ARG_NON_INTERACTIVE=1 ;;
      --dry-run)           ARG_DRY_RUN=1 ;;
      -h|--help)           show_help; exit 0 ;;
      *)                   err "$(t error_unknown_option) $arg"; show_help; exit 2 ;;
    esac
  done

  # 提前规范化（不要用 `[ -n ] && set` 模式——在 set -e 下空字符串会导致退出）
  API_BASE="${ARG_API_BASE:-$DEFAULT_API_BASE}"
  SCRAPE_BASE="${ARG_SCRAPE_BASE:-$DEFAULT_SCRAPE_BASE}"
  if [ -n "$ARG_SCOPE" ]; then SELECTED_SCOPE="$ARG_SCOPE"; fi
  if [ -n "$ARG_AGENT" ]; then SELECTED_AGENT="$ARG_AGENT"; fi
  if [ -n "$ARG_API_KEY" ]; then API_KEY="$ARG_API_KEY"; fi
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
  printf "%b\n" "${C_BOLD}[$(t banner_title) v${INSTALLER_VERSION}]${C_RESET}"
  printf "%b\n" "${C_DIM}$(t banner_intro)${C_RESET}"
  printf "%b\n" "${C_DIM}${GITHUB_URL}${C_RESET}"
  echo
  printf "%b\n" "$(t banner_desc_header)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t banner_desc_skills)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t banner_desc_mcp)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t banner_desc_apikey)"
  echo
}

# ---------------------------------------------------------------------------
# Step 1: Choose Agent
# ---------------------------------------------------------------------------
choose_agent() {
  if [ -n "$SELECTED_AGENT" ]; then
    if ! agent_paths "$SELECTED_AGENT" >/dev/null 2>&1; then
      fatal "$(t error_unknown_agent) $SELECTED_AGENT. $(t error_unknown_agent_hint)" 2
    fi
    return
  fi

  [ "$ARG_NON_INTERACTIVE" = 1 ] && fatal "$(t error_agent_required_ni)" 2

  # 自动嗅探用户机器上已装的 agent —— 检到的会在菜单标 (detected)，
  # 第一个检到的作为默认（直接回车即选）。
  default_idx=""
  detected_count=0
  i=1
  for a in $ALL_AGENTS; do
    if agent_is_installed "$a"; then
      detected_count=$((detected_count + 1))
      [ -z "$default_idx" ] && default_idx=$i
    fi
    i=$((i + 1))
  done

  # 检到的提示
  if [ "$detected_count" -gt 0 ]; then
    info "$(t info_agent_autodetect_summary) ${detected_count}"
  else
    info "$(t info_agent_autodetect_none)"
  fi
  echo

  printf "%b\n" "${C_BOLD}$(t menu_choose_agent)${C_RESET}"
  i=1
  for a in $ALL_AGENTS; do
    name=$(agent_paths "$a" | head -n 1)
    if agent_is_installed "$a"; then
      printf "  ${C_GREEN}%d)${C_RESET} %-25s ${C_DIM}(%s)${C_RESET} ${C_GREEN}● $(t label_detected)${C_RESET}\n" "$i" "$name" "$a"
    else
      printf "  ${C_GREEN}%d)${C_RESET} %-25s ${C_DIM}(%s)${C_RESET}\n" "$i" "$name" "$a"
    fi
    i=$((i + 1))
  done
  echo

  if [ -n "$default_idx" ]; then
    reply=$(prompt "$(t prompt_enter_agent_num_default) ${default_idx}]:")
    [ -z "$reply" ] && reply=$default_idx
  else
    reply=$(prompt "$(t prompt_enter_agent_num)")
  fi

  # 把数字映射回名字
  i=1
  for a in $ALL_AGENTS; do
    if [ "$reply" = "$i" ]; then
      SELECTED_AGENT="$a"
      break
    fi
    i=$((i + 1))
  done

  [ -z "$SELECTED_AGENT" ] && fatal "$(t error_invalid_selection) $reply" 2
  echo
}

# ---------------------------------------------------------------------------
# Step 2: Choose Scope
# ---------------------------------------------------------------------------
choose_scope() {
  # web agent 只支持 skills
  if [ "$SELECTED_AGENT" = "web" ]; then
    if [ -n "$SELECTED_SCOPE" ] && [ "$SELECTED_SCOPE" != "skills" ]; then
      warn "$(t warn_web_no_mcp)"
    fi
    SELECTED_SCOPE="skills"
    return
  fi

  if [ -n "$SELECTED_SCOPE" ]; then
    case "$SELECTED_SCOPE" in
      skills|mcp|both)
        # 命令行已指定 scope（典型场景：从落地页生成的命令）
        # → 跳过菜单，但打印一行提示让用户看到当前安装范围
        info "$(t info_scope_preset) ${C_BOLD}${SELECTED_SCOPE}${C_RESET}"
        # MCP-only 用户额外提示：你没装方法论
        if [ "$SELECTED_SCOPE" = "mcp" ]; then
          info "$(t info_scope_mcp_only_hint)"
        fi
        return
        ;;
      *) fatal "$(t error_invalid_scope): $SELECTED_SCOPE. $(t error_invalid_scope_hint)" 2 ;;
    esac
  fi

  [ "$ARG_NON_INTERACTIVE" = 1 ] && fatal "$(t error_scope_required_ni)" 2

  printf "%b\n" "${C_BOLD}$(t menu_choose_scope)${C_RESET}"
  printf "  ${C_GREEN}1)${C_RESET} 📘 %s\n" "$(t menu_scope_skills)"
  printf "  ${C_GREEN}2)${C_RESET} 🧰 %s\n" "$(t menu_scope_mcp)"
  printf "  ${C_GREEN}3)${C_RESET} ✨ ${C_BOLD}%s${C_RESET}\n" "$(t menu_scope_both)"
  echo
  reply=$(prompt "$(t prompt_enter_scope_num)")
  case "${reply:-3}" in
    1) SELECTED_SCOPE="skills" ;;
    2) SELECTED_SCOPE="mcp" ;;
    3) SELECTED_SCOPE="both" ;;
    *) fatal "$(t error_invalid_selection) $reply" 2 ;;
  esac
  echo
}

# ---------------------------------------------------------------------------
# Step 3: API Key flow (only if scope includes mcp)
# ---------------------------------------------------------------------------

# 调后端发验证码
backend_send_code() {
  email="$1"
  body=$(printf '{"type":"regist","to":"%s"}' "$email")
  curl -fsSL -X POST "${API_BASE}/email/code/send" \
    -H "Content-Type: application/json" \
    -d "$body" >/dev/null 2>&1
}

# 调后端注册，返回 session token
backend_register() {
  email="$1"; password="$2"; code="$3"
  # 注意 Email/Password 是大写（后端 DTO 用大写字段名）
  body=$(printf '{"Email":"%s","Password":"%s","code":"%s","source":"cli-installer"}' \
    "$email" "$password" "$code")
  resp=$(curl -fsSL -X POST "${API_BASE}/user/reg" \
    -H "Content-Type: application/json" \
    -d "$body" 2>/dev/null) || return 1
  # 取 "data" 字段（ApiResponse<String> 包装）
  echo "$resp" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p'
}

# 用 session token 拿 permanent token
backend_get_permanent_token() {
  session_token="$1"
  resp=$(curl -fsSL -X GET "${API_BASE}/user/permanent-token" \
    -H "Authorization: Bearer ${session_token}" 2>/dev/null) || return 1
  echo "$resp" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p'
}

# 验证 key 可用
backend_validate_key() {
  key="$1"
  curl -fsSL -X GET "${API_BASE}/user/permanent-token" \
    -H "Authorization: Bearer ${key}" >/dev/null 2>&1
}

# 邮箱格式简单校验
is_email() {
  echo "$1" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
}

# 密码强度校验（8-20 位含字母和数字）
is_strong_password() {
  pw="$1"
  len=${#pw}
  if [ "$len" -lt 8 ] || [ "$len" -gt 20 ]; then return 1; fi
  echo "$pw" | grep -qE '[A-Za-z]' || return 1
  echo "$pw" | grep -qE '[0-9]' || return 1
  return 0
}

setup_api_key() {
  # 不需要 MCP 就跳过整个 Key 流程
  case "$SELECTED_SCOPE" in
    skills) info "$(t info_scope_skills_no_key)"; return ;;
  esac

  # 已通过参数或环境提供
  if [ -n "$API_KEY" ]; then
    info "$(t info_validating_key)"
    if [ "$ARG_DRY_RUN" = 1 ]; then
      ok "$(t info_dryrun_validate_key) ${API_BASE}/user/permanent-token"
      return
    fi
    if backend_validate_key "$API_KEY"; then
      ok "$(t ok_key_valid)"
      return
    else
      err "$(t error_key_invalid_provided)"
      [ "$ARG_NON_INTERACTIVE" = 1 ] && exit 30
      API_KEY=""
    fi
  fi

  [ "$ARG_NON_INTERACTIVE" = 1 ] && fatal "$(t error_key_required_ni)" 2

  # --- Phase 2 引导 ---
  echo
  printf "%b\n" "${C_BOLD}$(t phase2_title)${C_RESET}"
  echo
  printf "%b\n" "${C_BOLD}$(t phase2_step1)${C_RESET}"
  echo "  $(t phase2_step1_intro)"
  echo
  printf "  %b %s\n" "${C_GREEN}•${C_RESET}" "$(t phase2_existing_label) $(t phase2_existing_hint)"
  printf "    %b%s%b\n" "${C_BLUE}" "$(t dashboard_url)" "${C_RESET}"
  echo
  printf "  %b %s\n" "${C_GREEN}•${C_RESET}" "$(t phase2_new_label) $(t phase2_new_hint)"
  printf "    %b%s%b\n" "${C_BLUE}" "$(t signup_url)" "${C_RESET}"
  echo

  # 询问用户
  printf "%b\n" "${C_BOLD}$(t prompt_has_key)${C_RESET}"
  reply=$(prompt "$(t prompt_arrow)")
  case "$reply" in
    [Yy]|[Yy][Ee][Ss])
      _read_existing_key
      ;;
    *)
      _register_new_account
      ;;
  esac
}

_read_existing_key() {
  while :; do
    API_KEY=$(prompt_silent "$(t prompt_paste_key)")
    if [ -z "$API_KEY" ]; then
      err "$(t error_empty_key)"; continue
    fi
    if [ "$ARG_DRY_RUN" = 1 ]; then
      ok "$(t info_dryrun_validate)"; return
    fi
    info "$(t info_validating)"
    if backend_validate_key "$API_KEY"; then
      ok "$(t ok_key_valid)"
      return
    fi
    err "$(t error_key_invalid_retry)"
    reply=$(prompt "$(t prompt_arrow)")
    [ "$reply" = "n" ] || [ "$reply" = "N" ] && { _register_new_account; return; }
  done
}

_register_new_account() {
  echo
  info "$(t info_register_intro)"
  echo

  # 1. 邮箱
  while :; do
    email=$(prompt "$(t prompt_email)")
    is_email "$email" && break
    err "$(t error_bad_email)"
  done

  # 2. 发验证码
  if [ "$ARG_DRY_RUN" = 1 ]; then
    ok "$(t info_dryrun_send_code) ${email}"
  else
    info "$(t info_sending_code) ${email}..."
    if ! backend_send_code "$email"; then
      err "$(t error_send_code_failed)"
      err "  • $(t error_send_code_reason_rate)"
      err "  • $(t error_send_code_reason_net)"
      exit 30
    fi
    ok "$(t ok_code_sent)"
  fi

  # 3. 验证码 + 密码
  code=$(prompt "$(t prompt_code)")
  while :; do
    password=$(prompt_silent "$(t prompt_password)")
    if is_strong_password "$password"; then break; fi
    err "$(t error_weak_password)"
  done

  # 4. 注册
  if [ "$ARG_DRY_RUN" = 1 ]; then
    ok "$(t info_dryrun_register)"
    API_KEY="pgl_dryrun_fake_key"
    return
  fi

  info "$(t info_creating_account)"
  session_token=$(backend_register "$email" "$password" "$code")
  if [ -z "$session_token" ]; then
    err "$(t error_register_failed)"
    exit 30
  fi
  ok "$(t ok_account_created)"

  info "$(t info_fetching_perm_key)"
  API_KEY=$(backend_get_permanent_token "$session_token")
  if [ -z "$API_KEY" ]; then
    err "$(t error_perm_key_failed)"
    exit 30
  fi
  ok "$(t ok_key_obtained)"
}

# ---------------------------------------------------------------------------
# Step 4: Save config
# ---------------------------------------------------------------------------
save_config() {
  [ -z "$API_KEY" ] && return  # skills-only 模式不需要存

  if [ "$ARG_DRY_RUN" = 1 ]; then
    ok "$(t info_dryrun_write_config) ${CONFIG_FILE}"
    _print_phase3_security
    return
  fi

  mkdir -p "$CONFIG_DIR" || fatal "$(t error_cannot_create_dir) $CONFIG_DIR" 40
  cat > "$CONFIG_FILE" <<EOF
{
  "api_key": "${API_KEY}",
  "api_base": "${API_BASE}",
  "scrape_base": "${SCRAPE_BASE}"
}
EOF
  chmod 600 "$CONFIG_FILE" || warn "$(t warn_chmod_failed) $CONFIG_FILE"
  ok "$(t ok_config_saved) ${CONFIG_FILE}"
  _print_phase3_security
}

_print_phase3_security() {
  echo
  printf "%b\n" "${C_BOLD}$(t phase3_title)${C_RESET}"
  echo
  printf "  ${C_DIM}%s${C_RESET}\n" "$(t phase3_security_header)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t phase3_security_local)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t phase3_security_https)"
  printf "  ${C_GREEN}•${C_RESET} %s\n" "$(t phase3_security_privacy)"
  echo
  printf "  ${C_YELLOW}⚠${C_RESET} ${C_DIM}%s${C_RESET}\n" "$(t phase3_warning)"
}

# ---------------------------------------------------------------------------
# Step 5: Install Skills
# ---------------------------------------------------------------------------
install_skills() {
  case "$SELECTED_SCOPE" in
    mcp) info "$(t info_scope_mcp_skip_skills)"; return ;;
  esac

  dist_dir=$(agent_dist_dir "$SELECTED_AGENT")
  install_path=$(agent_paths "$SELECTED_AGENT" | sed -n '2p')

  info "$(t info_installing_skills)"
  echo "  ↓ $(t label_source) dist/${dist_dir}/"
  echo "  → $(t label_target) ${install_path}"

  if [ "$ARG_DRY_RUN" = 1 ]; then
    ok "$(t info_dryrun_copy_skills) ${install_path}"
    return
  fi

  # v0.1：从本地 ../pangolinfo-skills/dist/<agent>/ 拷贝
  # 未来版本：从 GitHub Release 下载 tarball
  local_src="${SCRIPT_DIR}/../pangolinfo-skills/dist/${dist_dir}"
  if [ ! -d "$local_src" ]; then
    err "$(t error_skills_src_missing) $local_src"
    err "$(t error_skills_src_hint)"
    exit 20
  fi

  # 按 agent 分发到对应安装器（每家 agent 的 skill 加载机制不同）
  case "$SELECTED_AGENT" in
    web)      install_skills_web "$local_src" "$install_path" ;;
    cursor)   install_skills_cursor "$local_src" "$install_path" ;;
    cline)    install_skills_cline "$local_src" "$install_path" ;;
    windsurf) install_skills_windsurf "$local_src" "$install_path" ;;
    codex)    install_skills_codex "$local_src" "$install_path" ;;
    *)        install_skills_dir "$local_src" "$install_path" ;;
  esac
}

# 标准目录拷贝（claude-code / hermes / openclaw 用）
install_skills_dir() {
  src="$1"; dest="$2"
  parent=$(dirname "$dest")
  if [ ! -d "$parent" ]; then
    err "$(t error_parent_missing) $parent"
    err "$(t error_agent_not_installed_prefix) ${SELECTED_AGENT} $(t error_agent_not_installed_suffix)"
    exit 10
  fi
  if [ -e "$dest" ]; then
    backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup" && info "$(t info_backed_up) $backup"
  fi
  cp -r "$src" "$dest" || fatal "$(t error_copy_failed)" 40
  ok "$(t ok_skills_installed) ${dest}"
}

# Web: 打包 ZIP 让用户上传
install_skills_web() {
  src="$1"; zip_target="$2"
  mkdir -p "$(dirname "$zip_target")"
  if [ -e "$zip_target" ]; then
    backup="${zip_target}.bak.$(date +%s)"
    mv "$zip_target" "$backup" && info "$(t info_backed_up) $backup"
  fi
  dist_basename=$(basename "$src")
  (cd "$src/.." && zip -qr "$zip_target" "${dist_basename}")
  ok "$(t ok_packaged_skills) ${zip_target}"
  echo
  info "$(t info_web_next_header)"
  info "  1. $(t info_web_step1)"
  info "  2. $(t info_web_step2)"
  info "  3. $(t info_web_step3) ${zip_target}"
  info "  4. $(t info_web_step4)"
}

# Codex: 同时写 ~/.codex/skills/ 和 ~/.agents/skills/ (向前兼容)
install_skills_codex() {
  src="$1"; primary="$2"
  install_skills_dir "$src" "$primary"
  # 新 cross-tool convention: ~/.agents/skills/
  agents_dir="$HOME/.agents/skills/pangolinfo"
  parent=$(dirname "$agents_dir")
  if [ ! -d "$parent" ]; then
    mkdir -p "$parent" 2>/dev/null || true
  fi
  if [ -d "$parent" ]; then
    if [ -e "$agents_dir" ]; then
      backup="${agents_dir}.bak.$(date +%s)"
      mv "$agents_dir" "$backup" && info "$(t info_backed_up) $backup"
    fi
    cp -r "$src" "$agents_dir" 2>/dev/null && \
      info "$(t info_codex_dual_path) ${agents_dir}"
  fi
}

# Cursor (B2+B3): 把每个 skill 编译成 .cursor/rules/pangolinfo-<name>.mdc 单文件
# install_path 形如 "PROJECT:.cursor/rules"
install_skills_cursor() {
  src="$1"; project_subpath_spec="$2"
  # 解析 PROJECT:<subpath>
  subpath="${project_subpath_spec#PROJECT:}"
  # 写到当前 cwd (脚本运行目录) 的项目内子路径
  target_dir="$(pwd)/${subpath}"
  mkdir -p "$target_dir" || fatal "$(t error_cannot_create_dir) $target_dir" 40

  info "$(t info_cursor_project_scope) ${target_dir}"

  # 遍历 dist 中每个 skill 子目录的 SKILL.md → 生成 pangolinfo-<name>.mdc
  count=0
  for skill_dir in "$src"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || continue
    target_mdc="$target_dir/pangolinfo-${skill_name}.mdc"

    # .mdc frontmatter 字段：description / globs / alwaysApply
    # 从原 SKILL.md frontmatter 抽 description (兼容 inline / YAML pipe 多行)
    desc=$(awk '
      /^description:[[:space:]]*\|/ { mode="pipe"; next }
      mode=="pipe" && /^[[:space:]]+/ { sub(/^[[:space:]]+/,""); print; exit }
      /^description:[[:space:]]/ { sub(/^description:[[:space:]]*/,""); print; exit }
    ' "$skill_md")
    [ -z "$desc" ] && desc="Pangolinfo MCP skill: ${skill_name}"
    # 转义 mdc frontmatter 内的双引号
    desc=$(printf "%s" "$desc" | sed 's/"/\\"/g')

    {
      echo "---"
      echo "description: \"${desc}\""
      echo "globs: [\"**/*\"]"
      echo "alwaysApply: false"
      echo "---"
      echo
      # 剥掉原 SKILL.md frontmatter（首个 --- 到第二个 --- 之间）后追加正文
      awk 'BEGIN{f=0} /^---$/ {f++; next} f>=2 {print}' "$skill_md"
    } > "$target_mdc"
    count=$((count + 1))
  done
  ok "$(t ok_cursor_mdc_written) ${count} → ${target_dir}"
  info "$(t info_cursor_global_hint)"
}

# Cline (B4): 写到 ~/Documents/Cline/Rules/pangolinfo/
# install_path 已是 ~/Documents/Cline/Rules/pangolinfo
install_skills_cline() {
  src="$1"; dest="$2"
  # 先确保父目录存在（Cline 不会自动建 Documents/Cline/Rules/）
  mkdir -p "$(dirname "$dest")" || fatal "$(t error_cannot_create_dir) $(dirname $dest)" 40

  if [ -e "$dest" ]; then
    backup="${dest}.bak.$(date +%s)"
    mv "$dest" "$backup" && info "$(t info_backed_up) $backup"
  fi
  cp -r "$src" "$dest" || fatal "$(t error_copy_failed)" 40
  ok "$(t ok_skills_installed) ${dest}"
  info "$(t info_cline_global_loaded)"
}

# Windsurf (B5): 把所有 skill 合并追加到 ~/.codeium/windsurf/global_rules.md
# install_path 形如 "APPEND:/abs/path/to/global_rules.md"
install_skills_windsurf() {
  src="$1"; append_spec="$2"
  target_file="${append_spec#APPEND:}"
  mkdir -p "$(dirname "$target_file")" || fatal "$(t error_cannot_create_dir) $(dirname $target_file)" 40

  # 备份原文件
  if [ -f "$target_file" ]; then
    backup="${target_file}.bak.$(date +%s)"
    cp "$target_file" "$backup" && info "$(t info_backed_up) $backup"

    # 若文件里已有 Pangolinfo 段，删掉旧段再追加新的
    if grep -q "<!-- BEGIN PANGOLINFO -->" "$target_file" 2>/dev/null; then
      tmp="${target_file}.tmp.$$"
      awk '/<!-- BEGIN PANGOLINFO -->/{skip=1} /<!-- END PANGOLINFO -->/{skip=0; next} !skip' "$target_file" > "$tmp" && \
        mv "$tmp" "$target_file"
    fi
  fi

  # 追加新段
  {
    echo ""
    echo "<!-- BEGIN PANGOLINFO -->"
    echo "<!-- Auto-added by pangolinfo installer. Do not edit between markers. -->"
    echo ""
    for skill_dir in "$src"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "$skill_dir")
      skill_md="$skill_dir/SKILL.md"
      [ -f "$skill_md" ] || continue
      echo "## Pangolinfo Skill: ${skill_name}"
      echo ""
      # 剥掉 frontmatter，只追加 markdown 正文
      awk 'BEGIN{f=0} /^---$/ {f++; next} f>=2 {print}' "$skill_md"
      echo ""
      echo "---"
      echo ""
    done
    echo "<!-- END PANGOLINFO -->"
  } >> "$target_file"

  ok "$(t ok_windsurf_appended) ${target_file}"
}

# ---------------------------------------------------------------------------
# Step 6: Install MCP server + register
# ---------------------------------------------------------------------------
install_mcp() {
  case "$SELECTED_SCOPE" in
    skills) info "$(t info_scope_skills_skip_mcp)"; return ;;
  esac

  if [ "$SELECTED_AGENT" = "web" ]; then
    info "$(t info_web_skip_mcp)"
    return
  fi

  # 非阻断式 node 检查 — MCP server 启动需要 node 18+
  # 见 README.md "前置环境" / Prerequisites 段
  if ! command -v node >/dev/null 2>&1; then
    warn "$(t warn_node_missing)"
  fi

  mcp_config=$(agent_paths "$SELECTED_AGENT" | sed -n '3p')

  info "$(t info_installing_mcp)"
  if [ "$ARG_DRY_RUN" = 1 ]; then
    ok "$(t info_dryrun_install_mcp) ${MCP_INSTALL_DIR}"
    ok "$(t info_dryrun_register_mcp) ${mcp_config}"
    return
  fi

  # 从 GitHub Release 下载 server.mjs (单文件零依赖 ~800 KB)
  # URL 形态:
  #   latest:     ${MCP_RELEASE_BASE}/latest/download/server.mjs
  #   pinned:     ${MCP_RELEASE_BASE}/download/<tag>/server.mjs
  if [ "$ARG_MCP_VERSION" = "latest" ]; then
    mcp_url="${MCP_RELEASE_BASE}/latest/download/server.mjs"
    sha_url="${MCP_RELEASE_BASE}/latest/download/server.mjs.sha256"
  else
    mcp_url="${MCP_RELEASE_BASE}/download/${ARG_MCP_VERSION}/server.mjs"
    sha_url="${MCP_RELEASE_BASE}/download/${ARG_MCP_VERSION}/server.mjs.sha256"
  fi

  mkdir -p "$MCP_INSTALL_DIR" || fatal "$(t error_cannot_create_dir) $MCP_INSTALL_DIR" 40

  info "$(t info_downloading_mcp)"
  # curl -fL: -f 4xx/5xx fail, -L 跟随 redirect (Release URL 会 302 到 S3)
  # --retry 3 抗瞬时网络抖动
  if ! curl -fL --retry 3 --retry-delay 2 -o "$MCP_INSTALL_DIR/server.mjs" "$mcp_url"; then
    err "$(t error_mcp_download_failed) $mcp_url"
    err "$(t error_mcp_download_hint)"
    rm -f "$MCP_INSTALL_DIR/server.mjs"
    exit 20
  fi

  # 完整性校验 — 下载 .sha256 并对比。校验工具缺失时仅 warn,不阻塞
  # (sha256sum 在大多数 Linux 自带,macOS 用 shasum -a 256)。
  info "$(t info_verifying_sha256)"
  if curl -fL --retry 2 --retry-delay 1 -sS -o "$MCP_INSTALL_DIR/server.mjs.sha256" "$sha_url" 2>/dev/null; then
    if command -v sha256sum >/dev/null 2>&1; then
      sha_tool="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
      sha_tool="shasum -a 256"
    else
      sha_tool=""
    fi
    if [ -n "$sha_tool" ]; then
      # .sha256 文件格式:"<hash>  <filename>" 或 "<hash> *<filename>"
      # 在 install dir 里 cd 进去校验,避免路径不匹配
      ( cd "$MCP_INSTALL_DIR" && $sha_tool -c server.mjs.sha256 >/dev/null 2>&1 )
      if [ $? -ne 0 ]; then
        err "$(t error_sha256_mismatch)"
        rm -f "$MCP_INSTALL_DIR/server.mjs" "$MCP_INSTALL_DIR/server.mjs.sha256"
        exit 20
      fi
      ok "$(t ok_sha256_verified)"
    else
      warn "$(t warn_sha256_skipped)"
    fi
    rm -f "$MCP_INSTALL_DIR/server.mjs.sha256"
  fi

  ok "$(t ok_mcp_binary_at) ${MCP_INSTALL_DIR}/server.mjs"

  # 注册到 Agent 的 mcp.json
  if [ "$mcp_config" = "none" ]; then
    warn "$(t warn_no_mcp_config) ${SELECTED_AGENT}"
    return
  fi

  # 各 Agent 配置格式不同，按 agent 分发
  case "$SELECTED_AGENT" in
    claude-code) register_claude_code_mcp ;;        # B1
    cline)       register_cline_mcp "$mcp_config" ;; # S1 双路径
    hermes)      register_hermes_yaml "$mcp_config" ;;
    openclaw)    register_openclaw_json "$mcp_config" ;;
    codex)       register_codex_toml "$mcp_config" ;;
    *)           register_mcp_json "$mcp_config" ;;  # cursor / windsurf 走标准
  esac
}

# B1: Claude Code 不能直写 ~/.claude.json (项目嵌套结构)
# 优先 shell-out 调 `claude mcp add` (有 claude CLI 时)
# 备选写 ~/.claude/settings.json 的 mcpServers 键（user-scope 推荐）
register_claude_code_mcp() {
  if command -v claude >/dev/null 2>&1; then
    info "$(t info_using_claude_cli)"
    # claude mcp add 接受 stdin pipe 或参数
    if claude mcp add --scope user pangolinfo \
        --command node \
        --args "${MCP_INSTALL_DIR}/server.mjs" \
        --env "PANGOLINFO_API_KEY=${API_KEY}" 2>/dev/null; then
      ok "$(t ok_mcp_registered) (via 'claude mcp add')"
      return
    fi
    warn "$(t warn_claude_cli_failed)"
  fi

  # 备选：写 ~/.claude/settings.json
  settings="$HOME/.claude/settings.json"
  mkdir -p "$(dirname "$settings")"
  register_mcp_json "$settings"
}

# S1: Cline MCP 路径分两种 - VS Code 扩展 vs 独立 CLI
register_cline_mcp() {
  primary="$1"
  # _cline_vscode_ext_dir 找不到时 return 1，会被 `set -e` 顶飞 — 用 || true 兜住
  vscode_path=$(_cline_vscode_ext_dir 2>/dev/null || true)

  wrote_any=0
  if [ -n "$vscode_path" ]; then
    vscode_mcp="$vscode_path/settings/cline_mcp_settings.json"
    info "$(t info_cline_vscode_detected) ${vscode_mcp}"
    register_mcp_json "$vscode_mcp"
    wrote_any=1
  fi
  # 同时也写独立 CLI 路径作为兜底（如果该目录已存在的话）
  if [ -d "$(dirname "$primary")" ]; then
    register_mcp_json "$primary"
    wrote_any=1
  fi
  # 两个都没写到 → 至少建独立 CLI 路径写一份，避免 silent skip
  if [ "$wrote_any" -eq 0 ]; then
    mkdir -p "$(dirname "$primary")"
    register_mcp_json "$primary"
  fi
}

# Codex TOML
register_codex_toml() {
  config="$1"
  mkdir -p "$(dirname "$config")"

  toml_block="
# === Pangolinfo MCP server (auto-added by installer) ===
[mcp_servers.pangolinfo]
command = \"node\"
args = [\"${MCP_INSTALL_DIR}/server.mjs\"]

[mcp_servers.pangolinfo.env]
PANGOLINFO_API_KEY = \"${API_KEY}\"
"

  if [ ! -f "$config" ]; then
    printf "%s" "$toml_block" > "$config"
    ok "$(t ok_mcp_created_config) ${config}"
    return
  fi

  # 已存在：检查是否已有 [mcp_servers.pangolinfo]
  if grep -q "^\[mcp_servers.pangolinfo\]" "$config" 2>/dev/null; then
    info "$(t info_mcp_already_registered) ${config}"
    info "$(t info_mcp_manual_overwrite)"
    return
  fi

  backup="${config}.bak.$(date +%s)"
  cp "$config" "$backup"
  printf "%s" "$toml_block" >> "$config"
  ok "$(t ok_mcp_registered) ${config}"
  info "$(t info_backed_up) ${backup}"
}

# JSON 合并工具：优先 jq，回退 Node.js（用户装了 MCP server 必有 node）
# 用法：json_merge_mcp_server <config_path> <server_path> <api_key>
# 在 .mcpServers.pangolinfo 处写入标准 server 节点
json_merge_mcp_server() {
  cfg="$1"; srv="$2"; key="$3"
  if command -v jq >/dev/null 2>&1; then
    tmp="${cfg}.tmp.$$"
    jq --arg path "$srv" --arg key "$key" '
      .mcpServers = (.mcpServers // {}) |
      .mcpServers.pangolinfo = { command: "node", args: [$path], env: { PANGOLINFO_API_KEY: $key } }
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs');
      const p=process.argv[1], srv=process.argv[2], key=process.argv[3];
      const j=JSON.parse(fs.readFileSync(p,'utf8'));
      j.mcpServers=j.mcpServers||{};
      j.mcpServers.pangolinfo={command:'node',args:[srv],env:{PANGOLINFO_API_KEY:key}};
      fs.writeFileSync(p,JSON.stringify(j,null,2));
    " "$cfg" "$srv" "$key"
    return 0
  fi
  return 1
}

# OpenClaw 专用：合并 mcpServers.pangolinfo + skills.entries[] 追加 "pangolinfo"
json_merge_openclaw() {
  cfg="$1"; srv="$2"; key="$3"
  if command -v jq >/dev/null 2>&1; then
    tmp="${cfg}.tmp.$$"
    jq --arg path "$srv" --arg key "$key" '
      .skills = (.skills // {}) |
      .skills.entries = (.skills.entries // []) |
      (if (.skills.entries | index("pangolinfo")) then . else .skills.entries += ["pangolinfo"] end) |
      .mcpServers = (.mcpServers // {}) |
      .mcpServers.pangolinfo = { command: "node", args: [$path], env: { PANGOLINFO_API_KEY: $key } }
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs');
      const p=process.argv[1], srv=process.argv[2], key=process.argv[3];
      const j=JSON.parse(fs.readFileSync(p,'utf8'));
      j.skills=j.skills||{};
      j.skills.entries=j.skills.entries||[];
      if(!j.skills.entries.includes('pangolinfo')) j.skills.entries.push('pangolinfo');
      j.mcpServers=j.mcpServers||{};
      j.mcpServers.pangolinfo={command:'node',args:[srv],env:{PANGOLINFO_API_KEY:key}};
      fs.writeFileSync(p,JSON.stringify(j,null,2));
    " "$cfg" "$srv" "$key"
    return 0
  fi
  return 1
}

register_mcp_json() {
  config="$1"
  mkdir -p "$(dirname "$config")"

  # 新建文件
  if [ ! -f "$config" ]; then
    cat > "$config" <<EOF
{
  "mcpServers": {
    "pangolinfo": {
      "command": "node",
      "args": ["${MCP_INSTALL_DIR}/server.mjs"],
      "env": {
        "PANGOLINFO_API_KEY": "${API_KEY}"
      }
    }
  }
}
EOF
    ok "$(t ok_mcp_created_config) ${config}"
    return
  fi

  # 已存在：优先 jq 合并，没 jq 则用 Node.js (用户装了 MCP 必有 node)
  if json_merge_mcp_server "$config" "${MCP_INSTALL_DIR}/server.mjs" "${API_KEY}"; then
    ok "$(t ok_mcp_registered) ${config}"
  else
    warn "$(t warn_no_jq) ${config}"
    warn "$(t warn_add_manually)"
    cat <<EOF
  "pangolinfo": {
    "command": "node",
    "args": ["${MCP_INSTALL_DIR}/server.mjs"],
    "env": { "PANGOLINFO_API_KEY": "***" }
  }
EOF
  fi
}

# ----- Hermes YAML 自动写入 -----
# Hermes config.yaml 顶层若已存在 mcp_servers 节点，追加 pangolinfo 子节点；
# 若不存在则追加整个 mcp_servers 节点。
# POSIX sh 内手写 YAML 拼接（避免 yq 依赖）。
register_hermes_yaml() {
  config="$1"
  mkdir -p "$(dirname "$config")"

  # 拼好要追加的片段
  yaml_block="
# === Pangolinfo MCP server (auto-added by installer) ===
mcp_servers:
  pangolinfo:
    command: node
    args:
      - \"${MCP_INSTALL_DIR}/server.mjs\"
    env:
      PANGOLINFO_API_KEY: \"${API_KEY}\"
"

  if [ ! -f "$config" ]; then
    printf "%s" "$yaml_block" > "$config"
    ok "$(t ok_mcp_created_config) ${config}"
    return
  fi

  # 已存在 config.yaml：先备份再追加
  if grep -q "^mcp_servers:" "$config" 2>/dev/null; then
    # 已有 mcp_servers 顶层节点——追加 pangolinfo 子节点（不替换）
    # 用 awk 在 mcp_servers: 节点末尾插入
    tmp="${config}.tmp.$$"
    awk -v block="  pangolinfo:
    command: node
    args:
      - \"${MCP_INSTALL_DIR}/server.mjs\"
    env:
      PANGOLINFO_API_KEY: \"${API_KEY}\"" '
      /^mcp_servers:/ { print; print block; in_block=1; next }
      in_block && /^[^[:space:]]/ { in_block=0 }
      { print }
    ' "$config" > "$tmp" && mv "$tmp" "$config"
    ok "$(t ok_mcp_registered) ${config}"
  else
    # 没 mcp_servers 节点——文件末尾追加整段
    backup="${config}.bak.$(date +%s)"
    cp "$config" "$backup"
    printf "%s" "$yaml_block" >> "$config"
    ok "$(t ok_mcp_registered) ${config}"
    info "$(t info_backed_up) ${backup}"
  fi
}

# ----- OpenClaw 嵌套 JSON 自动写入 -----
# openclaw.json 用 jq 在 skills.entries / mcp_servers 节点下加 pangolinfo
register_openclaw_json() {
  config="$1"
  mkdir -p "$(dirname "$config")"

  # 新文件直接写
  if [ ! -f "$config" ]; then
    cat > "$config" <<EOF
{
  "skills": {
    "entries": ["pangolinfo"]
  },
  "mcpServers": {
    "pangolinfo": {
      "command": "node",
      "args": ["${MCP_INSTALL_DIR}/server.mjs"],
      "env": {
        "PANGOLINFO_API_KEY": "${API_KEY}"
      }
    }
  }
}
EOF
    ok "$(t ok_mcp_created_config) ${config}"
    return
  fi

  # 优先 jq，回退 Node.js
  if json_merge_openclaw "$config" "${MCP_INSTALL_DIR}/server.mjs" "${API_KEY}"; then
    ok "$(t ok_mcp_registered) ${config}"
  else
    warn "$(t warn_no_jq) ${config}"
    warn "$(t warn_add_manually)"
  fi
}

# ---------------------------------------------------------------------------
# Step 7: Done
# ---------------------------------------------------------------------------
print_done() {
  agent_display=$(agent_paths "$SELECTED_AGENT" | head -n 1)
  echo
  printf "%b\n" "${C_GREEN}═══════════════════════════════════════════════════════${C_RESET}"
  printf "%b\n" "${C_GREEN}${C_BOLD}$(t done_success)${C_RESET}"
  printf "%b\n" "${C_GREEN}═══════════════════════════════════════════════════════${C_RESET}"
  echo
  printf "%b%s%b %s\n" "${C_BOLD}" "$(t done_agent_label)" "${C_RESET}" "${agent_display}"
  printf "%b%s%b %s\n" "${C_BOLD}" "$(t done_scope_label)" "${C_RESET}" "${SELECTED_SCOPE}"
  echo
  printf "%b%s%b\n" "${C_BOLD}" "$(t done_try_header)" "${C_RESET}"
  echo "  › $(t done_try_1)"
  echo "  › $(t done_try_2)"
  echo
  printf "%b\n" "${C_DIM}─────────────────────────────────────────────────────${C_RESET}"
  echo
  printf "  ⭐  %b%s%b\n" "$C_BOLD" "$(t done_star_prompt)" "$C_RESET"
  echo "      ${C_BLUE}${GITHUB_URL}${C_RESET}"
  echo
  printf "  %b%s%b\n" "${C_DIM}" "$(t done_small_team)" "${C_RESET}"
  echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  print_banner

  # 非交互模式不弹"continue?"
  if [ "$ARG_NON_INTERACTIVE" != 1 ] && [ "$ARG_DRY_RUN" != 1 ]; then
    reply=$(prompt "$(t prompt_continue)")
    case "$reply" in [Nn]|[Nn][Oo]) info "$(t info_cancelled)"; exit 1 ;; esac
    echo
  fi

  choose_agent
  choose_scope
  setup_api_key
  save_config
  install_skills
  install_mcp
  print_done
}

main "$@"
