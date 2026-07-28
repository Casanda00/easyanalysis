#!/usr/bin/env Rscript
# ==========================================================================
# launcher/run.R  --  start EasyAnalysis and open it in the default browser
# --------------------------------------------------------------------------
# Called by install.ps1 / install.sh with up to two args:
#   1. app_dir -- folder holding ui.R / server.R / global.R  (default: cwd)
#   2. lib     -- private package library to prepend to .libPaths()  (optional)
# Picks a free local port, runs the app natively, and opens the browser.
# Shared by every "local door" (Windows / Mac / Linux) — no OS-specific code.
# ==========================================================================

args    <- commandArgs(trailingOnly = TRUE)
app_dir <- if (length(args) >= 1 && nzchar(args[1])) args[1] else getwd()
lib     <- if (length(args) >= 2 && nzchar(args[2])) args[2] else ""

if (nzchar(lib) && dir.exists(lib)) .libPaths(c(lib, .libPaths()))

if (!file.exists(file.path(app_dir, "global.R")))
  stop("run.R: no global.R found in '", app_dir, "' — wrong app folder?")

options(rgl.useNULL = TRUE)   # headless-safe 3D (matches global.R)

# Use a STABLE port so the URL is the same every launch and can be bookmarked.
# A random port each time meant users returned to a stale address. Override with
# $EASYANALYSIS_PORT. randomPort(min = max = p) returns p if it is free and
# errors if not, which is a cheap "is this port available?" test — if the
# preferred port is busy (another copy already running) we fall back to any free
# one rather than refusing to start.
.pref <- suppressWarnings(as.integer(Sys.getenv("EASYANALYSIS_PORT", "7788")))
if (is.na(.pref)) .pref <- 7788L
port <- tryCatch(
  httpuv::randomPort(min = .pref, max = .pref, host = "127.0.0.1"),
  error = function(e) {
    message("Port ", .pref, " is busy (is EasyAnalysis already running?) — picking another.")
    tryCatch(httpuv::randomPort(min = 3838, max = 8000, host = "127.0.0.1"),
             error = function(e2) 3838L)
  })

url <- sprintf("http://127.0.0.1:%s", port)
message("\n============================================================")
message("  EasyAnalysis is starting at  ", url)
message("  Your browser will open automatically in a moment.")
message("  Keep THIS window open while you work — close it to stop.")
message("============================================================\n")

shiny::runApp(
  appDir         = app_dir,
  port           = port,
  host           = "127.0.0.1",
  launch.browser = TRUE
)
