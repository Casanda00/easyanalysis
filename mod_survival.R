# ==========================================================================
# MODULE: Survival Analysis
# Kaplan-Meier | Cox PH | Log-rank
# survivalCanvasUI / survivalToolsUI / survivalServer
# Requires: survival (base R recommended package)
# ==========================================================================

survivalToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Survival Analysis", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "surv_vars",
      accordion_panel("Variables", value = "surv_vars", icon = icon("hourglass-half"),
        uiOutput(ns("time_ui")),
        uiOutput(ns("event_ui")),
        uiOutput(ns("group_ui")),
        tags$p(class = "small text-muted",
          "Event variable: 1 = event occurred, 0 = censored.")
      ),
      accordion_panel("Cox PH Covariates", value = "surv_cox", icon = icon("table"),
        uiOutput(ns("covar_ui")),
        checkboxInput(ns("cox_ties"), "Efron tie method", value = TRUE)
      ),
      accordion_panel("Plot Options", value = "surv_plot", icon = icon("chart-line"),
        checkboxInput(ns("km_conf"), "Show 95% CI bands", value = TRUE),
        checkboxInput(ns("km_censor"), "Mark censored observations", value = TRUE),
        numericInput(ns("conf_level"), "Confidence level", value = 0.95,
                     min = 0.8, max = 0.999, step = 0.005, width = "100%")
      ),
      accordion_panel("Export", value = "surv_exp", icon = icon("download"),
        downloadButton(ns("dl_km"),  "KM Table CSV",  class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_cox"), "Cox Summary CSV", class = "btn-sm btn-outline-success w-100"),
        tags$br(), tags$br()
      )
    ),
    actionButton(ns("run_surv"), "Run Analysis",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

.SURV_VIEWS <- c(kaplan_meier = "Kaplan-Meier", cox_ph_model = "Cox PH Model", log_rank_test = "Log-rank Test", survival_table = "Survival Table")
.SURV_VIEWS_PLOT <- c("kaplan_meier", "cox_ph_model")  # views whose body actually renders a plot


survivalCanvasUI <- function(id) {
  ns <- NS(id)
  # Select-and-split (helpers.R): one selection fills the area, several split it.
  card(
    card_header(ea_view_header(ns, .SURV_VIEWS)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

survivalServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- names(.SURV_VIEWS)[1]
      if (any(picked %in% .SURV_VIEWS_PLOT)) ea_plot_appearance()
    })
    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .SURV_VIEWS, function(k, solo) switch(k,
        kaplan_meier = tagList(layout_columns(col_widths = c(8, 4),
        card(plotOutput(ns("km_plot"), height = "460px")),
        card(card_header("KM Summary"), verbatimTextOutput(ns("km_summary")))
      )),
        cox_ph_model = tagList(layout_columns(col_widths = c(6, 6),
        card(card_header("Model Summary"), verbatimTextOutput(ns("cox_summary"))),
        tagList(
          card(card_header("Hazard Ratios"), plotOutput(ns("hr_plot"), height = "320px")),
          card(card_header("Proportional Hazards Check"), verbatimTextOutput(ns("ph_test"))),
          card(card_header("Concordance (C-index)"), verbatimTextOutput(ns("concordance_out")))
        )
      )),
        log_rank_test = tagList(card(verbatimTextOutput(ns("logrank_out")))),
        survival_table = tagList(DTOutput(ns("surv_table"), height = "500px")),
        NULL))
    })

    ns <- session$ns

    if (!requireNamespace("survival", quietly = TRUE)) {
      output$km_plot <- renderPlot(show_placeholder("Package 'survival' required.\nRun: install.packages('survival')"))
      return(list(context = reactive("Survival: 'survival' package missing."), plot = function() invisible()))
    }

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    output$time_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      num <- names(df)[sapply(df, is.numeric)]
      selectInput(ns("time_var"), "Time variable (survival time)", choices = num, width = "100%")
    })

    output$event_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      num <- names(df)[sapply(df, is.numeric)]
      selectInput(ns("event_var"), "Event indicator (1=event, 0=censored)", choices = num, width = "100%")
    })

    output$group_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      cols <- c("(none)" = "__none__", names(df))
      selectInput(ns("group_var"), "Grouping variable (for KM + log-rank)", choices = cols, width = "100%")
    })

    output$covar_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      others <- setdiff(names(df), c(input$time_var, input$event_var))
      selectInput(ns("covar_vars"), "Covariates (multiple)", choices = others,
                  multiple = TRUE, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_surv, {
      df <- active_data(); req(!is.null(df))
      tv <- input$time_var;  req(isTruthy(tv))
      ev <- input$event_var; req(isTruthy(ev))
      t_vec <- as.numeric(df[[tv]])
      e_vec <- as.integer(df[[ev]])
      keep  <- !is.na(t_vec) & !is.na(e_vec) & t_vec > 0
      req(sum(keep) >= 4)
      t_vec <- t_vec[keep]; e_vec <- e_vec[keep]
      surv_obj <- survival::Surv(t_vec, e_vec)

      gv <- input$group_var %||% "__none__"
      g_vec <- if (gv != "__none__" && gv %in% names(df)) as.factor(df[[gv]][keep]) else NULL

      res <- tryCatch({
        # KM
        km_formula <- if (!is.null(g_vec))
          survival::survfit(surv_obj ~ g_vec, conf.int = as.numeric(input$conf_level %||% 0.95))
        else
          survival::survfit(surv_obj ~ 1,     conf.int = as.numeric(input$conf_level %||% 0.95))

        # Log-rank
        logrank <- if (!is.null(g_vec))
          tryCatch(survival::survdiff(surv_obj ~ g_vec), error = function(e) NULL)
        else NULL

        # Cox PH
        cvars <- input$covar_vars
        cox_fit <- if (length(cvars) > 0) {
          sub_df <- as.data.frame(cbind(t_vec, e_vec, df[keep, cvars, drop = FALSE]))
          names(sub_df)[1:2] <- c("__t__", "__e__")
          fml <- as.formula(paste0("survival::Surv(__t__, __e__) ~ ",
                                   paste(cvars, collapse = " + ")))
          ties_m <- if (isTRUE(input$cox_ties)) "efron" else "breslow"
          tryCatch(survival::coxph(fml, data = sub_df, ties = ties_m), error = function(e) NULL)
        } else NULL

        # PH test
        ph_test <- if (!is.null(cox_fit))
          tryCatch(survival::cox.zph(cox_fit), error = function(e) NULL)
        else NULL

        list(km = km_formula, logrank = logrank, cox = cox_fit, ph_test = ph_test,
             surv = surv_obj, g_vec = g_vec, t_vec = t_vec, e_vec = e_vec,
             has_group = !is.null(g_vec))
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(res)
      if (!is.null(res)) showNotification("Survival analysis complete.", type = "message")
    })

    .km_cols <- function(n) {
      palette.colors(max(n, 1), palette = "Set2")
    }

    output$km_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Configure variables and click Run."); return() }
      km <- res$km
      n_grp <- length(km$strata) %||% 1; if (n_grp == 0) n_grp <- 1
      cols <- .km_cols(n_grp)
      plot(km, col = cols, lwd = 2, lty = 1,
           conf.int = isTRUE(input$km_conf),
           mark.time = isTRUE(input$km_censor),
           xlab = input$time_var %||% "Time",
           ylab = "Survival Probability",
           main = "Kaplan-Meier Survival Curves",
           ylim = c(0, 1))
      abline(h = 0.5, col = "grey60", lty = 2, lwd = 1)
      if (res$has_group && !is.null(km$strata)) {
        grp_labs <- sub("^g_vec=", "", names(km$strata))
        legend("topright", legend = grp_labs, col = cols, lwd = 2, bty = "n", cex = 0.85)
      }
      grid(col = "grey92")
    })

    output$km_summary <- renderPrint({
      res <- result_r(); req(!is.null(res))
      print(summary(res$km, times = quantile(res$t_vec, c(.25,.5,.75), na.rm=TRUE)))
    })

    output$cox_summary <- renderPrint({
      res <- result_r(); req(!is.null(res))
      if (is.null(res$cox)) {
        cat("No Cox model fitted.\nSelect covariates in the Cox PH panel.\n"); return()
      }
      print(summary(res$cox))
    })

    output$hr_plot <- renderPlot({
      res <- result_r(); req(!is.null(res), !is.null(res$cox))
      sm  <- summary(res$cox)
      hr  <- sm$conf.int[, c("exp(coef)", "lower .95", "upper .95"), drop = FALSE]
      df  <- as.data.frame(hr)
      colnames(df) <- c("HR", "Lower", "Upper")
      df$Variable <- rownames(df)
      df <- df[order(df$HR), ]
      df$Variable <- factor(df$Variable, levels = df$Variable)
      ggplot(df, aes(x = HR, y = Variable)) +
        geom_vline(xintercept = 1, col = "grey50", lty = 2) +
        geom_errorbarh(aes(xmin = Lower, xmax = Upper), height = 0.3, col = "#2e7d32", linewidth = 1) +
        geom_point(col = "#2e7d32", size = 3) +
        labs(title = "Hazard Ratios (95% CI)", x = "Hazard Ratio", y = NULL) +
        theme_minimal(base_size = 11)
    })

    output$ph_test <- renderPrint({
      res <- result_r(); req(!is.null(res))
      if (is.null(res$ph_test)) {
        cat("No proportional hazards test.\nFit a Cox model first.\n"); return()
      }
      cat("Schoenfeld Residuals Test (H0: proportional hazards holds):\n\n")
      print(res$ph_test)
    })

    output$concordance_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      if (is.null(res$cox)) { cat("Fit a Cox model first.\n"); return() }
      tryCatch({
        conc <- survival::concordance(res$cox)
        c_index <- conc$concordance
        se      <- sqrt(conc$var)
        cat(sprintf("C-index (Harrell's concordance): %.4f\n", c_index))
        cat(sprintf("SE: %.4f\n", se))
        cat(sprintf("95%% CI: [%.4f, %.4f]\n", c_index - 1.96*se, c_index + 1.96*se))
        cat("\nInterpretation:\n")
        cat("  0.5 = no discrimination (random)\n")
        cat("  0.7 = acceptable\n")
        cat("  0.8 = excellent\n")
        cat("  1.0 = perfect discrimination\n")
        lvl <- if (c_index >= 0.8) "Excellent" else if (c_index >= 0.7) "Acceptable" else if (c_index >= 0.6) "Poor" else "No better than chance"
        cat(sprintf("\nDiscrimination: %s\n", lvl))
      }, error=function(e) cat("Concordance error:", e$message, "\n"))
    })

    output$logrank_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      if (is.null(res$logrank)) {
        cat("Log-rank test requires a grouping variable.\n"); return()
      }
      lr <- res$logrank
      cat("Log-rank (Mantel-Haenszel) Test\n")
      cat(sprintf("Chi-squared = %.4f, df = %d, p-value = %.4f\n\n",
                  lr$chisq, length(lr$n) - 1,
                  1 - pchisq(lr$chisq, df = length(lr$n) - 1)))
      cat("Observed vs Expected:\n")
      print(data.frame(
        Group    = names(lr$n),
        N        = lr$n,
        Observed = lr$obs,
        Expected = round(lr$exp, 2),
        `(O-E)^2/E` = round((lr$obs - lr$exp)^2 / lr$exp, 4),
        check.names = FALSE
      ))
    })

    output$surv_table <- renderDT({
      res <- result_r(); req(!is.null(res))
      sm <- summary(res$km)
      df <- data.frame(
        Time      = sm$time,
        N_risk    = sm$n.risk,
        N_event   = sm$n.event,
        N_censor  = sm$n.censor,
        Survival  = round(sm$surv, 4),
        SE        = round(sm$std.err, 4),
        Lower_95  = round(sm$lower, 4),
        Upper_95  = round(sm$upper, 4)
      )
      if (!is.null(sm$strata)) df$Group <- sm$strata
      datatable(df, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 20))
    })

    output$dl_km <- downloadHandler(
      filename = function() "kaplan_meier.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        sm <- summary(res$km)
        df <- data.frame(Time=sm$time, N_risk=sm$n.risk, N_event=sm$n.event,
                         Survival=round(sm$surv,4), Lower=round(sm$lower,4), Upper=round(sm$upper,4))
        write.csv(df, f, row.names = FALSE)
      }
    )

    output$dl_cox <- downloadHandler(
      filename = function() "cox_summary.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res), !is.null(res$cox))
        sm <- summary(res$cox)
        write.csv(as.data.frame(sm$coefficients), f)
      }
    )

    

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Survival Analysis: not yet run.")
        km <- res$km
        med <- tryCatch(quantile(km, probs = 0.5)$quantile, error = function(e) NA)
        paste0("Survival Analysis | time=", input$time_var, " | event=", input$event_var,
               " | n=", sum(!is.na(res$t_vec)),
               " | median survival≈", round(med, 2),
               if (!is.null(res$logrank))
                 sprintf(" | log-rank p=%.4f", 1 - pchisq(res$logrank$chisq, df = length(res$logrank$n)-1))
               else "")
      }),
      plot = function() {
        res <- isolate(result_r()); if (is.null(res)) return(invisible())
        plot(res$km, col = .km_cols(max(length(res$km$strata),1)), lwd = 2,
             main = "KM", ylab = "Survival", ylim = c(0,1))
      }
    )
  })
}
