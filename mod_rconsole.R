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
    ".rc-editor { flex: 1 1 auto; min-height: 0; display: flex; }",
    ".rc-editor .shiny-input-container { flex: 1 1 auto; min-height: 0; display: flex;",
    "  margin-bottom: 0; width: 100% !important; }",
    ".rc-editor textarea { font-family: var(--mono); font-size: 12.5px; height: 100% !important;",
    "  resize: none; background: var(--sunk); color: var(--ink); border-color: var(--line); }",
    ".rc-actions { flex: none; display: flex; gap: 6px; margin-top: 6px; }",
    ".rc-plot { flex: none; margin-top: 8px; border-top: 1px solid var(--line); padding-top: 6px; }",
    sep = "\n")
  tagList(
    tags$style(HTML(css)),
    tags$div(class = "rc-split", id = ns("wrap"),
      # LEFT: the editor
      tags$div(class = "rc-col",
        tags$div(class = "rc-colh", tags$span("Code"), tags$span("Ctrl+Enter to run")),
        tags$div(class = "rc-editor",
          textAreaInput(ns("code"), NULL, width = "100%",
                        placeholder = "Type R here, e.g.  summary(df)")),
        tags$div(class = "rc-actions",
          actionButton(ns("run"), "Run", class = "btn-success btn-sm", icon = icon("play")),
          actionButton(ns("clear"), "Clear", class = "btn-outline-secondary btn-sm",
                       icon = icon("eraser")))),
      # RIGHT: results (and the plot, only once there is one)
      tags$div(class = "rc-col",
        tags$div(class = "rc-colh", tags$span("Results"), uiOutput(ns("objects_inline"), inline = TRUE)),
        tags$div(class = "rc-log", id = ns("logbox"), uiOutput(ns("log"))),
        uiOutput(ns("plotwrap")))
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

    # The plot slot only exists once something has been plotted, so the results
    # column is not permanently shortened by an empty box.
    output$plotwrap <- renderUI({
      if (is.null(last_plot())) return(NULL)
      tags$div(class = "rc-plot", plotOutput(ns("plot"), height = "150px"))
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
