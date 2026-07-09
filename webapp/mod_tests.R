# ==========================================================================
# MODULE: Statistical Tests
# t-Tests | Non-parametric | Categorical
# testsCanvasUI / testsToolsUI / testsServer
# ==========================================================================

testsToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Statistical Tests", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "tst_type",
      accordion_panel("Test Type", value = "tst_type", icon = icon("flask"),
        selectInput(ns("test_type"), NULL, width = "100%",
          choices = list(
            "Parametric (t-Tests)" = c(
              "One-sample t-test"        = "t_one",
              "Independent samples t-test (Welch)" = "t_indep",
              "Paired t-test"            = "t_paired"
            ),
            "Non-parametric" = c(
              "Mann-Whitney / Wilcoxon rank-sum" = "mw",
              "Wilcoxon signed-rank"             = "wcx_sr",
              "Kruskal-Wallis"                   = "kw",
              "Friedman test"                    = "friedman"
            ),
            "Categorical" = c(
              "Chi-square test"  = "chisq",
              "Fisher's exact"   = "fisher",
              "McNemar test"     = "mcnemar"
            )
          )
        )
      ),

      accordion_panel("Variables", value = "tst_vars", icon = icon("table-columns"),
        uiOutput(ns("var_inputs"))
      ),

      accordion_panel("Options", value = "tst_opts", icon = icon("sliders"),
        numericInput(ns("conf_level"), "Confidence level", value = 0.95,
                     min = 0.8, max = 0.999, step = 0.005, width = "100%"),
        conditionalPanel("input.test_type == 't_indep'", ns = ns,
          checkboxInput(ns("equal_var"), "Assume equal variances (Student)", value = FALSE)
        ),
        conditionalPanel(
          "input.test_type == 't_one' || input.test_type == 'wcx_sr'", ns = ns,
          numericInput(ns("mu0"), "Null hypothesis value (μ₀)", value = 0, width = "100%")
        ),
        conditionalPanel("input.test_type == 'chisq'", ns = ns,
          checkboxInput(ns("yates"), "Yates' continuity correction", value = FALSE)
        )
      )
    ),
    actionButton(ns("run_test"), "Run Test",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

testsCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(6, 6),
      card(
        card_header(class = "d-flex justify-content-between align-items-center",
          "Test Results",
          downloadButton(ns("dl_result"), "CSV", class = "btn-sm btn-outline-secondary")),
        verbatimTextOutput(ns("test_output"))
      ),
      tagList(
        card(
          card_header("Effect Size & Interpretation"),
          uiOutput(ns("effect_ui")),
          uiOutput(ns("interp_ui"))
        ),
        card(
          card_header("Plot"),
          plotOutput(ns("test_plot"), height = "280px")
        )
      )
    )
  )
}

testsServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds))
      dataset_pool[[ds]]
    })

    output$var_inputs <- renderUI({
      df <- active_data(); req(!is.null(df))
      num <- names(df)[sapply(df, is.numeric)]
      cat_all <- names(df)[sapply(df, function(x) is.factor(x) || is.character(x) || is.integer(x))]
      type <- input$test_type %||% "t_one"

      switch(type,
        t_one = tagList(
          selectInput(ns("var_x"), "Numeric variable", choices = num, width = "100%")
        ),
        t_indep = , mw = , kw = tagList(
          selectInput(ns("var_x"),     "Numeric variable",  choices = num,     width = "100%"),
          selectInput(ns("var_group"), "Group variable",    choices = names(df), width = "100%")
        ),
        t_paired = , wcx_sr = tagList(
          selectInput(ns("var_x"), "Variable 1 (before)", choices = num, width = "100%"),
          selectInput(ns("var_y"), "Variable 2 (after)",  choices = num, width = "100%")
        ),
        friedman = tagList(
          selectInput(ns("var_x"),     "Outcome variable",  choices = num,      width = "100%"),
          selectInput(ns("var_group"), "Treatment/group",   choices = names(df), width = "100%"),
          selectInput(ns("var_block"), "Block (subject)",   choices = names(df), width = "100%")
        ),
        chisq = , fisher = , mcnemar = tagList(
          selectInput(ns("var_x"), "Variable 1 (rows)",    choices = names(df), width = "100%"),
          selectInput(ns("var_y"), "Variable 2 (columns)", choices = names(df), width = "100%")
        )
      )
    })

    test_r <- eventReactive(input$run_test, {
      df   <- active_data(); req(!is.null(df))
      type <- input$test_type %||% "t_one"
      cl   <- as.numeric(input$conf_level %||% 0.95)

      tryCatch({
        switch(type,

          t_one = {
            x  <- as.numeric(df[[input$var_x]]); x <- x[!is.na(x)]
            mu <- as.numeric(input$mu0 %||% 0)
            res <- t.test(x, mu = mu, conf.level = cl)
            d   <- (mean(x) - mu) / sd(x)
            list(result = res, effect = sprintf("Cohen's d = %.3f", d),
                 effect_mag = abs(d), type = type, x = x)
          },

          t_indep = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            eq <- isTRUE(input$equal_var)
            res <- t.test(x ~ g, var.equal = eq, conf.level = cl)
            grps <- split(x[!is.na(x)], g[!is.na(x)])
            if (length(grps) >= 2) {
              n1 <- length(grps[[1]]); n2 <- length(grps[[2]])
              sp <- sqrt(((n1-1)*var(grps[[1]]) + (n2-1)*var(grps[[2]])) / (n1+n2-2))
              d <- (mean(grps[[1]]) - mean(grps[[2]])) / max(sp, 1e-12)
            } else d <- NA
            list(result = res, effect = sprintf("Cohen's d = %.3f", d),
                 effect_mag = abs(d), type = type, x = x, g = g)
          },

          t_paired = {
            x <- as.numeric(df[[input$var_x]])
            y <- as.numeric(df[[input$var_y]])
            keep <- !is.na(x) & !is.na(y)
            res <- t.test(x[keep], y[keep], paired = TRUE, conf.level = cl)
            d   <- mean(x[keep] - y[keep]) / sd(x[keep] - y[keep])
            list(result = res, effect = sprintf("Cohen's d = %.3f", d),
                 effect_mag = abs(d), type = type, x = x, y = y)
          },

          mw = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            res <- wilcox.test(x ~ g, conf.level = cl, conf.int = TRUE)
            n   <- sum(!is.na(x))
            r   <- abs(qnorm(res$p.value / 2)) / sqrt(n)
            list(result = res, effect = sprintf("r (rank-biserial) ≈ %.3f", r),
                 effect_mag = r, type = type, x = x, g = g)
          },

          wcx_sr = {
            x  <- as.numeric(df[[input$var_x]])
            y  <- as.numeric(df[[input$var_y]])
            keep <- !is.na(x) & !is.na(y)
            mu <- as.numeric(input$mu0 %||% 0)
            res <- if (input$var_x != input$var_y)
              wilcox.test(x[keep], y[keep], paired = TRUE, conf.level = cl, conf.int = TRUE)
            else
              wilcox.test(x[keep], mu = mu, conf.level = cl, conf.int = TRUE)
            n <- sum(keep)
            r <- abs(qnorm(res$p.value / 2)) / sqrt(n)
            list(result = res, effect = sprintf("r ≈ %.3f", r),
                 effect_mag = r, type = type, x = x, y = y)
          },

          kw = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            res <- kruskal.test(x ~ g)
            n   <- sum(!is.na(x))
            k   <- nlevels(g)
            eta2 <- (res$statistic - k + 1) / (n - k)
            list(result = res, effect = sprintf("η² ≈ %.3f", max(eta2, 0)),
                 effect_mag = max(eta2, 0), type = type, x = x, g = g)
          },

          friedman = {
            x <- as.numeric(df[[input$var_x]])
            g <- as.factor(df[[input$var_group]])
            b <- as.factor(df[[input$var_block]])
            res <- friedman.test(y = x, groups = g, blocks = b)
            list(result = res, effect = "", effect_mag = NA,
                 type = type, x = x, g = g)
          },

          chisq = {
            tbl <- table(df[[input$var_x]], df[[input$var_y]])
            yates <- isTRUE(input$yates) && all(dim(tbl) == 2)
            res <- chisq.test(tbl, correct = yates)
            n <- sum(tbl); k <- min(dim(tbl))
            V <- sqrt(res$statistic / (n * (k - 1)))
            list(result = res, tbl = tbl,
                 effect = sprintf("Cramér's V = %.3f", V),
                 effect_mag = V, type = type)
          },

          fisher = {
            tbl <- table(df[[input$var_x]], df[[input$var_y]])
            res <- fisher.test(tbl, conf.level = cl)
            list(result = res, tbl = tbl, effect = "", effect_mag = NA, type = type)
          },

          mcnemar = {
            tbl <- table(df[[input$var_x]], df[[input$var_y]])
            res <- mcnemar.test(tbl)
            list(result = res, tbl = tbl, effect = "", effect_mag = NA, type = type)
          }
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 8)
        NULL
      })
    })

    output$test_output <- renderPrint({
      res <- test_r(); req(!is.null(res))
      print(res$result)
    })

    output$effect_ui <- renderUI({
      res <- test_r(); req(!is.null(res))
      p <- res$result$p.value
      sig <- if (is.na(p)) "info" else if (p < 0.01) "danger" else if (p < 0.05) "success" else if (p < 0.10) "warning" else "secondary"
      sig_txt <- if (is.na(p)) "—" else if (p < 0.01) "Highly significant (p < 0.01)" else if (p < 0.05) "Significant (p < 0.05)" else if (p < 0.10) "Marginal (p < 0.10)" else "Not significant (p ≥ 0.10)"
      mag <- res$effect_mag
      mag_txt <- if (!is.na(mag)) {
        if (mag < 0.2) "Negligible" else if (mag < 0.5) "Small" else if (mag < 0.8) "Medium" else "Large"
      } else ""
      tagList(
        tags$div(class = paste0("alert alert-", sig, " py-2"),
          tags$strong(sig_txt),
          if (!is.na(p)) tags$span(sprintf(" (p = %.4f)", p))
        ),
        if (nzchar(res$effect))
          tags$div(class = "alert alert-light py-2",
            tags$strong(res$effect),
            if (nzchar(mag_txt)) tags$span(paste0(" — ", mag_txt, " effect"))
          )
      )
    })

    output$test_plot <- renderPlot({
      res <- test_r(); req(!is.null(res))
      type <- res$type
      if (type %in% c("t_indep", "mw", "kw") && !is.null(res$g)) {
        boxplot(res$x ~ res$g, col = "#4caf5088", border = "#2e7d32",
                main = "", xlab = "Group", ylab = "Value")
        stripchart(res$x ~ res$g, method = "jitter", add = TRUE, vertical = TRUE,
                   col = "#2e7d3244", pch = 16, cex = 0.6)
      } else if (type %in% c("t_paired", "wcx_sr") && !is.null(res$y)) {
        boxplot(list(Var1 = res$x[!is.na(res$x)], Var2 = res$y[!is.na(res$y)]),
                col = "#4caf5088", border = "#2e7d32",
                names = c(input$var_x, input$var_y), main = "")
      } else if (type %in% c("chisq", "fisher", "mcnemar") && !is.null(res$tbl)) {
        barplot(res$tbl, beside = TRUE, col = c("#4caf50","#2e7d32","#81c784","#1b5e20"),
                legend.text = rownames(res$tbl), args.legend = list(x = "topright", cex = 0.8),
                main = "Contingency Table", xlab = input$var_y, ylab = "Count")
      } else if (!is.null(res$x)) {
        hist(res$x[!is.na(res$x)], col = "#4caf5088", border = "white",
             main = "", xlab = "", freq = FALSE)
        lines(density(res$x[!is.na(res$x)]), col = "#2e7d32", lwd = 2)
      }
    })

    output$interp_ui <- renderUI({
      res <- test_r(); req(!is.null(res))
      p   <- res$result$p.value
      mag <- res$effect_mag
      sig_word <- if (!is.na(p) && p < 0.05) "significant" else "not significant"
      eff_word <- if (!is.na(mag)) {
        if (mag < 0.2) "negligible" else if (mag < 0.5) "small" else if (mag < 0.8) "medium" else "large"
      } else NULL
      method <- res$result$method
      sent <- paste0("The ", method, " showed a <b>", sig_word, "</b> result",
                     if (!is.na(p)) sprintf(" (p = %.4f)", p) else "",
                     if (!is.null(eff_word)) paste0(", with a <b>", eff_word, "</b> effect size") else "",
                     if (nzchar(res$effect)) paste0(" (", res$effect, ")") else "", ".")
      tags$div(class = "alert alert-light py-2 mt-2 small", HTML(sent))
    })

    output$dl_result <- downloadHandler(
      filename = function() paste0("test_results_", Sys.Date(), ".csv"),
      content  = function(file) {
        res <- test_r(); req(!is.null(res))
        p   <- tryCatch(res$result$p.value, error = function(e) NA)
        stat <- tryCatch(as.numeric(res$result$statistic), error = function(e) NA)
        out <- data.frame(
          test    = res$result$method,
          statistic = stat,
          p_value   = p,
          effect_size = res$effect,
          significant = !is.na(p) && p < 0.05,
          stringsAsFactors = FALSE
        )
        write.csv(out, file, row.names = FALSE)
      }
    )

    list(
      context = reactive({
        res <- tryCatch(test_r(), error = function(e) NULL)
        if (is.null(res)) return("Statistical Tests: no test run yet.")
        p <- res$result$p.value
        paste0("Statistical Test | Type: ", res$type, "\n",
               "Result: ", res$result$method, "\n",
               sprintf("p-value = %.4f | %s | %s", p,
                       if (!is.na(p) && p < 0.05) "Significant" else "Not significant",
                       res$effect))
      }),
      plot = function() {
        res <- isolate(tryCatch(test_r(), error = function(e) NULL))
        if (is.null(res) || is.null(res$x)) return(invisible())
        hist(res$x[!is.na(res$x)], col = "#4caf5088", border = "white",
             main = res$result$method, xlab = "", freq = FALSE)
      }
    )
  })
}
