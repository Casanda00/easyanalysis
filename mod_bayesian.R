# ==========================================================================
# MODULE: Bayesian Analysis
# Bayesian regression & ANOVA via BayesFactor (optional)
# Fallback: manual conjugate priors for simple cases
# bayesianCanvasUI / bayesianToolsUI / bayesianServer
# ==========================================================================

bayesianToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Bayesian Analysis", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "bayes_mode",
      accordion_panel("Analysis Type", value = "bayes_mode", icon = icon("flask"),
        selectInput(ns("bayes_type"), "Analysis", width = "100%",
          choices = c(
            "Bayesian t-test (BayesFactor)"        = "bf_t",
            "Bayesian linear regression (BF)"       = "bf_lm",
            "Bayesian ANOVA (BayesFactor)"          = "bf_anova",
            "Bayesian correlation (BF)"             = "bf_cor",
            "Normal-Normal conjugate (manual)"      = "conj_norm"
          ))
      ),
      accordion_panel("Variables", value = "bayes_vars", icon = icon("table-columns"),
        uiOutput(ns("var_ui"))
      ),
      accordion_panel("Prior Settings", value = "bayes_prior", icon = icon("sliders"),
        numericInput(ns("rscale"), "Cauchy prior scale (r)",
                     value = 0.707, min = 0.1, max = 5, step = 0.05, width = "100%"),
        tags$p(class = "small text-muted",
          "r = 0.707 (medium, recommended), 0.5 (wide), 1 (ultrawide). Used by BayesFactor.")
      )
    ),
    actionButton(ns("run_bayes"), "Run Analysis",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

bayesianCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Bayes Factor",
      layout_columns(col_widths = c(6, 6),
        card(card_header("Results"), verbatimTextOutput(ns("bf_out"))),
        card(card_header("Interpretation"), uiOutput(ns("bf_interp_ui")))
      )
    ),
    nav_panel("Posterior",
      card(plotOutput(ns("posterior_plot"), height = "440px"))
    ),
    nav_panel("About Bayesian Methods",
      card(
        tags$div(class = "p-4 small",
          tags$h6("What is a Bayes Factor (BF)?"),
          tags$p("BF₁₀ = P(data | H₁) / P(data | H₀). Ratio of evidence for H₁ vs H₀."),
          tags$table(class = "table table-sm table-bordered",
            tags$thead(tags$tr(tags$th("BF₁₀"), tags$th("Evidence"))),
            tags$tbody(
              tags$tr(tags$td("1–3"),    tags$td("Anecdotal for H₁")),
              tags$tr(tags$td("3–10"),   tags$td("Moderate for H₁")),
              tags$tr(tags$td("10–30"),  tags$td("Strong for H₁")),
              tags$tr(tags$td("30–100"), tags$td("Very strong for H₁")),
              tags$tr(tags$td("> 100"),  tags$td("Decisive for H₁")),
              tags$tr(tags$td("< 1"),    tags$td("Evidence for H₀"))
            )
          ),
          tags$hr(),
          tags$h6("Full Bayesian Modelling"),
          tags$p("For full posterior sampling (MCMC), install:"),
          tags$code("install.packages(c('rstanarm', 'brms', 'bayesplot'))"),
          tags$p(class = "mt-2",
            "These packages provide full probabilistic inference with Stan as the backend.",
            "Integration is planned for a future build.")
        )
      )
    )
  )
}

bayesianServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    has_bf <- requireNamespace("BayesFactor", quietly = TRUE)

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    num_cols <- reactive({
      df <- active_data(); req(!is.null(df))
      names(df)[sapply(df, is.numeric)]
    })

    output$var_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      nms  <- num_cols()
      all_nms <- names(df)
      type <- input$bayes_type %||% "bf_t"
      switch(type,
        bf_t = tagList(
          selectInput(ns("var_x"),     "Numeric variable", choices = nms, width = "100%"),
          tagList(
            selectInput(ns("var_group"), "Group column", choices = all_nms, width = "100%"),
            p(class="text-muted small mt-n2", "Select a column that has exactly 2 distinct values.")
          )
        ),
        bf_cor = tagList(
          selectInput(ns("var_x"), "Variable 1", choices = nms, width = "100%"),
          selectInput(ns("var_y"), "Variable 2", choices = nms, width = "100%")
        ),
        bf_anova = tagList(
          selectInput(ns("var_x"),     "Outcome variable", choices = nms, width = "100%"),
          selectInput(ns("var_group"), "Group variable",   choices = all_nms, width = "100%")
        ),
        bf_lm = tagList(
          selectInput(ns("var_x"),    "Outcome (Y)",       choices = nms, width = "100%"),
          selectInput(ns("var_preds"),"Predictors (X)",    choices = nms,
                      selected = nms, multiple = TRUE, width = "100%")
        ),
        conj_norm = tagList(
          selectInput(ns("var_x"), "Variable", choices = nms, width = "100%"),
          numericInput(ns("prior_mean"), "Prior mean (μ₀)", value = 0, width = "100%"),
          numericInput(ns("prior_sd"),   "Prior SD (σ₀)",   value = 1, min = 0.001, width = "100%")
        )
      )
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_bayes, {
      df <- active_data(); req(!is.null(df))
      type  <- input$bayes_type %||% "bf_t"
      rscale <- as.numeric(input$rscale %||% 0.707)

      result <- tryCatch({
        if (type == "conj_norm") {
          x   <- as.numeric(df[[input$var_x]]); x <- x[!is.na(x)]
          mu0 <- as.numeric(input$prior_mean %||% 0)
          s0  <- as.numeric(input$prior_sd   %||% 1)
          n   <- length(x); xbar <- mean(x); s <- sd(x)
          # Normal-Normal conjugate update (known variance proxy)
          sigma_sq <- s^2
          post_var  <- 1 / (1/s0^2 + n/sigma_sq)
          post_mean <- post_var * (mu0/s0^2 + n*xbar/sigma_sq)
          list(type = "conj", post_mean = post_mean, post_var = post_var,
               n = n, xbar = xbar, s = s, prior_mean = mu0, prior_sd = s0)

        } else if (!has_bf) {
          stop("Package 'BayesFactor' not installed.\nRun: install.packages('BayesFactor')")

        } else switch(type,
          bf_t = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            req(nlevels(g) == 2)
            grps <- split(x[!is.na(x)], g[!is.na(x)])
            bf <- BayesFactor::ttestBF(x = grps[[1]], y = grps[[2]], rscale = rscale)
            list(type = "bf", bf = bf, bf_val = as.numeric(BayesFactor::extractBF(bf)$bf))
          },
          bf_cor = {
            x <- as.numeric(df[[input$var_x]])
            y <- as.numeric(df[[input$var_y]])
            keep <- !is.na(x) & !is.na(y)
            bf <- BayesFactor::correlationBF(y = y[keep], x = x[keep], rscale = rscale)
            list(type = "bf", bf = bf, bf_val = as.numeric(BayesFactor::extractBF(bf)$bf))
          },
          bf_anova = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            sub <- data.frame(x = x, g = g); sub <- sub[complete.cases(sub), ]
            bf <- BayesFactor::anovaBF(x ~ g, data = sub, rscaleFixed = rscale)
            list(type = "bf", bf = bf, bf_val = as.numeric(BayesFactor::extractBF(bf)$bf[1]))
          },
          bf_lm = {
            yv <- input$var_x; pv <- input$var_preds
            req(isTruthy(yv), isTruthy(pv), length(pv) >= 1)
            sub <- df[, c(yv, pv), drop = FALSE]; sub <- sub[complete.cases(sub), ]
            fml <- as.formula(paste(yv, "~", paste(pv, collapse = " + ")))
            bf  <- BayesFactor::lmBF(fml, data = sub, rscaleFixed = rscale)
            list(type = "bf", bf = bf, bf_val = as.numeric(BayesFactor::extractBF(bf)$bf))
          }
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("Bayesian analysis complete.", type = "message")
    })

    .bf_label <- function(bf) {
      if (bf > 100)  "Decisive (BF > 100)"
      else if (bf > 30)  "Very Strong (BF 30–100)"
      else if (bf > 10)  "Strong (BF 10–30)"
      else if (bf > 3)   "Moderate (BF 3–10)"
      else if (bf > 1)   "Anecdotal (BF 1–3)"
      else if (bf > 1/3) "Anecdotal for H₀"
      else if (bf > 1/10)"Moderate for H₀"
      else "Strong for H₀"
    }

    output$bf_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      if (res$type == "conj") {
        cat("=== Normal-Normal Conjugate Update ===\n")
        cat(sprintf("Data: n=%d, x̄=%.4f, s=%.4f\n", res$n, res$xbar, res$s))
        cat(sprintf("Prior: μ₀=%.4f, σ₀=%.4f\n\n", res$prior_mean, res$prior_sd))
        cat(sprintf("Posterior mean:  %.4f\n", res$post_mean))
        cat(sprintf("Posterior SD:    %.4f\n", sqrt(res$post_var)))
        cat(sprintf("95%% Cred. Int.: [%.4f, %.4f]\n",
                    res$post_mean - 1.96*sqrt(res$post_var),
                    res$post_mean + 1.96*sqrt(res$post_var)))
      } else {
        cat("=== Bayes Factor Analysis ===\n\n")
        print(res$bf)
        cat(sprintf("\nBF₁₀ = %.4f\n", res$bf_val))
        cat("Evidence: ", .bf_label(res$bf_val), "\n")
      }
    })

    output$bf_interp_ui <- renderUI({
      res <- result_r()
      if (is.null(res)) return(tags$p(class = "text-muted p-3", "Run analysis first."))
      if (res$type == "conj") {
        pm   <- res$post_mean; ps <- sqrt(res$post_var)
        lower <- pm - 1.96*ps; upper <- pm + 1.96*ps
        tags$div(class = "p-3",
          tags$h6("Posterior Summary"),
          tags$p(sprintf("Mean: %.4f", pm)),
          tags$p(sprintf("SD:   %.4f", ps)),
          tags$p(sprintf("95%% CrI: [%.4f, %.4f]", lower, upper)),
          if (lower > 0 || upper < 0)
            tags$div(class="alert alert-success py-1 small","Zero excluded from 95% CrI")
          else
            tags$div(class="alert alert-secondary py-1 small","Zero within 95% CrI")
        )
      } else {
        bf <- res$bf_val
        lbl <- .bf_label(bf)
        favor_h1 <- bf >= 1
        tags$div(class = "p-3",
          tags$div(
            class = if (favor_h1) "alert alert-success py-2" else "alert alert-secondary py-2",
            tags$strong(lbl),
            tags$span(sprintf(" (BF₁₀ = %.3f)", bf))
          ),
          tags$p(class = "small text-muted mt-2",
            sprintf("BF₁₀ > 1 = evidence for H₁; BF₁₀ < 1 = evidence for H₀."))
        )
      }
    })

    output$posterior_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Run analysis to see posterior plot."); return() }

      if (res$type == "conj") {
        pm  <- res$post_mean; ps <- sqrt(res$post_var)
        mu0 <- res$prior_mean; s0 <- res$prior_sd
        x_rng <- range(c(mu0 - 3*s0, pm - 3*ps, mu0 + 3*s0, pm + 3*ps))
        xseq  <- seq(x_rng[1], x_rng[2], length.out = 400)
        prior_d <- dnorm(xseq, mu0, s0)
        post_d  <- dnorm(xseq, pm,  ps)
        ylim <- c(0, max(prior_d, post_d) * 1.05)
        plot(xseq, prior_d, type = "l", col = "#c62828", lwd = 2, lty = 2,
             ylim = ylim, xlab = "μ", ylab = "Density",
             main = "Prior vs Posterior Distribution")
        polygon(c(xseq, rev(xseq)), c(post_d, rep(0,400)), col="#4caf5033", border=NA)
        lines(xseq, post_d, col = "#2e7d32", lwd = 2)
        abline(v = res$xbar, col = "grey50", lty = 3, lwd = 1.5)
        legend("topright", c("Prior","Posterior","Data mean"),
               col=c("#c62828","#2e7d32","grey50"), lwd=c(2,2,1.5), lty=c(2,1,3), bty="n")

      } else if (has_bf && !is.null(res$bf)) {
        tryCatch({
          post_samp <- BayesFactor::posterior(res$bf, iterations = 2000, progress = FALSE)
          if (!is.null(post_samp)) {
            plot(post_samp[, 1], type = "l", col = "#2e7d32", lwd = 1,
                 main = "Posterior MCMC Chain (first parameter)",
                 xlab = "Iteration", ylab = "Value")
          }
        }, error = function(e) {
          show_placeholder("Could not sample posterior.")
        })
      }
    })

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Bayesian Analysis: not run yet.")
        if (res$type == "conj")
          paste0("Bayesian conjugate | posterior mean=", round(res$post_mean, 4))
        else
          paste0("Bayes Factor | BF₁₀=", round(res$bf_val, 4),
                 " | ", .bf_label(res$bf_val))
      }),
      plot = function() {
        res <- isolate(result_r())
        if (is.null(res) || res$type != "conj") return(invisible())
        pm <- res$post_mean; ps <- sqrt(res$post_var)
        curve(dnorm(x, pm, ps), from = pm-3*ps, to = pm+3*ps,
              col = "#2e7d32", lwd = 2, main = "Posterior", xlab = "μ", ylab = "Density")
      }
    )
  })
}
