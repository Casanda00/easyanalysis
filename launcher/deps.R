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

options(repos = c(CRAN = "https://cloud.r-project.org"),
        timeout = max(600, getOption("timeout")))   # big spatial binaries

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
  "e1071", "xgboost", "whitebox", "lavaan", "writexl"
)
# NOTE: ggord (DA biplot) is GitHub-only (fawda123/ggord) and optional — not
# installed here; its screen path is requireNamespace()-guarded.

want    <- unique(c(core, extras))
missing <- setdiff(want, rownames(installed.packages()))

if (!length(missing)) {
  message("deps: all ", length(want), " packages already present.")
} else {
  type <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType")
  message("deps: installing ", length(missing), " package(s) [", type, "]: ",
          paste(missing, collapse = ", "))

  # dependencies = NA (the default) => Depends + Imports + LinkingTo only, i.e.
  # exactly what's needed to RUN. We deliberately do NOT pull Suggests (TRUE),
  # which would drag in testthat/knitr/... and bloat the first-run download.
  # First pass: one batched call (resolves shared deps once, parallel-friendly).
  tryCatch(
    install.packages(missing, lib = lib, type = type, dependencies = NA,
                     Ncpus = max(1L, parallel::detectCores() - 1L)),
    error = function(e) message("deps: batch install hit an error: ",
                                conditionMessage(e)))

  # Second pass: retry whatever is still missing, one at a time (resilient).
  still <- setdiff(want, rownames(installed.packages()))
  for (p in still) {
    tryCatch(
      install.packages(p, lib = lib, type = type, dependencies = NA),
      error = function(e) message("deps: ! ", p, " failed: ",
                                  conditionMessage(e)))
  }
}

installed_now <- rownames(installed.packages())
missing_core  <- setdiff(core, installed_now)
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
