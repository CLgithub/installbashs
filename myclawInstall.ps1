# MyClaw 一键安装脚本 (Windows PowerShell)
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
$INSTALL_DIR = "$HOME\myclaw"
$ZIP_URL     = "https://myclawpackage.cldev.top/myclaw-latest.zip"

Write-Host ""
Write-Host "  MyClaw 安装程序" -ForegroundColor White -BackgroundColor DarkGray
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

    # 多源下载：Corretto → Adoptium → 自有服务器兜底（仅 x64 有包，Windows ARM 无自有包）
    $jreDownloadUrls = @(
        "https://corretto.aws/downloads/latest/amazon-corretto-17-$arch-windows-jdk.zip",
        "https://api.adoptium.net/v3/binary/latest/17/ga/windows/$arch/jre/hotspot/normal/eclipse"
    )
    if ($arch -eq "x64") {
        $jreDownloadUrls += "https://myclawpackage.cldev.top/jdk-17.0.18_windows-x64_bin.zip"
    }
    $downloadOk = $false
    foreach ($jreUrl in $jreDownloadUrls) {
        $sourceName = $jreUrl.Split('/')[2]
        Info "正在下载 JDK 17（windows/$arch，来源：$sourceName）..."
        try {
            Invoke-WebRequest -Uri $jreUrl -OutFile "$env:TEMP\myclaw_jre.zip" -UseBasicParsing -TimeoutSec 120
            $downloadOk = $true
            break
        } catch {
            Warn "从 $sourceName 下载失败，尝试备用源..."
        }
    }
    if (-not $downloadOk) {
        Err "JRE 17 下载失败。请手动安装 Java 17（https://adoptium.net），安装后重新运行本脚本。"
    }

    Info "正在解压 JRE..."
    $jreTmp = "$env:TEMP\myclaw_jre_tmp"
    try {
        Expand-Archive -Path "$env:TEMP\myclaw_jre.zip" -DestinationPath $jreTmp -Force
    } catch {
        Err "JRE 解压失败（文件可能已损坏，请重试）: $_"
    }
    $jreExtracted = Get-ChildItem $jreTmp | Select-Object -First 1
    if (-not $jreExtracted) { Err "JRE 解压目录为空，请重试" }
    Copy-Item -Path "$($jreExtracted.FullName)\*" -Destination $jreDir -Recurse -Force
    Remove-Item "$env:TEMP\myclaw_jre.zip" -Force -ErrorAction SilentlyContinue
    Remove-Item $jreTmp -Recurse -Force -ErrorAction SilentlyContinue

    $javaHomeCustom = $jreDir
    Success "JDK 17 已安装到 $jreDir"
}

# ── 3. 下载 & 解压 MyClaw ────────────────────────────────────────────────
Info "正在下载 MyClaw..."
try {
    Invoke-WebRequest -Uri $ZIP_URL -OutFile "$env:TEMP\myclaw_install.zip" -UseBasicParsing
} catch {
    Err "下载失败，请检查网络连接: $_"
}

Info "正在解压到 $INSTALL_DIR ..."
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
try {
    Expand-Archive -Path "$env:TEMP\myclaw_install.zip" -DestinationPath $INSTALL_DIR -Force
} catch {
    Err "MyClaw 解压失败（文件可能已损坏，请重试）: $_"
}
Remove-Item "$env:TEMP\myclaw_install.zip" -Force -ErrorAction SilentlyContinue
Success "程序已安装到 $INSTALL_DIR"

# ── 4. 创建 myclaw.bat ───────────────────────────────────────────────────
Info "创建 myclaw.bat 启动脚本..."

$batContent = @'
@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: 查找 JAR 文件（与脚本同目录）
set "JAR="
for %%f in ("%SCRIPT_DIR%\myclaw-*-jar-with-dependencies.jar") do set "JAR=%%f"

if not defined JAR (
    echo 错误: 找不到 JAR 文件，请确认 JAR 与 myclaw.bat 在同一目录
    pause
    exit /b 1
)

:: 优先使用自带 JRE
set "JAVA_CMD=java"
if exist "%SCRIPT_DIR%\jre\bin\java.exe" set "JAVA_CMD=%SCRIPT_DIR%\jre\bin\java.exe"

:: 自动加载同目录下的配置文件
set "CONFIG_ARG="
if exist "%SCRIPT_DIR%\application.properties" set "CONFIG_ARG=--config=%SCRIPT_DIR%\application.properties"

:: 解析 --config= --port= 参数
set "PORT_ARG="
for %%a in (%*) do (
    echo %%a | findstr /b /c:"--config=" >nul && set "CONFIG_ARG=%%a"
    echo %%a | findstr /b /c:"--port="   >nul && set "PORT_ARG=%%a"
)

set "DAEMON_DIR=%USERPROFILE%\.myclaw"

if "%1"=="daemon"        goto :daemon
if "%1"=="-i"            goto :interactive
if "%1"=="--interactive" goto :interactive
goto :interactive

:daemon
if "%2"=="start"   goto :daemon_start
if "%2"=="stop"    goto :daemon_stop
if "%2"=="status"  goto :daemon_status
if "%2"=="restart" goto :daemon_restart
echo 用法: myclaw.bat daemon {start^|stop^|status^|restart}
exit /b 1

:daemon_start
if not exist "%DAEMON_DIR%" mkdir "%DAEMON_DIR%"
if exist "%DAEMON_DIR%\daemon.pid" (
    set /p _PID=<"%DAEMON_DIR%\daemon.pid"
    tasklist /fi "pid eq !_PID!" 2>nul | findstr /i java >nul
    if not errorlevel 1 (
        echo [daemon] 已在运行中，PID=!_PID!
        exit /b 0
    )
)
start /b "" "%JAVA_CMD%" -jar "%JAR%" --mode=daemon %CONFIG_ARG% %PORT_ARG% >> "%DAEMON_DIR%\daemon.log" 2>&1
echo [daemon] 正在启动...
timeout /t 2 /nobreak >nul
"%JAVA_CMD%" -jar "%JAR%" --mode=daemon-status %CONFIG_ARG%
goto :end

:daemon_stop
"%JAVA_CMD%" -jar "%JAR%" --mode=daemon-stop %CONFIG_ARG%
goto :end

:daemon_status
"%JAVA_CMD%" -jar "%JAR%" --mode=daemon-status %CONFIG_ARG%
goto :end

:daemon_restart
"%JAVA_CMD%" -jar "%JAR%" --mode=daemon-stop %CONFIG_ARG%
timeout /t 1 /nobreak >nul
if not exist "%DAEMON_DIR%" mkdir "%DAEMON_DIR%"
start /b "" "%JAVA_CMD%" -jar "%JAR%" --mode=daemon %CONFIG_ARG% %PORT_ARG% >> "%DAEMON_DIR%\daemon.log" 2>&1
echo [daemon] 正在启动...
timeout /t 2 /nobreak >nul
"%JAVA_CMD%" -jar "%JAR%" --mode=daemon-status %CONFIG_ARG%
goto :end

:interactive
"%JAVA_CMD%" -jar "%JAR%" -i %CONFIG_ARG%

:end
endlocal
'@

$batContent | Set-Content "$INSTALL_DIR\myclaw.bat" -Encoding ASCII
Success "已创建 $INSTALL_DIR\myclaw.bat"

# ── 5. 创建桌面快捷方式 ──────────────────────────────────────────────────
Info "创建桌面快捷方式..."
$desktopPath = [System.Environment]::GetFolderPath("Desktop")
$shortcutPath = "$desktopPath\MyClaw.lnk"
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = "cmd.exe"
$shortcut.Arguments        = "/k `"$INSTALL_DIR\myclaw.bat`" -i"
$shortcut.WorkingDirectory = $INSTALL_DIR
$shortcut.Description      = "MyClaw AI 助手"
$shortcut.Save()
Success "已创建桌面快捷方式 MyClaw.lnk"

# ── 6. 配置环境变量 ──────────────────────────────────────────────────────
Info "配置环境变量..."

# 配置 JAVA_HOME（仅在自装 JRE 时）
if ($javaHomeCustom) {
    $existingJavaHome = [System.Environment]::GetEnvironmentVariable("MYCLAW_JAVA_HOME", "User")
    if (-not $existingJavaHome) {
        [System.Environment]::SetEnvironmentVariable("MYCLAW_JAVA_HOME", $javaHomeCustom, "User")
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

# 将 MyClaw 目录加入 PATH（使 myclaw.bat 可直接调用）
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$INSTALL_DIR*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$INSTALL_DIR;$userPath", "User")
    $env:PATH = "$INSTALL_DIR;$env:PATH"
    Success "已将 $INSTALL_DIR 添加到 PATH"
} else {
    Warn "PATH 已包含 MyClaw 目录，跳过"
}

# ── 5. 配置授权码 ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  第 1 步：配置授权码" -ForegroundColor White
Write-Host "  ────────────────────────────────────"
Write-Host "  授权码用于激活 MyClaw 完整功能。"
Write-Host ""
Write-Host "  获取方式："
Write-Host "  1. 访问 https://myclaw.cldev.top/"
Write-Host "  2. 注册/登录 → 进入「控制台」→ 复制授权码"
Write-Host "  （新用户注册即可获得免费授权码）"
Write-Host ""

$LICENSE_KEY = ""
do {
    $LICENSE_KEY = Read-Host "  请输入授权码"
    if ([string]::IsNullOrWhiteSpace($LICENSE_KEY)) { Warn "授权码不能为空，请重新输入" }
} while ([string]::IsNullOrWhiteSpace($LICENSE_KEY))

# ── 6. 配置 API Key ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  第 2 步：配置 API Key" -ForegroundColor White
Write-Host "  ────────────────────────────────────"
Write-Host "  MyClaw 通过大模型来完成任务，需要一个兼容 OpenAI 协议的 API Key。"
Write-Host ""
Write-Host "  免费获取方式（二选一）："
Write-Host ""
Write-Host "  · 阿里云百炼（推荐，有免费额度，国内速度快）"
Write-Host "    1. 访问 https://bailian.aliyun.com/"
Write-Host "    2. 注册/登录 → 右上角「API-KEY 管理」→ 创建 API Key"
Write-Host "    3. 复制以 sk- 开头的密钥"
Write-Host ""
Write-Host "  · OpenAI"
Write-Host "    1. 访问 https://platform.openai.com/api-keys"
Write-Host "    2. 点击「Create new secret key」→ 复制密钥"
Write-Host ""

$API_KEY = ""
do {
    $API_KEY = Read-Host "  请输入 API Key"
    if ([string]::IsNullOrWhiteSpace($API_KEY)) { Warn "API Key 不能为空，请重新输入" }
} while ([string]::IsNullOrWhiteSpace($API_KEY))

# ── 7. 写入配置文件 ──────────────────────────────────────────────────────
$CONFIG_FILE = "$INSTALL_DIR\application.properties"

function UpdateOrAppend {
    param([string]$key, [string]$value, [string]$file)
    $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
    if ($content -match "(?m)^${key}=") {
        $content = $content -replace "(?m)^${key}=.*", "${key}=${value}"
        $content | Set-Content $file -NoNewline
    } else {
        "`n${key}=${value}" | Add-Content $file
    }
}

if (Test-Path $CONFIG_FILE) {
    UpdateOrAppend "llm.apiKey"  $API_KEY     $CONFIG_FILE
    UpdateOrAppend "license.key" $LICENSE_KEY $CONFIG_FILE
} else {
    Warn "未找到 $CONFIG_FILE，将创建新配置文件"
    @"
llm.provider=openai
llm.baseUrl=https://dashscope.aliyuncs.com/compatible-mode/v1
llm.apiKey=$API_KEY
llm.model=qwen-plus

license.key=$LICENSE_KEY
"@ | Set-Content $CONFIG_FILE
}

Success "配置已写入 $CONFIG_FILE"

# ── 8. 完成 ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [v] MyClaw 安装完成！" -ForegroundColor Green
Write-Host "  ────────────────────────────────────"
Write-Host "  · 桌面双击 " -NoNewline
Write-Host "MyClaw" -ForegroundColor White -NoNewline
Write-Host " 图标即可启动"
Write-Host "  · 或重新打开 PowerShell 后输入: " -NoNewline
Write-Host "myclaw" -ForegroundColor White
Write-Host ""
