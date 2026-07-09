# ==========================================================================
# global.R  --  loaded once, shared by ui.R and server.R
# --------------------------------------------------------------------------
# Clean-rebuild scaffold. We add things back ONE component at a time and test
# each before adding the next. The full previous app is preserved in:
#   ui_legacy.R, server_legacy.R, global_legacy.R   (not sourced)
# ==========================================================================

library(shiny)
library(bslib)
library(shinyWidgets)

# Allow large file uploads (LiDAR .laz point clouds can be hundreds of MB).
# Default Shiny cap is 5 MB; raise to 3 GB.
options(shiny.maxRequestSize = 3 * 1024^3)
library(DT)
library(rhandsontable)
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
library(lidR)          # Spatial & LiDAR screens
library(sf)
library(terra)
options(rgl.useNULL = TRUE)  # must precede library(rgl) — prevents OpenGL crash on headless servers (shinyapps.io)
library(rgl)           # 3D point-cloud widget (interactive)
library(scatterplot3d) # headless static 3D render (download + AI snapshot)

# --- Spatial / Remote Sensing expansion (Phase 2) ---
library(leaflet)
library(leaflet.extras)  # draw toolbar (addDrawToolbar)
library(leafem)          # addGeoRaster (terra rasters in leaflet)
library(viridisLite)     # colour palettes for raster display
library(httr)            # CDSE OAuth2 token exchange
library(stars)           # stars rasters for ggplot2 / map export
library(ggplot2)         # already loaded via factoextra; explicit for map export
library(ggspatial)       # north arrow + scale bar in ggplot2 map layouts
library(patchwork)       # combine ggplots with / and | operators
# rstac, exactextractr used via requireNamespace() guards in their respective modules
# Install if needed:
#   install.packages(c("leaflet","leaflet.extras","leafem","viridisLite",
#                      "httr","stars","ggspatial","rstac","exactextractr"))

# Shared stateless helpers + plotting engines.
source("helpers.R")
source("evaluation_function.R")  # uef_evaluation() for LiDAR model evaluation

# Shared green theme used across the whole app.
app_theme <- bs_theme(
  preset   = "zephyr",
  primary  = "#2e7d32",
  secondary = "#4caf50",
  success  = "#4caf50",
  info     = "#4caf50"
)

# --- Modules are sourced here as we add them back, one at a time ---
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
