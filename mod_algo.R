# mod_algo.R -- generic runner for one processing algorithm (see algorithms.R)
#
# Every algorithm gets the same panel: pick the input layer(s), set the
# parameters, name the output, press Run. The result goes straight into the
# matching pool, so it appears in the Layers panel and draws on the workspace
# map like anything else the project holds. There is no canvas -- these tools
# are map_based, which is the whole point of the split (backlog D18).
#
# algoToolsUI(id, spec) / algoServer(id, spec, pools)
#   pools is a named list: las, raster, vector, table.

# Band and field pickers must be built from the CHOSEN layer, so they render
# server-side (output$dyn_ui) while everything else is static UI.
.ea_is_dyn <- function(p) p$kind %in% c("band", "field")

algoToolsUI <- function(id, spec) {
  ns <- NS(id)
  ctl <- function(p) {
    inp <- switch(p$kind,
      num = numericInput(ns(paste0("p_", p$key)), p$label, value = p$value,
                         min = p$min, max = p$max, step = p$step),
      txt = if (isTRUE(p$rows > 1))
              textAreaInput(ns(paste0("p_", p$key)), p$label, value = p$value, rows = p$rows)
            else textInput(ns(paste0("p_", p$key)), p$label, value = p$value),
      sel = selectInput(ns(paste0("p_", p$key)), p$label, choices = p$choices,
                        selected = p$value),
      crs = selectizeInput(ns(paste0("p_", p$key)), p$label,
                           choices = .ea_crs_choices(),
                           selected = p$value,
                           options = list(create = TRUE,
                                          createOnBlur = TRUE,
                                          placeholder = "Search EPSG code or CRS name...")))
    if (is.null(p$hint)) inp
    else tagList(inp, tags$p(class = "text-muted small mt-n1 mb-2", p$hint))
  }
  static <- Filter(function(p) !.ea_is_dyn(p), spec$params)
  tagList(
    tags$p(class = "text-muted small mb-2", spec$summary),
    uiOutput(ns("inputs_ui")),
    if (length(spec$params)) tagList(
      tags$h6(class = "text-uppercase text-muted small mt-2", "Parameters"),
      uiOutput(ns("dyn_ui")),
      lapply(static, ctl)),
    tags$h6(class = "text-uppercase text-muted small mt-2", "Output"),
    textInput(ns("out_name"), "Save as layer", placeholder = spec$output$default),
    # Run and Stop swap places: Stop is only real while something is running, and
    # it only works because a heavy run happens in another process (compute_worker.R)
    # -- a Stop button on an in-process run could never be clicked.
    uiOutput(ns("run_ui")),
    uiOutput(ns("status"))
  )
}

algoServer <- function(id, spec, pools) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    .pool <- function(nm) pools[[nm]]
    .names <- function(nm) {
      p <- .pool(nm)
      if (is.null(p)) return(character(0))
      n <- tryCatch(names(reactiveValuesToList(p)), error = function(e) character(0))
      # A reactiveValues key set to NULL keeps its name (gotcha 14), so a layer
      # that was deleted would still be offered here.
      Filter(function(k) !is.null(tryCatch(p[[k]], error = function(e) NULL)), n)
    }

    # Input pickers are renderUI, not update*Input: this panel is created the
    # moment the tool is opened and the pools may already be populated, and a
    # renderUI simply builds with whatever is there (gotcha 18 never applies).
    output$inputs_ui <- renderUI({
      lapply(spec$inputs, function(i) {
        nms <- .names(i$pool)
        if (!length(nms))
          return(div(class = "ea-hint",
            sprintf("No %s layer in this project yet.", i$pool)))
        # Keep what the user picked. This block re-renders whenever the pool
        # changes, and a run ADDS to the pool -- so without this, running an
        # algorithm cleared its own input and you had to re-pick the layer before
        # you could run it again with a different parameter. isolate() because we
        # depend on the pool here, never on our own selection.
        prev <- isolate(input[[paste0("in_", i$key)]])
        keep <- if (length(prev)) prev[prev %in% nms] else character(0)
        tagList(
          if (isTRUE(i$multiple))
            selectizeInput(ns(paste0("in_", i$key)), i$label, choices = nms,
                           selected = keep, multiple = TRUE,
                           options = list(plugins = list("remove_button"),
                                          placeholder = "Choose layers"))
          else
            # An empty first choice, so the tool NEVER picks a layer for you. A
            # plain selectInput auto-selects its first option, which meant ITD
            # silently pointed at whatever raster happened to be first in the
            # pool -- run it without looking and you would be detecting treetops
            # on a DTM. Run refuses until something is chosen.
            selectInput(ns(paste0("in_", i$key)), i$label,
                        choices = c(stats::setNames("", "Choose a layer..."), nms),
                        selected = if (length(keep)) keep[1] else ""),
          if (!is.null(i$hint)) tags$p(class = "text-muted small mt-n1 mb-2", i$hint))
      })
    })

    # Band / field pickers, built from the layer actually chosen above. They
    # depend ONLY on the input selectors, never on the parameter values, so
    # typing in a parameter cannot rebuild (and blank) this block (gotcha 21).
    output$dyn_ui <- renderUI({
      dyn <- Filter(.ea_is_dyn, spec$params)
      if (!length(dyn)) return(NULL)
      lapply(dyn, function(p) {
        src <- Filter(function(i) identical(i$key, p$from), spec$inputs)[[1]]
        key <- input[[paste0("in_", p$from)]]
        lay <- if (isTruthy(key)) tryCatch(.pool(src$pool)[[key]], error = function(e) NULL) else NULL
        ch <- if (is.null(lay)) character(0) else if (identical(p$kind, "band")) {
          nb <- terra::nlyr(lay)
          bn <- names(lay)
          if (is.null(bn) || !all(nzchar(bn))) bn <- paste("Band", seq_len(nb))
          stats::setNames(as.character(seq_len(nb)), bn)
        } else {
          f <- tryCatch(names(sf::st_drop_geometry(lay)), error = function(e) character(0))
          if (!is.null(p$blank)) c(stats::setNames("", p$blank), f) else f
        }
        if (!length(ch))
          return(div(class = "ea-hint", sprintf("%s: choose an input layer first.", p$label)))
        sel <- if (identical(p$kind, "band"))
                 as.character(min(as.integer(p$value), length(ch))) else NULL
        tagList(
          selectInput(ns(paste0("p_", p$key)), p$label, choices = ch, selected = sel),
          if (!is.null(p$hint)) tags$p(class = "text-muted small mt-n1 mb-2", p$hint))
      })
    })

    last <- reactiveVal(NULL)      # name of the layer this tool last produced

    # Bumped on every poll. The status line has to depend on SOMETHING reactive to
    # re-render, and the worker's state lives in a plain environment, not a
    # reactive -- so without this the elapsed counter rendered once when the job
    # started and then sat there. Observed: 14s frozen on screen while the run was
    # 38s in, which reads exactly like the app having hung.
    tick <- reactiveVal(0)

    output$status <- renderUI({
      tick()
      job <- pending()
      if (!is.null(job)) {
        # Real state, not a fake bar: what it is doing and how long it has been
        # doing it. "Preparing" is the one-time package load in the background
        # session, which is genuinely slow and worth naming rather than hiding.
        el <- round(as.numeric(difftime(Sys.time(), job$started, units = "secs")))
        return(div(class = "ea-hint mt-2",
          if (identical(ea_worker_state(), "warming"))
            sprintf("Preparing the background session (first heavy run only)... %ds", el)
          else sprintf("Running on %.1fM cells in the background... %ds - Stop is safe",
                       job$cells / 1e6, el)))
      }
      nm <- last()
      if (is.null(nm)) return(NULL)
      div(class = "ea-hint mt-2",
          sprintf("Added '%s' to the %s layers. It is on the map.",
                  nm, spec$output$pool))
    })

    # Never overwrite an existing layer silently -- suffix until the name is free.
    .free_name <- function(pool, nm) {
      base <- nm; i <- 2L
      while (!is.null(isolate(pool[[nm]]))) { nm <- sprintf("%s_%d", base, i); i <- i + 1L }
      nm
    }

    observeEvent(input$run, {
      inp <- list()
      for (i in spec$inputs) {
        keys <- input[[paste0("in_", i$key)]]
        p <- .pool(i$pool)
        if (!isTruthy(keys) || is.null(p)) {
          showNotification(sprintf("Choose a %s first.", tolower(i$label)), type = "warning")
          return()
        }
        vals <- lapply(keys, function(k) tryCatch(p[[k]], error = function(e) NULL))
        if (any(vapply(vals, is.null, logical(1)))) {
          showNotification(sprintf("Choose a %s first.", tolower(i$label)), type = "warning")
          return()
        }
        # A multi-layer input hands `run` the LIST; a single one hands the object.
        inp[[i$key]] <- if (isTRUE(i$multiple)) stats::setNames(vals, keys) else vals[[1]]
      }
      p <- list()
      for (q in spec$params) p[[q$key]] <- input[[paste0("p_", q$key)]]

      outp <- .pool(spec$output$pool)
      if (is.null(outp)) {
        showNotification("This build has no pool for that output type.", type = "error")
        return()
      }
      nm <- trimws(input$out_name %||% "")
      if (!nzchar(nm)) nm <- spec$output$default
      nm <- .free_name(outp, nm)

      # HEAVY runs go to the background session so they can be stopped; light ones
      # stay in-process because they finish before you could reach a Stop button,
      # and routing them out would add ~1.6 s each (plus ~13 s the first time) for
      # nothing. The gate is the input cell count -- tune with
      # options(ea.worker_min_cells = ...).
      #
      # LAS inputs deliberately stay in-process. Staging a point cloud means
      # serialising it, which can cost more than the computation, and its file path
      # cannot be reused instead: a cloud in the pool may have been clipped or
      # height-normalised, so the file no longer matches it -- the same trap as a
      # raster subset reporting its parent's path.
      cells <- sum(vapply(inp, function(x)
        if (inherits(x, "SpatRaster")) as.numeric(terra::ncell(x))
        else if (is.list(x)) sum(vapply(x, function(y)
          if (inherits(y, "SpatRaster")) as.numeric(terra::ncell(y)) else 0, 0))
        else 0, numeric(1)))
      has_las <- any(vapply(inp, function(x) inherits(x, "LAS"), logical(1)))
      heavy <- !has_las && cells > getOption("ea.worker_min_cells", 2e6) &&
               requireNamespace("callr", quietly = TRUE)

      if (heavy) {
        staged <- lapply(inp, function(x)
          if (is.list(x) && !inherits(x, "SpatRaster"))
            list(kind = "raster", paths = lapply(x, function(y) ea_worker_stage(y)$path))
          else ea_worker_stage(x))
        pending(list(inputs = staged, params = p, nm = nm, started = Sys.time(),
                     out = NULL, cells = cells))
        if (identical(ea_worker_state(), "off")) ea_worker_warm()
        return()
      }

      withProgress(message = paste0("Running ", spec$label, "..."), value = 0.4, {
        res <- tryCatch(spec$run(inp, p), error = function(e) e)
        if (inherits(res, "error")) {
          showNotification(paste0(spec$label, " failed: ", conditionMessage(res)),
                           type = "error", duration = 10)
          return()
        }
        incProgress(0.5, detail = "Adding layer...")
        .deliver(res, nm, outp)
      })
    })

    # ---- Background run: state machine -------------------------------------
    # Polled rather than blocking, which is the whole point -- the session stays
    # responsive, so the Stop button below is actually clickable.
    pending <- reactiveVal(NULL)

    # Shared by both paths so an in-process and a background result are stored
    # identically.
    .deliver <- function(res, nm, outp) {
      # Name the BAND after the layer, for single-band rasters. mod_terrain.R
      # and mod_hydro.R both did this (`names(result) <- out_nm`) and it is what
      # labels the band in the map legend -- without it every terrain
      # derivative shows up as "slope" or "lyr.1" whatever you called it.
      if (inherits(res, "SpatRaster") && terra::nlyr(res) == 1L)
        try(names(res) <- nm, silent = TRUE)
      outp[[nm]] <- res
      last(nm)
      showNotification(sprintf("%s complete - added layer '%s'.", spec$label, nm),
                       type = "message")
    }

    observe({
      job <- pending()
      if (is.null(job)) return()
      invalidateLater(250)
      tick(isolate(tick()) + 1L)      # drives the status line, see above
      st <- ea_worker_state()

      if (identical(st, "off")) {          # worker died or could not start
        pending(NULL)
        showNotification("Could not start the background compute session; run again to try in-process.",
                         type = "error", duration = 8)
        return()
      }
      if (identical(st, "warming")) { ea_worker_ready(); return() }

      if (is.null(job$out) && identical(st, "idle")) {
        out <- ea_worker_run(getwd(), spec$id, job$inputs, job$params, spec$label)
        if (is.null(out)) return()         # worker busy with someone else; wait
        job$out <- out; pending(job)
        return()
      }
      if (!is.null(job$out) && ea_worker_ready()) {
        r <- ea_worker_result()
        pending(NULL)
        if (is.null(r) || !is.null(r$error)) {
          showNotification(paste0(spec$label, " failed: ",
            if (is.null(r)) "the compute session stopped" else conditionMessage(r$error)),
            type = "error", duration = 10)
          return()
        }
        res <- tryCatch(
          if (identical(r$result, "raster")) terra::rast(job$out) else readRDS(job$out),
          error = function(e) e)
        if (inherits(res, "error")) {
          showNotification(paste0(spec$label, ": could not read the result - ",
                                  conditionMessage(res)), type = "error", duration = 10)
          return()
        }
        outp <- .pool(spec$output$pool)
        .deliver(res, .free_name(outp, job$nm), outp)
      }
    })

    output$run_ui <- renderUI({
      if (is.null(pending()))
        return(actionButton(ns("run"), tagList(icon("play"), " Run"),
                            class = "btn-success w-100"))
      actionButton(ns("stop"), tagList(icon("stop"), " Stop"),
                   class = "btn-outline-danger w-100")
    })

    observeEvent(input$stop, {
      ea_worker_cancel()
      pending(NULL)
      showNotification(paste0(spec$label, " stopped."), type = "warning", duration = 4)
    })

    # Context for the Co-Analyst: what this tool made, in one line.
    list(context = reactive({
      nm <- last()
      if (is.null(nm)) sprintf("%s: not run yet.", spec$label)
      else sprintf("%s produced the %s layer '%s'.", spec$label, spec$output$pool, nm)
    }))
  })
}
