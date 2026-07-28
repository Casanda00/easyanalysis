# ==========================================================================
#  EasyAnalysis - Windows one-command launcher (no Docker, no admin)
# --------------------------------------------------------------------------
#  Usage (end users):
#     iwr -useb https://easyanalysis.vercel.app/install.ps1 | iex
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
  [string]$RVersion  = "4.5.3",
  # Re-run dependency installation even if the cache marker says it is done.
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference     = "SilentlyContinue"   # faster Invoke-WebRequest

function Say($msg)  { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "[EasyAnalysis] $msg" -ForegroundColor Red; exit 1 }

# --- Paths -----------------------------------------------------------------
# NB: do NOT use $Home - it is a PowerShell automatic variable (user profile).
$AppHome = Join-Path $env:LOCALAPPDATA "EasyAnalysis"
$RDir    = Join-Path $AppHome "R"
$LibDir  = Join-Path $AppHome "library"
$AppDir  = Join-Path $AppHome "app"
New-Item -ItemType Directory -Force -Path $AppHome, $LibDir | Out-Null

# Default download source: the lean app bundle served from the same Vercel
# host as the browser build. ~0.3 MB - the R packages install locally, once.
# Override with -AppSource <folder|url> or $env:EASYANALYSIS_SRC.
$DefaultZip = "https://easyanalysis.vercel.app/easyanalysis-app.zip"

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
  try   { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $exe }
  catch { Die "Could not download R from $url : $($_.Exception.Message)" }
  Say "Installing R into $RDir (silent, no admin)..."
  # R's Inno Setup installer: silent, user-dir target => no admin needed.
  $rargs = @("/VERYSILENT","/SUPPRESSMSGBOXES","/NOICONS","/DIR=`"$RDir`"")
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
  try   { Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip }
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
$depsR  = Join-Path $App "launcher\deps.R"
$needDeps = $Force -or -not (Test-Path $marker) -or `
            ((Get-Item $depsR).LastWriteTimeUtc -gt (Get-Item $marker).LastWriteTimeUtc)

if ($needDeps) {
  Say "Checking / installing R packages (first run can take several minutes)..."
  & $Rscript $depsR $LibDir
  if ($LASTEXITCODE -ne 0) { Die "Package installation failed (see messages above)." }
  Set-Content -Path $marker -Value (Get-Date -Format o)
} else {
  Say "Packages already installed (cached). Use -Force to re-check."
}

# --- 4. Launch -------------------------------------------------------------
Say "Launching EasyAnalysis - your browser will open shortly."
Say "Keep the R window open while you work; close it to stop the app."
& $Rscript (Join-Path $App "launcher\run.R") $App $LibDir
