# ==========================================================================
# plugins.R -- external tool providers, opt-in and user-activated
# --------------------------------------------------------------------------
# WHY THIS EXISTS
#
# WhiteboxTools ships 484 algorithms. Hand-wrapping them would be 484 pieces of
# code that go stale on every WhiteboxTools release; registering them all at
# boot would be worse. Both costs are measured, not assumed:
#
#   * metadata      0.55 s per tool  ->  266 s to enumerate all 484
#   * module binding 33 ms per tool  ->   16 s added to EVERY session start
#
# So this file does two things. It GENERATES registry specs from the tool's own
# self-description rather than restating it, and it makes every external tool
# OPT-IN so nothing is registered, bound or paid for until a user asks for it.
#
# The opt-in half is not only performance. WhiteboxTools is somebody else's
# work -- Prof. John Lindsay's, wrapped for R by Qiusheng Wu and Andrew Brown
# (MIT). It strengthens this platform; it is not part of it. Enabling it should
# be a decision the user makes and can see, with the authors named.
#
# STATE lives at <home>/plugins/state.json, NOT in a project: activating a tool
# is a preference about this installation, not data about one analysis. A user
# who enables Watershed once expects it everywhere.
# ==========================================================================

.ea_plugin_dir <- function() file.path(ea_home(), "plugins")

# ---- activation state ----------------------------------------------------
# Shape: list(providers = c("whitebox"), tools = list(whitebox = c("Slope", ...)))
# A provider that is off hides its tools regardless of the per-tool list, so
# turning the whole thing off is one switch and never loses the per-tool picks.
.ea_state_path <- function() file.path(.ea_plugin_dir(), "state.json")

ea_plugin_state <- function() {
  p <- .ea_state_path()
  if (!file.exists(p)) return(list(providers = character(0), tools = list()))
  st <- tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE),
                 error = function(e) NULL)
  if (!is.list(st)) return(list(providers = character(0), tools = list()))
  list(providers = as.character(st$providers %||% character(0)),
       tools     = if (is.list(st$tools)) lapply(st$tools, as.character) else list())
}

ea_plugin_state_set <- function(st) {
  dir.create(.ea_plugin_dir(), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(.ea_state_path(), ".tmp")
  writeLines(jsonlite::toJSON(st, auto_unbox = TRUE, pretty = TRUE), tmp)
  file.rename(tmp, .ea_state_path())          # atomic, like the project store
  invisible(st)
}

ea_plugin_on <- function(provider) provider %in% ea_plugin_state()$providers

ea_plugin_set <- function(provider, on = TRUE) {
  st <- ea_plugin_state()
  st$providers <- if (on) union(st$providers, provider)
                  else setdiff(st$providers, provider)
  ea_plugin_state_set(st)
}

ea_tool_on <- function(provider, tool) {
  st <- ea_plugin_state()
  provider %in% st$providers && tool %in% (st$tools[[provider]] %||% character(0))
}

ea_tool_set <- function(provider, tool, on = TRUE) {
  st <- ea_plugin_state()
  cur <- st$tools[[provider]] %||% character(0)
  # Refuse to enable something that cannot become a tool. Hiding the button is
  # not enough: any other path here would otherwise store an activation that
  # silently produces nothing, which is indistinguishable from a broken app.
  if (on && identical(provider, "whitebox")) {
    e <- Filter(function(x) identical(x$name, tool), (ea_wbt_manifest() %||% list())$tools)
    if (length(e) && is.null(tryCatch(ea_wbt_spec(e[[1]]), error = function(err) NULL)))
      stop("'", tool, "' cannot be used here: it declares no output that can be ",
           "loaded as a layer.")
  }
  st$tools[[provider]] <- if (on) union(cur, tool) else setdiff(cur, tool)
  ea_plugin_state_set(st)
}

# ==========================================================================
# WhiteboxTools provider
# ==========================================================================

.ea_wbt_manifest_path <- function() file.path(.ea_plugin_dir(), "whitebox-manifest.json")

.ea_wbt_version <- function()
  tryCatch(paste(whitebox::wbt_version(), collapse = " "), error = function(e) "unknown")

# Build the catalogue ONCE. 484 tools x 0.55 s is 266 s, so this can never run
# at boot or on demand -- it is an explicit, progress-reported action, and the
# result is cached and keyed by the WhiteboxTools version so an upgrade rebuilds
# it and nothing else does.
ea_wbt_build_manifest <- function(progress = NULL, limit = NULL, only = NULL) {
  .ea_require_whitebox()
  raw <- whitebox::wbt_list_tools()
  raw <- raw[grepl(": ", raw, fixed = TRUE)]        # drop the "All N Tools" header
  nms <- sub(":.*$", "", raw)
  dsc <- trimws(sub("^[^:]*:", "", raw))
  # `only` builds a partial manifest for a named subset. Used by the checks --
  # a full build is ~8 minutes, which no test can pay.
  if (!is.null(only)) { keep <- nms %in% only; nms <- nms[keep]; dsc <- dsc[keep] }
  if (!is.null(limit)) { nms <- utils::head(nms, limit); dsc <- utils::head(dsc, limit) }

  out <- vector("list", length(nms))
  for (i in seq_along(nms)) {
    if (is.function(progress)) progress(i, length(nms), nms[i])
    pj <- tryCatch(whitebox::wbt_tool_parameters(nms[i]), error = function(e) NULL)
    prm <- if (is.null(pj)) list() else
      tryCatch(jsonlite::fromJSON(pj, simplifyVector = FALSE)$parameters,
               error = function(e) list())
    # Category comes from the tool itself. NOTE wbt_toolbox() with NO argument is
    # BROKEN in the R package -- it passes the executable path where a tool name
    # belongs and WhiteboxTools panics with "Unrecognized tool name ...exe". Per
    # tool it works fine, which is why this is captured here rather than fetched
    # once. It costs ~0.47 s on top of the ~0.55 s for parameters, so the whole
    # build is roughly 1 s per tool -- about 8 minutes for 484. Once, cached.
    tbx <- tryCatch(paste(whitebox::wbt_toolbox(nms[i]), collapse = " "),
                    error = function(e) "")
    out[[i]] <- list(name = nms[i], desc = dsc[i], toolbox = trimws(tbx), params = prm)
  }
  man <- list(version = .ea_wbt_version(), built = as.character(Sys.time()),
              tools = out)
  dir.create(.ea_plugin_dir(), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(.ea_wbt_manifest_path(), ".tmp")
  writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, null = "null"), tmp)
  file.rename(tmp, .ea_wbt_manifest_path())
  invisible(man)
}

# Build in the BACKGROUND. Indexing all 484 tools takes about 8 minutes, and
# Shiny is single-threaded -- an in-process build would freeze the entire app for
# that whole time, which is precisely what gotcha 29 is about. Even the 31
# featured tools would block for ~30 s.
#
# Returns a callr process the caller polls. Deliberately NOT compute_worker.R:
# that session is shaped around running one algorithm spec, and it preloads a
# heavy package set this does not need.
ea_wbt_build_async <- function(wd = getwd(), only = NULL) {
  if (!requireNamespace("callr", quietly = TRUE))
    stop("Background indexing needs the 'callr' package.")
  callr::r_bg(function(wd, home, only) {
    setwd(wd)
    Sys.setenv(EASYANALYSIS_HOME = home)
    suppressMessages({library(shiny); library(jsonlite)})
    source("helpers.R"); source("project_store.R")
    source("algorithms.R"); source("plugins.R")
    n <- 0L
    ea_wbt_build_manifest(only = only, progress = function(i, tot, nm) {
      # One line per tool on stdout: the caller reads it as a progress feed
      # without any shared state between the two processes.
      cat(sprintf("%d/%d %s
", i, tot, nm))
    })
    "done"
  }, args = list(wd = normalizePath(wd, winslash = "/"),
                 home = ea_home(), only = only),
     stdout = "|", stderr = "|", supervise = TRUE)
}

# Cached read. Returns NULL when absent or built against a different
# WhiteboxTools version -- the caller decides whether to rebuild, because
# rebuilding takes minutes and must never happen behind the user's back.
.ea_wbt_cache <- new.env(parent = emptyenv())
ea_wbt_manifest <- function(check_version = TRUE) {
  if (!is.null(.ea_wbt_cache$man)) return(.ea_wbt_cache$man)
  p <- .ea_wbt_manifest_path()
  if (!file.exists(p)) return(NULL)
  man <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(man) || !length(man$tools)) return(NULL)
  if (check_version && !identical(man$version, .ea_wbt_version())) return(NULL)
  .ea_wbt_cache$man <- man
  man
}
ea_wbt_manifest_clear <- function() { rm(list = ls(.ea_wbt_cache), envir = .ea_wbt_cache)
                                      invisible(TRUE) }

# ---- the type mapper -----------------------------------------------------
# WhiteboxTools' parameter_type vocabulary is small and closed. Measured across
# a sample spanning hydrology, terrain, raster and LiDAR, it is these eight
# cases -- and an OptionList carries its own choices, so nothing is hardcoded.
.ea_wbt_kind <- function(pt) {
  if (is.list(pt)) {
    k <- names(pt)[1]; v <- as.character(unlist(pt)[1])
    if (identical(k, "ExistingFile") || identical(k, "ExistingFileOrFloat"))
      return(list(role = "in", pool = switch(v, Raster = "raster", Lidar = "las",
                                             Vector = "vector", Point = "vector",
                                             Csv = "table", Text = "table", "raster")))
    if (identical(k, "NewFile"))
      return(list(role = "out", pool = switch(v, Raster = "raster", Lidar = "las",
                                              Vector = "vector", Html = "table", "raster")))
    if (identical(k, "OptionList"))
      return(list(role = "sel", choices = as.character(unlist(pt))))
    if (identical(k, "Directory")) return(list(role = "skip"))
    return(list(role = "skip"))
  }
  switch(as.character(pt),
    Float = , Integer = list(role = "num"),
    Boolean = list(role = "bool"),
    String = , StringOrNumber = list(role = "txt"),
    list(role = "skip"))
}

# One manifest entry -> one registry spec. The `run` closure is IDENTICAL for
# every tool, because WhiteboxTools is uniformly file-based: inputs are written
# to temp files, flags are assembled from the params, the executable does the
# work, and the output file is read back. That is why 484 tools need no
# per-tool code at all.
ea_wbt_spec <- function(entry) {
  inputs <- list(); params <- list(); outp <- NULL; flagmap <- list()
  usedk  <- character(0)
  key_of <- function(flags, nm) {
    f <- flags[grepl("^--", flags)]
    k <- gsub("^--", "", if (length(f)) f[1] else nm)
    k <- gsub("[^A-Za-z0-9]+", "_", k)
    while (k %in% usedk) k <- paste0(k, "_2")
    usedk <<- c(usedk, k); k
  }
  for (q in entry$params) {
    kd <- .ea_wbt_kind(q$parameter_type)
    if (identical(kd$role, "skip")) next
    fl <- as.character(unlist(q$flags))
    lb <- q$name %||% fl[1]
    k  <- key_of(fl, lb)
    dv <- q$default_value
    if (identical(kd$role, "in")) {
      inputs[[length(inputs) + 1]] <- ea_in(k, lb, kd$pool)
      flagmap[[k]] <- list(flag = fl[1], role = "in")
    } else if (identical(kd$role, "out")) {
      if (is.null(outp)) { outp <- ea_out(kd$pool, entry$name)
                           flagmap[[k]] <- list(flag = fl[1], role = "out") }
    } else if (identical(kd$role, "num")) {
      params[[length(params) + 1]] <-
        ea_num(k, lb, value = suppressWarnings(as.numeric(dv %||% NA)))
      flagmap[[k]] <- list(flag = fl[1], role = "p")
    } else if (identical(kd$role, "sel")) {
      params[[length(params) + 1]] <- ea_sel(k, lb, kd$choices,
                                             value = dv %||% kd$choices[1])
      flagmap[[k]] <- list(flag = fl[1], role = "p")
    } else if (identical(kd$role, "bool")) {
      params[[length(params) + 1]] <- ea_bool(k, lb, isTRUE(identical(dv, "true")))
      flagmap[[k]] <- list(flag = fl[1], role = "b")
    } else if (identical(kd$role, "txt")) {
      params[[length(params) + 1]] <- ea_txt(k, lb, value = as.character(dv %||% ""))
      flagmap[[k]] <- list(flag = fl[1], role = "p")
    }
  }
  if (!length(inputs) || is.null(outp)) return(NULL)   # not expressible; skip it

  tool <- entry$name
  list(
    id = paste0("wbt_", tolower(gsub("[^A-Za-z0-9]+", "_", tool))),
    label = paste0(gsub("(?<=[a-z])(?=[A-Z])", " ", tool, perl = TRUE),
                   " (WhiteboxTools)"),
    group = "WhiteboxTools", summary = entry$desc,
    provider = "whitebox", tool = tool,
    inputs = inputs, params = params, output = outp,
    run = function(inp, p) {
      .ea_require_whitebox()
      args <- character(0)
      for (k in names(flagmap)) {
        fm <- flagmap[[k]]
        if (identical(fm$role, "in")) {
          v <- inp[[k]]
          if (is.null(v)) next
          f <- tempfile(fileext = if (inherits(v, "SpatVector")) ".shp" else ".tif")
          if (inherits(v, "SpatRaster")) terra::writeRaster(v, f, overwrite = TRUE)
          else if (inherits(v, "sf")) sf::st_write(v, f, quiet = TRUE, delete_dsn = TRUE)
          else if (is.character(v)) f <- v
          args <- c(args, sprintf('%s=%s', fm$flag, shQuote(f)))
        } else if (identical(fm$role, "out")) {
          outf <- tempfile(fileext = ".tif")
          args <- c(args, sprintf('%s=%s', fm$flag, shQuote(outf)))
          assign(".out", outf, envir = environment())
        } else if (identical(fm$role, "b")) {
          if (isTRUE(p[[k]])) args <- c(args, fm$flag)
        } else {
          v <- p[[k]]
          if (!is.null(v) && !is.na(v) && nzchar(as.character(v)))
            args <- c(args, sprintf('%s=%s', fm$flag, shQuote(as.character(v))))
        }
      }
      outf <- get(".out", envir = environment())
      whitebox::wbt_run_tool(tool, paste(args, collapse = " "), verbose_mode = FALSE)
      if (!file.exists(outf)) stop("WhiteboxTools produced no output for ", tool, ".")
      terra::rast(outf)
    })
}

# ---- the provider --------------------------------------------------------
# Only ACTIVATED tools become specs. Everything else stays in the manifest,
# findable by search but costing nothing: no spec, no module binding, no memory.
ea_provider_whitebox <- function() {
  if (!ea_plugin_on("whitebox")) return(list())
  man <- ea_wbt_manifest()
  if (is.null(man)) return(list())
  on <- ea_plugin_state()$tools[["whitebox"]] %||% character(0)
  if (!length(on)) return(list())
  specs <- lapply(Filter(function(e) e$name %in% on, man$tools), ea_wbt_spec)
  Filter(Negate(is.null), specs)
}

# ---- the featured set ----------------------------------------------------
# A starting point, so activating the plugin does not present 484 undifferentiated
# tools. These are the standard workflows -- the DEM-to-streams hydrology chain,
# the common geomorphometric derivatives, the LiDAR gridding/filtering pair --
# not a judgement about which tools are "best".
#
# EVERY NAME HERE WAS VERIFIED against `wbt_list_tools()` on the installed
# version rather than written from memory: a featured tool that does not exist
# would render a broken row with no way to tell why.
EA_WBT_FEATURED <- c(
  # Hydrology -- the standard DEM-to-streams workflow, in order
  "FillDepressions", "BreachDepressionsLeastCost", "D8Pointer",
  "D8FlowAccumulation", "DInfFlowAccumulation", "WetnessIndex",
  "ExtractStreams", "StreamLinkIdentifier", "Watershed", "Basins", "Sink",
  # Geomorphometry
  "Slope", "Aspect", "Hillshade", "ProfileCurvature", "PlanCurvature",
  "TangentialCurvature", "RelativeTopographicPosition", "RuggednessIndex",
  "MultiscaleTopographicPositionImage", "HypsometricAnalysis",
  "FeaturePreservingSmoothing",
  # LiDAR
  "LidarTINGridding", "LidarGroundPointFilter", "LidarIdwInterpolation",
  "LidarInfo", "LidarSegmentation", "LidarTophatTransform",
  # Image processing
  "NormalizedDifferenceIndex", "GaussianFilter", "MajorityFilter"
)

# Turn the plugin on with the featured set active. Anything else stays findable
# by search and costs nothing until the user activates it.
ea_wbt_enable_featured <- function() {
  ea_plugin_set("whitebox", TRUE)
  st <- ea_plugin_state()
  st$tools[["whitebox"]] <- union(st$tools[["whitebox"]] %||% character(0),
                                  EA_WBT_FEATURED)
  ea_plugin_state_set(st)
}

# ---- the search index ----------------------------------------------------
# The manifest doubles as a catalogue of things NOT yet activated, so a user can
# search for a tool they have never enabled and turn it on from the result. That
# is what keeps the app fast without hiding capability: the index is text, and
# text is cheap.
ea_wbt_catalogue <- function(query = "", limit = 40L) {
  man <- ea_wbt_manifest()
  if (is.null(man)) return(data.frame())
  nm <- vapply(man$tools, function(e) e$name %||% "", character(1))
  ds <- vapply(man$tools, function(e) e$desc %||% "", character(1))
  hit <- if (!nzchar(query)) rep(TRUE, length(nm)) else {
    toks <- strsplit(tolower(trimws(query)), "\\s+")[[1]]
    hay  <- tolower(paste(nm, ds))
    Reduce(`&`, lapply(toks, function(t) grepl(t, hay, fixed = TRUE)))
  }
  i <- which(hit)
  if (!length(i)) return(data.frame())
  i <- utils::head(i, limit)
  on <- ea_plugin_state()$tools[["whitebox"]] %||% character(0)
  tb <- vapply(man$tools, function(e) e$toolbox %||% "", character(1))
  # USABLE = the mapper can express it as a spec. Not everything can be: some
  # WhiteboxTools tools declare no output parameter at all and write a file
  # implicitly beside their input (LasToShapefile is one), so there is nothing to
  # put in a pool. Those must still APPEAR in search -- a user who looks for a
  # tool deserves to learn it exists and why it is unavailable, rather than get
  # silence -- but they must never be offered an Activate that would do nothing.
  usable <- vapply(man$tools[i], function(e)
    !is.null(tryCatch(ea_wbt_spec(e), error = function(err) NULL)), logical(1))
  data.frame(tool = nm[i], toolbox = tb[i], description = ds[i],
             active = nm[i] %in% on, featured = nm[i] %in% EA_WBT_FEATURED,
             usable = usable, stringsAsFactors = FALSE)
}
