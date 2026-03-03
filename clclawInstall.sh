#!/usr/bin/env bash
# ClClaw 一键安装脚本
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
INSTALL_DIR="$PWD"
JAR_URL="https://clclawpackage.cldev.top/clclaw-latest.jar"

echo ""
printf "${BOLD}  ClClaw 安装程序${NC}\n"
echo "  ────────────────────────────────────"
printf "  安装目录: %s\n" "$INSTALL_DIR"
echo ""

# ── 1. 依赖检查 ──────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || err "缺少依赖: curl，请先安装后重试"

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
  warn "未找到 Java 17+，将自动安装 JDK 17..."

  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Darwin) ADOPT_OS="mac";   SELF_OS="macos" ;;
    Linux)  ADOPT_OS="linux"; SELF_OS="linux"  ;;
    *) err "不支持的操作系统: $OS" ;;
  esac
  case "$ARCH" in
    x86_64)        ADOPT_ARCH="x64"     ;;
    aarch64|arm64) ADOPT_ARCH="aarch64" ;;
    *) err "不支持的 CPU 架构: $ARCH" ;;
  esac

  JRE_DIR="$INSTALL_DIR/jre"
  mkdir -p "$JRE_DIR"

  # 多源下载：自有服务器优先 → Adoptium → Corretto 兜底
  JRE_URLS=(
    "https://clclawpackage.cldev.top/jdk-17.0.18_${SELF_OS}-${ADOPT_ARCH}_bin.tar.gz"
    "https://api.adoptium.net/v3/binary/latest/17/ga/${ADOPT_OS}/${ADOPT_ARCH}/jre/hotspot/normal/eclipse"
    "https://corretto.aws/downloads/latest/amazon-corretto-17-${ADOPT_ARCH}-${SELF_OS}-jdk.tar.gz"
  )

  JRE_DOWNLOADED=false
  for JRE_URL in "${JRE_URLS[@]}"; do
    SOURCE=$(printf '%s' "$JRE_URL" | cut -d/ -f3)
    info "正在下载 JDK 17（${ADOPT_OS}/${ADOPT_ARCH}，来源：${SOURCE}）..."
    if curl -fsSL -L --connect-timeout 30 --max-time 300 "$JRE_URL" -o /tmp/clclaw_jre.tar.gz; then
      JRE_DOWNLOADED=true
      break
    else
      warn "从 ${SOURCE} 下载失败，尝试备用源..."
    fi
  done
  $JRE_DOWNLOADED || err "JDK 17 下载失败，请手动安装 Java 17 后重试"

  info "正在解压 JDK..."
  tar -xzf /tmp/clclaw_jre.tar.gz -C "$JRE_DIR" --strip-components=1
  rm -f /tmp/clclaw_jre.tar.gz

  # Oracle/Corretto 的 macOS JDK 解压后为 Contents/Home/ 结构，Adoptium 是扁平的
  if [[ -x "$JRE_DIR/bin/java" ]]; then
    JAVA_HOME_CUSTOM="$JRE_DIR"
  elif [[ -x "$JRE_DIR/Contents/Home/bin/java" ]]; then
    JAVA_HOME_CUSTOM="$JRE_DIR/Contents/Home"
  else
    err "JDK 解压后未找到 java 可执行文件，请手动安装 Java 17 后重试"
  fi
  success "JDK 17 已安装到 $JAVA_HOME_CUSTOM"
fi

# ── 3. 下载 ClClaw ───────────────────────────────────────────────────────
info "正在下载 ClClaw..."
curl -fsSL "$JAR_URL" -o "$INSTALL_DIR/clclaw-latest.jar" || err "下载失败，请检查网络连接"
success "程序已安装到 $INSTALL_DIR"

# ── 4. 创建 clclaw 启动脚本 ──────────────────────────────────────────────
info "创建启动脚本..."
WRAPPER="$INSTALL_DIR/clclaw"
cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
JAR=$(ls "$DIR"/clclaw-*.jar 2>/dev/null | tail -1)
[[ -z "$JAR" ]] && { echo "错误: 找不到 JAR 文件" >&2; exit 1; }
JAVA_CMD=java
[[ -x "$DIR/jre/bin/java" ]] && JAVA_CMD="$DIR/jre/bin/java"
[[ -x "$DIR/jre/Contents/Home/bin/java" ]] && JAVA_CMD="$DIR/jre/Contents/Home/bin/java"
exec "$JAVA_CMD" -jar "$JAR" "$@"
WRAPPER_EOF
chmod +x "$WRAPPER"
success "已创建 $WRAPPER"

# ── 5. 配置授权码 ────────────────────────────────────────────────────────
echo ""
printf "${BOLD}  配置授权码${NC}\n"
echo "  ────────────────────────────────────"

if [[ -n "${LICENSE_KEY:-}" ]]; then
  success "已从安装命令获取授权码"
else
  echo "  授权码用于激活 ClClaw，首次登录官网自动生成。"
  echo ""
  echo "  获取方式："
  echo "  1. 访问 https://clclaw.ai/"
  echo "  2. 注册/登录 → 进入「控制台」→ 复制安装命令"
  echo ""
  while [[ -z "${LICENSE_KEY:-}" ]]; do
    read_tty "  请输入授权码: " LICENSE_KEY
    [[ -z "$LICENSE_KEY" ]] && warn "授权码不能为空，请重新输入"
  done
fi

# ── 6. 写入配置文件 ──────────────────────────────────────────────────────
CONFIG_FILE="$INSTALL_DIR/application.properties"

if [[ -f "$CONFIG_FILE" ]]; then
  if grep -q "^license.key=" "$CONFIG_FILE"; then
    LICENSE_KEY="$LICENSE_KEY" awk \
      '/^license\.key=/{print "license.key=" ENVIRON["LICENSE_KEY"]; next} {print}' \
      "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    printf 'license.key=%s\n' "$LICENSE_KEY" >> "$CONFIG_FILE"
  fi
else
  printf 'license.key=%s\n' "$LICENSE_KEY" > "$CONFIG_FILE"
fi

success "配置已写入 $CONFIG_FILE"

# ── 7. 完成 & 询问是否立即启动 ──────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}  ✓ ClClaw 安装完成！${NC}\n"
echo "  ────────────────────────────────────"
printf "  运行命令: ${BOLD}./clclaw start${NC}\n"
echo ""

RUN_NOW=""
read_tty "  立即启动 ClClaw？[Y/n] " RUN_NOW
if [[ -z "$RUN_NOW" || "$RUN_NOW" =~ ^[Yy] ]]; then
  echo ""
  "$INSTALL_DIR/clclaw" start
fi
echo ""
