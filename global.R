# ==========================================================================
# global.R  --  loaded once, shared by ui.R and server.R
# --------------------------------------------------------------------------
# Clean-rebuild scaffold. We add things back ONE component at a time and test
# each before adding the next. The full previous app is preserved in:
#   ui_legacy.R, server_legacy.R, global_legacy.R   (not sourced)
# ==========================================================================

# App version — single source of truth. Bump on every build/push and add a
# matching entry to RELEASE_NOTES.md (public) AND CHANGELOG.md (internal).
# Shown in the status bar + About panel, and
# stamped into the browser build's service-worker cache key by webapp_export.R.
APP_VERSION <- "0.11.3"

library(shiny)
library(bslib)
library(shinyWidgets)

# --- Pre-load R's lazily-linked shared libraries (browser/wasm build) -------
# R links some of its own .so files LAZILY, on first use: cairo.so on the first
# plot, libRlapack.so on the first linear-algebra call. In this app that first
# use happens AFTER the heavy C++ side-modules (terra/sf/lidR/rgl) are loaded,
# and in the browser build that late link FAILS:
#   cairo  -> "Could not load dynamic lib .../cairo.so",
#             "bad export type for '_ZTINSt3__216__owns_one_stateIcEE'"
#             => every plot silently renders blank
#   LAPACK -> "LAPACK routines cannot be loaded"
#             => every model summary / decomposition dies
# Touching both here forces them to link FIRST, while they still can. Cheap,
# and harmless on a normal server (a temp device + a 2x2 matrix).
# NOTE: must stay ABOVE library(lidR)/sf/terra/rgl — order is the whole point.
try(suppressWarnings({
  .probe_png <- tempfile(fileext = ".png")
  grDevices::png(.probe_png, width = 8, height = 8)
  graphics::plot.new()
  grDevices::dev.off()
  unlink(.probe_png)
}), silent = TRUE)
try(suppressWarnings({
  svd(matrix(c(2, 1, 1, 3), 2))          # forces libRlapack.so
  solve(matrix(c(2, 1, 1, 3), 2))
}), silent = TRUE)

# Allow large file uploads (LiDAR .laz point clouds can be hundreds of MB).
# Default Shiny cap is 5 MB; raise to 3 GB.
options(shiny.maxRequestSize = 3 * 1024^3)
library(DT)
library(zip)          # portable .eap (zipped project) export/import
library(rhandsontable)

# Pre-warm Tcl/Tk at BOOT so the native folder/file dialogs open instantly on
# first click. Tk's first init is the slow part (~1-2 s); paying it here (boot
# is already slow) makes the dialogs feel snappy. Local desktop only — guarded,
# so a headless/browser build where Tk is unavailable just skips it.
try(suppressWarnings({
  if (capabilities("tcltk") && requireNamespace("tcltk", quietly = TRUE)) {
    loadNamespace("tcltk")
    tcltk::tclRequire("Tk", warn = FALSE)   # boots the Tcl interpreter + Tk
  }
}), silent = TRUE)
library(readxl)
library(tools)
library(nnet)    # multinom() -> Logistic Regression
library(nlme)    # lme()      -> Linear Mixed Effects
library(MuMIn)   # r.squaredGLMM() -> LME performance
library(randomForest)  # Random Forest
library(pdp)           # Partial Dependence Plots
library(ggplot2)       # Clustering / Classification plots
library(cluster)       # daisy, pam, silhouette
library(factoextra)    # fviz_*, get_dist
library(ape)           # phylogenetic tree (clustering)
library(MASS)          # lda/qda -> Discriminant Analysis
# NOTE: klaR, kernlab, heplots, ggord are used by Discriminant Analysis via
# requireNamespace() guards (optional methods) — NOT hard dependencies here.
# --- Heavy spatial stack: MUST be attached at boot (do NOT lazy-load) -------
# HARD LESSON (v0.5.0 -> v0.6.1): making these lazy broke .laz/.tif loading.
# A heavy C++ package whose .so loads LATE (on first `pkg::fn()` use, after the
# module table has filled) fails to dynamically link in this webR build with:
#   "bad export type for '_ZTINSt3__216__owns_one_stateIcEE': undefined"
# — the SAME failure mode as the cairo/LAPACK probes above. terra/sf already load
# early via leaflet's imports; lidR/stars did not, so lidR::readLAS died. They
# must all attach at boot, while the module table is still empty.
# NOTE: the Node webR harness does NOT reproduce this (it loaded lidR lazily
# fine) — only the browser does. Trust the browser here.
library(lidR)          # Spatial & LiDAR screens (readLAS/readLASheader)
library(sf)
library(terra)
library(stars)         # stars rasters for ggplot2 / map export
# Link lidR's full COMPILED dependency tree at BOOT. In this webR build a
# compiled .so that loads LATE fails ('_ZTINSt3__216__owns_one_stateIcEE').
# library(lidR) loads lidR.so but NOT every transitive compiled dep — readLAS
# pulls rlas, lazyeval, e1071, s2, units, wk, classInt, proxy, Rnanoflann,
# RcppArmadillo, KernSmooth, class, data.table on demand, each of which then
# fails to link. loadNamespace() links each .so now, while the module table is
# still empty. Already-loaded ones are instant no-ops. (Derived from
# tools::package_dependencies("lidR", recursive=TRUE); keep in sync if lidR's
# deps change.)
for (.p in c("rlas", "lazyeval", "e1071", "classInt", "proxy", "s2", "units",
             "wk", "Rnanoflann", "RcppArmadillo", "KernSmooth", "class",
             "data.table", "abind", "DBI", "terra", "sf", "stars",
             # Optional pkgs reached via requireNamespace() on a button click
             # (LATE). exactextractr is compiled and would hit the same ABI bug;
             # rstac is pure-R belt-and-suspenders. Both are bundled (see _deps.R).
             "rstac", "exactextractr")) {
  try(suppressWarnings(loadNamespace(.p)), silent = TRUE)
}
rm(.p)
# NOTE — do NOT bulk-preload the optional model/stats packages here.
# This webR build has a hard BUDGET for how many compiled side-modules (.so) can
# be dynamically linked before the libc++ symbol '_ZTINSt3__216__owns_one_state
# IcEE' becomes unavailable and further links fail. The lidR tree above already
# uses most of it. Adding xgboost/glmnet/kernlab/mgcv/... pushed past the budget
# and broke even base64enc — the app then failed to boot entirely.
# So those compiled packages (xgboost, glmnet, kernlab, mgcv, survival, rpart,
# car, klaR, ...) currently CANNOT be made to load in the browser build; their
# screens show a friendly "install package" message. Making them work needs a
# different strategy (e.g. a slimmer boot set, or those analyses on the server
# build). Keep this list EMPTY unless you have re-measured the budget.
options(rgl.useNULL = TRUE)  # must precede library(rgl) — prevents OpenGL crash on headless servers (shinyapps.io)
library(rgl)           # 3D point-cloud widget (interactive) — needed by the UI
library(scatterplot3d) # headless static 3D render (download + AI snapshot)

# --- Spatial / Remote Sensing expansion (Phase 2) ---
library(leaflet)
library(leaflet.extras)  # draw toolbar (addDrawToolbar)
library(leafem)          # addGeoRaster (terra rasters in leaflet)
library(viridisLite)     # colour palettes for raster display
library(httr)            # CDSE OAuth2 token exchange
library(ggplot2)         # already loaded via factoextra; explicit for map export
library(ggspatial)       # north arrow + scale bar in ggplot2 map layouts
library(patchwork)       # combine ggplots with / and | operators
# rstac, exactextractr used via requireNamespace() guards in their respective modules
# Install if needed:
#   install.packages(c("leaflet","leaflet.extras","leafem","viridisLite",
#                      "httr","stars","ggspatial","rstac","exactextractr"))

# Shared stateless helpers + plotting engines.
source("helpers.R")
source("project_store.R")        # on-disk projects = the app's saved state
source("evaluation_function.R")  # uef_evaluation() for LiDAR model evaluation
source("references.R")           # in-app References screen (papers implemented)
source("mod_docs.R")             # in-app Documentation / user guide (static screen)
source("mod_rconsole.R")         # in-app R console (browser build = per-user sandbox)
source("agent_tools.R")          # Co-Analyst agent: tool registry + dispatcher

# Shared green theme used across the whole app.
# Colour lives in ONE place: theme.R. It produces both the bslib theme and the
# CSS variables ui.R uses, so the two can never drift apart.
source("theme.R")
app_theme <- ea_theme()

# --- Modules are sourced here as we add them back, one at a time ---
source("mod_projects.R")   # Projects = the first screen the user sees
source("mod_project.R")    # inside a project: data-first entry, then a summary
source("mod_workspace.R")  # unified workspace (BETA) — two views; see UNIFIED_WORKSPACE.md
source("mod_data.R")
source("mod_linear_regression.R")
source("mod_lme.R")
source("mod_anova.R")
source("mod_logistic.R")
source("mod_rf.R")
source("mod_clustering.R")
source("mod_classification.R")
source("mod_da.R")
source("mod_lidar.R")
source("mod_raster.R")
# Processing algorithms: one searchable tool per operation (QGIS Processing
# style). algorithms.R is the registry, mod_algo.R renders and runs any entry.
source("algorithms.R")
# Killable background session, so a heavy algorithm can be stopped from the app
# instead of Ctrl-C in the terminal (see the note at the top of the file).
source("compute_worker.R")
source("mod_algo.R")
# Statistical methods: the same move for analyses that algorithms.R made for
# spatial operations. statistics.R is the registry, mod_stat.R renders and runs
# any entry. Sourced AFTER algorithms.R because the specs reuse its parameter
# constructors (ea_sel/ea_num/ea_txt) rather than defining a second set.
source("statistics.R")
source("mod_stat.R")
# mod_surface.R is RETIRED: its DTM/DSM/CHM/nDSM now live in algorithms.R as
# four separate tools, so "Surface models" no longer hides four operations
# behind a radio button. Left sourced only so nothing that still references
# surfaceServer breaks; it is no longer registered as a tool.
source("mod_surface.R")
source("mod_terrain.R")
source("mod_suitability.R")
source("mod_hydro.R")
source("mod_land_classify.R")
source("mod_descriptive.R")
source("mod_tests.R")
source("mod_pca.R")
source("mod_timeseries.R")
source("mod_survival.R")
source("mod_xgboost.R")
source("mod_dtree.R")
source("mod_nnet_ml.R")
source("mod_svm.R")
source("mod_sem.R")
source("mod_bayesian.R")
source("mod_recommend.R")
source("mod_rs_search.R")
# --- New spatial modeling & analysis modules ---
source("mod_ntl.R")
source("mod_climate_trend.R")
source("mod_wind.R")
source("mod_gam.R")
source("mod_chat.R")
