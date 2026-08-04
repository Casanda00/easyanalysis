#!/usr/bin/env Rscript
# ==========================================================================
# launcher/deps.R  --  ensure EasyAnalysis's R packages are installed
# --------------------------------------------------------------------------
# Called by install.ps1 (Windows) / install.sh (Mac/Linux) with ONE arg:
#   1. lib  -- private package library to install into (created if missing)
# Installs only what's MISSING, so 2nd+ runs are fast. On Windows it uses
# CRAN *binary* packages, which are self-contained (sf/terra/lidR bundle the
# GDAL/PROJ/GEOS DLLs) -> no system installs, no Docker, no admin.
# Each install is wrapped so one failure never aborts the rest; the OPTIONAL
# "extras" only power individual screens (guarded by requireNamespace()).
# ==========================================================================

args <- commandArgs(trailingOnly = TRUE)
lib  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else .libPaths()[1]
dir.create(lib, showWarnings = FALSE, recursive = TRUE)
.libPaths(c(lib, .libPaths()))

options(repos = c(
  lidar = "https://r-lidar.r-universe.dev",
  CRAN  = "https://cloud.r-project.org"
), timeout = max(600, getOption("timeout")))   # big spatial binaries

# --- CORE: the app will not boot without these (library() in global.R) -----
core <- c(
  "shiny", "bslib", "shinyWidgets", "DT", "rhandsontable", "readxl",
  "nnet", "nlme", "MuMIn", "randomForest", "pdp", "ggplot2", "cluster",
  "factoextra", "ape", "MASS", "lidR", "sf", "terra", "stars", "rgl",
  "scatterplot3d", "leaflet", "leaflet.extras", "leafem", "viridisLite",
  "httr", "jsonlite", "base64enc", "ggspatial", "patchwork", "data.table",
  "zip"
)

# --- EXTRAS: power individual screens; guarded by requireNamespace() --------
# If one fails to install the app still runs; only that screen shows a notice.
extras <- c(
  "BayesFactor", "mgcv", "klaR", "kernlab", "heplots", "rpart", "Hmisc",
  "trend", "car", "glmnet", "exactextractr", "rstac", "survival", "tseries",
  "e1071", "xgboost", "whitebox", "lavaan", "writexl", "plotly", "lme4"
)
# NOTE: ggord (DA biplot) is GitHub-only (fawda123/ggord) and optional — not
# installed here; its screen path is requireNamespace()-guarded.

want    <- unique(c(core, extras))
missing <- setdiff(want, rownames(installed.packages()))

# --- Package TYPE: binaries wherever CRAN publishes them --------------------
# The whole promise of this launcher is "no toolchain, no admin". CRAN ships
# prebuilt binaries for BOTH Windows and macOS, and the spatial ones bundle
# their own GDAL/PROJ/GEOS.
#
# macOS's default pkgType is "both", which silently prefers SOURCE whenever
# CRAN's source version is newer than the published binary. That is how a Mac
# with no compiler ends up in `make: *** [classInt.ts] Error 1` — classInt
# needs Fortran, sf needs classInt, so the CORE set fails and nothing launches.
# Ask for binaries explicitly, and never quietly fall back to compiling.
bin_ok <- Sys.info()[["sysname"]] %in% c("Windows", "Darwin")
type   <- if (bin_ok) "binary" else "source"
if (bin_ok) options(install.packages.compile.from.source = "never")

.try_install <- function(pkgs, ptype, ncpus = 1L) {
  if (!length(pkgs)) return(invisible(NULL))
  tryCatch(
    install.packages(pkgs, lib = lib, type = ptype, dependencies = NA,
                     Ncpus = ncpus),
    error   = function(e) message("deps: ", ptype, " install error: ",
                                  conditionMessage(e)),
    warning = function(w) message("deps: ", ptype, " install warning: ",
                                  conditionMessage(w)))
}

if (!length(missing)) {
  message("deps: all ", length(want), " packages already present.")
} else {
  message("deps: installing ", length(missing), " package(s) [", type, "]: ",
          paste(missing, collapse = ", "))
  if (bin_ok)
    message("deps: using CRAN binaries — no compiler or Xcode tools needed.")

  # dependencies = NA (the default) => Depends + Imports + LinkingTo only, i.e.
  # exactly what's needed to RUN. We deliberately do NOT pull Suggests (TRUE),
  # which would drag in testthat/knitr/... and bloat the first-run download.
  # First pass: one batched call (resolves shared deps once, parallel-friendly).
  .try_install(missing, type, max(1L, parallel::detectCores() - 1L))

  # Second pass: retry whatever is still missing, one at a time (resilient).
  for (p in setdiff(want, rownames(installed.packages()))) .try_install(p, type)

  # Third pass: a package with no binary for this R version / architecture can
  # only come from source. Try it — if there is no compiler it fails, and the
  # report below says exactly which package that was.
  if (bin_ok) {
    still <- setdiff(want, rownames(installed.packages()))
    if (length(still)) {
      message("deps: no binary for: ", paste(still, collapse = ", "),
              " — trying source (needs a compiler; safe to fail).")
      for (p in still) .try_install(p, "source")
    }
  }
}

# Presence in the library is NOT proof a package works — a binary built for a
# different R build can install cleanly and then fail to load. Check the CORE
# set actually loads, so a broken install is caught HERE and not at boot.
options(rgl.useNULL = TRUE)   # rgl must not try to open a window (CLAUDE.md #6)
.loads <- function(p) isTRUE(tryCatch(requireNamespace(p, quietly = TRUE),
                                      error = function(e) FALSE))
broken <- Filter(function(p) p %in% rownames(installed.packages()) && !.loads(p),
                 core)
if (length(broken)) {
  message("deps: installed but will not load: ", paste(broken, collapse = ", "),
          " — reinstalling from source.")
  for (p in broken) .try_install(p, "source")
  broken <- Filter(function(p) !.loads(p), broken)
}

installed_now <- rownames(installed.packages())
missing_core  <- unique(c(setdiff(core, installed_now), broken))
missing_extra <- setdiff(extras, installed_now)

if (length(missing_core)) {
  message("deps: ERROR — missing CORE packages: ",
          paste(missing_core, collapse = ", "))
  message("deps: the app may not boot. Re-run, or install these manually.")
  quit(status = 2L, save = "no")
}
if (length(missing_extra))
  message("deps: note — optional extras unavailable (screens degrade ",
          "gracefully): ", paste(missing_extra, collapse = ", "))

message("deps: OK")
