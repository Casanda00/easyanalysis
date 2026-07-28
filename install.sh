#!/bin/sh
# ==========================================================================
#  EasyAnalysis - macOS / Linux one-command launcher (no Docker, no sudo)
# --------------------------------------------------------------------------
#  Usage (end users):
#     curl -fsSL https://easyanalysis.vercel.app/install.sh | sh
#
#  What it does, in order (mirrors install.ps1 on Windows):
#     1. Ensure R          - use a system R if present; otherwise explain how
#                            to get it (there is no portable R for macOS, so
#                            we do NOT silently install a toolchain).
#     2. Ensure app source - use a local folder ($EASYANALYSIS_SRC) or
#                            download the app zip into the app home.
#     3. Ensure packages   - install missing R packages into a PRIVATE library
#                            (launcher/deps.R). First run only; cached after.
#     4. Launch            - launcher/run.R starts the app + opens the browser.
#  Second run onward: steps 1-3 are cached, so it launches in seconds.
#
#  Env overrides:
#     EASYANALYSIS_SRC   local folder OR .zip URL holding ui.R/server.R/global.R
#     EASYANALYSIS_FORCE =1 to re-run dependency installation
#     EASYANALYSIS_HOME  where to keep R library + app (default below)
#     EASYANALYSIS_PORT  port for the app (default 7788, honoured by run.R)
# --------------------------------------------------------------------------
set -eu

# NB: all logging goes to STDERR. Functions below "return" paths by echoing them
# to stdout and are read with $( ) — a log line on stdout would be captured as
# part of the path.
say()  { printf '\033[32m[EasyAnalysis]\033[0m %s\n' "$1" >&2; }
warn() { printf '\033[33m[EasyAnalysis]\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[EasyAnalysis]\033[0m %s\n' "$1" >&2; exit 1; }

# --- Paths -----------------------------------------------------------------
OS="$(uname -s)"
case "$OS" in
  Darwin) DEFAULT_HOME="$HOME/Library/Application Support/EasyAnalysis" ;;
  Linux)  DEFAULT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/EasyAnalysis" ;;
  *)      die "Unsupported system '$OS'. On Windows use install.ps1." ;;
esac
APP_HOME="${EASYANALYSIS_HOME:-$DEFAULT_HOME}"
LIB_DIR="$APP_HOME/library"
APP_DIR="$APP_HOME/app"
mkdir -p "$APP_HOME" "$LIB_DIR"

# GitHub's archive of main: always present, always current, and it nests the
# app in "easyanalysis-main/" - resolve_app_dir finds global.R inside it.
DEFAULT_ZIP="https://github.com/Casanda00/easyanalysis/archive/refs/heads/main.zip"
APP_SOURCE="${EASYANALYSIS_SRC:-}"

# --- 1. Ensure R -----------------------------------------------------------
# macOS has no "portable R" the way Windows does (the CRAN build is a .pkg that
# needs an installer), so instead of silently dragging in a toolchain we detect
# R and, if it is missing, say exactly how to get it.
find_rscript() {
  if command -v Rscript >/dev/null 2>&1; then command -v Rscript; return 0; fi
  for p in /usr/local/bin/Rscript /opt/homebrew/bin/Rscript \
           /Library/Frameworks/R.framework/Resources/bin/Rscript \
           /usr/lib/R/bin/Rscript; do
    [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

if ! RSCRIPT="$(find_rscript)"; then
  warn "R was not found on this system."
  if [ "$OS" = "Darwin" ]; then
    if command -v brew >/dev/null 2>&1; then
      say "Installing R with Homebrew (one-time)..."
      brew install --quiet r || die "Homebrew could not install R. Install it from https://cran.r-project.org/bin/macosx/ and re-run."
    else
      die "Install R first, then re-run this command:
    - with Homebrew:  brew install r
    - or download:    https://cran.r-project.org/bin/macosx/"
    fi
  else
    die "Install R first, then re-run this command:
    - Debian/Ubuntu:  sudo apt install r-base
    - Fedora:         sudo dnf install R
    - or see:         https://cran.r-project.org/bin/linux/"
  fi
  RSCRIPT="$(find_rscript)" || die "R still not found after installation."
fi
say "Using R: $RSCRIPT"

# --- 2. Ensure app source --------------------------------------------------
resolve_app_dir() {
  # (a) a local folder -> use IN PLACE (dev), no copy
  if [ -n "$APP_SOURCE" ] && [ -d "$APP_SOURCE" ]; then
    if [ -f "$APP_SOURCE/global.R" ]; then
      say "Using local app source in place: $APP_SOURCE"
      ( cd "$APP_SOURCE" && pwd )
      return 0
    fi
    warn "$APP_SOURCE has no global.R - falling back to download."
  fi
  # (b) download a zip (explicit URL or default) and expand it
  case "$APP_SOURCE" in
    http://*|https://*) zip_url="$APP_SOURCE" ;;
    *)                  zip_url="$DEFAULT_ZIP" ;;
  esac
  say "Downloading app from $zip_url ..."
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ea-XXXXXX")"
  zip="$tmp/app.zip"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$zip_url" -o "$zip" || die "Could not download the app zip."
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$zip" "$zip_url" || die "Could not download the app zip."
  else
    die "Neither curl nor wget is available."
  fi
  command -v unzip >/dev/null 2>&1 || die "'unzip' is required but not installed."
  unzip -q "$zip" -d "$tmp/x" || die "Could not unpack the app zip."
  # the zip may nest the app one level deep - locate global.R
  g="$(find "$tmp/x" -name global.R -maxdepth 3 -print 2>/dev/null | head -n 1)"
  [ -n "$g" ] || die "Downloaded zip has no global.R."
  src="$(dirname "$g")"
  rm -rf "$APP_DIR"; mkdir -p "$APP_DIR"
  ( cd "$src" && tar cf - . ) | ( cd "$APP_DIR" && tar xf - )
  rm -rf "$tmp"
  printf '%s\n' "$APP_DIR"
}

APP="$(resolve_app_dir)"
[ -f "$APP/launcher/deps.R" ] || die "App source is missing launcher/deps.R - update the source/zip."

# --- 3. Ensure packages (cached via a marker) ------------------------------
MARKER="$LIB_DIR/.deps-ok"
DEPS="$APP/launcher/deps.R"
need_deps=0
[ "${EASYANALYSIS_FORCE:-0}" = "1" ] && need_deps=1
[ -f "$MARKER" ] || need_deps=1
[ -f "$MARKER" ] && [ "$DEPS" -nt "$MARKER" ] && need_deps=1

if [ "$need_deps" = "1" ]; then
  say "Checking / installing R packages (first run can take several minutes)..."
  warn "On macOS/Linux some spatial packages compile from source, so be patient."
  "$RSCRIPT" "$DEPS" "$LIB_DIR" || die "Package installation failed (see messages above)."
  date > "$MARKER"
else
  say "Packages already installed (cached). Set EASYANALYSIS_FORCE=1 to re-check."
fi

# --- 4. Launch -------------------------------------------------------------
say "Launching EasyAnalysis - your browser will open shortly."
say "Keep this terminal window open while you work; close it to stop the app."
exec "$RSCRIPT" "$APP/launcher/run.R" "$APP" "$LIB_DIR"
