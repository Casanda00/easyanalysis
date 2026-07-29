# compute_worker.R -- a killable background R session for long computations
#
# WHY THIS EXISTS. Shiny is single-threaded. While a terra call is running the
# session cannot process a click, so a "Cancel" button next to the progress bar
# could never be reached -- the only way to stop a heavy run was Ctrl-C in the
# terminal, killing the whole app. withProgress() only REPORTS; it does not yield.
#
# WHY A PERSISTENT SESSION RATHER THAN ONE PROCESS PER RUN. Measured on this
# machine: a fresh `callr::r_bg()` per run costs **13-16 s** of startup before any
# work happens (loading terra/lidR), which is absurd for an operation that takes
# 0.02 s. A persistent `callr::r_session` costs ~1 s to spawn plus ~14 s to preload
# those packages ONCE, after which each run adds only ~0.6-1.6 s.
#
# WHY kill() AND NOT interrupt(). `r_session$interrupt()` does NOT stop a running
# terra computation -- measured: the poll timed out after 4 s, the session stayed
# busy, and the next call errored. R only checks interrupts at R level and terra's
# C++ loop never yields. `kill()` does work: 0.33 s, and it leaves no partial
# output file behind. The cost is that the killed session's preload is lost, so
# cancelling means paying the ~14 s warm-up again -- which is the right place to
# put that cost, since it only happens when the user actually cancels.
#
# ONE session is shared by the whole app. On a local-first single-user app that is
# the point; if two browser sessions both run something, the second queues.

.EA_W <- new.env(parent = emptyenv())
.EA_W$session <- NULL     # callr::r_session
.EA_W$state   <- "off"    # off | warming | idle | busy
.EA_W$job     <- NULL     # list(out_path, kind, started, label)

ea_worker_state <- function() .EA_W$state

# Spawn and start preloading. Spawning is ~1 s so it happens inline; the PRELOAD
# is issued as a call and polled, because doing it synchronously would freeze the
# app for 14 s -- exactly the thing this file exists to avoid.
ea_worker_warm <- function() {
  if (!is.null(.EA_W$session) && .EA_W$state %in% c("warming", "idle", "busy"))
    return(invisible(FALSE))
  if (!requireNamespace("callr", quietly = TRUE)) return(invisible(FALSE))
  s <- tryCatch(callr::r_session$new(), error = function(e) NULL)
  if (is.null(s)) return(invisible(FALSE))
  .EA_W$session <- s
  .EA_W$state <- "warming"
  s$call(function() {
    suppressMessages({
      requireNamespace("terra", quietly = TRUE)
      requireNamespace("lidR",  quietly = TRUE)
      requireNamespace("sf",    quietly = TRUE)
    })
    TRUE
  })
  invisible(TRUE)
}

# Non-blocking: TRUE when the session has finished whatever it was doing.
ea_worker_ready <- function() {
  s <- .EA_W$session
  if (is.null(s)) return(FALSE)
  st <- tryCatch(s$poll_process(0), error = function(e) "error")
  if (!identical(st, "ready")) return(FALSE)
  res <- tryCatch(s$read(), error = function(e) NULL)
  if (identical(.EA_W$state, "warming")) { .EA_W$state <- "idle"; return(FALSE) }
  .EA_W$last <- res
  .EA_W$state <- "idle"
  TRUE
}

# What runs in the worker. It sources algorithms.R rather than receiving the
# `run` closure, so nothing about the algorithm has to be serialisable.
.ea_worker_body <- function(app_dir, id, inputs, params, out_path) {
  setwd(app_dir)
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b
  source("algorithms.R")
  inp <- lapply(inputs, function(x)
    if (identical(x$kind, "raster")) terra::rast(x$path) else readRDS(x$path))
  # a multi-layer input arrives as a list of layers under one key
  for (k in names(inp)) if (is.list(inputs[[k]]$paths))
    inp[[k]] <- lapply(inputs[[k]]$paths, terra::rast)
  spec <- ea_algorithms()[[id]]
  res <- spec$run(inp, params)
  if (inherits(res, "SpatRaster")) {
    terra::writeRaster(res, out_path, overwrite = TRUE); "raster"
  } else {
    saveRDS(res, out_path); "rds"
  }
}

# Hand a layer to the worker as a FILE. A raster is never passed by its own
# source() path: terra reports the path of the file a subset came FROM, so
# `d[[2]]` claims the 3-band file it was sliced out of -- verified -- and the
# worker would silently read 3 bands instead of 1. Always write it out.
ea_worker_stage <- function(obj) {
  if (inherits(obj, "SpatRaster")) {
    f <- tempfile(fileext = ".tif")
    terra::writeRaster(obj, f, overwrite = TRUE)
    list(kind = "raster", path = f)
  } else {
    f <- tempfile(fileext = ".rds")
    saveRDS(obj, f)
    list(kind = "rds", path = f)
  }
}

# Start a run. Returns the output path, or NULL if the worker could not be used.
ea_worker_run <- function(app_dir, id, inputs, params, label = id) {
  if (is.null(.EA_W$session) || !identical(.EA_W$state, "idle")) return(NULL)
  out <- tempfile(fileext = ".tif")
  .EA_W$job <- list(out_path = out, started = Sys.time(), label = label)
  .EA_W$state <- "busy"
  tryCatch({
    .EA_W$session$call(.ea_worker_body,
                       args = list(app_dir, id, inputs, params, out))
    out
  }, error = function(e) { .EA_W$state <- "idle"; NULL })
}

ea_worker_job    <- function() .EA_W$job
ea_worker_result <- function() .EA_W$last

# Cancel: kill the process and drop it. The next warm-up re-pays the preload,
# which is deliberate -- see the note at the top.
ea_worker_cancel <- function() {
  s <- .EA_W$session
  if (!is.null(s)) tryCatch(s$kill(), error = function(e) NULL)
  out <- .EA_W$job$out_path
  if (!is.null(out) && file.exists(out)) unlink(out)
  .EA_W$session <- NULL; .EA_W$state <- "off"; .EA_W$job <- NULL; .EA_W$last <- NULL
  invisible(TRUE)
}

ea_worker_shutdown <- function() {
  s <- .EA_W$session
  if (!is.null(s)) tryCatch(s$close(), error = function(e) tryCatch(s$kill(), error = function(e) NULL))
  .EA_W$session <- NULL; .EA_W$state <- "off"; .EA_W$job <- NULL
  invisible(TRUE)
}
