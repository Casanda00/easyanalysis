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

# `show_if` is a JS condition (as for conditionalPanel) that hides a parameter
# until it applies -- polynomial degree only matters for a polynomial kernel.
# mod_algo.R ignores it; mod_stat.R honours it. Kept on the shared constructors
# so both registries take exactly the same parameter shapes.
ea_num <- function(key, label, value, min = NA, max = NA, step = NA, hint = NULL,
                   show_if = NULL)
  list(kind = "num", key = key, label = label, value = value,
       min = min, max = max, step = step, hint = hint, show_if = show_if)

ea_txt <- function(key, label, value = "", hint = NULL, rows = 1, show_if = NULL)
  list(kind = "txt", key = key, label = label, value = value, hint = hint,
       rows = rows, show_if = show_if)

ea_sel <- function(key, label, choices, value = NULL, hint = NULL, show_if = NULL)
  list(kind = "sel", key = key, label = label, choices = choices,
       value = value %||% unname(choices)[1], hint = hint, show_if = show_if)

# A searchable CRS selector with typeahead matching for global, regional, and UTM EPSGs.
# Supports custom entry (create = TRUE) for any EPSG code, PROJ string, or WKT.
ea_crs <- function(key, label = "Target CRS (EPSG / PROJ / WKT)", value = "EPSG:4326", hint = NULL)
  list(kind = "crs", key = key, label = label, value = value, hint = hint)

# --- The CRS catalogue, read once from GDAL/PROJ's own proj.db -------------
#
# Every usable EPSG entry, not a curated shortlist. `vertical` and `engineering`
# are excluded because they cannot serve as a horizontal target CRS; everything
# else (projected, geographic 2D/3D, geocentric, compound) is offered -- 6,886
# entries against the 8 the built-in fallback can name.
#
# Cached for the life of the process: the query costs one SQLite read, and the
# app builds five CRS pickers.
.ea_crs_cache <- new.env(parent = emptyenv())

ea_crs_all <- function() {
  if (!is.null(.ea_crs_cache$all)) return(.ea_crs_cache$all)

  db_path <- tryCatch(
    file.path(system.file("proj", package = "sf"), "proj.db"),
    error = function(e) ""
  )
  if (!file.exists(db_path) || !requireNamespace("RSQLite", quietly = TRUE))
    return(.ea_crs_choices_fallback())

  con <- tryCatch(RSQLite::dbConnect(RSQLite::SQLite(), db_path), error = function(e) NULL)
  if (is.null(con)) return(.ea_crs_choices_fallback())
  on.exit(try(RSQLite::dbDisconnect(con), silent = TRUE), add = TRUE)

  df <- tryCatch(RSQLite::dbGetQuery(con,
    "SELECT code, name FROM crs_view
     WHERE auth_name = 'EPSG' AND deprecated = 0
       AND type IN ('projected','geographic 2D','geographic 3D','geocentric','compound')
     ORDER BY CASE WHEN code IN ('4326','3857','3067','4269','4258','25832','25833','32632')
                   THEN 0 ELSE 1 END,
              CAST(code AS INTEGER) ASC"), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(.ea_crs_choices_fallback())

  out <- stats::setNames(sprintf("EPSG:%s", df$code),
                         sprintf("EPSG:%s - %s", df$code, df$name))
  .ea_crs_cache$all <- out
  out
}

# Programmatic search over the catalogue (the Co-Analyst and any non-UI caller).
# Matching is TOKENISED and conjunctive: every whitespace-separated token must
# appear somewhere in "EPSG:<code> - <name>". A single substring test cannot do
# this -- LIKE '%utm 35n%' matches nothing, because the real name is
# "WGS 84 / UTM zone 35N". Tokenising finds it, and the same rule covers a bare
# code, a name, or any mixture of the two.
ea_search_crs <- function(query = "", limit = 100) {
  all <- ea_crs_all()
  q <- trimws(query %||% "")
  if (!nzchar(q)) return(utils::head(all, limit))

  key <- unique(strsplit(tolower(q), "\\s+")[[1]])
  key <- key[nzchar(key)]
  lab <- tolower(names(all))
  hit <- Reduce(`&`, lapply(key, function(k) grepl(k, lab, fixed = TRUE)))

  if (!any(hit)) {
    # Not in the catalogue -- let the user's own entry through rather than
    # silently offering nothing (selectize's create = TRUE accepts it).
    val <- if (grepl("^[0-9]+$", q)) paste0("EPSG:", q) else q
    return(stats::setNames(val, paste("Custom CRS:", q)))
  }
  utils::head(all[hit], limit)
}

# Attach the catalogue to a selectize picker as a SERVER-SIDE data source.
#
# Server-side is not a micro-optimisation here, it is the only workable option:
# embedding 6,886 entries client-side costs ~509 KB PER picker and the app builds
# five of them, which Shiny itself warns against. It also buys the tokenised AND
# matching described above -- Shiny's search server splits the typed query on
# whitespace and requires every token to match.
#
# `deferred = TRUE` is for a picker created inside renderUI: an update aimed at
# an element that does not exist yet is silently DROPPED (CLAUDE.md gotcha 18),
# so the attach is postponed to onFlushed, which runs after outputs have reached
# the client and the element is really there.
ea_crs_selectize <- function(session, input_id, selected = "EPSG:4326",
                             deferred = FALSE) {
  attach <- function() {
    updateSelectizeInput(
      session, input_id, choices = ea_crs_all(), selected = selected,
      server = TRUE,
      options = list(create = TRUE, createOnBlur = TRUE,
                     searchConjunction = "and", maxOptions = 200,
                     placeholder = "Search EPSG code or CRS name...")
    )
  }
  if (deferred) session$onFlushed(attach, once = TRUE) else attach()
}

# The choices a CRS picker is BUILT with. Deliberately tiny: the real catalogue
# arrives from ea_crs_selectize() over the server-side channel. Seeding it with
# the current value keeps the picker showing its selection before that lands.
.ea_crs_choices <- function(selected = NULL) {
  seed <- .ea_crs_choices_fallback()
  if (!is.null(selected) && nzchar(selected) && !selected %in% seed)
    seed <- c(stats::setNames(selected, selected), seed)
  seed
}

.ea_crs_choices_fallback <- function() {
  c(
    "EPSG:4326 - WGS 84 (Geographic Lat/Lon)" = "EPSG:4326",
    "EPSG:3857 - WGS 84 / Pseudo-Mercator (Web Mercator)" = "EPSG:3857",
    "EPSG:3067 - ETRS89 / TM35FIN (Finland Transverse Mercator)" = "EPSG:3067",
    "EPSG:4269 - NAD83 (North America)" = "EPSG:4269",
    "EPSG:4258 - ETRS89 (Europe)" = "EPSG:4258",
    "EPSG:25832 - ETRS89 / UTM zone 32N" = "EPSG:25832",
    "EPSG:25833 - ETRS89 / UTM zone 33N" = "EPSG:25833",
    "EPSG:32632 - WGS 84 / UTM zone 32N" = "EPSG:32632"
  )
}

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
       params = list(ea_crs("crs", "Target CRS", "EPSG:3067",
                            hint = "Search CRS name or EPSG code (e.g. EPSG:3067, EPSG:4326, EPSG:3857, EPSG:32635). Custom entries supported.")),
       default = "Reprojected",
       run = function(inp, p) {
         crs_raw <- trimws(p$crs %||% "")
         if (!nzchar(crs_raw)) stop("Enter or select a target CRS (e.g. EPSG:3067).")
         crs_val <- if (grepl("^[0-9]+$", crs_raw)) paste0("EPSG:", crs_raw) else crs_raw
         terra::project(inp$r, crs_val)
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

    mk("focal_mean", "Focal Mean Filter", "Smooths raster cell values using a moving window mean.",
       params = list(ea_num("size", "Window size (cells)", 3, 3, 21, 2)),
       default = "Focal_Mean",
       run = function(inp, p) {
         sz <- as.integer(p$size); if (sz %% 2 == 0) sz <- sz + 1L
         w <- matrix(1, sz, sz)
         terra::focal(inp$r, w = w, fun = "mean", na.policy = "omit")
       }),

    mk("focal_sd", "Focal Standard Deviation Filter", "Computes local variance/SD using a moving window.",
       params = list(ea_num("size", "Window size (cells)", 3, 3, 21, 2)),
       default = "Focal_SD",
       run = function(inp, p) {
         sz <- as.integer(p$size); if (sz %% 2 == 0) sz <- sz + 1L
         w <- matrix(1, sz, sz)
         terra::focal(inp$r, w = w, fun = "sd", na.policy = "omit")
       }),

    mk("rast_mask_range", "Mask Value Range", "Masks out raster cells outside a specified min and max range.",
       params = list(ea_num("min_val", "Min Value", 0, NA, NA, 1),
                     ea_num("max_val", "Max Value", 100, NA, NA, 1)),
       default = "Masked_Raster",
       run = function(inp, p) {
         r <- inp$r
         min_v <- as.numeric(p$min_val); max_v <- as.numeric(p$max_val)
         terra::clamp(r, lower = min_v, upper = max_v, values = FALSE)
       }),

    mk("rast_reclass", "Reclassify Raster", "Reclassifies raster values into discrete numeric classes.",
       params = list(ea_txt("rcl", "Reclass matrix (from, to, new_val; comma-separated)", "0,10,1, 10,50,2, 50,100,3")),
       default = "Reclassified_Raster",
       run = function(inp, p) {
         txt <- trimws(p$rcl %||% "")
         vals <- suppressWarnings(as.numeric(trimws(unlist(strsplit(txt, ",")))))
         vals <- vals[!is.na(vals)]
         if (length(vals) %% 3 != 0) stop("Reclass matrix values must be multiples of 3 (from, to, new_val).")
         rcl_mat <- matrix(vals, ncol = 3, byrow = TRUE)
         terra::classify(inp$r, rcl_mat)
       }),

    mk("las_metrics_grid_algo", "LiDAR Structural Metrics Grid", "Computes canopy metrics (mean Z, P95, density) across cells.",
       inputs = list(ea_in("las", "Point cloud", "las")),
       params = list(ea_num("res", "Grid Resolution (m)", 10, 1, 50, 1)),
       default = "LiDAR_Metrics",
       run = function(inp, p) {
         res_val <- as.numeric(p$res)
         lidR::pixel_metrics(inp$las, ~list(mean_z = mean(Z), p95 = quantile(Z, 0.95), count = length(Z)), res = res_val)
       })
  )
}

# ==========================================================================
# Vector operations -- ported from mod_raster.R's run_vec_op switch().
# ==========================================================================
.ea_vector_algs <- function() {
  vin <- function() list(ea_in("v", "Input vector layer", "vector"))
  mk <- function(id, label, summary, run, params = list(), default, inputs = vin(), pool = "vector")
    list(id = id, label = label, group = "Vector", summary = summary,
         inputs = inputs, params = params,
         output = ea_out(pool, default), run = run)

  list(
    mk("xy_to_sf", "XY Coordinates to Vector", "Converts tabular X and Y coordinate columns to a spatial point layer.",
       inputs = list(ea_in("tbl", "Tabular dataset", "table")),
       params = list(
         ea_field("x_col", "X Coordinate Column (Easting/Lon)", "tbl"),
         ea_field("y_col", "Y Coordinate Column (Northing/Lat)", "tbl"),
         ea_crs("crs", "Target CRS", "EPSG:4326",
                hint = "Search CRS name or EPSG code (e.g. EPSG:4326 WGS84, EPSG:3067 TM35FIN, EPSG:3857 Web Mercator).")
       ),
       default = "Points_Layer",
       run = function(inp, p) {
         df <- inp$tbl; x <- p$x_col %||% ""; y <- p$y_col %||% ""
         if (!nzchar(x) || !nzchar(y)) stop("Select valid X and Y coordinate columns.")
         crs_raw <- trimws(p$crs %||% "EPSG:4326")
         crs_val <- if (grepl("^[0-9]+$", crs_raw)) paste0("EPSG:", crs_raw) else crs_raw
         sf::st_as_sf(df, coords = c(x, y), crs = crs_val, remove = FALSE)
       }),

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
       run = function(inp, p) sf::st_centroid(inp$v)),

    mk("vec_reproject", "Reproject Vector", "Reprojects a vector layer into a target CRS.",
       params = list(ea_crs("crs", "Target CRS", "EPSG:3067",
                            hint = "Search CRS name or EPSG code (e.g. EPSG:3067, EPSG:4326, EPSG:3857, EPSG:32635). Custom entries supported.")),
       default = "Reprojected_Vector",
       run = function(inp, p) {
         crs_raw <- trimws(p$crs %||% "")
         if (!nzchar(crs_raw)) stop("Enter a target CRS.")
         crs_val <- if (grepl("^[0-9]+$", crs_raw)) paste0("EPSG:", crs_raw) else crs_raw
         sf::st_transform(inp$v, crs_val)
       }),

    mk("vec_clip", "Clip Vector by Polygon", "Intersects vector features with a polygon boundary.",
       inputs = list(ea_in("v", "Vector layer to clip", "vector"),
                     ea_in("mask", "Clipping polygon", "vector")),
       default = "Clipped_Vector",
       run = function(inp, p) {
         m <- sf::st_transform(inp$mask, sf::st_crs(inp$v))
         sf::st_intersection(inp$v, m)
       }),

    mk("vec_bbox", "Bounding Box Polygon", "Computes the minimum bounding box polygon around a vector layer.",
       default = "Bounding_Box",
       run = function(inp, p) {
         bb <- sf::st_bbox(inp$v)
         sf::st_as_sfc(bb)
       }),

    mk("vec_convex_hull", "Convex Hull", "Computes the minimum convex polygon enclosing geometries.",
       default = "Convex_Hull",
       run = function(inp, p) {
         sf::st_sf(geometry = sf::st_convex_hull(sf::st_union(inp$v)))
       }),

    mk("vec_simplify", "Simplify Geometries", "Reduces vertex density while preserving general shapes.",
       params = list(ea_num("tol", "Tolerance distance (map units)", 5, 0.1, 1000, 1)),
       default = "Simplified_Vector",
       run = function(inp, p) {
         sf::st_simplify(inp$v, dTolerance = as.numeric(p$tol))
       }),

    mk("vec_spatial_join", "Spatial Join", "Joins attributes from a second vector layer based on spatial overlap.",
       inputs = list(ea_in("v", "Target vector layer", "vector"),
                     ea_in("join_layer", "Source vector layer", "vector")),
       default = "Spatially_Joined",
       run = function(inp, p) {
         j <- sf::st_transform(inp$join_layer, sf::st_crs(inp$v))
         sf::st_join(inp$v, j)
       }),

    mk("point_density", "Point Density Heatmap", "Computes a continuous point density raster grid from points.",
       params = list(ea_num("res", "Grid Resolution (m)", 10, 1, 500, 5)),
       default = "Point_Density",
       run = function(inp, p) {
         v <- inp$v; res_val <- as.numeric(p$res)
         v_terra <- terra::vect(v)
         r_tmpl <- terra::rast(terra::ext(v_terra), res = res_val, crs = terra::crs(v_terra))
         terra::rasterize(v_terra, r_tmpl, fun = "length", background = 0)
       }),

    mk("rast_dist_vector", "Distance to Vector Features", "Computes raster grid of distance to nearest vector geometry.",
       inputs = list(ea_in("v", "Input vector layer", "vector"), ea_in("r_ref", "Reference raster extent", "raster")),
       params = list(),
       default = "Distance_To_Vector",
       run = function(inp, p) {
         v_terra <- terra::vect(sf::st_transform(inp$v, terra::crs(inp$r_ref)))
         terra::distance(inp$r_ref, v_terra)
       }),

    mk("multidir_hillshade", "Multidirectional Hillshade", "Computes multidirectional hillshade composite.",
       inputs = list(ea_in("dem", "DEM (input raster)", "raster")),
       params = list(ea_num("alt", "Sun altitude", 45, 0, 90, 5)),
       default = "Multidir_Hillshade",
       run = function(inp, p) {
         sl <- terra::terrain(inp$dem, "slope", unit = "radians")
         as <- terra::terrain(inp$dem, "aspect", unit = "radians")
         h1 <- terra::shade(sl, as, angle = as.numeric(p$alt), direction = 225)
         h2 <- terra::shade(sl, as, angle = as.numeric(p$alt), direction = 315)
         (h1 + h2) / 2
       }),

    mk("las_normalize_algo", "Normalize Point Cloud Heights", "Subtracts ground elevation from point cloud Z coordinates.",
       inputs = list(ea_in("las", "Point cloud", "las"), ea_in("dtm", "Bare-earth DTM", "raster")),
       default = "Normalized_Cloud",
       pool = "las",
       run = function(inp, p) {
         lidR::normalize_height(inp$las, inp$dtm)
       }),

    mk("vec_area_length", "Geometry Area and Length", "Calculates polygon area (m2/ha) or line length.",
       inputs = list(ea_in("v", "Input vector layer", "vector")),
       default = "Geom_Metrics",
       pool = "table",
       run = function(inp, p) {
         v <- inp$v
         df <- sf::st_drop_geometry(v)
         df$geom_area_m2 <- as.numeric(sf::st_area(v))
         df$geom_area_ha <- df$geom_area_m2 / 10000
         df$geom_length_m <- as.numeric(sf::st_length(v))
         df
       }),

    mk("vec_points_along_line", "Generate Points Along Line", "Places equidistant sample points along line geometries.",
       inputs = list(ea_in("v", "Line vector layer", "vector")),
       params = list(ea_num("dist", "Spacing distance (map units)", 50, 1, 5000, 10)),
       default = "Sample_Points",
       run = function(inp, p) {
         sf::st_line_sample(inp$v, density = 1 / as.numeric(p$dist))
       })
  )
}
