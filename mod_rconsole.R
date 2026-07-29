# ==========================================================================
# MODULE: R Console  (canvas + tools contract)
# rconsoleToolsUI / rconsoleCanvasUI / rconsoleServer(id, dataset_pool, active_dataset)
# --------------------------------------------------------------------------
# An in-app R console: run arbitrary R against your loaded data.
#
# SAFETY: this evaluates user-supplied R code. It is safe in the BROWSER
# (Shinylive/webR) build — each user runs their own sandboxed R session in their
# own browser, on their own data; there is no server and no other user to affect.
# On a shared SERVER build it would be arbitrary code execution and should be
# gated/removed. The shipped product is the browser build.
#
# The active dataset is exposed as `df`; every loaded dataset as make.names(name).
# Assignments persist between runs (one env per session). A single evaluation
# captures BOTH printed text and any plot (base or ggplot) — no double-eval, so
# side effects and RNG behave as the user expects.
# ==========================================================================

# (helpers below are console-local)

# Robust across ggplot2 versions (4.0 renamed is.ggplot -> is_ggplot).
.is_ggplot <- function(x) isTRUE(tryCatch(ggplot2::is_ggplot(x),
  error = function(e) tryCatch(ggplot2::is.ggplot(x),
  error = function(e2) inherits(x, "ggplot"))))

# Fill the code box with an example (client-side; also fires the input event).
.rc_chip <- function(ns, code) tags$button(
  type = "button",
  class = "btn btn-sm btn-outline-success w-100 text-start mb-1",
  style = "font-family:monospace; font-size:11px; white-space:normal;",
  onclick = sprintf(
    "var t=document.getElementById('%s'); t.value=%s; t.dispatchEvent(new Event('input',{bubbles:true})); t.focus();",
    ns("code"), jsonlite::toJSON(code, auto_unbox = TRUE)),
  code)

rconsoleToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "R Console"),
    markdown(paste(
      "Run R directly on your data. The active dataset is **`df`**; every loaded",
      "dataset is also available by name. Assignments persist between runs.")),
    uiOutput(ns("objects")),
    hr(),
    tags$small(class = "text-muted d-block mb-1", "Examples (click to insert):"),
    .rc_chip(ns, "summary(df)"),
    .rc_chip(ns, "str(df)"),
    .rc_chip(ns, "cor(df[sapply(df, is.numeric)], use = 'pairwise')"),
    .rc_chip(ns, "hist(df[[1]], main = names(df)[1])"),
    .rc_chip(ns, "ggplot(df, aes(df[[1]])) + geom_histogram(bins = 30)"),
    hr(),
    actionButton(ns("clear"), "Clear console",
      class = "btn-outline-secondary btn-sm w-100", icon = icon("eraser"))
  )
}

rconsoleCanvasUI <- function(id) {
  ns <- NS(id)
  # Static CSS (no sprintf / no namespaced ids) — the classes are global but
  # scoped enough for this one screen, and this avoids brace/percent pitfalls
  # inside an HTML() string. Every colour is a THEME TOKEN: the console used to
  # hardcode a near-black (#0f1a12) and stayed dark on the light colour sets.
  css <- paste(
    ".rc-split { display: grid; grid-template-columns: minmax(0,.85fr) minmax(0,1.15fr);",
    "  gap: 10px; height: 100%; min-height: 0; }",
    ".rc-col { display: flex; flex-direction: column; min-height: 0; min-width: 0; }",
    ".rc-colh { font: 600 8.5px var(--mono); text-transform: uppercase; letter-spacing: .08em;",
    "  color: var(--bark); margin-bottom: 4px; flex: none; display: flex;",
    "  align-items: center; justify-content: space-between; gap: 8px; }",
    ".rc-log { flex: 1 1 auto; min-height: 60px; overflow-y: auto; background: var(--sunk);",
    "  border: 1px solid var(--line); border-radius: 8px; padding: 8px 10px; font-size: 12.5px; }",
    ".rc-log pre { background: transparent; border: 0; padding: 0; color: var(--ink);",
    "  white-space: pre-wrap; margin: 2px 0; }",
    ".rc-prompt { color: var(--canopy); font-weight: 600; font-family: var(--mono);",
    "  white-space: pre-wrap; margin-top: 8px; }",
    ".rc-log pre.rc-err { color: var(--danger); }",
    ".rc-note { color: var(--canopy); font-size: 11px; }",
    ".rc-empty { color: var(--bark); font-style: italic; }",
    ".rc-editor { flex: 1 1 auto; min-height: 0; display: flex;",
    "  border: 1px solid var(--line); border-radius: 6px; overflow: hidden;",
    "  background: var(--sunk); }",
    # Line-number gutter. Scrolls in lockstep with the textarea; both use the
    # same font metrics and line-height, and wrapping is OFF so one number is
    # always one line.
    ".rc-gutter { flex: none; width: 34px; padding: 6px 6px 6px 0; overflow: hidden;",
    "  text-align: right; font: 12.5px/1.5 var(--mono); color: var(--bark);",
    "  background: var(--sunk); border-right: 1px solid var(--line);",
    "  user-select: none; white-space: pre; }",
    ".rc-editor .shiny-input-container { flex: 1 1 auto; min-height: 0; display: flex;",
    "  margin-bottom: 0; width: 100% !important; }",
    ".rc-editor textarea { font: 12.5px/1.5 var(--mono); height: 100% !important;",
    "  resize: none; background: var(--sunk); color: var(--ink);",
    "  border: none; border-radius: 0; padding: 6px 8px;",
    "  white-space: pre; overflow-wrap: normal; overflow-x: auto; }",
    ".rc-editor textarea:focus { box-shadow: none; outline: none; }",
    ".rc-actions { flex: none; display: flex; gap: 6px; margin-top: 6px; }",
    ".rc-sync { flex: none; display: flex; align-items: center; gap: 8px; margin-bottom: 6px;",
    "  padding: 6px 8px; font-size: 11.5px; color: var(--ink);",
    "  background: var(--sunk); border: 1px solid var(--line); border-radius: 6px; }",
    ".rc-sync > span { flex: 1 1 auto; min-width: 0; }",
    # Floating plot window: resize grip via CSS `resize`, maximize via a class.
    # No dock mode on purpose — see the note where it is built.
    ".rc-plotwin { display: none; position: fixed; right: 26px; bottom: 26px;",
    "  width: min(46vw, 620px); height: min(46vh, 430px); min-width: 260px; min-height: 180px;",
    "  background: var(--panel); border: 1px solid var(--line); border-radius: 10px;",
    "  box-shadow: 0 18px 50px rgba(0,0,0,.45); z-index: 1300;",
    "  flex-direction: column; overflow: hidden; resize: both; }",
    ".rc-plotwin.open { display: flex; }",
    ".rc-plotwin.max { left: 4vw; top: 6vh; right: 4vw; bottom: 6vh;",
    "  width: auto; height: auto; resize: none; }",
    ".rc-pw-head { flex: none; display: flex; align-items: center; gap: 8px; padding: 6px 10px;",
    "  background: var(--sunk); border-bottom: 1px solid var(--line); cursor: move;",
    "  font: 600 10px var(--mono); text-transform: uppercase; letter-spacing: .08em;",
    "  color: var(--bark); }",
    ".rc-plotwin.max .rc-pw-head { cursor: default; }",
    ".rc-pw-x { margin-left: auto; display: flex; gap: 2px; }",
    ".rc-pw-x button { border: none; background: transparent; color: var(--bark); cursor: pointer;",
    "  font: 600 14px var(--mono); line-height: 1; padding: 0 5px; }",
    ".rc-pw-x button:hover { color: var(--ink); }",
    ".rc-pw-body { flex: 1 1 auto; min-height: 0; padding: 8px; background: var(--panel); }",
    sep = "\n")
  tagList(
    tags$style(HTML(css)),
    tags$div(class = "rc-split", id = ns("wrap"),
      # LEFT: the editor
      tags$div(class = "rc-col",
        tags$div(class = "rc-colh", tags$span("Code"), tags$span("Ctrl+Enter to run")),
        tags$div(class = "rc-editor",
          tags$div(class = "rc-gutter", id = ns("gutter"), "1"),
          textAreaInput(ns("code"), NULL, width = "100%",
                        placeholder = "Type R here, e.g.  summary(df)")),
        tags$div(class = "rc-actions",
          # Run sends the textarea's CURRENT contents, rather than relying on
          # input$code. A Shiny text input is debounced, so typing and clicking
          # Run quickly used to run the PREVIOUS command with no sign anything
          # was wrong — and on the first command there was nothing to re-run, so
          # it looked like Run did nothing at all.
          actionButton(ns("run"), "Run", class = "btn-success btn-sm", icon = icon("play"),
            onclick = sprintf(
              "Shiny.setInputValue('%s', document.getElementById('%s').value, {priority:'event'});",
              ns("run_code"), ns("code"))),
          actionButton(ns("clear"), "Clear", class = "btn-outline-secondary btn-sm",
                       icon = icon("eraser")))),
      # RIGHT: results (and the plot, only once there is one)
      tags$div(class = "rc-col",
        tags$div(class = "rc-colh", tags$span("Results"), uiOutput(ns("objects_inline"), inline = TRUE)),
        uiOutput(ns("sync_bar")),
        tags$div(class = "rc-log", id = ns("logbox"), uiOutput(ns("log"))))
    ),
    # Plots open in a FLOATING window: resizable and maximizable, deliberately
    # not dockable — a plot is something you look at next to your code, not a
    # permanent region competing with the editor for the dock's height.
    tags$div(id = ns("plotwin"), class = "rc-plotwin",
      tags$div(class = "rc-pw-head",
        tags$span("Plot"),
        tags$span(class = "rc-pw-x",
          tags$button(type = "button", title = "Maximize / restore",
            onclick = sprintf("eaPlotWin('%s','max')", ns("plotwin")), HTML("&#9723;")),
          tags$button(type = "button", title = "Close",
            onclick = sprintf("eaPlotWin('%s','close')", ns("plotwin")), "×"))),
      tags$div(class = "rc-pw-body", plotOutput(ns("plot"), height = "100%"))),
    tags$script(HTML(sprintf(
      "$(document).on('keydown', '#%s', function(e){ if((e.ctrlKey||e.metaKey) && e.key==='Enter'){ e.preventDefault(); Shiny.setInputValue('%s', this.value, {priority:'event'}); }});
       eaCodeGutter('%s','%s');",
      ns("code"), ns("run_code"), ns("code"), ns("gutter"))))
  )
}

rconsoleServer <- function(id, dataset_pool, active_dataset,
                           raster_pool = NULL, las_pool = NULL, vector_pool = NULL,
                           sync_mode = getOption("ea.console_sync", "auto")) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    log_r     <- reactiveVal(list())
    last_plot <- reactiveVal(NULL)
    cenv      <- reactiveVal(NULL)

    # What get_env() last copied IN, so the write-back can tell a user-made
    # object from one of ours that came along for the ride.
    injected <- reactiveVal(list())

    # One persistent env per session; datasets refreshed each run (user vars kept).
    get_env <- function() {
      e <- cenv()
      if (is.null(e)) { e <- new.env(parent = globalenv()); cenv(e) }
      inj <- list()
      .put <- function(nm, val) { assign(nm, val, envir = e); inj[[nm]] <<- val }
      nms <- tryCatch(names(dataset_pool), error = function(err) character(0))
      for (nm in nms) try(.put(make.names(nm), dataset_pool[[nm]]), silent = TRUE)
      # spatial pools too, so a script can clip a raster it can actually see
      for (pl in list(raster_pool, las_pool, vector_pool)) {
        if (is.null(pl)) next
        for (nm in tryCatch(names(pl), error = function(err) character(0)))
          try(.put(make.names(nm), pl[[nm]]), silent = TRUE)
      }
      ad <- tryCatch(active_dataset(), error = function(err) NULL)
      if (!is.null(ad) && ad %in% nms) .put("df", dataset_pool[[ad]])
      injected(inj)
      e
    }

    # ---- Write-back: console objects become project layers --------------------
    # The console used to be a READ-ONLY scratchpad: pools were copied in, and
    # nothing ever came back, so a clipped raster lived and died in the console.
    # Now every eligible object it produces is routed to the pool for its type,
    # which puts it in the Layers panel and on the map like any other layer.
    #
    # sync_mode is "auto" (write back on every run) or "ask" (collect them and
    # let the user add them explicitly). See UNIFIED_WORKSPACE.md; switch with
    # options(ea.console_sync = "ask").
    pending <- reactiveVal(list())

    # Which names a script actually PRODUCES, as opposed to passes through.
    # An intermediate is consumed: in
    #   r1 <- crop(r, box); r2 <- mask(r1, poly); final <- project(r2, crs)
    # r1 and r2 appear on the right-hand side of a LATER assignment, final does
    # not — so only `final` is an output. Usage that merely looks at a value
    # (print(final), plot(final), a bare `final`) is not an assignment and so
    # does not count, which is what keeps the real output from being filtered.
    # Returns NULL when the script cannot be parsed, meaning "do not filter".
    .script_outputs <- function(code) {
      ex <- tryCatch(parse(text = code), error = function(e) NULL)
      if (is.null(ex) || !length(ex)) return(NULL)
      assigns <- list(); rhs <- list()
      for (i in seq_along(ex)) {
        e <- ex[[i]]
        if (is.call(e) && length(e) >= 3 &&
            as.character(e[[1]])[1] %in% c("<-", "=", "<<-")) {
          tgt <- e[[2]]
          if (is.symbol(tgt)) assigns[[as.character(tgt)]] <- i
          rhs[[as.character(i)]] <- tryCatch(all.vars(e[[3]]), error = function(err) character(0))
        }
      }
      if (!length(assigns)) return(NULL)
      keep <- character(0)
      for (nm in names(assigns)) {
        i <- assigns[[nm]]; consumed <- FALSE
        for (j in names(rhs)) {
          if (as.integer(j) > i && nm %in% rhs[[j]]) { consumed <- TRUE; break }
        }
        if (!consumed) keep <- c(keep, nm)
      }
      if (length(keep)) keep else NULL
    }

    .classify <- function(x) {
      if (is.data.frame(x))            "table"
      else if (inherits(x, "SpatRaster")) "raster"
      else if (inherits(x, "sf"))         "vector"
      else if (inherits(x, "LAS"))        "lidar"
      else NULL
    }
    .pool_for <- function(kind) switch(kind,
      table = dataset_pool, raster = raster_pool, vector = vector_pool,
      lidar = las_pool, NULL)

    # Eligible objects that are NEW or CHANGED since we copied the pools in.
    .harvest <- function(e, code = NULL) {
      inj <- injected()
      ad  <- tryCatch(active_dataset(), error = function(err) NULL)
      outs <- if (is.null(code)) NULL else .script_outputs(code)
      out <- list()
      for (nm in ls(e)) {
        if (startsWith(nm, ".")) next
        # keep only what the script produced, not what it passed through
        if (!is.null(outs) && !(nm %in% outs) && !identical(nm, "df")) next
        x <- tryCatch(get(nm, envir = e), error = function(err) NULL)
        kind <- .classify(x)
        if (is.null(kind)) next
        # Skip anything that IS one of the objects we copied in — under its own
        # name (untouched) or under a new one. `r <- my_raster` is an alias, not
        # a new layer, and adding it would duplicate what is already loaded.
        same <- FALSE
        for (w in inj) {
          if (isTRUE(tryCatch(identical(w, x), error = function(err) FALSE))) { same <- TRUE; break }
        }
        if (same) next
        # `df` is an ALIAS for the active dataset; write it back under the real
        # name rather than creating a stray layer called "df".
        target <- if (identical(nm, "df") && !is.null(ad)) ad else nm
        out[[target]] <- list(kind = kind, value = x)
      }
      out
    }

    .commit <- function(items) {
      done <- character(0)
      for (nm in names(items)) {
        it <- items[[nm]]; pool <- .pool_for(it$kind)
        if (is.null(pool)) next
        try({ pool[[nm]] <- it$value; done <- c(done, paste0(nm, " (", it$kind, ")")) },
            silent = TRUE)
      }
      done
    }

    output$objects <- renderUI({
      nms <- tryCatch(names(dataset_pool), error = function(err) character(0))
      if (!length(nms))
        return(tags$small(class = "text-muted", "No datasets loaded yet — `df` will be empty."))
      tagList(
        tags$small(class = "text-muted d-block mb-1", "Available as:"),
        tags$code(style = "display:block;font-size:11px;", "df  (active dataset)"),
        lapply(nms, function(n) tags$code(style = "display:block;font-size:11px;", make.names(n)))
      )
    })

    run_code <- function(code) {
      code <- trimws(code %||% "")
      req(nzchar(code))
      e <- get_env()
      status <- "ok"; plot_obj <- NULL
      grDevices::pdf(NULL); grDevices::dev.control(displaylist = "enable")
      out <- tryCatch(
        paste(utils::capture.output({
          r <- withVisible(eval(parse(text = code), envir = e))
          if (.is_ggplot(r$value)) { plot_obj <<- r$value; print(r$value) }
          else if (r$visible) print(r$value)
        }), collapse = "\n"),
        error = function(err) { status <<- "error"; paste0("Error: ", conditionMessage(err)) }
      )
      if (is.null(plot_obj)) {
        rp <- tryCatch(grDevices::recordPlot(), error = function(err) NULL)
        if (!is.null(rp) && length(rp[[1]]) > 0) plot_obj <- rp
      }
      try(grDevices::dev.off(), silent = TRUE)
      if (!is.null(plot_obj)) last_plot(plot_obj)
      h <- log_r()
      h[[length(h) + 1]] <- list(code = code, out = out, status = status,
                                 plotted = !is.null(plot_obj))
      log_r(h)
      # The editor deliberately KEEPS its contents: this is a script you iterate
      # on, not a one-shot prompt, and clearing it threw the user's work away on
      # every Run. "Clear" empties the log; nothing empties the editor but you.
      if (!is.null(plot_obj))
        session$sendCustomMessage("rc_plotwin", session$ns("plotwin"))

      # Anything the script produced joins the project.
      items <- tryCatch(.harvest(e, code), error = function(err) list())
      if (length(items)) {
        if (identical(sync_mode, "auto")) {
          added <- .commit(items)
          if (length(added))
            showNotification(paste0("Added to the project: ", paste(added, collapse = ", ")),
                             type = "message", duration = 6)
        } else {
          pending(items)
        }
      }
    }

    # Driven by run_code (the exact text at click time), not input$run.
    observeEvent(input$run_code, run_code(input$run_code))
    observeEvent(input$clear, {
      log_r(list()); last_plot(NULL)
      session$sendCustomMessage("rc_plotwin_close", session$ns("plotwin"))
    })

    # Only ever shown in "ask" mode; in "auto" mode `pending` stays empty.
    output$sync_bar <- renderUI({
      items <- pending()
      if (!length(items)) return(NULL)
      tags$div(class = "rc-sync",
        tags$span(paste0(length(items), " object",
                         if (length(items) == 1) "" else "s", " ready: ",
                         paste(names(items), collapse = ", "))),
        actionButton(ns("sync_add"), "Add to project",
                     class = "btn-success btn-sm", icon = icon("plus")),
        actionButton(ns("sync_skip"), "Dismiss",
                     class = "btn-outline-secondary btn-sm"))
    })
    observeEvent(input$sync_add, {
      added <- .commit(pending()); pending(list())
      if (length(added))
        showNotification(paste0("Added to the project: ", paste(added, collapse = ", ")),
                         type = "message", duration = 6)
    })
    observeEvent(input$sync_skip, { pending(list()) })

    output$log <- renderUI({
      entries <- log_r()
      if (!length(entries))
        return(tags$div(class = "rc-empty",
          "Results appear here. Write R on the left and press Run (or Ctrl+Enter)."))
      items <- lapply(entries, function(en) {
        tagList(
          tags$div(class = "rc-prompt", paste0("> ", en$code)),
          if (nzchar(en$out))
            tags$pre(class = if (identical(en$status, "error")) "rc-err" else NULL, en$out),
          if (isTRUE(en$plotted)) tags$div(class = "rc-note", "[plot shown below]")
        )
      })
      tagList(items, tags$script(HTML(sprintf(
        "var b=document.getElementById('%s'); if(b) b.scrollTop=b.scrollHeight;", ns("logbox")))))
    })

    # Compact "df + N datasets" hint in the results header (the old tools panel
    # that carried this is not mounted anywhere — the console lives in the dock).
    output$objects_inline <- renderUI({
      nms <- tryCatch(names(dataset_pool), error = function(err) character(0))
      nms <- nms[!vapply(nms, function(n) is.null(dataset_pool[[n]]), logical(1))]
      tags$span(if (length(nms))
                  paste0("df + ", length(nms), " dataset", if (length(nms) == 1) "" else "s")
                else "no datasets loaded")
    })

    # shiny::renderPlot ON PURPOSE, bypassing the app-wide styling wrapper in
    # helpers.R. In the console YOUR CODE is the source of truth: if you write
    # geom_point(colour = "red"), the app repainting it from a screen's plot
    # settings would be the app lying about what your script does. Console plots
    # therefore ignore the plot-appearance tool — set titles and colours in the
    # code, which is the whole point of having a console.
    output$plot <- shiny::renderPlot({
      p <- last_plot(); req(!is.null(p))
      if (.is_ggplot(p)) print(p) else grDevices::replayPlot(p)
    })

    # Co-Pilot context contract
    list(
      context = reactive({
        nms <- tryCatch(names(dataset_pool), error = function(err) character(0))
        n   <- length(log_r())
        paste0("R Console screen. Datasets available as objects: ",
               if (length(nms)) paste(make.names(nms), collapse = ", ") else "(none)",
               ". `df` = active dataset. ", n, " command(s) run this session.")
      }),
      plot = function() {
        p <- last_plot()
        if (!is.null(p)) { if (.is_ggplot(p)) print(p) else grDevices::replayPlot(p) }
      }
    )
  })
}
