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

ea_in  <- function(key, label, pool, hint = NULL)
  list(key = key, label = label, pool = pool, hint = hint)

ea_num <- function(key, label, value, min = NA, max = NA, step = NA, hint = NULL)
  list(kind = "num", key = key, label = label, value = value,
       min = min, max = max, step = step, hint = hint)

ea_txt <- function(key, label, value = "", hint = NULL)
  list(kind = "txt", key = key, label = label, value = value, hint = hint)

ea_sel <- function(key, label, choices, value = NULL, hint = NULL)
  list(kind = "sel", key = key, label = label, choices = choices,
       value = value %||% unname(choices)[1], hint = hint)

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

  stats::setNames(algs, vapply(algs, function(a) a$id, character(1)))
}
