# algorithms.R -- the PROCESSING ALGORITHM registry
#
# One entry per operation, in the QGIS Processing sense: you search for the
# thing you want to make ("DTM"), fill in a couple of parameters, press Run, and
# the result lands in the project as a layer on the map.
#
# This replaces bundling several operations behind a radio button inside one
# screen. "Surface models" used to offer DTM / DSM / CHM / nDSM that way, which
# meant you had to know that a DTM lives inside a screen called Surface models
# before you could make one -- and CHM existed there AND inside the LiDAR screen,
# with the same lidR call in both places.
#
# Each entry is data, not UI. `mod_algo.R` renders the panel and runs it, and
# `mod_workspace.R` turns every entry into its own searchable tool. Adding an
# operation means adding a list here and nothing else.
#
# Spec fields
#   id       unique key; the tool key becomes "algo_<id>"
#   label    what the menu and the search box show
#   group    menu group it appears under
#   summary  one line shown at the top of the panel
#   inputs   list of ea_in(): each is a layer picked from a pool
#   params   list of ea_num()/ea_txt()/ea_sel(): plain values
#   output   ea_out(): which pool the result goes to, and the default name
#   run      function(inp, p) -> the result object. `inp` holds the chosen
#            layers by key, `p` the parameter values by key. Throw to fail --
#            mod_algo.R reports the message.

# `multiple = TRUE` lets one input take several layers at once (mosaic needs 2+);
# `run` then receives a LIST of layers under that key instead of one object.
ea_in  <- function(key, label, pool, hint = NULL, multiple = FALSE)
  list(key = key, label = label, pool = pool, hint = hint, multiple = multiple)

ea_num <- function(key, label, value, min = NA, max = NA, step = NA, hint = NULL)
  list(kind = "num", key = key, label = label, value = value,
       min = min, max = max, step = step, hint = hint)

ea_txt <- function(key, label, value = "", hint = NULL, rows = 1)
  list(kind = "txt", key = key, label = label, value = value, hint = hint, rows = rows)

ea_sel <- function(key, label, choices, value = NULL, hint = NULL)
  list(kind = "sel", key = key, label = label, choices = choices,
       value = value %||% unname(choices)[1], hint = hint)

# A BAND picker: its choices are the band names of whichever raster is chosen for
# input `from`, so a Sentinel-2 stack shows its real band names rather than
# asking the user to remember that NIR is number 4. `value` is the band index to
# preselect, clamped to the layer's band count. Rendered reactively, so it can
# only exist as a separate UI block from the static parameters.
ea_band <- function(key, label, from, value = 1L, hint = NULL)
  list(kind = "band", key = key, label = label, from = from,
       value = value, hint = hint)

# A FIELD picker: the attribute columns of whichever vector layer is chosen for
# input `from`. `blank` adds an empty first choice with that label.
ea_field <- function(key, label, from, blank = NULL, hint = NULL)
  list(kind = "field", key = key, label = label, from = from,
       blank = blank, hint = hint)

ea_out <- function(pool, default) list(pool = pool, default = default)

# Comma-separated numbers -> numeric vector, with a fallback when the field is
# empty or unparseable. Used by the pitfree thresholds.
.ea_nums <- function(txt, fallback) {
  v <- suppressWarnings(as.numeric(trimws(unlist(strsplit(txt %||% "", ",")))))
  v <- v[!is.na(v)]
  if (length(v)) v else fallback
}

ea_algorithms <- function() {
  algs <- list(

    # ---- Surfaces from a point cloud ------------------------------------
    list(
      id = "dtm", label = "DTM (Digital Terrain Model)", group = "Surfaces & LiDAR",
      summary = "Bare-earth elevation, interpolated from ground returns (TIN).",
      inputs = list(ea_in("las", "Point cloud", "las")),
      params = list(ea_num("res", "Resolution (m)", 1, 0.1, 5, 0.1)),
      output = ea_out("raster", "DTM"),
      run = function(inp, p)
        lidR::rasterize_terrain(inp$las, res = p$res, algorithm = lidR::tin())
    ),

    list(
      id = "dsm", label = "DSM (Digital Surface Model)", group = "Surfaces & LiDAR",
      summary = "Top-of-surface elevation, highest return per cell (points-to-raster).",
      inputs = list(ea_in("las", "Point cloud", "las")),
      params = list(ea_num("res", "Resolution (m)", 1, 0.1, 5, 0.1)),
      output = ea_out("raster", "DSM"),
      run = function(inp, p)
        lidR::rasterize_canopy(inp$las, res = p$res, algorithm = lidR::p2r())
    ),

    list(
      id = "chm", label = "CHM (Canopy Height Model)", group = "Surfaces & LiDAR",
      summary = "Canopy height surface using the pit-free algorithm.",
      inputs = list(ea_in("las", "Point cloud", "las",
                          hint = "Normalize height first for a true canopy height.")),
      params = list(
        ea_num("res", "Resolution (m)", 0.5, 0.1, 5, 0.1),
        ea_txt("thresholds", "Pit-free thresholds (comma-separated)", "0, 5, 10, 15, 20, 25")),
      output = ea_out("raster", "CHM"),
      run = function(inp, p)
        lidR::rasterize_canopy(inp$las, res = p$res,
          algorithm = lidR::pitfree(thresholds = .ea_nums(p$thresholds, c(0, 5, 10, 15, 20, 25))))
    ),

    list(
      id = "ndsm", label = "nDSM (Normalized Surface Model)", group = "Surfaces & LiDAR",
      summary = "Height above ground: DSM minus DTM, computed in one pass.",
      inputs = list(ea_in("las", "Point cloud", "las")),
      params = list(ea_num("res", "Resolution (m)", 1, 0.1, 5, 0.1)),
      output = ea_out("raster", "nDSM"),
      run = function(inp, p) {
        dtm <- lidR::rasterize_terrain(inp$las, res = p$res, algorithm = lidR::tin())
        dsm <- lidR::rasterize_canopy(inp$las, res = p$res, algorithm = lidR::p2r())
        dsm - dtm
      }
    ),

    # ---- Detection on a surface -----------------------------------------
    list(
      id = "itd", label = "ITD (Individual Tree Detection)", group = "Surfaces & LiDAR",
      summary = "Locate treetops on a canopy height model with a local maximum filter.",
      inputs = list(ea_in("chm", "Canopy height model", "raster",
                          hint = "Any raster in the project - make one with the CHM tool.")),
      params = list(
        ea_num("a", "Window size: a", 1.2, 0, 20, 0.1,
               hint = "Search window is a + b x height^2."),
        ea_num("b", "Window size: b", 0.003, 0, 1, 0.001)),
      output = ea_out("vector", "Tree_tops"),
      run = function(inp, p) {
        f_win <- function(height) p$a + p$b * height^2
        tops <- lidR::locate_trees(inp$chm, lidR::lmf(f_win))
        if (!nrow(tops)) stop("No treetops found. Try a smaller window (lower a).")
        tops
      }
    )
  )

  algs <- c(algs, .ea_terrain_algs(), .ea_hydro_algs(),
            .ea_raster_algs(), .ea_vector_algs())
  ids <- vapply(algs, function(a) a$id, character(1))
  # Keyed by id: server.R binds one algoServer per name and keys the Co-Analyst
  # context off it, and a duplicate id would silently shadow an operation.
  if (anyDuplicated(ids))
    stop("algorithms.R: duplicate algorithm id(s): ",
         paste(unique(ids[duplicated(ids)]), collapse = ", "))
  stats::setNames(algs, ids)
}

# ==========================================================================
# Terrain derivatives -- ported verbatim from mod_terrain.R's switch().
# Each one used to be an option in a "Terrain Derivative" dropdown inside one
# screen; the terra calls below are unchanged. That module also did
# `names(result) <- out_nm` to label the band in the map legend -- mod_algo.R now
# does that for every single-band raster result, so it is not repeated here.
# ==========================================================================
.ea_terrain_algs <- function() {
  dem <- function() list(ea_in("dem", "DEM (input raster)", "raster"))
  mk <- function(id, label, summary, run, params = list(), default = NULL)
    list(id = id, label = label, group = "Terrain", summary = summary,
         inputs = dem(), params = params,
         output = ea_out("raster", default %||% toupper(id)), run = run)

  # terra::terrain() name -> our entry, for the ones that take no extra options.
  # NOTE: curvature is NOT in this list. mod_terrain.R offered "Profile Curvature"
  # and "Plan Curvature" as terra::terrain(dem, "profc"/"planc"), but terra has no
  # curvature variable at all -- it supports only slope, aspect, TPI, TRI,
  # TRIriley, TRIrmsd, roughness and flowdir, so picking either of those two
  # options always errored. They are computed properly below instead.
  plain <- list(
    c("tpi",       "TPI (Topographic Position Index)",
                   "Cell height relative to its neighbourhood."),
    c("tri",       "TRI (Terrain Ruggedness Index)",
                   "Mean elevation difference to neighbouring cells."),
    c("roughness", "Roughness", "Elevation range within the neighbourhood."))
  tname <- c(tpi = "TPI", tri = "TRI", roughness = "roughness")
  dname <- c(tpi = "TPI", tri = "TRI", roughness = "Roughness")
  out <- lapply(plain, function(x) {
    id <- x[1]
    local({
      tn <- tname[[id]]
      mk(id, x[2], x[3], function(inp, p) terra::terrain(inp$dem, tn),
         default = dname[[id]])
    })
  })

  c(out, list(
    mk("slope_deg", "Slope (degrees)", "Steepness in degrees.", default = "Slope_deg",
       run = function(inp, p) terra::terrain(inp$dem, "slope", unit = "degrees")),

    mk("slope_pct", "Slope (percent rise)", "Steepness as percent rise.", default = "Slope_pct",
       run = function(inp, p) tan(terra::terrain(inp$dem, "slope", unit = "radians")) * 100),

    mk("aspect", "Aspect", "Downslope compass direction, in degrees.", default = "Aspect",
       run = function(inp, p) terra::terrain(inp$dem, "aspect", unit = "degrees")),

    mk("hillshade", "Hillshade", "Shaded relief for a given sun position.", default = "Hillshade",
       params = list(
         ea_num("alt",  "Sun altitude (degrees)", 45,  0, 90,  5),
         ea_num("azim", "Sun azimuth (degrees)",  315, 0, 360, 5)),
       run = function(inp, p) {
         sl <- terra::terrain(inp$dem, "slope",  unit = "radians")
         as <- terra::terrain(inp$dem, "aspect", unit = "radians")
         terra::shade(sl, as, angle = as.numeric(p$alt), direction = as.numeric(p$azim))
       }),

    mk("profc", "Profile curvature",
       "Curvature along the slope: negative where the slope steepens (Zevenbergen & Thorne).",
       default = "ProfCurv",
       run = function(inp, p) .ea_curvature(inp$dem, "profile")),

    mk("planc", "Plan curvature",
       "Curvature across the slope: positive on ridges, negative in hollows.",
       default = "PlanCurv",
       run = function(inp, p) .ea_curvature(inp$dem, "plan"))
  ))
}

# Zevenbergen & Thorne (1987) curvature. terra has no curvature variable, so this
# is computed from the 3x3 partial derivatives directly. Each of D,E,F,G,H is a
# LINEAR combination of the nine cells, so each is one focal() with an explicit
# weight matrix -- that way nothing depends on the order terra would hand window
# values to a callback.
#
# Verified against analytic surfaces: for z = a(x^2 + y^2) this returns exactly
# -2a (profile) and +2a (plan) with sd ~1e-16; a saddle straddles zero; a plane
# gives ~0.
.ea_curvature <- function(dem, which = c("profile", "plan")) {
  which <- match.arg(which)
  L <- mean(terra::res(dem))
  wt <- list(
    D = matrix(c(0,0,0, 0.5,-1,0.5, 0,0,0), 3, 3, byrow = TRUE) / L^2,
    E = matrix(c(0,0.5,0, 0,-1,0, 0,0.5,0), 3, 3, byrow = TRUE) / L^2,
    F = matrix(c(-1,0,1, 0,0,0, 1,0,-1), 3, 3, byrow = TRUE) / (4 * L^2),
    G = matrix(c(0,0,0, -1,0,1, 0,0,0), 3, 3, byrow = TRUE) / (2 * L),
    H = matrix(c(0,1,0, 0,0,0, 0,-1,0), 3, 3, byrow = TRUE) / (2 * L))
  z <- lapply(wt, function(w) terra::focal(dem, w = w, fun = "sum", na.policy = "omit"))
  denom <- z$G^2 + z$H^2
  r <- if (identical(which, "profile"))
    -2 * (z$D * z$G^2 + z$E * z$H^2 + z$F * z$G * z$H) / denom
  else
     2 * (z$D * z$H^2 + z$E * z$G^2 - z$F * z$G * z$H) / denom
  # Curvature is undefined on a perfectly flat cell (zero gradient): report 0
  # rather than letting the division produce NaN across flat ground.
  #
  # On the combination step: rewriting this as one block-wise terra::lapp() pass
  # to avoid the ~8 full-raster temporaries makes NO reliable difference. Median
  # of 3 reps on disk-backed DEMs: 1.4 M cells 2.76 s arithmetic vs 3.06 s lapp;
  # 6.2 M cells 9.35 s vs 8.74 s -- each wins once and the ranges overlap, so the
  # cost is dominated by the five focal() passes, not by how they are combined.
  # Left as arithmetic because it is the clearer expression of the formula. If
  # curvature needs to get genuinely faster, attack the focal passes.
  #
  # For scale when reading a bug report about this being slow: ~9 s at 6.2 M
  # cells, so a 50 M-cell DEM is over a minute. Slow, but finite.
  terra::ifel(denom < 1e-12, 0, r)
}

# ==========================================================================
# Hydrology -- ported verbatim from mod_hydro.R.
# The summaries repeat the caveats that module's own comments carry: TWI and
# slope x area here use CELL AREA as the contributing area, with no flow
# routing, so they are rough. The whitebox pair does the real thing but needs
# that package installed.
# ==========================================================================
.ea_hydro_algs <- function() {
  dem <- function() list(ea_in("dem", "DEM (input raster)", "raster"))
  mk <- function(id, label, summary, run, params = list(), default)
    list(id = id, label = label, group = "Hydrology", summary = summary,
         inputs = dem(), params = params,
         output = ea_out("raster", default), run = run)

  list(
    mk("twi", "TWI (Topographic Wetness Index)",
       "Approximate: contributing area is the cell area, with no flow routing.",
       default = "TWI",
       run = function(inp, p) {
         sl <- terra::terrain(inp$dem, "slope", unit = "radians")
         ca <- prod(terra::res(inp$dem))
         log(ca / (tan(sl) + 1e-6))
       }),

    mk("flowdir", "Flow direction (D8)", "D8 flow direction from terra.",
       default = "FlowDir",
       run = function(inp, p) terra::terrain(inp$dem, "flowdir")),

    mk("streams", "Stream extraction (slope threshold)",
       "Marks cells steeper than the threshold. A slope proxy, not a channel network.",
       default = "Streams",
       params = list(ea_num("thr", "Slope threshold (degrees)", 8, 1, 30, 1)),
       run = function(inp, p)
         terra::terrain(inp$dem, "slope", unit = "degrees") >= as.numeric(p$thr)),

    mk("sca", "Slope x contributing area",
       "Approximate: contributing area is the cell area, with no flow routing.",
       default = "SCA",
       run = function(inp, p) {
         sl <- terra::terrain(inp$dem, "slope", unit = "radians")
         sl * prod(terra::res(inp$dem))
       }),

    mk("fill_wb", "Fill depressions (whitebox)",
       "True depression filling. Requires the whitebox package.",
       default = "Filled",
       run = function(inp, p) {
         if (!requireNamespace("whitebox", quietly = TRUE))
           stop("Package 'whitebox' is not installed. Run: install.packages('whitebox'); whitebox::install_whitebox()")
         din <- tempfile(fileext = ".tif"); dout <- tempfile(fileext = ".tif")
         terra::writeRaster(inp$dem, din, overwrite = TRUE)
         whitebox::wbt_fill_depressions(din, dout)
         terra::rast(dout)
       }),

    mk("flowacc_wb", "Flow accumulation (whitebox)",
       "Fills depressions, then D8 accumulation in cells. Requires whitebox.",
       default = "FlowAcc",
       run = function(inp, p) {
         if (!requireNamespace("whitebox", quietly = TRUE))
           stop("Package 'whitebox' is not installed. Run: install.packages('whitebox'); whitebox::install_whitebox()")
         din <- tempfile(fileext = ".tif"); dfill <- tempfile(fileext = ".tif")
         dout <- tempfile(fileext = ".tif")
         terra::writeRaster(inp$dem, din, overwrite = TRUE)
         whitebox::wbt_fill_depressions(din, dfill)
         whitebox::wbt_d8_flow_accumulation(dfill, dout, out_type = "cells")
         terra::rast(dout)
       })
  )
}

# ==========================================================================
# Raster operations -- ported from mod_raster.R's run_op switch().
#
# NOT ported, deliberately: "Crop to drawn shape". It reads rv$drawn, a polygon
# drawn on that module's own map, so it is a map INTERACTION rather than an
# operation over pool layers and has nothing to select here. It stays in
# mod_raster.R. "Clip to vector layer" below is the pool-driven equivalent.
#
# The four spectral indices were one dropdown with band pickers that changed
# with the choice; they are four tools now, which is what makes each findable.
# ==========================================================================
.ea_raster_algs <- function() {
  rin <- function(label = "Input raster") list(ea_in("r", label, "raster"))
  mk <- function(id, label, summary, run, inputs = rin(), params = list(),
                 pool = "raster", default)
    list(id = id, label = label, group = "Raster", summary = summary,
         inputs = inputs, params = params,
         output = ea_out(pool, default), run = run)

  # (NIR-Red)/(NIR+Red) and friends: same formulas as mod_raster.R, one tool each.
  idx <- function(id, label, formula, b1, b2, d1, d2) {
    mk(id, label, formula,
       params = list(ea_band("x", b1, "r", d1), ea_band("y", b2, "r", d2)),
       default = toupper(id),
       run = function(inp, p) {
         a <- inp$r[[as.integer(p$x)]]; b <- inp$r[[as.integer(p$y)]]
         (a - b) / (a + b)      # mod_algo.R names the band after the output layer
       })
  }

  list(
    mk("clip_vec", "Clip raster to vector layer",
       "Crops and masks the raster to a polygon layer, reprojecting it to match.",
       inputs = c(rin(), list(ea_in("v", "Clip polygons (vector layer)", "vector"))),
       default = "Clipped",
       run = function(inp, p) {
         v <- sf::st_transform(inp$v, terra::crs(inp$r))
         terra::crop(inp$r, terra::vect(v), mask = TRUE)
       }),

    mk("mosaic", "Mosaic rasters", "Merges several rasters into one.",
       inputs = list(ea_in("rs", "Rasters to merge", "raster", multiple = TRUE,
                           hint = "Pick at least two.")),
       default = "Mosaic",
       run = function(inp, p) {
         if (length(inp$rs) < 2) stop("Select at least 2 layers.")
         terra::mosaic(terra::sprc(unname(inp$rs)))
       }),

    mk("reproject", "Reproject raster", "Warps the raster to another CRS.",
       params = list(ea_txt("crs", "Target CRS", "EPSG:3067",
                            hint = "An EPSG code, PROJ string or WKT.")),
       default = "Reprojected",
       run = function(inp, p) {
         crs_str <- trimws(p$crs %||% "")
         if (!nzchar(crs_str)) stop("Enter a target CRS (e.g. EPSG:3067).")
         terra::project(inp$r, crs_str)
       }),

    mk("resample", "Resample resolution", "Resamples to a new cell size.",
       params = list(
         ea_num("res_x", "X resolution (map units)", 10, 1e-6, NA, 1),
         ea_num("res_y", "Y resolution (map units)", 10, 1e-6, NA, 1),
         ea_sel("method", "Method",
                c("bilinear", "near", "cubic", "cubicspline", "lanczos"))),
       default = "Resampled",
       run = function(inp, p) {
         tmpl <- terra::rast(ext = terra::ext(inp$r), crs = terra::crs(inp$r),
                             res = c(as.numeric(p$res_x), as.numeric(p$res_y)))
         terra::resample(inp$r, tmpl, method = p$method)
       }),

    mk("bandcalc", "Band calculator", "Arbitrary formula over the bands.",
       params = list(ea_txt("formula", "Formula", "(b4-b3)/(b4+b3)", rows = 2,
                            hint = "Refer to bands as b1, b2, ...")),
       default = "BandCalc",
       run = function(inp, p) {
         f <- trimws(p$formula %||% "")
         if (!nzchar(f)) stop("Enter a formula.")
         r <- inp$r
         env <- list2env(
           stats::setNames(lapply(seq_len(terra::nlyr(r)), function(i) r[[i]]),
                           paste0("b", seq_len(terra::nlyr(r)))),
           parent = globalenv())
         res <- eval(parse(text = f), envir = env)
         if (!inherits(res, "SpatRaster")) stop("Formula did not produce a raster.")
         res
       }),

    idx("ndvi", "NDVI (vegetation index)", "(NIR - Red) / (NIR + Red)",
        "NIR band", "Red band", 4L, 3L),
    idx("ndwi", "NDWI (water index)", "(Green - NIR) / (Green + NIR)",
        "Green band", "NIR band", 2L, 4L),
    idx("nbr",  "NBR (burn ratio)", "(NIR - SWIR) / (NIR + SWIR)",
        "NIR band", "SWIR band", 4L, 6L),
    idx("ndre", "NDRE (red-edge index)", "(RedEdge - Red) / (RedEdge + Red)",
        "RedEdge band", "Red band", 5L, 3L),

    # The one algorithm here whose output is a TABLE, not a layer: it lands in
    # the data view rather than on the map.
    mk("zonal", "Zonal statistics",
       "Summarises raster values inside each polygon. Result is a table.",
       inputs = c(rin(), list(ea_in("v", "Zone polygons (vector layer)", "vector"))),
       params = list(
         ea_sel("stat", "Summary statistic",
                c("mean", "sum", "min", "max", "sd", "count", "median")),
         ea_field("id_col", "Zone ID column", "v", blank = "(use row number)")),
       pool = "table", default = "zonal_stats",
       run = function(inp, p) {
         if (!requireNamespace("exactextractr", quietly = TRUE))
           stop("Install 'exactextractr' for zonal statistics.")
         zones <- sf::st_transform(inp$v, terra::crs(inp$r))
         stat <- exactextractr::exact_extract(inp$r[[1]], zones,
                                              fun = p$stat, progress = FALSE)
         id <- trimws(p$id_col %||% "")
         df <- if (nzchar(id) && id %in% names(sf::st_drop_geometry(zones)))
                 data.frame(zone = sf::st_drop_geometry(zones)[[id]], value = stat)
               else data.frame(zone_id = seq_along(stat), value = stat)
         colnames(df)[2] <- paste0(p$stat, "_value")
         df
       })
  )
}

# ==========================================================================
# Vector operations -- ported from mod_raster.R's run_vec_op switch().
#
# NOT ported, deliberately: "Clip to drawn shape", for the same reason as the
# raster crop above -- it needs a polygon drawn on the map, not a pool layer.
# ==========================================================================
.ea_vector_algs <- function() {
  vin <- function() list(ea_in("v", "Input vector layer", "vector"))
  mk <- function(id, label, summary, run, params = list(), default)
    list(id = id, label = label, group = "Vector", summary = summary,
         inputs = vin(), params = params,
         output = ea_out("vector", default), run = run)

  list(
    mk("buffer", "Buffer", "Grows each feature by a fixed distance.",
       params = list(ea_num("dist", "Distance (map units)", 100, 0, NA, 10,
                            hint = "Units follow the layer CRS - metres for EPSG:3067.")),
       default = "Buffer",
       run = function(inp, p) sf::st_buffer(inp$v, dist = as.numeric(p$dist))),

    mk("dissolve", "Dissolve", "Merges features, optionally grouped by a field.",
       params = list(ea_field("by", "Dissolve by field", "v",
                              blank = "(merge everything)")),
       default = "Dissolved",
       run = function(inp, p) {
         v <- inp$v; by <- p$by %||% ""
         if (nzchar(by) && by %in% names(sf::st_drop_geometry(v))) {
           grps <- split(seq_len(nrow(v)), sf::st_drop_geometry(v)[[by]])
           parts <- lapply(names(grps), function(g)
             sf::st_sf(data.frame(stats::setNames(list(g), by), stringsAsFactors = FALSE),
                       geometry = sf::st_union(v[grps[[g]], ])))
           do.call(rbind, parts)
         } else sf::st_sf(geometry = sf::st_union(v))
       }),

    mk("centroid", "Centroids", "One point per feature, at its centre.",
       default = "Centroids",
       run = function(inp, p) sf::st_centroid(inp$v))
  )
}
