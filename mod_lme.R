# ==========================================================================
# MODULE: Linear Mixed Effects (LME)  (canvas + tools contract)
# lmeToolsUI / lmeCanvasUI / lmeServer(id, dataset_pool, active_dataset)
# Fit is triggered by the "Fit LME Model" button (nlme::lme).
# ==========================================================================

lmeToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "LME Parameters"),
    selectInput(ns("y"), "Dependent Variable (Y):", choices = NULL),
    hr(),
    markdown("**Fixed Effects Formula**\n*Predictors (X)*"),
    textAreaInput(ns("fixed_text"), "Fixed Effects (~):", value = "", rows = 3, placeholder = "e.g., ih5_dm + Soiltype2 * Texture"),
    div(class = "ea-subpanel",
        markdown("**Quick Builder**"),
        selectInput(ns("build_var"), "Select Variable:", choices = NULL),
        selectInput(ns("build_trans"), "Apply Transformation:", choices = c("None (Raw)" = "raw", "Logarithm (log)" = "log", "Square Root (sqrt)" = "sqrt", "Quadratic (^2)" = "poly")),
        fluidRow(
          column(6, actionButton(ns("btn_add_var"), "Insert", class = "btn-primary btn-sm", width = "100%", style = "margin-bottom:5px;")),
          column(3, actionButton(ns("btn_add_plus"), " + ", class = "btn-secondary btn-sm", width = "100%", style = "margin-bottom:5px;")),
          column(3, actionButton(ns("btn_add_star"), " * ", class = "btn-secondary btn-sm", width = "100%", style = "margin-bottom:5px;"))
        ),
        actionButton(ns("btn_clear"), "Clear Formula", class = "btn-outline-danger btn-sm", width = "100%")
    ),
    hr(),
    markdown("**Random Effects Formula**"),
    textInput(ns("random_text"), "Random structure (e.g., ~1 | Group):", placeholder = "~ 1 | PlotID"),
    div(class = "ea-subpanel",
        markdown("**Quick Builder**"),
        selectInput(ns("re_group"), "Grouping Variable:", choices = NULL),
        selectInput(ns("re_slope"), "Random Slope (optional):", choices = c("(Intercept only)" = "")),
        actionButton(ns("re_insert"), "Insert Random Effect", class = "btn-primary btn-sm", width = "100%")
    ),
    hr(),
    div(class = "ea-subpanel ea-subpanel-warn",
      markdown("**Convergence Options**"),
      checkboxInput(ns("auto_scale"), "Auto-scale numeric predictors (helps convergence)", value = FALSE),
      tags$p(class = "small text-muted mb-0",
        "Scaling centres and standardises predictors before fitting. Coefficients become SD units.")
    ),
    hr(),
    .cv_ui(ns),
    hr(),
    actionButton(ns("run"), "Fit LME Model", class = "btn-primary", width = "100%")
  )
}

lmeCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Model Diagnostics",
      ea_plot_appearance()),
      div(style = "overflow-y: auto; height: 400px; padding: 5px;", plotOutput(ns("diagnostics_plot")))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "d-flex justify-content-between align-items-center bg-light",
          "Model Summary",
          downloadButton(ns("dl_fixed_effects"), "CSV", class = "btn-sm btn-outline-secondary")),
        div(class = "formula-box", textOutput(ns("formula_display"))),
        div(style = "overflow-y: auto; height: 400px; padding: 5px;", verbatimTextOutput(ns("summary")))
      ),
      card(
        card_header(class = "bg-light", "Performance Metrics (Nakagawa R²) & VIF"),
        div(style = "overflow-y: auto; height: 400px; padding: 5px;", verbatimTextOutput(ns("performance")))
      ),
      card(
        card_header(class = "bg-light", "Cross-Validation"),
        div(style = "padding: 5px;", verbatimTextOutput(ns("cv_out")))
      )
    )
  )
}

lmeServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset()
      if (is.null(ds)) return(NULL)
      dataset_pool[[ds]]
    })

    observe({
      df <- active_data()
      req(df)
      cols <- names(df)
      cat_cols <- names(df)[sapply(df, is_safe_cat)]
      num_cols <- names(df)[sapply(df, is.numeric)]
      updateSelectInput(session, "y", choices = cols, selected = isolate(input$y))
      updateSelectInput(session, "build_var", choices = cols, selected = isolate(input$build_var))
      updateSelectInput(session, "re_group", choices = cat_cols, selected = isolate(input$re_group))
      updateSelectInput(session, "re_slope", choices = c("(Intercept only)" = "", num_cols), selected = isolate(input$re_slope))
    })

    # Random-effects quick builder: build "~ 1 | Group" or "~ slope | Group".
    observeEvent(input$re_insert, {
      req(input$re_group)
      lhs <- if (isTruthy(input$re_slope) && nzchar(input$re_slope)) input$re_slope else "1"
      updateTextInput(session, "random_text", value = paste0("~ ", lhs, " | ", input$re_group))
    })

    observeEvent(input$btn_add_var, {
      var <- input$build_var
      term <- switch(input$build_trans,
                     "raw" = var, "log" = paste0("log(", var, ")"),
                     "sqrt" = paste0("sqrt(", var, ")"), "poly" = paste0("I(", var, "^2)"))
      curr <- input$fixed_text
      new_text <- if (curr == "") term else paste(curr, "+", term)
      updateTextAreaInput(session, "fixed_text", value = new_text)
    })
    observeEvent(input$btn_add_plus, { updateTextAreaInput(session, "fixed_text", value = paste(input$fixed_text, "+ ")) })
    observeEvent(input$btn_add_star, { updateTextAreaInput(session, "fixed_text", value = paste(input$fixed_text, "* ")) })
    observeEvent(input$btn_clear, { updateTextAreaInput(session, "fixed_text", value = "") })

    output$formula_display <- renderText({
      if (input$fixed_text == "" && input$random_text == "") return("Awaiting formula...")
      paste(input$y, "~", input$fixed_text, "\nRandom:", input$random_text)
    })

    model_obj <- reactiveVal(NULL)

    observeEvent(input$run, {
      req(active_dataset(), input$y, input$fixed_text, input$random_text)
      df <- active_data()
      fixed_form_str <- paste(input$y, "~", input$fixed_text)
      withProgress(message = 'Fitting LME Model...', value = 0.5, {
        tryCatch({
          # Optional: scale all numeric predictors to improve convergence.
          df_fit  <- df
          scaled  <- FALSE
          if (isTRUE(input$auto_scale)) {
            num_cols <- names(df_fit)[sapply(df_fit, is.numeric)]
            # Don't scale the response variable itself.
            num_cols <- setdiff(num_cols, input$y)
            if (length(num_cols) > 0) {
              df_fit[num_cols] <- lapply(df_fit[num_cols], scale)
              scaled <- TRUE
            }
          }
          fixed_form  <- as.formula(fixed_form_str)
          random_form <- as.formula(input$random_text)
          # Always use optim + generous iteration limit to avoid premature failures.
          ctrl <- nlme::lmeControl(opt = "optim", msMaxIter = 1000)
          fit  <- nlme::lme(fixed = fixed_form, random = random_form,
                            data = df_fit, na.action = na.omit, control = ctrl)
          r2 <- tryCatch(MuMIn::r.squaredGLMM(fit),
                         error = function(e) matrix(NA, ncol = 2, dimnames = list(NULL, c("R2m", "R2c"))))
          model_obj(list(model = fit, data = df_fit, target = input$y, r2 = r2, scaled = scaled))
          msg <- if (scaled) "LME fitted (predictors were auto-scaled — coefficients in SD units)."
                 else        "LME Model fitted successfully!"
          showNotification(msg, type = "message")
        }, error = function(e) {
          showNotification(paste("Error fitting LME:", e$message), type = "error")
        })
      })
    })

    output$summary <- renderPrint({
      obj <- model_obj()
      if (is.null(obj)) return(cat("Awaiting model training..."))
      summary(obj$model)
    })

    output$performance <- renderPrint({
      obj <- model_obj()
      if (is.null(obj)) return(cat("Awaiting model training..."))
      if (isTRUE(obj$scaled))
        cat("NOTE: Predictors were auto-scaled. Coefficients are in standard deviation units.\n\n")
      cat("=== Nakagawa R-squared (GLMM) ===\n")
      cat("Marginal R2 (Fixed effects only):  ", round(obj$r2[1, "R2m"], 4), "\n")
      cat("Conditional R2 (Fixed + Random):   ", round(obj$r2[1, "R2c"], 4), "\n\n")
      cat("=== Variance Inflation Factors (VIF) ===\n")
      tryCatch({
        cor_mat <- cov2cor(vcov(obj$model))
        vifs <- diag(solve(cor_mat))
        print(vifs)
      }, error = function(e) { cat("VIF not available for this model structure.") })
      cat("\n=== Prediction Accuracy (training data) ===\n")
      tryCatch({
        pred <- fitted(obj$model)
        obs  <- pred + resid(obj$model, type = "response")
        m    <- uef_evaluation(pred, obs)
        cat(sprintf("RMSE   : %.4f\nR²     : %.4f\nBias   : %.4f\nRelBias: %.4f\nRRMSE  : %.4f\n",
                    m$RMSE, m$R2, m$Bias, m$RelBias, m$RRMSE))
      }, error = function(e) cat("Metrics error:", e$message, "\n"))
    })

    output$cv_out <- renderPrint({
      obj <- model_obj()
      if (is.null(obj)) { cat("Fit a model first.\n"); return() }
      tryCatch({
        fml    <- formula(obj$model)
        rnd    <- as.character(obj$model$call$random)[[2]]
        grp    <- as.character(obj$model$call$random)[[3]]
        df_cv  <- obj$data
        n      <- nrow(df_cv)
        k      <- .cv_k(input, df_cv)
        lbl    <- .cv_label(k, n)
        if (k >= n) cat("NOTE: LOOCV fits", n, "separate models — may be slow.\n\n")
        set.seed(42)
        folds  <- sample(rep_len(seq_len(k), n))
        preds  <- numeric(n)
        for (fold in seq_len(k)) {
          tr <- df_cv[folds != fold, , drop=FALSE]
          te <- df_cv[folds == fold, , drop=FALSE]
          m  <- tryCatch(
            nlme::lme(fml, data=tr, random=obj$model$call$random,
                      control=nlme::lmeControl(opt="optim", msMaxIter=200, returnObject=TRUE)),
            error=function(e) NULL)
          if (is.null(m)) { preds[folds==fold] <- NA; next }
          preds[folds==fold] <- tryCatch(predict(m, newdata=te, level=0), error=function(e) NA_real_)
        }
        obs <- df_cv[[obj$target]]
        keep <- !is.na(preds) & !is.na(obs)
        if (sum(keep) < 5) { cat("CV failed (too many fold errors).\n"); return() }
        e   <- obs[keep] - preds[keep]
        r2  <- 1 - sum(e^2) / sum((obs[keep]-mean(obs[keep]))^2)
        cat(sprintf("%s RMSE : %.4f\n%s MAE  : %.4f\n%s R²   : %.4f\n",
                    lbl, sqrt(mean(e^2)), lbl, mean(abs(e)), lbl, r2))
        cat(sprintf("(Population-level predictions; %d/%d rows used)\n", sum(keep), n))
      }, error=function(e) cat("CV error:", e$message, "\n"))
    })

    diag_fn <- function() {
      obj <- model_obj()
      if (is.null(obj)) { show_placeholder("Fit a model to see diagnostics."); return() }
      old_par <- ea_multi_par(mfrow = c(1, 2), mar = c(5, 5, 4, 2))
      on.exit({ ea_fig_title(); par(old_par) })
      fit_vals <- fitted(obj$model)
      res_vals <- resid(obj$model, type = "pearson")
      plot(fit_vals, res_vals, main = "Residuals vs Fitted", xlab = "Fitted values", ylab = "Standardized Residuals", pch = 16, col = rgb(0.2, 0.5, 0.8, 0.5), cex.lab = 1.2)
      abline(h = 0, col = "red", lwd = 2, lty = 2)
      qqnorm(res_vals, main = "Normal Q-Q Plot", pch = 16, col = rgb(0.3, 0.3, 0.3, 0.5), cex.lab = 1.2)
      qqline(res_vals, col = "red", lwd = 2)
    }

    output$diagnostics_plot <- renderPlot({ diag_fn() })

    

    output$dl_fixed_effects <- downloadHandler(
      filename = function() paste0("lme_fixed_effects_", Sys.Date(), ".csv"),
      content  = function(file) {
        obj <- model_obj(); req(!is.null(obj))
        fe  <- as.data.frame(summary(obj$model)$tTable)
        fe  <- cbind(term = rownames(fe), fe)
        write.csv(fe, file, row.names = FALSE)
      }
    )

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        obj <- model_obj()
        if (is.null(obj)) return(paste0("Linear Mixed Effects — not fitted yet. Intended: ",
                                        input$y, " ~ ", input$fixed_text, " ; random ", input$random_text))
        paste0("Linear Mixed Effects. Fixed: ", input$y, " ~ ", input$fixed_text,
               " ; Random: ", input$random_text,
               "\nNakagawa R2m=", round(obj$r2[1, "R2m"], 4), " R2c=", round(obj$r2[1, "R2c"], 4),
               "\n\nModel summary:\n", paste(utils::capture.output(summary(obj$model)), collapse = "\n"))
      }),
      plot = function() diag_fn()
    )
  })
}
