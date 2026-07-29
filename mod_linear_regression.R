# ==========================================================================
# MODULE: Statistical Regression
# Types: Multiple Linear | Polynomial | Ridge / Lasso | Poisson (count)
# lmToolsUI / lmCanvasUI / lmServer  (kept as "lm" for backward compat)
# ==========================================================================

# ---- File-scope helpers ---------------------------------------------------

.as_row <- function(label, status, value, note = NULL) {
  # Semantic colours from the theme, and the row background as a TRANSLUCENT
  # tint of the same colour. The old fixed pastels (#f1f8e9 and friends) with
  # grey text were unreadable on the dark sets — a tint works on every set
  # because it takes its lightness from whatever is behind it.
  col <- c(pass = "var(--forest)", warn = "var(--warn)",
           fail = "var(--danger)", info = "var(--canopy)")
  bg  <- vapply(col, function(c) paste0("color-mix(in srgb, ", c, " 14%, transparent)"),
                character(1))
  # icons, not emoji (app rule: no picture characters anywhere in the UI)
  sym <- list(pass = icon("circle-check"), warn = icon("triangle-exclamation"),
              fail = icon("circle-xmark"),  info = icon("circle-info"))
  tags$div(
    style = paste0(
      "display:flex;align-items:flex-start;gap:10px;padding:9px 12px;",
      "margin-bottom:6px;border-radius:6px;background:", bg[[status]], ";"
    ),
    tags$span(style = paste0("color:", col[[status]], ";font-size:16px;flex-shrink:0;"),
              sym[[status]]),
    tags$div(
      tags$div(style = "font-size:13px;font-weight:600;", label),
      tags$div(style = "font-size:12px;color:var(--ink);", value),
      if (!is.null(note))
        tags$div(style = "font-size:11px;color:var(--bark);margin-top:2px;", note)
    )
  )
}

# VIF: uses car if available, otherwise auxiliary-regression approach
.lm_vif <- function(model) {
  tryCatch({
    if (requireNamespace("car", quietly = TRUE)) {
      v <- car::vif(model)
      return(if (is.matrix(v)) v[, "GVIF"] else v)
    }
    mm <- model.matrix(model)[, -1, drop = FALSE]
    if (ncol(mm) < 2) return(NULL)
    setNames(
      sapply(seq_len(ncol(mm)), function(j) {
        r2 <- summary(lm(mm[, j] ~ mm[, -j]))$r.squared
        1 / max(1e-9, 1 - r2)
      }),
      colnames(mm)
    )
  }, error = function(e) NULL)
}

# Assumption panel for lm / poly
.assump_lm <- function(model) {
  tagList(
    tryCatch({
      r  <- residuals(model)
      sw <- if (length(r) <= 5000) shapiro.test(r) else NULL
      if (!is.null(sw)) {
        st <- if (sw$p.value > 0.05) "pass" else if (sw$p.value > 0.01) "warn" else "fail"
        .as_row("Normality of residuals (Shapiro-Wilk)", st,
          sprintf("W = %.4f,  p = %.4f", sw$statistic, sw$p.value),
          if (st != "pass") "Consider log/sqrt transforming Y, or use a GLM.")
      } else {
        ct <- cor.test(sort(r), qnorm(ppoints(length(r))), method = "pearson")
        st <- if (ct$p.value > 0.05) "pass" else "warn"
        .as_row("Normality (QQ-correlation, n > 5000)", st,
          sprintf("r = %.4f,  p = %.4f", ct$estimate, ct$p.value))
      }
    }, error = function(e)
      .as_row("Normality", "info", paste("Could not test:", e$message))),

    tryCatch({
      ct <- cor.test(residuals(model)^2, fitted(model),
                     method = "spearman", exact = FALSE)
      st <- if (ct$p.value > 0.05) "pass" else if (ct$p.value > 0.01) "warn" else "fail"
      .as_row("Homoscedasticity (Spearman |resid²| ~ fitted)", st,
        sprintf("ρ = %.4f,  p = %.4f", ct$estimate, ct$p.value),
        if (st != "pass")
          "Variance grows with fitted values. Try log(Y) or weighted regression.")
    }, error = function(e)
      .as_row("Homoscedasticity", "info", paste("Could not test:", e$message))),

    tryCatch({
      vf <- .lm_vif(model)
      if (!is.null(vf) && length(vf) > 0) {
        mx <- max(vf, na.rm = TRUE)
        st <- if (mx < 5) "pass" else if (mx < 10) "warn" else "fail"
        .as_row("Multicollinearity (VIF)", st,
          paste(sprintf("%s: %.2f", names(vf), vf), collapse = "  |  "),
          if (st != "pass")
            "VIF > 5 indicates collinearity. Remove or combine correlated predictors.")
      } else {
        .as_row("Multicollinearity (VIF)", "info",
          "Single predictor — VIF not applicable.")
      }
    }, error = function(e)
      .as_row("Multicollinearity", "info", paste("VIF error:", e$message))),

    tryCatch({
      ck  <- cooks.distance(model)
      thr <- 4 / length(ck)
      n_  <- sum(ck > thr, na.rm = TRUE)
      st  <- if (n_ == 0) "pass" else if (n_ <= 3) "warn" else "fail"
      .as_row("Influential observations (Cook's D)", st,
        sprintf("%d observation(s) exceed 4/n = %.4f", n_, thr),
        if (n_ > 0) paste("Rows:", paste(which(ck > thr), collapse = ", ")))
    }, error = function(e)
      .as_row("Cook's D", "info", paste("Could not compute:", e$message)))
  )
}

# Assumption panel for Poisson GLM
.assump_poisson <- function(model) {
  y_vec <- model$model[[1]]
  tagList(
    tryCatch({
      ok <- all(y_vec >= 0) && all(y_vec == floor(y_vec))
      .as_row("Response: non-negative integers",
        if (ok) "pass" else "fail",
        if (ok) "All values are non-negative integers."
        else "Negative or non-integer values found. Poisson requires count data.")
    }, error = function(e)
      .as_row("Response check", "info", e$message)),

    tryCatch({
      disp <- sum(residuals(model, type = "pearson")^2) / df.residual(model)
      st   <- if (disp < 1.5) "pass" else if (disp < 3) "warn" else "fail"
      .as_row("Overdispersion (Pearson χ²/df)", st,
        sprintf("Dispersion ratio = %.3f", disp),
        switch(st,
          warn = "Mild overdispersion. Consider quasi-Poisson.",
          fail = "Severe overdispersion. Use negative binomial regression.",
          NULL))
    }, error = function(e)
      .as_row("Overdispersion", "info", e$message)),

    tryCatch({
      p  <- pchisq(model$deviance, model$df.residual, lower.tail = FALSE)
      st <- if (p > 0.05) "pass" else if (p > 0.01) "warn" else "fail"
      .as_row("Goodness of fit (deviance χ² test)", st,
        sprintf("Deviance = %.2f on %d df,  p = %.4f",
                model$deviance, model$df.residual, p),
        if (st != "pass")
          "Poor fit. Check for missing predictors or use negative binomial.")
    }, error = function(e)
      .as_row("Goodness of fit", "info", e$message)),

    tryCatch({
      ck  <- cooks.distance(model)
      thr <- 4 / length(ck)
      n_  <- sum(ck > thr, na.rm = TRUE)
      st  <- if (n_ == 0) "pass" else if (n_ <= 3) "warn" else "fail"
      .as_row("Influential observations (Cook's D)", st,
        sprintf("%d observation(s) exceed 4/n = %.4f", n_, thr),
        if (n_ > 0) paste("Rows:", paste(which(ck > thr), collapse = ", ")))
    }, error = function(e)
      .as_row("Cook's D", "info", e$message))
  )
}

# Assumption panel for Ridge / Lasso (glmnet)
.assump_glmnet <- function(res) {
  nm  <- if (res$alpha == 0) "Ridge" else if (res$alpha == 1) "Lasso" else "Elastic Net"
  r   <- res$y - res$pred
  tss <- sum((res$y - mean(res$y))^2)
  rss <- sum(r^2)
  r2  <- 1 - rss / max(tss, 1e-12)
  tagList(
    .as_row("Assumption context", "info",
      paste(nm, "is a regularised estimator — classical OLS assumptions do not strictly apply."),
      "Assess predictive performance and coefficient stability rather than p-values."),

    tryCatch({
      cf   <- res$coef[-1]
      n_nz <- sum(abs(cf) > 1e-10)
      n_z  <- length(cf) - n_nz
      if (res$alpha >= 0.5) {
        st <- if (n_nz > 0) "pass" else "warn"
        .as_row(sprintf("Sparsity at optimal λ (%.5f)", res$lambda), st,
          sprintf("%d predictor(s) retained, %d shrunk to zero.", n_nz, n_z))
      } else {
        .as_row(sprintf("Ridge coefficients at optimal λ (%.5f)", res$lambda),
          "info",
          sprintf("All %d predictor(s) retained (Ridge never zeroes out).", length(cf)),
          "Ridge shrinks but never eliminates — all predictors remain in the model.")
      }
    }, error = function(e) .as_row("Coefficients", "info", e$message)),

    tryCatch({
      st <- if (r2 > 0.7) "pass" else if (r2 > 0.4) "warn" else "fail"
      .as_row("In-sample predictive fit", st,
        sprintf("R² = %.4f  |  RMSE = %.4f", r2, sqrt(mean(r^2))),
        "Computed on training data at the optimal cross-validated λ.")
    }, error = function(e) .as_row("Predictive fit", "info", e$message))
  )
}

# ==========================================================================
# UI
# ==========================================================================

lmToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$p(
      style = "font-size:10px;text-transform:uppercase;letter-spacing:.8px;color:var(--forest);font-weight:700;margin:0 0 4px;",
      "Regression Type"
    ),
    radioButtons(ns("reg_type"), NULL,
      choices = c(
        "Multiple Linear"   = "lm",
        "Polynomial"        = "poly",
        "Ridge / Lasso"     = "glmnet",
        "Poisson (counts)"  = "poisson"
      ),
      selected = "lm"
    ),
    hr(style = "margin:8px 0;"),

    selectInput(ns("y"), "Response Variable (Y):", choices = NULL, width = "100%"),

    # Dependent-variable transform + bias-corrected back-transform.
    # Always visible (nothing hidden). Poisson ignores these — its link handles
    # the response scale — and the caption says so.
    selectInput(ns("y_trans"), "Transform Y:", width = "100%",
      choices = c("None"       = "raw",
                  "log(Y)"     = "log",
                  "log(1 + Y)" = "log1p",
                  "sqrt(Y)"    = "sqrt",
                  "1 / Y"      = "inv")),
    checkboxInput(ns("y_backtrans"),
      "Back-transform to original scale (bias-corrected)", value = TRUE),
    tags$small(class = "text-muted d-block mb-2",
      "When Y is transformed, metrics are reported on the original Y scale using the",
      "Kalliovirta & Tokola (2005) bias correction. (Ignored for Poisson.)"),

    # ---- Multiple Linear + Poisson: formula builder ----
    conditionalPanel(
      "input.reg_type == 'lm' || input.reg_type == 'poisson'", ns = ns,
      conditionalPanel("input.reg_type == 'poisson'", ns = ns,
        selectInput(ns("poisson_link"), "Link function:",
          choices  = c("log" = "log", "sqrt" = "sqrt", "identity" = "identity"),
          selected = "log", width = "100%")
      ),
      tags$small(class = "text-muted fw-bold d-block mb-1", "Predictors (X)"),
      textAreaInput(ns("formula_text"), NULL, value = "", rows = 3,
        placeholder = "e.g., x1 + log(x2) + x1:x2", width = "100%"),
      div(
        style = "background:var(--sunk);color:var(--ink);padding:8px;border-radius:4px;border:1px solid var(--line);",
        tags$small(class = "text-muted", "Quick Builder"),
        selectInput(ns("build_var"),   NULL, choices = NULL, width = "100%"),
        selectInput(ns("build_trans"), NULL, width = "100%",
          choices = c("None"    = "raw",
                      "log()"   = "log",
                      "sqrt()"  = "sqrt",
                      "I(x²)" = "sq")),
        div(style = "display:flex;gap:4px;",
          actionButton(ns("btn_add_var"),  "Insert",
            class = "btn-primary btn-sm flex-fill"),
          actionButton(ns("btn_add_plus"), "+",
            class = "btn-secondary btn-sm px-3"),
          actionButton(ns("btn_add_star"), "×",
            class = "btn-secondary btn-sm px-3"),
          actionButton(ns("btn_clear"),    "✕",
            class = "btn-outline-danger btn-sm px-2")
        )
      )
    ),

    # ---- Polynomial ----
    conditionalPanel("input.reg_type == 'poly'", ns = ns,
      selectInput(ns("poly_x"), "Predictor (X):", choices = NULL, width = "100%"),
      sliderInput(ns("poly_deg"), "Degree:", min = 1, max = 6, value = 2, step = 1),
      checkboxInput(ns("poly_raw"), "Raw (non-orthogonal) polynomials", value = FALSE)
    ),

    # ---- Ridge / Lasso ----
    conditionalPanel("input.reg_type == 'glmnet'", ns = ns,
      selectInput(ns("glmnet_x"), "Predictors (X):",
        choices = NULL, multiple = TRUE, width = "100%"),
      sliderInput(ns("glmnet_alpha"),
        "Alpha  (0 = Ridge · 1 = Lasso):",
        min = 0, max = 1, value = 1, step = 0.1),
      radioButtons(ns("lambda_mode"), "Lambda selection:",
        choices  = c("Auto (cross-validation)" = "cv", "Manual" = "manual"),
        selected = "cv", inline = TRUE),
      conditionalPanel("input.lambda_mode == 'manual'", ns = ns,
        numericInput(ns("lambda_val"), NULL, value = 0.01, min = 1e-8, step = 0.001))
    ),

    hr(style = "margin:10px 0;"),
    actionButton(ns("run_model"), "Run Model",
      class = "btn-success w-100", icon = icon("play"))
  )
}

lmCanvasUI <- function(id) {
  ns <- NS(id)
  # You choose what is on screen, and it splits between them.
  #
  # This screen used to show six outputs at once across three tabs: summary,
  # metrics and LOOCV squeezed side by side, ANOVA below them, plots and
  # assumption checks on their own tabs. Everything competed for the same space
  # and nothing had enough of it.
  #
  # DEFAULT IS ONE. That is the whole point -- clutter you chose is fine, clutter
  # by default is what was wrong. Pick a second output and the area splits, with
  # a draggable divider between panes.
  #
  # Stacked rather than side by side on purpose: summary, ANOVA and metrics are
  # wide monospace text that wraps badly at half width, and plots want width too.
  # Stacking keeps full width for every pane and lets you trade height instead.
  #
  # Note this is presentation only -- every output id is unchanged, so the
  # server still renders exactly what it did before (verified working: R-squared
  # and RMSE, the diagnostic plot, Shapiro-Wilk and the rest).
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center gap-2",
      div(class = "d-flex align-items-center gap-2",
        tags$span(class = "lm-view-label", "Show"),
        selectizeInput(ns("view_pick"), NULL, width = "330px", multiple = TRUE,
          choices = c("Model summary"      = "summary",
                      "Performance metrics" = "metrics",
                      "Cross-validation (LOOCV)" = "loocv",
                      "ANOVA / deviance table"   = "anova",
                      "Diagnostic plots"    = "diag",
                      "Assumption checks"   = "assume"),
          selected = "summary",
          options = list(plugins = list("remove_button"),
                         placeholder = "Pick one or more"))),
      # Controls that belong to the CURRENT view only, so the header does not
      # carry buttons for things that are not on screen.
      uiOutput(ns("view_tools"), inline = TRUE)
    ),
    # The interpretation line stays visible across views: it is the plain-English
    # answer, and hiding it behind a dropdown choice would bury the point.
    uiOutput(ns("interp_ui")),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

# ==========================================================================
# Server
# ==========================================================================

lmServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- The single view area (backlog item 12) ----------------------------
    # Renders ONE output at a time. Every id here is the same one the rest of
    # this server already writes to, so nothing about the modelling changed.
    .VIEW_NAMES <- c(summary = "Model summary", metrics = "Performance metrics",
                     loocv = "Cross-validation (LOOCV)", anova = "ANOVA / deviance table",
                     diag = "Diagnostic plots", assume = "Assumption checks")
    .view_one <- function(k, solo) switch(k,
      summary = tagList(
        div(class = "lm-formula-box", textOutput(ns("formula_display"))),
        div(class = "lm-scroll", verbatimTextOutput(ns("summary")))),
      metrics = div(class = "lm-scroll", verbatimTextOutput(ns("uef_metrics"))),
      loocv   = div(class = "lm-scroll", verbatimTextOutput(ns("loocv_out"))),
      anova   = div(class = "lm-scroll", verbatimTextOutput(ns("anova"))),
      # A plot needs a real height; when sharing the area it takes the pane's.
      diag    = plotOutput(ns("diag_plot"), height = if (solo) "560px" else "100%"),
      assume  = div(class = "lm-scroll", uiOutput(ns("assumption_ui"))),
      NULL)

    output$view_body <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- "summary"        # never show an empty canvas
      if (length(picked) == 1) return(.view_one(picked, solo = TRUE))
      # 2+ : stacked panes, each labelled, with a draggable divider between them
      panes <- list()
      for (i in seq_along(picked)) {
        k <- picked[[i]]
        if (i > 1) panes[[length(panes) + 1]] <- div(class = "lm-split",
                                                     title = "Drag to resize")
        panes[[length(panes) + 1]] <- div(class = "lm-pane",
          div(class = "lm-pane-h", .VIEW_NAMES[[k]] %||% k),
          div(class = "lm-pane-b", .view_one(k, solo = FALSE)))
      }
      div(class = "lm-panes", panes)
    })
    # Header controls follow the view: the CSV download belongs to the summary,
    # the grid/single switch belongs to the plots, and neither should sit in the
    # header while the other is showing.
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- "summary"
      tagList(
        if ("summary" %in% picked)
          downloadButton(ns("dl_coefs"), "CSV", class = "btn-sm btn-outline-secondary"),
        if ("diag" %in% picked)
          div(class = "d-flex align-items-center gap-2",
              uiOutput(ns("diag_mode_ui")), uiOutput(ns("single_selector"))),
        # only when a plot is actually on screen
        if (any(vapply(picked, ea_is_plot_view, logical(1)))) ea_plot_appearance())
    })

    active_data <- reactive({
      ds <- active_dataset()
      if (is.null(ds)) return(NULL)
      dataset_pool[[ds]]
    })

    # --- dependent-variable transforms -------------------------------------
    # Wrap the response term in a formula (for lm/poly/poisson), or transform a
    # numeric response vector (for glmnet, which bypasses the formula). Both use
    # the same input$y_trans so what you see in the formula is what is fitted.
    .y_term <- function(safe_y, trans) switch(trans %||% "raw",
      raw = safe_y, log = paste0("log(", safe_y, ")"),
      log1p = paste0("log1p(", safe_y, ")"), sqrt = paste0("sqrt(", safe_y, ")"),
      inv = paste0("I(1/", safe_y, ")"), safe_y)
    .y_vec <- function(y, trans) switch(trans %||% "raw",
      raw = y, log = log(y), log1p = log1p(y), sqrt = sqrt(y), inv = 1 / y, y)
    # Exact inverse of a Y-transform — recovers OBSERVED values on the original
    # scale (no bias term; it just undoes the transform).
    .y_invert <- function(v, trans) switch(trans %||% "raw",
      raw = v, log = exp(v), log1p = expm1(v), sqrt = v^2, inv = 1 / v, v)
    # Bias-corrected back-transform of PREDICTIONS (Kalliovirta & Tokola 2005).
    # s2 = residual variance on the fit (transformed) scale.
    #   log / log1p : lognormal correction  E[Y] = exp(mu + s2/2)
    #   sqrt        : d = f^2 + var(eps)     (paper eq. for diameter)
    #   inverse     : naive 1/fit only — the 2nd-order Taylor correction for
    #                 E[1/X] is numerically unstable near small fitted values,
    #                 and the paper does not use an inverse transform.
    .y_backpred <- function(fit, trans, s2) switch(trans %||% "raw",
      raw   = fit,
      log   = exp(fit) * exp(s2 / 2),
      log1p = expm1(fit + s2 / 2),
      sqrt  = fit^2 + s2,
      inv   = 1 / fit,
      fit)
    # Returns an error string if the transform is invalid for the data, else NULL.
    .y_trans_problem <- function(y, trans) {
      trans <- trans %||% "raw"
      if (trans %in% c("log", "sqrt") && any(y <= 0, na.rm = TRUE))
        return(sprintf("Cannot apply %s to a response with values ≤ 0. Use log(1 + Y), or shift the variable first.", trans))
      if (trans == "inv" && any(y == 0, na.rm = TRUE))
        return("Cannot apply 1 / Y when the response contains zeros.")
      if (trans == "log1p" && any(y <= -1, na.rm = TRUE))
        return("Cannot apply log(1 + Y) when the response has values ≤ -1.")
      NULL
    }

    # Populate selectors on dataset change
    observe({
      df <- active_data(); req(df)
      cols <- names(df)
      upd <- function(id, chs) {
        cur <- isolate(input[[id]])
        updateSelectInput(session, id, choices = chs,
          selected = if (isTruthy(cur) && cur %in% chs) cur else chs[1])
      }
      upd("y",         cols)
      upd("build_var", cols)
      upd("poly_x",    cols)
      cur_x <- isolate(input$glmnet_x)
      valid  <- intersect(cur_x, cols)
      updateSelectInput(session, "glmnet_x", choices = cols,
        selected = if (length(valid)) valid else character(0))
    })

    # Formula builder (lm / poisson path)
    observeEvent(input$btn_add_var, {
      var  <- paste0("`", input$build_var, "`")
      term <- switch(input$build_trans %||% "raw",
        raw  = var,
        log  = paste0("log(", var, ")"),
        sqrt = paste0("sqrt(", var, ")"),
        sq   = paste0("I(", var, "^2)"),
        var
      )
      cur <- trimws(input$formula_text %||% "")
      updateTextAreaInput(session, "formula_text",
        value = if (nchar(cur)) paste(cur, term) else term)
    })
    observeEvent(input$btn_add_plus, {
      cur <- trimws(input$formula_text %||% "")
      if (nchar(cur)) updateTextAreaInput(session, "formula_text",
        value = paste(cur, "+"))
    })
    observeEvent(input$btn_add_star, {
      cur <- trimws(input$formula_text %||% "")
      if (nchar(cur)) updateTextAreaInput(session, "formula_text",
        value = paste(cur, "*"))
    })
    observeEvent(input$btn_clear, {
      updateTextAreaInput(session, "formula_text", value = "")
    })

    formula_str <- reactive({
      req(input$y)
      type   <- input$reg_type %||% "lm"
      # Poisson keeps the raw response (its link handles the scale); everything
      # else honours the Transform Y selector.
      safe_y <- paste0("`", input$y, "`")
      if (type != "poisson") safe_y <- .y_term(safe_y, input$y_trans)
      if (type == "poly") {
        x <- input$poly_x %||% names(active_data())[2]
        d <- input$poly_deg %||% 2
        r <- if (isTRUE(input$poly_raw)) ", raw = TRUE" else ""
        return(paste0(safe_y, " ~ poly(`", x, "`, ", d, r, ")"))
      }
      xs <- trimws(input$formula_text %||% "")
      if (!nchar(xs)) return(paste(safe_y, "~ ..."))
      paste(safe_y, "~", xs)
    })

    output$formula_display <- renderText({ formula_str() })

    # ---- Fit model (button-triggered) -------------------------------------

    fitted_model_r <- eventReactive(input$run_model, ignoreNULL = FALSE, {
      df   <- active_data(); req(df)
      type <- input$reg_type %||% "lm"
      y_nm <- input$y;      req(isTruthy(y_nm), y_nm %in% names(df))

      if (type %in% c("lm", "poly")) {
        fs <- formula_str()
        if (grepl("\\.\\.\\.", fs)) return("Add predictors to the formula first.")
        prob <- .y_trans_problem(df[[y_nm]], input$y_trans)
        if (!is.null(prob)) return(prob)
        m <- tryCatch(lm(as.formula(fs), data = df),
                      error = function(e) paste("Formula error:", e$message))
        if (is.character(m)) return(m)
        list(model = m, type = type, y_var = y_nm)

      } else if (type == "poisson") {
        fs  <- formula_str()
        if (grepl("\\.\\.\\.", fs)) return("Add predictors to the formula first.")
        lnk <- input$poisson_link %||% "log"
        m   <- tryCatch(
          glm(as.formula(fs), data = df, family = poisson(link = lnk)),
          error = function(e) paste("GLM error:", e$message))
        if (is.character(m)) return(m)
        list(model = m, type = "poisson", y_var = y_nm)

      } else {
        if (!requireNamespace("glmnet", quietly = TRUE))
          return("Package 'glmnet' is not installed.\nRun: install.packages('glmnet')")
        x_nms <- input$glmnet_x
        if (!length(x_nms)) return("Select at least one predictor (X).")
        prob <- .y_trans_problem(df[[y_nm]], input$y_trans)
        if (!is.null(prob)) return(prob)
        y_vec <- .y_vec(df[[y_nm]], input$y_trans)
        x_mat <- tryCatch(
          model.matrix(~ . - 1, data = df[, x_nms, drop = FALSE]),
          error = function(e) NULL)
        if (is.null(x_mat)) return("Could not build predictor matrix.")
        alp  <- input$glmnet_alpha %||% 1
        gfit <- glmnet::glmnet(x_mat, y_vec, alpha = alp)
        if ((input$lambda_mode %||% "cv") == "cv") {
          cvf <- glmnet::cv.glmnet(x_mat, y_vec, alpha = alp)
          lam <- cvf$lambda.min
        } else {
          cvf <- NULL; lam <- input$lambda_val %||% 0.01
        }
        cf   <- as.numeric(coef(gfit, s = lam))
        pred <- as.numeric(predict(gfit, x_mat, s = lam))
        list(
          type       = "glmnet",
          y_var      = y_nm,
          y          = y_vec,
          pred       = pred,
          coef       = setNames(cf, c("(Intercept)", colnames(x_mat))),
          cv_fit     = cvf,
          glmnet_fit = gfit,
          lambda     = lam,
          alpha      = alp
        )
      }
    })

    # ---- Outputs -----------------------------------------------------------

    output$summary <- renderPrint({
      res <- fitted_model_r()
      if (is.character(res)) { cat(res); return() }
      if (res$type == "glmnet") {
        cf <- res$coef
        cat(sprintf("%-30s  %s\n\n", "Coefficient", "Value"))
        for (i in seq_along(cf))
          cat(sprintf("%-30s  % .6f\n", names(cf)[i], cf[i]))
        if (!is.null(res$cv_fit))
          cat(sprintf("\nOptimal lambda (CV): %.6f\n", res$lambda))
      } else {
        print(res$model$call); cat("\n"); print(summary(res$model))
      }
    })

    output$anova <- renderPrint({
      res <- fitted_model_r()
      if (is.character(res)) { cat("Awaiting valid model.\n"); return() }
      if (res$type == "glmnet") {
        cat("ANOVA not applicable for regularised regression.\n")
      } else {
        tryCatch(print(anova(res$model)),
                 error = function(e) cat("ANOVA error:", e$message))
      }
    })

    output$uef_metrics <- renderPrint({
      res <- fitted_model_r()
      if (is.character(res)) { cat("Awaiting valid model.\n"); return() }
      tryCatch({
        if (res$type == "glmnet") { pred_t <- res$pred; obs_t <- res$y }
        else { pred_t <- fitted(res$model); obs_t <- res$model$model[[1]] }

        trans <- input$y_trans %||% "raw"
        backt <- isTRUE(input$y_backtrans) && trans != "raw" &&
                 res$type %in% c("lm", "poly", "glmnet")
        if (backt) {
          s2   <- if (res$type == "glmnet") mean((obs_t - pred_t)^2)
                  else summary(res$model)$sigma^2
          pred <- .y_backpred(pred_t, trans, s2)
          obs  <- .y_invert(obs_t, trans)
          scale_lbl <- "original Y (bias-corrected)"
        } else {
          pred <- pred_t; obs <- obs_t
          scale_lbl <- if (trans != "raw") sprintf("%s(Y) — fit scale", trans) else "original Y"
        }

        m <- uef_evaluation(pred, obs)
        cat(sprintf("Scale    : %s\n", scale_lbl))
        cat(sprintf(
          "RMSE     : %.4f\nR²       : %.4f\nBias     : %.4f\nRelBias  : %.4f\nRRMSE    : %.4f\n",
          m$RMSE, m$R2, m$Bias, m$RelBias, m$RRMSE))
        if (backt) {
          corr <- switch(trans, log = , log1p = "× exp(s²/2)", sqrt = "+ s²",
                         inv = "none (naive 1/fit — unstable to correct)", "")
          cat(sprintf("\nBias correction: %s   (s² = %.5f on fit scale)\n", corr, s2))
        }
      }, error = function(e) cat("Metrics error:", e$message, "\n"))
    })

    output$loocv_out <- renderPrint({
      res <- fitted_model_r()
      if (is.character(res) || is.null(res)) { cat("Fit a model first.\n"); return() }
      if (res$type == "glmnet") { cat("LOOCV not available for regularised (ridge/lasso) models.\n"); return() }
      tryCatch({
        cv <- .loocv_lm(res$model)
        cat(sprintf("LOOCV RMSE : %.4f\nLOOCV MAE  : %.4f\nLOOCV R²   : %.4f\n",
                    cv$LOOCV_RMSE, cv$LOOCV_MAE, cv$LOOCV_R2))
        cat("\n(Exact: uses hat-matrix shortcut, no model refits.)\n")
      }, error = function(e) cat("LOOCV error:", e$message, "\n"))
    })

    # Diagnostics tab --------------------------------------------------------

    output$diag_mode_ui <- renderUI({
      res <- fitted_model_r()
      if (is.character(res) || is.null(res) ||
          (!is.character(res) && res$type == "glmnet")) return(NULL)
      radioGroupButtons(ns("view_mode"), NULL,
        choices  = c("Grid" = "Grid View", "Single" = "Single Plot"),
        selected = "Grid View", size = "sm", status = "primary")
    })

    output$single_selector <- renderUI({
      res <- fitted_model_r()
      if (is.character(res) || is.null(res)) return(NULL)
      if (res$type == "glmnet") return(NULL)
      req(input$view_mode == "Single Plot")
      selectInput(ns("zoom_target"), NULL,
        choices = c("Fitted vs Actual", "Residual Plot", "Target Distribution"),
        width   = "200px")
    })

    output$diag_plot <- renderPlot({
      res <- fitted_model_r()
      if (is.character(res) || is.null(res)) {
        show_placeholder(res %||% "Run a model to see diagnostics.")
        return()
      }
      if (res$type == "glmnet") {
        ea_multi_par(mfrow = c(1, if (!is.null(res$cv_fit)) 2L else 1L))
        if (!is.null(res$cv_fit)) {
          plot(res$cv_fit, main = "CV Curve: Lambda vs MSE")
          abline(v = log(res$lambda), col = "#2e7d32", lwd = 2, lty = 2)
        }
        plot(res$glmnet_fit, xvar = "lambda",
             main = "Coefficient Regularisation Path")
        abline(v = log(res$lambda), col = "#2e7d32", lwd = 2, lty = 2)
        ea_fig_title()
        par(mfrow = c(1, 1))
      } else {
        df <- active_data(); req(df)
        vm <- input$view_mode   %||% "Grid View"
        zt <- input$zoom_target %||% "Fitted vs Actual"
        plot_lm_diagnostics(res$model, df, res$y_var, vm, zt)
      }
    })

    

    # Assumptions tab --------------------------------------------------------

    output$assumption_ui <- renderUI({
      res <- fitted_model_r()
      if (is.character(res) || is.null(res))
        return(div(class = "text-muted p-3",
          "Run a model first to see assumption checks."))
      tryCatch(
        switch(res$type,
          lm = .assump_lm(res$model),

          poly = tagList(
            .assump_lm(res$model),
            hr(),
            tryCatch({
              df   <- active_data(); req(df)
              x_nm <- input$poly_x %||% names(df)[2]
              y_nm <- res$y_var
              aics <- sapply(1:6, function(d) {
                m <- tryCatch(
                  lm(as.formula(paste0("`", y_nm,
                       "` ~ poly(`", x_nm, "`, ", d, ")")), data = df),
                  error = function(e) NULL)
                if (is.null(m)) NA_real_ else AIC(m)
              })
              best <- which.min(aics)
              cur  <- input$poly_deg %||% 2
              tbl  <- data.frame(
                Degree = 1:6,
                AIC    = round(aics, 2),
                Note   = ifelse(1:6 == best, "<- best", "")
              )
              .as_row("Optimal degree (AIC comparison)",
                if (best == cur) "pass" else "warn",
                paste("Best:", best, "| Current:", cur),
                paste(utils::capture.output(
                  print(tbl, row.names = FALSE)), collapse = "\n"))
            }, error = function(e)
              .as_row("AIC comparison", "info", e$message))
          ),

          poisson = .assump_poisson(res$model),
          glmnet  = .assump_glmnet(res)
        ),
        error = function(e)
          div(class = "text-danger p-3", paste("Assumption check error:", e$message))
      )
    })

    output$interp_ui <- renderUI({
      res <- fitted_model_r(); req(!is.character(res), !is.null(res))
      tryCatch({
        if (res$type == "glmnet") {
          cf  <- res$coef[-1]
          n_k <- sum(abs(cf) > 1e-10)
          nm  <- if (res$alpha == 0) "Ridge" else if (res$alpha == 1) "Lasso" else "Elastic-Net"
          r   <- res$y - res$pred
          r2  <- 1 - sum(r^2) / max(sum((res$y - mean(res$y))^2), 1e-12)
          sent <- sprintf(
            "%s regression retained <b>%d predictor(s)</b> at λ = %.5f. In-sample R² = <b>%.3f</b>.",
            nm, n_k, res$lambda, r2)
        } else {
          sm  <- summary(res$model)
          r2  <- sm$r.squared
          n_s <- if (!is.null(sm$coefficients))
            sum(sm$coefficients[-1, "Pr(>|t|)"] < 0.05, na.rm = TRUE) else NA
          m   <- tryCatch(uef_evaluation(fitted(res$model), res$model$model[[1]]),
                          error = function(e) NULL)
          rmse_txt <- if (!is.null(m)) sprintf(", RMSE = <b>%.3f</b>", m$RMSE) else ""
          sent <- sprintf(
            "The model explains <b>%.1f%%</b> of variance in <b>%s</b> (R² = %.3f%s)%s.",
            100 * r2, res$y_var, r2, rmse_txt,
            if (!is.na(n_s)) sprintf(". <b>%d</b> predictor(s) were significant (p < 0.05)", n_s) else "")
        }
        card(tags$div(class = "p-3 small", HTML(sent)))
      }, error = function(e) NULL)
    })

    output$dl_coefs <- downloadHandler(
      filename = function() paste0("regression_coefficients_", Sys.Date(), ".csv"),
      content  = function(file) {
        res <- fitted_model_r(); req(!is.character(res), !is.null(res))
        if (res$type == "glmnet") {
          out <- data.frame(term = names(res$coef), estimate = res$coef,
                            stringsAsFactors = FALSE)
        } else {
          sm  <- summary(res$model)
          out <- as.data.frame(sm$coefficients)
          out <- cbind(term = rownames(out), out)
        }
        write.csv(out, file, row.names = FALSE)
      }
    )

    # AI co-pilot context
    list(
      context = reactive({
        res <- fitted_model_r()
        if (is.character(res) || is.null(res))
          return(paste("Statistical Regression — no model yet:", res))
        lbl <- c(lm = "Multiple Linear", poly = "Polynomial",
                 glmnet = "Ridge/Lasso", poisson = "Poisson")[[res$type]]
        if (res$type == "glmnet") {
          paste0(lbl, " Regression. Alpha=", res$alpha,
            ", Lambda=", round(res$lambda, 6), "\nCoefficients:\n",
            paste(sprintf("  %s: %.4f", names(res$coef), res$coef),
                  collapse = "\n"))
        } else {
          paste0(lbl, " Regression. Formula: ", formula_str(), "\n\nSummary:\n",
            paste(utils::capture.output(summary(res$model)), collapse = "\n"))
        }
      }),
      plot = function() {
        res <- fitted_model_r()
        if (is.null(res) || is.character(res)) return(invisible())
        if (res$type == "glmnet") {
          ea_multi_par(mfrow = c(1, if (!is.null(res$cv_fit)) 2L else 1L))
          if (!is.null(res$cv_fit)) plot(res$cv_fit)
          plot(res$glmnet_fit, xvar = "lambda")
          par(mfrow = c(1, 1))
        } else {
          plot_lm_diagnostics(res$model, active_data(), res$y_var,
            input$view_mode %||% "Grid View",
            input$zoom_target %||% "Fitted vs Actual")
        }
      }
    )
  })
}
