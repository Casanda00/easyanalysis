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
                        selected = p$value))
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
    actionButton(ns("run"), tagList(icon("play"), " Run"),
                 class = "btn-success w-100"),
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
        tagList(
          if (isTRUE(i$multiple))
            selectizeInput(ns(paste0("in_", i$key)), i$label, choices = nms,
                           multiple = TRUE,
                           options = list(plugins = list("remove_button")))
          else selectInput(ns(paste0("in_", i$key)), i$label, choices = nms),
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

    output$status <- renderUI({
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

      withProgress(message = paste0("Running ", spec$label, "..."), value = 0.4, {
        res <- tryCatch(spec$run(inp, p), error = function(e) e)
        if (inherits(res, "error")) {
          showNotification(paste0(spec$label, " failed: ", conditionMessage(res)),
                           type = "error", duration = 10)
          return()
        }
        incProgress(0.5, detail = "Adding layer...")
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
      })
    })

    # Context for the Co-Analyst: what this tool made, in one line.
    list(context = reactive({
      nm <- last()
      if (is.null(nm)) sprintf("%s: not run yet.", spec$label)
      else sprintf("%s produced the %s layer '%s'.", spec$label, spec$output$pool, nm)
    }))
  })
}
