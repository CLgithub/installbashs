# ClClaw 一键安装脚本 (Windows PowerShell)
# https://github.com/CLgithub/installbashs
#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # 禁用进度条，避免干扰输出且可加速大文件下载

# ── 辅助函数 ────────────────────────────────────────────────────────────
function Info    { param($msg) Write-Host "  [>] $msg" -ForegroundColor Cyan }
function Success { param($msg) Write-Host "  [v] $msg" -ForegroundColor Green }
function Warn    { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Err     { param($msg) Write-Host "  [x] $msg" -ForegroundColor Red; Write-Host ""; Write-Host "  按任意键退出..." -ForegroundColor Gray; try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}; exit 1 }

# ── 配置 ────────────────────────────────────────────────────────────────
$INSTALL_DIR = "$HOME\clclaw"
$JAR_URL     = "https://clclawpackage.cldev.top/clclaw-latest.jar"

Write-Host ""
Write-Host "  ClClaw 安装程序" -ForegroundColor White -BackgroundColor DarkGray
Write-Host "  ────────────────────────────────────"
Write-Host ""

# ── 1. 检查执行策略 ──────────────────────────────────────────────────────
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq "Restricted") {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Success "已设置 PowerShell 执行策略为 RemoteSigned"
}

# ── 2. Java 17 检查 & 安装 ───────────────────────────────────────────────
Info "检查 Java 环境..."

$javaHomeCustom = ""
$javaOk = $false

try {
    $javaVerOutput = & java -version 2>&1
    $javaVerStr = ($javaVerOutput | Select-String '"(\d+)').Matches[0].Groups[1].Value
    if ([int]$javaVerStr -ge 17) {
        Success "已检测到 Java $javaVerStr，无需另行安装"
        $javaOk = $true
    }
} catch {}

if (-not $javaOk) {
    Warn "未找到 Java 17+，将自动安装 JDK 17..."

    $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "aarch64" } else { "x64" }
    $jreDir = "$INSTALL_DIR\jre"
    New-Item -ItemType Directory -Force -Path $jreDir | Out-Null

    # 多源下载：自有服务器优先（仅 x64）→ Corretto → Adoptium 兜底
    $jreDownloadUrls = @()
    if ($arch -eq "x64") {
        $jreDownloadUrls += "https://clclawpackage.cldev.top/jdk-17.0.18_windows-x64_bin.zip"
    }
    $jreDownloadUrls += "https://corretto.aws/downloads/latest/amazon-corretto-17-$arch-windows-jdk.zip"
    $jreDownloadUrls += "https://api.adoptium.net/v3/binary/latest/17/ga/windows/$arch/jre/hotspot/normal/eclipse"

    $downloadOk = $false
    foreach ($jreUrl in $jreDownloadUrls) {
        $sourceName = $jreUrl.Split('/')[2]
        Info "正在下载 JDK 17（windows/$arch，来源：$sourceName）..."
        try {
            Invoke-WebRequest -Uri $jreUrl -OutFile "$env:TEMP\clclaw_jre.zip" -UseBasicParsing -TimeoutSec 120
            $downloadOk = $true
            break
        } catch {
            Warn "从 $sourceName 下载失败，尝试备用源..."
        }
    }
    if (-not $downloadOk) {
        Err "JDK 17 下载失败。请手动安装 Java 17（https://adoptium.net），安装后重新运行本脚本。"
    }

    Info "正在解压 JDK..."
    $jreTmp = "$env:TEMP\clclaw_jre_tmp"
    try {
        Expand-Archive -Path "$env:TEMP\clclaw_jre.zip" -DestinationPath $jreTmp -Force
    } catch {
        Err "JDK 解压失败（文件可能已损坏，请重试）: $_"
    }
    $jreExtracted = Get-ChildItem $jreTmp | Select-Object -First 1
    if (-not $jreExtracted) { Err "JDK 解压目录为空，请重试" }
    Copy-Item -Path "$($jreExtracted.FullName)\*" -Destination $jreDir -Recurse -Force
    Remove-Item "$env:TEMP\clclaw_jre.zip" -Force -ErrorAction SilentlyContinue
    Remove-Item $jreTmp -Recurse -Force -ErrorAction SilentlyContinue

    $javaHomeCustom = $jreDir
    Success "JDK 17 已安装到 $jreDir"
}

# ── 3. 下载 ClClaw ───────────────────────────────────────────────────────
Info "正在下载 ClClaw..."
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
try {
    Invoke-WebRequest -Uri $JAR_URL -OutFile "$INSTALL_DIR\clclaw-latest.jar" -UseBasicParsing
} catch {
    Err "下载失败，请检查网络连接: $_"
}
Success "程序已安装到 $INSTALL_DIR"

# ── 4. 创建 clclaw.bat ───────────────────────────────────────────────────
Info "创建 clclaw.bat 启动脚本..."

$batContent = @'
@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 查找 JAR 文件（与脚本同目录）
set "JAR="
for %%f in ("%SCRIPT_DIR%\clclaw-*.jar") do set "JAR=%%f"

if not defined JAR (
    echo 错误: 找不到 JAR 文件，请确认 JAR 与 clclaw.bat 在同一目录
    pause
    exit /b 1
)

:: 优先使用自带 JRE
set "JAVA_CMD=java"
if exist "%SCRIPT_DIR%\jre\bin\java.exe" set "JAVA_CMD=%SCRIPT_DIR%\jre\bin\java.exe"

"%JAVA_CMD%" -jar "%JAR%" %*
'@

$batContent | Set-Content "$INSTALL_DIR\clclaw.bat" -Encoding ASCII
Success "已创建 $INSTALL_DIR\clclaw.bat"

# ── 5. 创建桌面快捷方式 ──────────────────────────────────────────────────
Info "创建桌面快捷方式..."
$desktopPath = [System.Environment]::GetFolderPath("Desktop")
@"
[InternetShortcut]
URL=http://127.0.0.1:18788
"@ | Set-Content "$desktopPath\ClClaw.url" -Encoding ASCII
Success "已创建桌面快捷方式 ClClaw.url"

# ── 6. 配置环境变量 ──────────────────────────────────────────────────────
Info "配置环境变量..."

if ($javaHomeCustom) {
    $existingJavaHome = [System.Environment]::GetEnvironmentVariable("CLCLAW_JAVA_HOME", "User")
    if (-not $existingJavaHome) {
        [System.Environment]::SetEnvironmentVariable("CLCLAW_JAVA_HOME", $javaHomeCustom, "User")
        $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath -notlike "*$javaHomeCustom\bin*") {
            [System.Environment]::SetEnvironmentVariable("PATH", "$javaHomeCustom\bin;$userPath", "User")
        }
        $env:PATH = "$javaHomeCustom\bin;$env:PATH"
        Success "已配置 JAVA_HOME → $javaHomeCustom"
    } else {
        Warn "JAVA_HOME 已存在，跳过"
    }
}

$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$INSTALL_DIR;$userPath", "User")
    $env:PATH = "$INSTALL_DIR;$env:PATH"
    Success "已将 $INSTALL_DIR 添加到 PATH"
} else {
    Warn "PATH 已包含 ClClaw 目录，跳过"
}

# ── 7. 配置授权码 ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  配置授权码" -ForegroundColor White
Write-Host "  ────────────────────────────────────"
Write-Host "  授权码用于激活 ClClaw，首次登录官网自动生成。"
Write-Host ""
Write-Host "  获取方式："
Write-Host "  1. 访问 https://clclaw.ai/"
Write-Host "  2. 注册/登录 → 进入「控制台」→ 复制授权码"
Write-Host ""

$LICENSE_KEY = ""
do {
    $LICENSE_KEY = Read-Host "  请输入授权码"
    if ([string]::IsNullOrWhiteSpace($LICENSE_KEY)) { Warn "授权码不能为空，请重新输入" }
} while ([string]::IsNullOrWhiteSpace($LICENSE_KEY))

# ── 8. 写入配置文件 ──────────────────────────────────────────────────────
$CONFIG_FILE = "$INSTALL_DIR\application.properties"

if (Test-Path $CONFIG_FILE) {
    $content = Get-Content $CONFIG_FILE -Raw -ErrorAction SilentlyContinue
    if ($content -match "(?m)^license\.key=") {
        $content = $content -replace "(?m)^license\.key=.*", "license.key=$LICENSE_KEY"
        $content | Set-Content $CONFIG_FILE -NoNewline
    } else {
        "`nlicense.key=$LICENSE_KEY" | Add-Content $CONFIG_FILE
    }
} else {
    "license.key=$LICENSE_KEY" | Set-Content $CONFIG_FILE
}

Success "配置已写入 $CONFIG_FILE"

# ── 9. 完成 ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [v] ClClaw 安装完成！" -ForegroundColor Green
Write-Host "  ────────────────────────────────────"
Write-Host "  · 先运行: " -NoNewline
Write-Host "clclaw --daemon-start" -ForegroundColor White
Write-Host "  · 再双击桌面 " -NoNewline
Write-Host "ClClaw" -ForegroundColor White -NoNewline
Write-Host " 图标打开 Web 客户端"
Write-Host "  · 或重新打开终端后输入: " -NoNewline
Write-Host "clclaw --daemon-start" -ForegroundColor White
Write-Host ""
