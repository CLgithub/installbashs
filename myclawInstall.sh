#!/usr/bin/env bash
# MyClaw 一键安装脚本
# https://github.com/CLgithub/installbashs

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'

info()    { printf "${GREEN}▶${NC}  %s\n" "$*"; }
success() { printf "${GREEN}✓${NC}  %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${NC}  %s\n" "$*"; }
err()     { printf "${RED}✗${NC}  %s\n" "$*" >&2; exit 1; }

# curl | bash 时 stdin 被管道占用，read 必须从终端读取
read_tty() {
  local prompt="$1" varname="$2"
  printf "%s" "$prompt" > /dev/tty
  read -r "$varname" < /dev/tty
}

# ── 配置 ────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/myclaw"
ZIP_URL="https://myclawpack.cldev.top/myclaw-latest.zip"

echo ""
printf "${BOLD}  MyClaw 安装程序${NC}\n"
echo "  ────────────────────────────────────"
echo ""

# ── 1. 依赖检查 ──────────────────────────────────────────────────────────
for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || err "缺少依赖: $cmd，请先安装后重试"
done

# ── 2. Java 17 检查 & 安装 ───────────────────────────────────────────────
JAVA_HOME_CUSTOM=""

check_java_version() {
  local java_bin="$1"
  local ver
  ver=$("$java_bin" -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
  [[ "$ver" -ge 17 ]] 2>/dev/null && return 0 || return 1
}

info "检查 Java 环境..."

if command -v java >/dev/null 2>&1 && check_java_version "java"; then
  success "已检测到 Java $(java -version 2>&1 | head -1 | sed -E 's/.*version "(.*)".*/\1/')，无需另行安装"
else
  warn "未找到 Java 17+，将自动安装 JRE 17..."

  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Darwin) ADOPT_OS="mac"   ;;
    Linux)  ADOPT_OS="linux" ;;
    *) err "不支持的操作系统: $OS" ;;
  esac
  case "$ARCH" in
    x86_64)        ADOPT_ARCH="x64"     ;;
    aarch64|arm64) ADOPT_ARCH="aarch64" ;;
    *) err "不支持的 CPU 架构: $ARCH" ;;
  esac

  JRE_DIR="$INSTALL_DIR/jre"
  mkdir -p "$JRE_DIR"

  JRE_URL="https://api.adoptium.net/v3/binary/latest/17/ga/${ADOPT_OS}/${ADOPT_ARCH}/jre/hotspot/normal/eclipse"
  info "正在下载 JRE 17（${ADOPT_OS}/${ADOPT_ARCH}）..."
  curl -fsSL -L "$JRE_URL" -o /tmp/myclaw_jre.tar.gz || err "JRE 17 下载失败，请检查网络连接"

  info "正在解压 JRE..."
  tar -xzf /tmp/myclaw_jre.tar.gz -C "$JRE_DIR" --strip-components=1
  rm -f /tmp/myclaw_jre.tar.gz

  JAVA_HOME_CUSTOM="$JRE_DIR"
  success "JRE 17 已安装到 $JRE_DIR"
fi

# ── 3. 下载 & 解压 MyClaw ────────────────────────────────────────────────
info "正在下载 MyClaw..."
curl -fsSL "$ZIP_URL" -o /tmp/myclaw_install.zip || err "下载失败，请检查网络连接"

info "正在解压到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
unzip -q -o /tmp/myclaw_install.zip -d "$INSTALL_DIR"
rm -f /tmp/myclaw_install.zip
chmod +x "$INSTALL_DIR/myclaw.sh"
success "程序已安装到 $INSTALL_DIR"

# ── 4. 配置 Shell 环境（PATH & 快捷命令）───────────────────────────────
info "配置 Shell 环境..."

if [[ "${SHELL:-}" == */zsh ]] || [[ -n "${ZSH_VERSION:-}" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ "$(uname)" == "Darwin" ]]; then
  SHELL_RC="$HOME/.zprofile"
else
  SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$JAVA_HOME_CUSTOM" ]]; then
  if grep -qF "MYCLAW_JAVA_HOME" "$SHELL_RC" 2>/dev/null; then
    warn "JAVA_HOME 配置已存在，跳过"
  else
    printf '\n# MyClaw JRE\nexport MYCLAW_JAVA_HOME="%s"\nexport PATH="$MYCLAW_JAVA_HOME/bin:$PATH"\n' \
      "$JAVA_HOME_CUSTOM" >> "$SHELL_RC"
    success "已写入 JAVA_HOME 到 $SHELL_RC"
  fi
  export PATH="$JAVA_HOME_CUSTOM/bin:$PATH"
fi

ALIAS_LINE="alias myclaw='sh $INSTALL_DIR/myclaw.sh'"
if grep -qF "alias myclaw=" "$SHELL_RC" 2>/dev/null; then
  warn "快捷命令 myclaw 已存在，跳过"
else
  printf '\n# MyClaw\n%s\n' "$ALIAS_LINE" >> "$SHELL_RC"
  success "已写入 myclaw 命令到 $SHELL_RC"
fi

# ── 5. 配置 API Key ──────────────────────────────────────────────────────
echo ""
printf "${BOLD}  第 1 步：配置 API Key${NC}\n"
echo "  ────────────────────────────────────"
echo "  MyClaw 通过大模型来完成任务，需要一个兼容 OpenAI 协议的 API Key。"
echo ""
echo "  免费获取方式（二选一）："
echo ""
echo "  · 阿里云百炼（推荐，有免费额度，国内速度快）"
echo "    1. 访问 https://bailian.aliyun.com/"
echo "    2. 注册/登录 → 右上角「API-KEY 管理」→ 创建 API Key"
echo "    3. 复制以 sk- 开头的密钥"
echo ""
echo "  · OpenAI"
echo "    1. 访问 https://platform.openai.com/api-keys"
echo "    2. 点击「Create new secret key」→ 复制密钥"
echo ""

API_KEY=""
while [[ -z "$API_KEY" ]]; do
  read_tty "  请输入 API Key: " API_KEY
  [[ -z "$API_KEY" ]] && warn "API Key 不能为空，请重新输入"
done

# ── 6. 配置授权码 ────────────────────────────────────────────────────────
echo ""
printf "${BOLD}  第 2 步：配置授权码${NC}\n"
echo "  ────────────────────────────────────"
echo "  授权码用于激活 MyClaw 完整功能。"
echo ""
echo "  获取方式："
echo "  1. 访问 https://myclaw.chenlei.app/"
echo "  2. 注册/登录 → 进入「控制台」→ 复制授权码"
echo "  （新用户注册即可获得免费授权码）"
echo ""

LICENSE_KEY=""
while [[ -z "$LICENSE_KEY" ]]; do
  read_tty "  请输入授权码: " LICENSE_KEY
  [[ -z "$LICENSE_KEY" ]] && warn "授权码不能为空，请重新输入"
done

# ── 7. 写入配置文件 ──────────────────────────────────────────────────────
CONFIG_FILE="$INSTALL_DIR/application.properties"

update_or_append() {
  local key="$1" value="$2" file="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    fi
  else
    echo "${key}=${value}" >> "$file"
  fi
}

if [[ -f "$CONFIG_FILE" ]]; then
  update_or_append "llm.apiKey"  "$API_KEY"     "$CONFIG_FILE"
  update_or_append "license.key" "$LICENSE_KEY" "$CONFIG_FILE"
else
  warn "未找到 $CONFIG_FILE，将创建新配置文件"
  cat > "$CONFIG_FILE" <<CONF
llm.provider=openai
llm.baseUrl=https://dashscope.aliyuncs.com/compatible-mode/v1
llm.apiKey=${API_KEY}
llm.model=qwen-plus

license.key=${LICENSE_KEY}
CONF
fi

success "配置已写入 $CONFIG_FILE"

# ── 8. source Shell 配置 ─────────────────────────────────────────────────
# shellcheck disable=SC1090
source "$SHELL_RC" 2>/dev/null && success "已加载 $SHELL_RC" || warn "source 失败，请手动执行: source $SHELL_RC"

# ── 完成 ─────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}  ✓ MyClaw 安装完成！${NC}\n"
echo "  ────────────────────────────────────"
printf "  当前终端运行: ${BOLD}myclaw${NC}\n"
printf "  或直接运行:   ${BOLD}sh $INSTALL_DIR/myclaw.sh${NC}\n"
echo ""
