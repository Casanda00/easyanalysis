# ==========================================================================
# MODULE: Time Series & Forecasting
# ARIMA | SARIMA | Holt-Winters | Decomposition | Diagnostics
# timeseriesCanvasUI / timeseriesToolsUI / timeseriesServer
# ==========================================================================

timeseriesToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Time Series", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "ts_data",
      accordion_panel("Series Setup", value = "ts_data", icon = icon("chart-line"),
        uiOutput(ns("y_var_ui")),
        uiOutput(ns("date_var_ui")),
        numericInput(ns("freq"), "Frequency (obs/cycle: 1=annual, 4=quarterly, 12=monthly, 52=weekly)",
                     value = 12, min = 1, step = 1, width = "100%"),
        numericInput(ns("horizon"), "Forecast horizon (periods)", value = 12, min = 1, width = "100%")
      ),
      accordion_panel("ARIMA / SARIMA", value = "ts_arima", icon = icon("wave-square"),
        tags$small(class = "text-muted d-block mb-1", "Non-seasonal (p, d, q)"),
        layout_columns(col_widths = c(4, 4, 4),
          numericInput(ns("ar_p"), "p", value = 1, min = 0, max = 10),
          numericInput(ns("ar_d"), "d", value = 1, min = 0, max = 3),
          numericInput(ns("ar_q"), "q", value = 1, min = 0, max = 10)
        ),
        checkboxInput(ns("use_seasonal"), "Seasonal component (SARIMA)", value = FALSE),
        conditionalPanel("input.use_seasonal", ns = ns,
          tags$small(class = "text-muted d-block mb-1", "Seasonal (P, D, Q)"),
          layout_columns(col_widths = c(4, 4, 4),
            numericInput(ns("ar_P"), "P", value = 1, min = 0, max = 5),
            numericInput(ns("ar_D"), "D", value = 1, min = 0, max = 2),
            numericInput(ns("ar_Q"), "Q", value = 1, min = 0, max = 5)
          )
        )
      ),
      accordion_panel("Smoothing", value = "ts_smooth", icon = icon("sliders"),
        selectInput(ns("smooth_type"), "Method", width = "100%",
          choices = c("Holt-Winters (additive)"       = "hw_add",
                      "Holt-Winters (multiplicative)"  = "hw_mult",
                      "Simple exponential smoothing"   = "ses",
                      "Trend + level (Holt)"           = "holt")),
        numericInput(ns("alpha"), "α (level)", value = 0.2, min = 0.01, max = 0.99, step = 0.05, width = "100%"),
        conditionalPanel(
          "input.smooth_type == 'hw_add' || input.smooth_type == 'hw_mult' || input.smooth_type == 'holt'",
          ns = ns,
          numericInput(ns("beta"),  "β (trend)",  value = 0.1, min = 0.01, max = 0.99, step = 0.05, width = "100%")
        ),
        conditionalPanel(
          "input.smooth_type == 'hw_add' || input.smooth_type == 'hw_mult'", ns = ns,
          numericInput(ns("gamma"), "γ (seasonal)", value = 0.1, min = 0.01, max = 0.99, step = 0.05, width = "100%")
        )
      ),
      accordion_panel("Export", value = "ts_exp", icon = icon("download"),
        downloadButton(ns("dl_forecast"), "Forecast CSV", class = "btn-sm btn-success w-100"),
        tags$br(), tags$br()
      )
    ),
    actionButton(ns("run_ts"), "Run Analysis",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

.TS_VIEWS <- c(raw_series = "Raw Series", acf_pacf = "ACF / PACF", decomposition = "Decomposition", arima = "ARIMA", smoothing = "Smoothing", stationarity = "Stationarity")
.TS_VIEWS_PLOT <- c("raw_series", "acf_pacf", "decomposition", "arima", "smoothing")  # views whose body actually renders a plot


timeseriesCanvasUI <- function(id) {
  ns <- NS(id)
  # Select-and-split (helpers.R): one selection fills the area, several split it.
  card(
    card_header(ea_view_header(ns, .TS_VIEWS)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

timeseriesServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- names(.TS_VIEWS)[1]
      if (any(picked %in% .TS_VIEWS_PLOT)) ea_plot_appearance()
    })
    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .TS_VIEWS, function(k, solo) switch(k,
        raw_series = tagList(plotOutput(ns("raw_plot"),    height = if (solo) "420px" else "100%")),
        acf_pacf = tagList(plotOutput(ns("acf_plot"),    height = if (solo) "420px" else "100%")),
        decomposition = tagList(plotOutput(ns("decomp_plot"), height = if (solo) "500px" else "100%")),
        arima = tagList(layout_columns(col_widths = c(8, 4),
        plotOutput(ns("arima_plot"), height = if (solo) "420px" else "100%"),
        card(card_header("Model Info"), verbatimTextOutput(ns("arima_info")))
      )),
        smoothing = tagList(layout_columns(col_widths = c(8, 4),
        plotOutput(ns("hw_plot"), height = if (solo) "420px" else "100%"),
        card(card_header("Smoothing Info"), verbatimTextOutput(ns("hw_info")))
      )),
        stationarity = tagList(card(verbatimTextOutput(ns("stationarity_out")))),
        NULL))
    })

    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    num_cols <- reactive({
      df <- active_data(); req(!is.null(df))
      names(df)[sapply(df, is.numeric)]
    })

    output$y_var_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) == 0) return(tags$p(class="small text-warning","No numeric columns."))
      selectInput(ns("y_var"), "Time series variable (Y)", choices = nms, width = "100%")
    })

    output$date_var_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      cols <- c("(row index)" = "__index__",
                names(df)[sapply(df, function(x) inherits(x, c("Date","POSIXct","POSIXlt")) || is.character(x))])
      selectInput(ns("date_var"), "Date / index column (optional)", choices = cols, width = "100%")
    })

    ts_data <- reactive({
      df <- active_data(); req(!is.null(df))
      y  <- as.numeric(df[[input$y_var]]); req(length(y) > 4)
      freq <- max(1L, as.integer(input$freq %||% 12L))
      ts(y, frequency = freq)
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_ts, {
      y_ts <- tryCatch(ts_data(), error = function(e) NULL); req(!is.null(y_ts))
      freq  <- max(1L, as.integer(input$freq %||% 12L))
      h     <- max(1L, as.integer(input$horizon %||% 12L))

      res <- tryCatch({
        # ARIMA
        p <- as.integer(input$ar_p %||% 1L); d <- as.integer(input$ar_d %||% 1L)
        q <- as.integer(input$ar_q %||% 1L)
        ord <- c(p, d, q)
        seas <- if (isTRUE(input$use_seasonal)) {
          list(order = c(as.integer(input$ar_P %||% 1L),
                         as.integer(input$ar_D %||% 1L),
                         as.integer(input$ar_Q %||% 1L)),
               period = freq)
        } else NULL
        arima_fit <- if (is.null(seas))
          arima(y_ts, order = ord)
        else
          arima(y_ts, order = ord, seasonal = seas)
        arima_fc <- predict(arima_fit, n.ahead = h)

        # Holt-Winters / smoothing
        sm_type <- input$smooth_type %||% "hw_add"
        alpha <- as.numeric(input$alpha %||% 0.2)
        beta  <- as.numeric(input$beta  %||% 0.1)
        gamma <- as.numeric(input$gamma %||% 0.1)
        hw_fit <- tryCatch({
          if (sm_type == "ses") {
            HoltWinters(y_ts, beta = FALSE, gamma = FALSE, alpha = alpha)
          } else if (sm_type == "holt") {
            HoltWinters(y_ts, gamma = FALSE, alpha = alpha, beta = beta)
          } else {
            seasonal <- if (sm_type == "hw_mult") "multiplicative" else "additive"
            if (freq < 2) HoltWinters(y_ts, beta = FALSE, gamma = FALSE, alpha = alpha)
            else HoltWinters(y_ts, seasonal = seasonal, alpha = alpha, beta = beta, gamma = gamma)
          }
        }, error = function(e) {
          HoltWinters(y_ts, beta = FALSE, gamma = FALSE, alpha = alpha)
        })
        hw_fc <- predict(hw_fit, n.ahead = h, prediction.interval = TRUE)

        # Decomposition (only if freq > 1)
        decomp <- if (freq > 1) tryCatch(decompose(y_ts), error = function(e) NULL) else NULL

        list(ts = y_ts, freq = freq, h = h,
             arima_fit = arima_fit, arima_fc = arima_fc,
             hw_fit = hw_fit, hw_fc = hw_fc,
             decomp = decomp)
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(res)
      if (!is.null(res)) showNotification("Time series analysis complete.", type = "message")
    })

    output$raw_plot <- renderPlot({
      y_ts <- tryCatch(ts_data(), error = function(e) NULL)
      if (is.null(y_ts)) { show_placeholder("Select a variable and run analysis."); return() }
      plot(y_ts, main = ea_main(paste("Time Series:", input$y_var %||% "")),
           xlab = "Time", ylab = input$y_var %||% "Value",
           col = "#2e7d32", lwd = 1.5, type = "l")
      grid(col = "grey90")
    })

    output$acf_plot <- renderPlot({
      y_ts <- tryCatch(ts_data(), error = function(e) NULL)
      req(!is.null(y_ts))
      par(mfrow = c(2, 1), mar = c(4, 4, 2, 1))
      acf(y_ts,  main = "ACF",  lag.max = 40, col = "#2e7d32")
      pacf(y_ts, main = "PACF", lag.max = 40, col = "#2e7d32")
      par(mfrow = c(1, 1))
    })

    output$decomp_plot <- renderPlot({
      res <- result_r()
      if (is.null(res) || is.null(res$decomp)) {
        y_ts <- tryCatch(ts_data(), error = function(e) NULL)
        if (is.null(y_ts) || frequency(y_ts) < 2) {
          show_placeholder("Decomposition requires frequency ≥ 2.\nSet Frequency in Setup and run.")
          return()
        }
        d <- tryCatch(decompose(y_ts), error = function(e) conditionMessage(e))
        if (is.character(d)) {
          show_placeholder(paste0("Decomposition failed:\n", d)); return()
        }
        plot(d, col = "#2e7d32")
        return()
      }
      plot(res$decomp, col = "#2e7d32")
    })

    output$arima_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Run analysis to see ARIMA forecast."); return() }
      fc_mean <- as.numeric(res$arima_fc$pred)
      fc_se   <- as.numeric(res$arima_fc$se)
      n_obs   <- length(res$ts)
      t_obs   <- time(res$ts)
      t_fc    <- seq(max(t_obs) + 1/res$freq, by = 1/res$freq, length.out = res$h)
      ylim    <- range(c(as.numeric(res$ts), fc_mean + 2*fc_se, fc_mean - 2*fc_se), na.rm = TRUE)
      plot(t_obs, as.numeric(res$ts), type = "l", col = "#2e7d32", lwd = 1.5,
           xlim = c(min(t_obs), max(t_fc)), ylim = ylim,
           xlab = "Time", ylab = input$y_var %||% "Value",
           main = sprintf("ARIMA(%s,%s,%s) Forecast", input$ar_p, input$ar_d, input$ar_q))
      polygon(c(t_fc, rev(t_fc)),
              c(fc_mean + 2*fc_se, rev(fc_mean - 2*fc_se)),
              col = "#4caf5033", border = NA)
      lines(t_fc, fc_mean, col = "#c62828", lwd = 2, lty = 1)
      lines(t_fc, fc_mean + 2*fc_se, col = "#c6282866", lwd = 1, lty = 2)
      lines(t_fc, fc_mean - 2*fc_se, col = "#c6282866", lwd = 1, lty = 2)
      legend("topleft", c("Observed","Forecast","95% CI"),
             col = c("#2e7d32","#c62828","#4caf5033"),
             lwd = c(1.5, 2, 8), bty = "n", cex = 0.8)
      grid(col = "grey90")
    })

    output$arima_info <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat(sprintf("Model:    ARIMA(%s,%s,%s)\n", input$ar_p, input$ar_d, input$ar_q))
      cat(sprintf("AIC:      %.2f\n", AIC(res$arima_fit)))
      cat(sprintf("BIC:      %.2f\n\n", BIC(res$arima_fit)))
      cat("Coefficients:\n"); print(round(coef(res$arima_fit), 4))
      cat("\nResidual variance:", round(res$arima_fit$sigma2, 4), "\n")
    })

    output$hw_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Run analysis to see smoothing forecast."); return() }
      fc <- res$hw_fc
      t_fc <- time(fc[, "fit"])
      t_obs <- time(res$ts)
      ylim <- range(c(as.numeric(res$ts), fc), na.rm = TRUE)
      plot(t_obs, as.numeric(res$ts), type = "l", col = "#2e7d32", lwd = 1.5,
           xlim = c(min(t_obs), max(t_fc)), ylim = ylim,
           xlab = "Time", ylab = input$y_var %||% "Value",
           main = paste("Holt-Winters Forecast:", input$smooth_type %||% ""))
      polygon(c(t_fc, rev(t_fc)),
              c(as.numeric(fc[, "upr"]), rev(as.numeric(fc[, "lwr"]))),
              col = "#4caf5033", border = NA)
      lines(t_fc, fc[, "fit"], col = "#c62828", lwd = 2)
      lines(t_fc, fc[, "upr"], col = "#c6282866", lwd = 1, lty = 2)
      lines(t_fc, fc[, "lwr"], col = "#c6282866", lwd = 1, lty = 2)
      legend("topleft", c("Observed","Forecast","95% CI"),
             col = c("#2e7d32","#c62828","#4caf5033"),
             lwd = c(1.5, 2, 8), bty = "n", cex = 0.8)
      grid(col = "grey90")
    })

    output$hw_info <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("Method:", class(res$hw_fit), "\n")
      cat("Alpha (level):", round(res$hw_fit$alpha, 4), "\n")
      if (!is.null(res$hw_fit$beta))  cat("Beta  (trend):", round(res$hw_fit$beta, 4), "\n")
      if (!is.null(res$hw_fit$gamma)) cat("Gamma (season):", round(res$hw_fit$gamma, 4), "\n")
      cat("\nSSE:", round(res$hw_fit$SSE, 4), "\n")
      cat("In-sample RMSE:", round(sqrt(mean(residuals(res$hw_fit)^2, na.rm=TRUE)), 4), "\n")
    })

    output$stationarity_out <- renderPrint({
      y_ts <- tryCatch(ts_data(), error = function(e) NULL); req(!is.null(y_ts))
      cat("=== Stationarity Diagnostics ===\n\n")
      y_vec <- as.numeric(y_ts)

      # ADF test via tseries (optional)
      if (requireNamespace("tseries", quietly = TRUE)) {
        adf <- tryCatch(tseries::adf.test(y_vec), error = function(e) conditionMessage(e))
        if (!is.character(adf)) {
          cat(sprintf("Augmented Dickey-Fuller Test\n  Statistic: %.4f\n  p-value:   %.4f\n  %s\n\n",
            adf$statistic, adf$p.value,
            if (adf$p.value < 0.05) "=> Series likely STATIONARY (reject H0)"
            else "=> Series likely NON-STATIONARY (fail to reject H0)"))
        } else {
          # Printing nothing made a FAILED test look like a test that was never
          # part of the screen -- the user cannot tell absence from failure.
          cat("Augmented Dickey-Fuller Test\n  Could not be computed (", adf, ")\n\n", sep = "")
        }
      } else {
        cat("Note: install 'tseries' for ADF test.\n\n")
      }

      # KPSS-like variance ratio (manual)
      cat("Variance ratio (rough): ")
      ratio <- var(diff(y_vec), na.rm = TRUE) / var(y_vec, na.rm = TRUE)
      cat(sprintf("%.4f (< 0.15 suggests non-stationarity)\n\n", ratio))

      cat("Summary statistics:\n")
      cat(sprintf("  N:    %d\n  Mean: %.4f\n  SD:   %.4f\n  CV:   %.2f%%\n",
                  length(y_vec), mean(y_vec, na.rm=TRUE), sd(y_vec, na.rm=TRUE),
                  100*sd(y_vec,na.rm=TRUE)/abs(mean(y_vec,na.rm=TRUE))))
    })

    output$dl_forecast <- downloadHandler(
      filename = function() paste0("forecast_", input$y_var %||% "ts", ".csv"),
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        fc_mean <- as.numeric(res$arima_fc$pred)
        fc_se   <- as.numeric(res$arima_fc$se)
        df <- data.frame(
          period   = seq_len(res$h),
          forecast = fc_mean,
          lower95  = fc_mean - 1.96 * fc_se,
          upper95  = fc_mean + 1.96 * fc_se
        )
        write.csv(df, f, row.names = FALSE)
      }
    )

    

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return(paste0("Time Series: variable=", input$y_var %||% "none", ", not yet run."))
        paste0("Time Series | Variable: ", input$y_var, " | freq=", res$freq,
               sprintf("\nARIMA(%s,%s,%s): AIC=%.2f", input$ar_p, input$ar_d, input$ar_q, AIC(res$arima_fit)))
      }),
      plot = function() {
        y_ts <- isolate(tryCatch(ts_data(), error = function(e) NULL))
        if (is.null(y_ts)) return(invisible())
        plot(y_ts, main = ea_main(isolate(input$y_var) %||% "Time Series"), col = "#2e7d32", lwd = 1.5)
      }
    )
  })
}
