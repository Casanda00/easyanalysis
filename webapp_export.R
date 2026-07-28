# ==========================================================================
# webapp_export.R — build the browser-native (WebAssembly) version of the app
# --------------------------------------------------------------------------
# Compiles webapp/ into webapp_site/, a static website that runs the whole
# app inside each visitor's browser (webR). Run with:
#
#   "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" webapp_export.R
#
# Then serve locally to test:
#
#   "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" -e "httpuv::runStaticServer('webapp_site', port=8899)"
#
# and open http://localhost:8899 (first boot takes 1-3 min; hard-refresh with
# Ctrl+Shift+R after a rebuild so the service worker drops stale files).
#
# WHY THE PINS BELOW (learned the hard way, July 2026):
# - shinylive assets 0.10.11+ bundle webR 0.6 (R 4.6 wasm channel), where the
#   rlas and deSolve binaries do not exist yet -> lidR cannot load, app dies.
# - Assets 0.10.10 = webR 0.5.x = R 4.5 channel, which has ALL our packages.
# - But the shinylive R package hardcodes WEBR_R_VERSION="4.6.0" for package
#   downloads, so it must be patched in-session to match the 4.5 runtime.
#   Mixing channels (or r-universe binaries) => Emscripten ABI errors like
#   "resolved is not a function" at boot.
# - The exporter reuses any file already in webapp_site, including truncated
#   ones from interrupted downloads (this shipped a corrupt mgcv once), so we
#   always build into a wiped folder.
# Once repo.r-wasm.org's 4.6 channel gains rlas + deSolve, all three pins can
# be dropped (use latest assets, no patch, done).
# ==========================================================================

Sys.setenv(SHINYLIVE_ASSETS_VERSION = "0.10.10")
options(timeout = 600)  # wasm packages are big; default 60s timeout truncates

suppressMessages(loadNamespace("shinylive"))
unlockBinding("WEBR_R_VERSION", getNamespace("shinylive"))
assignInNamespace("WEBR_R_VERSION", "4.5.0", ns = "shinylive")
stopifnot(getNamespace("shinylive")[["WEBR_R_VERSION"]] == "4.5.0")

if (!dir.exists("webapp")) stop("Run this from the Shiny_app folder (webapp/ not found).")

# App version (single source: webapp/global.R's APP_VERSION). Stamped into the
# service-worker cache key and the build report so every build is traceable.
app_version <- tryCatch(
  sub('.*"(.*)".*', "\\1",
      grep("^APP_VERSION\\s*<-", readLines("webapp/global.R"), value = TRUE)[1]),
  error = function(e) "0.0.0")
cat(sprintf("Building EasyAnalysis v%s ...\n", app_version))

# --- hide packages that have NO wasm build from shinylive's scanner ---------
# ggord (GitHub-only) and heplots have no WebAssembly binary. If shinylive sees a
# literal `ggord::` / `requireNamespace("ggord")` it tries to resolve them and the
# export DIES ("Can't find GitHub release for github::fawda123/ggord@HEAD").
# They are optional DA extras, so route them through string indirection
# (.opt_pkg/.opt_fun in helpers.R) which the scanner cannot see.
#
# This runs on every build because webapp/ is a hand-synced copy of the root app:
# any `cp mod_*.R webapp/` silently reintroduces the literal references. Applying
# the transform here makes the build self-healing instead of depending on
# remembering not to overwrite one file.
.hide_nonwasm_pkgs <- function(path) {
  if (!file.exists(path)) return(invisible(FALSE))
  txt <- readChar(path, file.size(path), useBytes = TRUE)
  orig <- txt
  for (p in c("ggord", "heplots")) {
    txt <- gsub(sprintf('requireNamespace("%s", quietly = TRUE)', p),
                sprintf('.opt_pkg("%s")', p), txt, fixed = TRUE)
    # pkg::fun(  ->  .opt_fun("pkg","fun")(
    txt <- gsub(sprintf("%s::([A-Za-z0-9._]+)\\(", p),
                sprintf('.opt_fun("%s", "\\1")(', p), txt)
  }
  if (!identical(txt, orig)) {
    con <- file(path, open = "wb"); writeBin(charToRaw(txt), con); close(con)
    cat("  patched (no-wasm pkg indirection):", basename(path), "\n")
    return(invisible(TRUE))
  }
  invisible(FALSE)
}
# --- webapp/ must contain ONLY what global.R actually sources ---------------
# shinylive scans EVERY .R file in the app folder for dependencies, not just the
# ones that run. An un-sourced module (e.g. mod_gee.R, which references
# rgee/reticulate — no wasm build) silently poisons the bundle:
# "fatal-missing: reticulate". A blanket `cp mod_*.R webapp/` reintroduces them,
# so prune here rather than relying on remembering.
.core_files <- c("global.R", "ui.R", "server.R", "helpers.R",
                 "evaluation_function.R", "references.R", "agent_tools.R",
                 "mod_rconsole.R",
                 "_deps.R")   # not sourced, but scanned so rstac/exactextractr get bundled
.sourced <- regmatches(
  paste(readLines("webapp/global.R", warn = FALSE), collapse = "\n"),
  gregexpr('(?<=source\\(")[^"]+\\.R(?=")',
           paste(readLines("webapp/global.R", warn = FALSE), collapse = "\n"), perl = TRUE)
)[[1]]
.keep <- unique(c(.core_files, .sourced))
.extra <- setdiff(basename(list.files("webapp", pattern = "\\.R$")), .keep)
if (length(.extra)) {
  file.remove(file.path("webapp", .extra))
  cat("  pruned un-sourced files from webapp/ (would poison the bundle): ",
      paste(.extra, collapse = ", "), "\n", sep = "")
}

for (f in list.files("webapp", pattern = "\\.R$", full.names = TRUE)) .hide_nonwasm_pkgs(f)
leftover <- unlist(lapply(list.files("webapp", pattern = "\\.R$", full.names = TRUE), function(f) {
  t <- readChar(f, file.size(f), useBytes = TRUE)
  if (grepl("ggord::|heplots::|requireNamespace\\(\"(ggord|heplots)\"", t)) basename(f) else NULL
}))
if (length(leftover))
  stop("Literal ggord/heplots refs still in: ", paste(leftover, collapse = ", "),
       " — the export would fail. Extend .hide_nonwasm_pkgs().")

unlink("webapp_site", recursive = TRUE, force = TRUE)  # never reuse stale/truncated files
shinylive::export("webapp", "webapp_site")

# --- patch webR's dynamic loader (R.js) for the broken terra wasm build ---
# repo.r-wasm.org's terra.so imports 7 PROJ symbols renamed "internal_proj_*"
# (GDAL PROJ_RENAME_SYMBOLS build) that NO shipped library exports, so
# library(terra) dies with "resolved is not a function" (and lidR with it,
# since lidR imports terra). Those 7 are only terra's direct PROJ utility
# calls (search paths / network toggles / version probe); actual projection
# runs through GDAL's own statically-linked PROJ inside terra.so. Stubbing
# them as no-ops lets terra load AND reproject correctly (verified headlessly
# in Node webR: terra::project() works). Re-applied after every export
# because export overwrites R.js.
# Bump the service-worker cache version per build so returning visitors never
# run a stale runtime from the browser cache (the SW caches R.js and friends;
# without this, even hard refreshes can serve the previous build).
sw_path <- "webapp_site/shinylive-sw.js"
sw <- readChar(sw_path, file.size(sw_path), useBytes = TRUE)
sw <- sub('var version = "v10[^"]*"',
          sprintf('var version = "v10-easyanalysis-%s-%s"',
                  app_version, format(Sys.time(), "%Y%m%d%H%M%S")),
          sw)
con <- file(sw_path, open = "wb"); writeBin(charToRaw(sw), con); close(con)
cat(sprintf("service worker cache version bumped (v%s)\n", app_version))

# Patch resolveSymbol() ONLY — the single place where an unresolved dynamic
# symbol is looked up. If (and only if) a symbol is genuinely missing AND is one
# of terra's renamed PROJ imports, hand back a no-op. Everything else is
# untouched.
#
# DO NOT patch the generic stub factory instead, and DO NOT add a throw for
# unresolved symbols: that blast radius breaks side-module loading — cairo.so
# then fails with "bad export type for '_ZTINSt3__216__owns_one_stateIcEE'" and
# EVERY plot silently renders blank (verified: a control app with pristine R.js
# and identical pins renders plots fine; with the broad patch it does not).
#
# Written with writeBin, not writeLines: on Windows writeLines re-encodes every
# line ending (LF -> CRLF), rewriting the whole file for no reason.
rjs_path <- "webapp_site/shinylive/webr/R.js"
rjs <- readChar(rjs_path, file.size(rjs_path), useBytes = TRUE)
res_old <- "function resolveSymbol(sym){var resolved=resolveGlobalSymbol(sym).sym;if(!resolved&&localScope){resolved=localScope[sym]}if(!resolved){resolved=moduleExports[sym]}return resolved}"
res_new <- paste0(
  "function resolveSymbol(sym){var resolved=resolveGlobalSymbol(sym).sym;",
  "if(!resolved&&localScope){resolved=localScope[sym]}",
  "if(!resolved){resolved=moduleExports[sym]}",
  "if(!resolved&&typeof sym===\"string\"&&sym.indexOf(\"internal_proj_\")===0)",
  "{resolved=function(){return 0}}",
  "return resolved}")
if (grepl(res_old, rjs, fixed = TRUE)) {
  patched <- sub(res_old, res_new, rjs, fixed = TRUE)
  con <- file(rjs_path, open = "wb"); writeBin(charToRaw(patched), con); close(con)
  cat("R.js resolveSymbol patched for terra/lidR (internal_proj_* no-ops)\n")
} else if (grepl("internal_proj_", rjs, fixed = TRUE)) {
  cat("R.js already patched\n")
} else {
  stop("R.js resolveSymbol pattern not found — webR version changed; revisit the terra patch")
}

# --- post-build integrity check: every bundled package must be a valid tgz ---
pkgs <- list.files("webapp_site/shinylive/webr/packages",
                   pattern = "\\.tgz$", recursive = TRUE, full.names = TRUE)
bad <- character(0)
for (f in pkgs) {
  ok <- tryCatch({ con <- gzfile(f, "rb"); readBin(con, "raw", 1e7); close(con); TRUE },
                 error = function(e) FALSE)
  if (!ok) bad <- c(bad, f)
}
# Browser tab title: shinylive ships "<title>Shiny App</title>". Rename it so the
# tab (and bookmarks) read EasyAnalysis.
for (idx in c("webapp_site/index.html", "webapp_site/edit/index.html")) {
  if (file.exists(idx)) {
    h <- readChar(idx, file.size(idx), useBytes = TRUE)
    if (grepl("<title>", h, fixed = TRUE))
      h <- sub("<title>[^<]*</title>", "<title>EasyAnalysis</title>", h)
    # EasyAnalysis favicon — absolute /favicon.png so it resolves from any page.
    # Also declares apple-touch-icon; the /favicon.ico copy (below) stops the 404.
    if (!grepl("rel=\"icon\"", h, fixed = TRUE) && grepl("</head>", h, fixed = TRUE))
      h <- sub("</head>", paste0(
        "<link rel=\"icon\" type=\"image/png\" href=\"/favicon.png\">",
        "<link rel=\"apple-touch-icon\" href=\"/favicon.png\"></head>"), h, fixed = TRUE)
    con <- file(idx, "wb"); writeBin(charToRaw(h), con); close(con)
  }
}
cat("browser tab title + favicon set\n")

# --- Branded loading splash (shown during the ~1-3 min first boot) -----------
# Inject splash_template.html before </body>, stamping in the latest CHANGELOG
# section as "What's new". The app posts 'ea-app-ready' when its UI renders
# (see ui.R) and the splash fades out. Applied on every build.
if (file.exists("splash_template.html")) {
  # latest CHANGELOG block -> HTML list
  whatsnew <- "<div class='ea-ver'>What's new</div>"
  if (file.exists("CHANGELOG.md")) {
    cl <- readLines("CHANGELOG.md", warn = FALSE)
    h2 <- grep("^## ", cl)
    if (length(h2) >= 1) {
      blk  <- cl[h2[1]:(if (length(h2) >= 2) h2[2] - 1 else length(cl))]
      vled <- sub("^##\\s*", "", blk[1])
      items <- sub("^-\\s*", "", blk[grepl("^- ", blk)])
      items <- gsub("\\*\\*([^*]+)\\*\\*", "<b>\\1</b>", items)
      items <- gsub("`([^`]+)`", "<code>\\1</code>", items)
      items <- gsub("&", "&amp;", items, fixed = TRUE)
      items <- gsub("&amp;amp;", "&amp;", items, fixed = TRUE)
      lis <- paste0("<li>", items, "</li>", collapse = "")
      whatsnew <- paste0("<div class='ea-ver'>New in ", vled, "</div><ul class='ea-news'>", lis, "</ul>")
    }
  }
  splash <- readChar("splash_template.html", file.size("splash_template.html"), useBytes = TRUE)
  splash <- sub("{{WHATSNEW}}", whatsnew, splash, fixed = TRUE)
  idx <- "webapp_site/index.html"
  h <- readChar(idx, file.size(idx), useBytes = TRUE)
  h <- sub("</body>", paste0(splash, "\n</body>"), h, fixed = TRUE)
  con <- file(idx, "wb"); writeBin(charToRaw(h), con); close(con)
  cat("loading splash injected\n")
}

# Copy llms.txt (LLM/search discovery file, llmstxt.org) into the site root so it
# is served at /llms.txt. Wiped-and-rebuilt each time, so it must be re-copied.
if (file.exists("llms.txt")) {
  file.copy("llms.txt", "webapp_site/llms.txt", overwrite = TRUE)
  cat("llms.txt copied to site root\n")
}

# Favicon: copy the square PNG to the site root as favicon.png AND favicon.ico
# (browsers auto-request /favicon.ico; PNG bytes there stop the 404 in Chrome/Edge/FF).
if (file.exists("favicon.png")) {
  file.copy("favicon.png", "webapp_site/favicon.png", overwrite = TRUE)
  file.copy("favicon.png", "webapp_site/favicon.ico", overwrite = TRUE)
  cat("favicon copied to site root (favicon.png + favicon.ico)\n")
}

meta <- readRDS("webapp_site/shinylive/webr/packages/metadata.rds")
noasset <- names(Filter(function(x) length(x$assets) == 0, meta))
# deSolve (via hypergeo <- BayesFactor) and quadprog (via tseries) have no wasm
# builds in the 4.5 channel. They are NOT in global.R's startup chain — only the
# Bayesian screen's BayesFactor method and tseries-based time-series tests fail
# at runtime. Accepted limitation of the browser build; boot is unaffected.
known_missing <- c("deSolve", "quadprog")
fatal_missing <- setdiff(noasset, known_missing)
cat("\n==== BUILD REPORT ====\n")
cat("packages bundled :", length(pkgs), "\n")
cat("corrupt tarballs :", if (length(bad)) paste(bad, collapse = ", ") else "none", "\n")
cat("known-missing    :", paste(intersect(noasset, known_missing), collapse = ", "),
    "(expected; Bayesian/tseries methods degrade at runtime)\n")
cat("fatal-missing    :", if (length(fatal_missing)) paste(fatal_missing, collapse = ", ") else "none", "\n")
if (length(bad) || length(fatal_missing)) {
  cat("BUILD BAD — do not deploy. Re-run on a stable connection.\n")
} else {
  cat("BUILD OK — serve webapp_site/ and test in the browser.\n")
}
