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
  # inside an HTML() string.
  css <- paste(
    ".rc-log { height: 46vh; min-height: 240px; overflow-y: auto; background: #0f1a12;",
    "  border-radius: 8px; padding: 10px 12px; font-size: 12.5px; }",
    ".rc-log pre { background: transparent; border: 0; padding: 0; color: #d7e3d8; }",
    ".rc-prompt { color: #7ddc8a; font-weight: 600; font-family: monospace; white-space: pre-wrap; margin-top: 8px; }",
    ".rc-input textarea { font-family: monospace; font-size: 13px; }",
    sep = "\n")
  tagList(
    tags$style(HTML(css)),
    tags$div(id = ns("wrap"),
      card(
        card_header(class = "d-flex justify-content-between align-items-center",
          "R Console",
          tags$small(class = "text-muted", "Ctrl+Enter to run")),
        tags$div(class = "rc-log", id = ns("logbox"), uiOutput(ns("log"))),
        tags$div(class = "rc-input", style = "margin-top:8px; display:flex; gap:8px; align-items:flex-end;",
          tags$div(style = "flex:1 1 auto;",
            textAreaInput(ns("code"), NULL, rows = 3, width = "100%",
              placeholder = "Type R here, e.g.  summary(df)")),
          actionButton(ns("run"), "Run", class = "btn-success", icon = icon("play"),
            style = "height:38px;"))
      ),
      card(
        card_header("Last plot"),
        plotOutput(ns("plot"), height = "320px")
      )
    ),
    tags$script(HTML(sprintf(
      "$(document).on('keydown', '#%s', function(e){ if((e.ctrlKey||e.metaKey) && e.key==='Enter'){ e.preventDefault(); $('#%s').click(); }});",
      ns("code"), ns("run"))))
  )
}

rconsoleServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    log_r     <- reactiveVal(list())
    last_plot <- reactiveVal(NULL)
    cenv      <- reactiveVal(NULL)

    # One persistent env per session; datasets refreshed each run (user vars kept).
    get_env <- function() {
      e <- cenv()
      if (is.null(e)) { e <- new.env(parent = globalenv()); cenv(e) }
      nms <- tryCatch(names(dataset_pool), error = function(err) character(0))
      for (nm in nms) try(assign(make.names(nm), dataset_pool[[nm]], envir = e), silent = TRUE)
      ad <- tryCatch(active_dataset(), error = function(err) NULL)
      if (!is.null(ad) && ad %in% nms) assign("df", dataset_pool[[ad]], envir = e)
      e
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
      updateTextAreaInput(session, "code", value = "")
    }

    observeEvent(input$run, run_code(input$code))
    observeEvent(input$clear, { log_r(list()); last_plot(NULL) })

    output$log <- renderUI({
      entries <- log_r()
      if (!length(entries))
        return(tags$div(class = "text-muted", style = "font-style:italic;color:#8aa78d;",
          "Results appear here. Type R below and press Run (or Ctrl+Enter)."))
      items <- lapply(entries, function(en) {
        col <- if (identical(en$status, "error")) "#ff8a80" else "#d7e3d8"
        tagList(
          tags$div(class = "rc-prompt", paste0("> ", en$code)),
          if (nzchar(en$out))
            tags$pre(style = sprintf("color:%s; white-space:pre-wrap; margin:2px 0;", col), en$out),
          if (isTRUE(en$plotted))
            tags$div(style = "color:#7ddc8a; font-size:11px;", "[plot rendered below]")
        )
      })
      tagList(items, tags$script(HTML(sprintf(
        "var b=document.getElementById('%s'); if(b) b.scrollTop=b.scrollHeight;", ns("logbox")))))
    })

    output$plot <- renderPlot({
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
