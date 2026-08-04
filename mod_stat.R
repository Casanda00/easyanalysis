# mod_stat.R -- generic runner for one statistical method (see statistics.R)
#
# Every method gets the same panel: pick the columns by ROLE, set the
# parameters, press Run; results fill the canvas with the app's standard
# select-and-split view header. There is no per-method module.
#
#   statToolsUI(id, spec) / statCanvasUI(id, spec)
#   statServer(id, spec, dataset_pool, active_dataset)
#
# Deliberately mirrors mod_algo.R. Each rule below was paid for once already:
#
#  * Role pickers are renderUI, NEVER update*Input. A module's panel renders
#    lazily, so an update aimed at an element that does not exist yet is
#    silently dropped -- that is gotchas 18/26, which produced empty Response
#    dropdowns on four screens and made them impossible to run. A renderUI
#    simply builds with whatever the pool holds when it renders, so the bug
#    cannot occur for ANY method hosted here.
#  * An empty first choice, so the tool never picks a column for you (G27).
#  * The user's selection survives a re-render (the isolate/keep pattern).
#  * Predictors use selectizeInput(multiple = TRUE) per UX rule 11 -- declared
#    once here rather than per screen, which is what E19/E20 asked for.

statToolsUI <- function(id, spec) {
  ns <- NS(id)
  ctl <- function(p) {
    inp <- switch(p$kind,
      num = numericInput(ns(paste0("p_", p$key)), p$label, value = p$value,
                         min = p$min, max = p$max, step = p$step),
      txt = textInput(ns(paste0("p_", p$key)), p$label, value = p$value),
      sel = selectInput(ns(paste0("p_", p$key)), p$label, choices = p$choices,
                        selected = p$value),
      NULL)
    if (is.null(p$hint)) inp
    else tagList(inp, tags$p(class = "text-muted small mt-n1 mb-2", p$hint))
  }
  tagList(
    tags$p(class = "text-muted small mb-2", spec$summary),
    uiOutput(ns("roles_ui")),
    if (length(spec$params)) tagList(
      tags$h6(class = "text-uppercase text-muted small mt-2", "Options"),
      lapply(spec$params, ctl)),
    actionButton(ns("run"), tagList(icon("play"), " Run"),
                 class = "btn-success w-100 mt-2"),
    uiOutput(ns("status"))
  )
}

statCanvasUI <- function(id, spec) {
  ns <- NS(id)
  card(
    card_header(ea_view_header(ns, spec$views)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

statServer <- function(id, spec, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    .df <- reactive({
      ds <- active_dataset()
      if (!isTruthy(ds)) return(NULL)
      tryCatch(dataset_pool[[ds]], error = function(e) NULL)
    })

    # ---- Role pickers -------------------------------------------------------
    # Built from the ACTIVE dataset and filtered by each role's declared type,
    # so a numeric-only response never offers a text column.
    output$roles_ui <- renderUI({
      df <- .df()
      if (!is.data.frame(df) || !ncol(df))
        return(div(class = "ea-hint", "Choose a dataset in the layers panel first."))
      lapply(spec$roles, function(rl) {
        ok <- names(df)[vapply(df, function(x) ea_role_ok(x, rl$types), logical(1))]
        if (!length(ok))
          return(div(class = "ea-hint",
            sprintf("%s: this dataset has no %s column.", rl$label, rl$types)))
        # Keep what the user picked across re-renders. isolate() because we
        # depend on the DATASET here, never on our own selection -- without it
        # the picker would rebuild on every keystroke elsewhere and blank
        # itself (gotcha 21).
        prev <- isolate(input[[paste0("r_", rl$key)]])
        keep <- if (length(prev)) prev[prev %in% ok] else character(0)
        lbl <- if (isTRUE(rl$required)) rl$label else paste0(rl$label)
        tagList(
          if (isTRUE(rl$multiple))
            selectizeInput(ns(paste0("r_", rl$key)), lbl, choices = ok,
                           selected = keep, multiple = TRUE,
                           options = list(plugins = list("remove_button"),
                                          placeholder = "Choose one or more columns"))
          else
            selectInput(ns(paste0("r_", rl$key)), lbl,
                        choices = c(stats::setNames("", "Choose a column..."), ok),
                        selected = if (length(keep)) keep[1] else ""),
          if (!is.null(rl$hint))
            tags$p(class = "text-muted small mt-n1 mb-2", rl$hint))
      })
    })

    fit_obj <- reactiveVal(NULL)
    err_msg <- reactiveVal(NULL)

    # Clear a stale result when the dataset changes -- otherwise the canvas
    # keeps showing a model fitted on data that is no longer on screen.
    observeEvent(active_dataset(), {
      fit_obj(NULL); err_msg(NULL)
    }, ignoreInit = TRUE)

    observeEvent(input$run, {
      df <- .df()
      if (!is.data.frame(df)) {
        showNotification("No dataset selected.", type = "warning"); return()
      }
      r <- list()
      for (rl in spec$roles) {
        v <- input[[paste0("r_", rl$key)]]
        v <- v[nzchar(v)]
        if (!length(v)) {
          if (isTRUE(rl$required)) {
            showNotification(sprintf("Choose a %s first.", tolower(rl$label)),
                             type = "warning")
            return()
          }
          v <- NULL
        }
        r[[rl$key]] <- if (isTRUE(rl$multiple)) v else v[1]
      }
      p <- list()
      for (q in spec$params) p[[q$key]] <- input[[paste0("p_", q$key)]]

      withProgress(message = paste0("Fitting ", spec$label, "..."), value = 0.5, {
        res <- tryCatch(spec$fit(df, r, p), error = function(e) e,
                        warning = function(w) w)
        if (inherits(res, "error")) {
          fit_obj(NULL); err_msg(conditionMessage(res))
          showNotification(paste0(spec$label, " failed: ", conditionMessage(res)),
                           type = "error", duration = 10)
          return()
        }
        # A warning is not a failure -- a convergence warning still returns a
        # usable fit, and hiding it would be worse than showing it.
        if (inherits(res, "condition")) {
          err_msg(conditionMessage(res))
          res <- tryCatch(suppressWarnings(spec$fit(df, r, p)),
                          error = function(e) NULL)
          if (is.null(res)) { fit_obj(NULL); return() }
        } else err_msg(NULL)
        fit_obj(list(fit = res, roles = r, params = p, n = nrow(df)))
        showNotification(paste0(spec$label, " fitted."), type = "message")
      })
    })

    output$status <- renderUI({
      e <- err_msg()
      f <- fit_obj()
      if (!is.null(e) && is.null(f))
        return(div(class = "ea-subpanel ea-subpanel-warn mt-2", tags$small(e)))
      if (!is.null(e))
        return(div(class = "ea-subpanel ea-subpanel-warn mt-2",
                   tags$small(tags$b("Fitted with a warning: "), e)))
      if (is.null(f)) return(NULL)
      div(class = "ea-hint mt-2", sprintf("Fitted on %d rows.", f$n))
    })

    output$view_body <- renderUI({
      f <- fit_obj()
      if (is.null(f))
        return(show_placeholder(paste0("Set the options, then press Run to fit ",
                                       tolower(spec$label), ".")))
      ea_view_panes(input$view_pick, spec$views, function(k, solo)
        tryCatch(spec$render(f$fit, k, solo),
                 error = function(e)
                   show_placeholder(paste("Could not render this view:",
                                          conditionMessage(e)))))
    })

    # Context for the Co-Analyst, keyed the same way every other screen is.
    list(
      context = reactive({
        f <- fit_obj()
        if (is.null(f)) return(sprintf("%s: not run yet.", spec$label))
        roles_txt <- paste(
          sprintf("%s = %s", names(f$roles),
                  vapply(f$roles, function(v) paste(v, collapse = " + "),
                         character(1))),
          collapse = "; ")
        paste0(spec$label, " fitted on ", f$n, " rows.\n",
               "Roles: ", roles_txt, "\n\n",
               paste(utils::capture.output(summary(f$fit)), collapse = "\n"))
      }),
      plot = function() NULL
    )
  })
}
