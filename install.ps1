# ==========================================================================
#  EasyAnalysis - Windows one-command launcher (no Docker, no admin)
# --------------------------------------------------------------------------
#  Usage (end users):
#     iwr -useb https://easyanalysis.dev/install.ps1 | iex
#
#  What it does, in order:
#     1. Ensure R          - use a system R if present, else download a
#                            portable R into %LOCALAPPDATA%\EasyAnalysis\R.
#     2. Ensure app source - use a local folder (-AppSource) or download the
#                            app zip into %LOCALAPPDATA%\EasyAnalysis\app.
#     3. Ensure packages   - install missing R packages into a private library
#                            (launcher/deps.R). First run only; cached after.
#     4. Launch            - launcher/run.R starts the app + opens the browser.
#  Second run onward: steps 1-3 are cached, so it launches in seconds.
# --------------------------------------------------------------------------
[CmdletBinding()]
param(
  # Local folder OR .zip URL holding ui.R/server.R/global.R. When a local
  # folder is given it is used IN PLACE (no copy) - ideal for dev testing.
  [string]$AppSource = $env:EASYANALYSIS_SRC,
  # R version to download if no system R is found.
  [string]$RVersion = "4.5.3",
  # Re-run dependency installation even if the cache marker says it is done.
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # faster Invoke-WebRequest

function Say($msg) { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Red; exit 1 }

# --- Paths -----------------------------------------------------------------
# NB: do NOT use $Home - it is a PowerShell automatic variable (user profile).
$AppHome = Join-Path $env:LOCALAPPDATA "EasyAnalysis"
$RDir = Join-Path $AppHome "R"
$LibDir = Join-Path $AppHome "library"
$AppDir = Join-Path $AppHome "app"
New-Item -ItemType Directory -Force -Path $AppHome, $LibDir | Out-Null

# Default download source: GitHub's auto-generated archive of main. It always
# exists and is always current, so there is no separate zip to build/upload
# (the old vercel-hosted zip URL 404'd because nothing ever produced it).
# The archive nests everything in "easyanalysis-main/" - Resolve-AppDir already
# handles that by locating global.R inside the extracted tree.
# Override with -AppSource <folder|url> or $env:EASYANALYSIS_SRC.
$DefaultZip = "https://github.com/Casanda00/easyanalysis/archive/refs/heads/main.zip"

# --- 1. Ensure R -----------------------------------------------------------
function Get-Rscript {
  # (a) portable R we installed previously
  $p = Join-Path $RDir "bin\Rscript.exe"
  if (Test-Path $p) { return $p }
  # (b) R on PATH
  $cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  # (c) standard install locations, newest first
  $found = Get-ChildItem "C:\Program Files\R\R-*\bin\Rscript.exe",
  "$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe" `
    -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1
  if ($found) { return $found.FullName }
  return $null
}

function Install-PortableR {
  Say "No R found - downloading portable R $RVersion (one-time, ~90 MB)..."
  $exe = Join-Path $env:TEMP "R-$RVersion-win.exe"
  $url = "https://cran.r-project.org/bin/windows/base/R-$RVersion-win.exe"
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $exe }
  catch { Die "Could not download R from $url : $($_.Exception.Message)" }
  Say "Installing R into $RDir (silent, no admin)..."
  # R's Inno Setup installer: silent, user-dir target => no admin needed.
  $rargs = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NOICONS", "/DIR=`"$RDir`"")
  Start-Process -FilePath $exe -ArgumentList $rargs -Wait
  Remove-Item $exe -ErrorAction SilentlyContinue
  $rs = Join-Path $RDir "bin\Rscript.exe"
  if (-not (Test-Path $rs)) { Die "R install did not produce $rs" }
  return $rs
}

$Rscript = Get-Rscript
if (-not $Rscript) { $Rscript = Install-PortableR }
Say "Using R: $Rscript"

# --- 2. Ensure app source --------------------------------------------------
function Resolve-AppDir {
  # (a) local folder given -> use in place (dev), no copy
  if ($AppSource -and (Test-Path $AppSource -PathType Container)) {
    if (Test-Path (Join-Path $AppSource "global.R")) {
      Say "Using local app source in place: $AppSource"
      return (Resolve-Path $AppSource).Path
    }
    Warn "$AppSource has no global.R - falling back to download."
  }
  # (b) download a zip (explicit URL or default), expand into $AppDir
  $zipUrl = if ($AppSource -and $AppSource -match '^https?://') { $AppSource } else { $DefaultZip }
  Say "Downloading app from $zipUrl ..."
  $zip = Join-Path $env:TEMP "easyanalysis-app.zip"
  try { Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip }
  catch { Die "Could not download app zip: $($_.Exception.Message)" }
  if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
  $tmp = Join-Path $env:TEMP ("ea-unzip-" + [guid]::NewGuid().ToString("N"))
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  # zip may nest the app one level deep (repo-name folder) - find global.R
  $g = Get-ChildItem $tmp -Recurse -Filter global.R -ErrorAction SilentlyContinue |
  Select-Object -First 1
  if (-not $g) { Die "Downloaded zip has no global.R." }
  $src = Split-Path $g.FullName -Parent
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Copy-Item (Join-Path $src '*') $AppDir -Recurse -Force
  Remove-Item $tmp, $zip -Recurse -Force -ErrorAction SilentlyContinue
  return $AppDir
}

$App = Resolve-AppDir
if (-not (Test-Path (Join-Path $App "launcher\deps.R"))) {
  Die "App source is missing launcher\deps.R - update the source/zip."
}

# --- 3. Ensure packages (cached via a marker) ------------------------------
$marker = Join-Path $LibDir ".deps-ok"
$depsR = Join-Path $App "launcher\deps.R"
$needDeps = $Force -or -not (Test-Path $marker) -or `
((Get-Item $depsR).LastWriteTimeUtc -gt (Get-Item $marker).LastWriteTimeUtc)

if ($needDeps) {
  Say "Checking / installing R packages (first run can take several minutes)..."
  & $Rscript $depsR $LibDir
  if ($LASTEXITCODE -ne 0) { Die "Package installation failed (see messages above)." }
  Set-Content -Path $marker -Value (Get-Date -Format o)
}
else {
  Say "Packages already installed (cached). Use -Force to re-check."
}

# --- 3.5 Shortcuts ---------------------------------------------------------
# Without this the terminal is needed on EVERY launch, not just the first: the
# only documented way in was to paste the install one-liner again. A user who
# installed last week had no way back into the app.
#
# The shortcut runs a small LOCAL launcher rather than re-running this script,
# because this script is normally executed via `iwr | iex` and so has no file on
# disk to point at. The launcher skips the download and dependency steps (both
# already cached) and just starts the app, which is what makes it quick.
function New-Launcher {
  $lp = Join-Path $AppHome "launch.ps1"
  # $App and $LibDir are baked in at install time so the launcher does no
  # discovery of its own. R is re-resolved at run time in case the user later
  # installs or upgrades a system R.
  $body = @"
# EasyAnalysis launcher - generated by install.ps1. Re-run the installer to update.
`$ErrorActionPreference = 'Stop'
`$App    = '$App'
`$LibDir = '$LibDir'
`$RDir   = '$RDir'

function Get-Rscript {
  `$p = Join-Path `$RDir 'bin\Rscript.exe'
  if (Test-Path `$p) { return `$p }
  `$cmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue
  if (`$cmd) { return `$cmd.Source }
  `$f = Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe', "`$env:LOCALAPPDATA\Programs\R\R-*\bin\Rscript.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
  if (`$f) { return `$f.FullName }
  return `$null
}

`$Rscript = Get-Rscript
if (-not `$Rscript) {
  Write-Host 'EasyAnalysis: R not found. Re-run the installer:' -ForegroundColor Red
  Write-Host '  iwr -useb https://easyanalysis.dev/install.ps1 | iex'
  Read-Host 'Press Enter to close'; exit 1
}
if (-not (Test-Path (Join-Path `$App 'global.R'))) {
  Write-Host 'EasyAnalysis: app files are missing. Re-run the installer:' -ForegroundColor Red
  Write-Host '  iwr -useb https://easyanalysis.dev/install.ps1 | iex'
  Read-Host 'Press Enter to close'; exit 1
}

Write-Host 'Starting EasyAnalysis - your browser will open shortly.' -ForegroundColor Green
Write-Host 'Use the Quit button in the app to close it, or close this window.'
& `$Rscript (Join-Path `$App 'launcher\run.R') `$App `$LibDir
# Only reached if the app exits with an error; otherwise Quit ends the process.
if (`$LASTEXITCODE -ne 0) { Read-Host 'EasyAnalysis stopped unexpectedly. Press Enter to close' }
"@
  Set-Content -Path $lp -Value $body -Encoding UTF8
  return $lp
}

function New-Shortcut($linkPath, $target) {
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($linkPath)
  $sc.TargetPath = (Get-Command powershell.exe).Source
  # Minimized, NOT Hidden. Hidden looks tidier, but a failed start would then
  # show the user absolutely nothing. Minimized keeps the window in the taskbar
  # as an escape hatch while staying out of the way -- and the app now has its
  # own Quit button, so this window is no longer the only way to stop it.
  $sc.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$target`""
  $sc.WorkingDirectory = $AppHome
  $sc.Description = "EasyAnalysis - analyse data and map it, in one place"
  # The app's own icon, built from favicon.png by tools/make-icon.ps1 and shipped
  # with the app. Copied into $AppHome first: the shortcut stores a PATH, so if it
  # pointed into $App it would break the moment the app folder is replaced by a
  # reinstall. Without this the shortcut shows the PowerShell icon.
  $ico = Join-Path $App "launcher\easyanalysis.ico"
  if (Test-Path $ico) {
    $localIco = Join-Path $AppHome "easyanalysis.ico"
    Copy-Item $ico $localIco -Force -ErrorAction SilentlyContinue
    if (Test-Path $localIco) { $sc.IconLocation = "$localIco,0" }
  }
  $sc.Save()
}

try {
  $launcher = New-Launcher
  $desktop = [Environment]::GetFolderPath("Desktop")
  $startDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
  New-Item -ItemType Directory -Force -Path $startDir | Out-Null
  New-Shortcut (Join-Path $desktop  "EasyAnalysis.lnk") $launcher
  New-Shortcut (Join-Path $startDir "EasyAnalysis.lnk") $launcher
  Say "Shortcut created on your Desktop and in the Start Menu."
  Say "From now on just double-click EasyAnalysis - no terminal needed."
}
catch {
  # Never fail the install over a shortcut; the app still works without one.
  Warn "Could not create shortcuts ($($_.Exception.Message)). The app still works."
}

# --- 4. Launch -------------------------------------------------------------
Say "Launching EasyAnalysis - your browser will open shortly."
Say "Use the Quit button in the app to close it, or close this window."
& $Rscript (Join-Path $App "launcher\run.R") $App $LibDir
