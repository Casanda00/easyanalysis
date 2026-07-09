# ==========================================================================
# MODULE: ANOVA  (canvas + tools contract)
# anovaToolsUI(id) / anovaCanvasUI(id) / anovaServer(id, dataset_pool, active_dataset)
# Tests continuous differences across categorical groups (one-way ANOVA + Tukey).
# ==========================================================================

anovaToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "ANOVA Parameters"),
    markdown("*Tests continuous differences across categorical groups.*"),
    selectInput(ns("y"), "Continuous Target (Y):", choices = NULL),
    selectInput(ns("x"), "Categorical Group (X):", choices = NULL)
  )
}

anovaCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Diagnostics",
                  div(class = "d-flex align-items-center gap-2 header-controls",
                      radioGroupButtons(ns("view_mode"), label = NULL, choices = c("Grid View", "Single Plot"), selected = "Grid View", size = "sm", status = "primary"),
                      uiOutput(ns("single_selector")),
                      downloadButton(ns("download_plot"), "Download Plot", class = "btn-sm btn-outline-success"))
      ),
      div(style = "overflow-y: auto; height: 520px; padding: 5px;", uiOutput(ns("dynamic_plot_ui")))
    ),
    uiOutput(ns("interp_ui")),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "d-flex justify-content-between align-items-center bg-light",
          "ANOVA Table",
          downloadButton(ns("dl_summary"), "CSV", class = "btn-sm btn-outline-secondary")),
        div(style = "overflow-y: auto; height: 300px; padding: 5px;", verbatimTextOutput(ns("summary")))
      ),
      card(
        card_header(class = "bg-light", "Tukey HSD (Post-Hoc)"),
        div(style = "overflow-y: auto; height: 300px; padding: 5px;", verbatimTextOutput(ns("tukey")))
      )
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "bg-light", "Effect Size (η² / Cohen's f)"),
        div(style = "padding: 5px;", verbatimTextOutput(ns("effect_size")))
      ),
      card(
        card_header(class = "bg-light", "LOOCV"),
        div(style = "padding: 5px;", verbatimTextOutput(ns("loocv_out")))
      )
    )
  )
}

anovaServer <- function(id, dataset_pool, active_dataset) {
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
      num_cols <- names(df)[sapply(df, is.numeric)]
      cat_cols <- names(df)[sapply(df, is_safe_cat)]
      curr_y <- if (isTruthy(isolate(input$y)) && isolate(input$y) %in% num_cols) isolate(input$y) else if (length(num_cols) > 0) num_cols[1] else NULL
      curr_x <- if (isTruthy(isolate(input$x)) && isolate(input$x) %in% cat_cols) isolate(input$x) else if (length(cat_cols) > 0) cat_cols[1] else NULL
      updateSelectInput(session, "y", choices = num_cols, selected = curr_y)
      updateSelectInput(session, "x", choices = cat_cols, selected = curr_x)
    })

    aov_model <- reactive({
      df <- active_data()
      if (is.null(df)) return("Awaiting dataset...")
      if (!isTruthy(input$y) || !isTruthy(input$x)) return("Awaiting Predictors: Select a Continuous Y and Categorical X.")

      clean_df <- df[, c(input$y, input$x), drop = FALSE]
      clean_df <- clean_df[complete.cases(clean_df), , drop = FALSE]
      if (nrow(clean_df) < 10) return("Data Error: Insufficient complete cases.")
      clean_df[[input$x]] <- droplevels(as.factor(clean_df[[input$x]]))
      if (length(levels(clean_df[[input$x]])) < 2) return("Data Error: Categorical variable must have at least 2 valid levels.")

      form_str <- paste0("`", input$y, "` ~ `", input$x, "`")
      tryCatch({ aov(as.formula(form_str), data = clean_df) }, error = function(e) { return(paste("ANOVA Error:", e$message)) })
    })

    output$summary <- renderPrint({
      model <- aov_model()
      if (is.character(model)) cat(model) else print(summary(model))
    })

    output$tukey <- renderPrint({
      model <- aov_model()
      if (is.character(model)) return(cat("Awaiting valid model parameters..."))
      tryCatch({ print(TukeyHSD(model)) }, error = function(e) { cat("Tukey HSD Test Requires Factors. Error:\n", e$message) })
    })

    output$single_selector <- renderUI({
      req(input$view_mode == "Single Plot")
      selectInput(ns("zoom_target"), label = NULL, choices = c("Residuals vs Fitted", "Normal Q-Q"), width = "200px")
    })

    output$dynamic_plot_ui <- renderUI({
      req(input$view_mode)
      plotOutput(ns("diag_plot"), height = "500px")
    })

    output$diag_plot <- renderPlot({
      req(input$view_mode)
      if (input$view_mode == "Single Plot") req(input$zoom_target)
      plot_aov_diagnostics(aov_model(), input$view_mode, input$zoom_target)
    })

    output$download_plot <- downloadHandler(
      filename = function() { paste0("anova_diagnostic_", Sys.Date(), ".png") },
      content = function(file) {
        png(file, width = 800, height = 600)
        plot_aov_diagnostics(aov_model(), input$view_mode, input$zoom_target)
        dev.off()
      }
    )

    output$interp_ui <- renderUI({
      m <- aov_model(); req(!is.character(m))
      sm  <- summary(m)[[1]]
      f   <- sm[["F value"]][[1]]
      p   <- sm[["Pr(>F)"]][[1]]
      sig_word <- if (!is.na(p) && p < 0.05) "significant" else "not significant"
      tk  <- tryCatch({
        th <- TukeyHSD(m)[[input$x]]
        sum(th[, "p adj"] < 0.05, na.rm = TRUE)
      }, error = function(e) NA)
      sent <- paste0(
        "One-way ANOVA found a <b>", sig_word, "</b> effect of <b>", input$x,
        "</b> on <b>", input$y, "</b>",
        sprintf(" (F = %.2f, p = %.4f)", f, p),
        if (!is.na(tk)) paste0(". Post-hoc Tukey tests identified <b>", tk,
                               " significant</b> pairwise comparison(s)") else "",
        "."
      )
      card(tags$div(class = "p-3 small", HTML(sent)))
    })

    output$effect_size <- renderPrint({
      m <- aov_model(); req(!is.character(m))
      tryCatch({
        sm   <- summary(m)[[1]]
        ss_b <- sm[["Sum Sq"]][[1]]
        ss_e <- sm[["Sum Sq"]][[2]]
        ss_t <- ss_b + ss_e
        eta2 <- ss_b / ss_t
        f2   <- eta2 / (1 - eta2)
        cat(sprintf("η² (eta-squared)  : %.4f\n", eta2))
        cat(sprintf("Cohen's f         : %.4f\n", sqrt(f2)))
        cat("\nConventional thresholds:\n")
        cat("  small: η²≥0.01, medium: η²≥0.06, large: η²≥0.14\n")
        size <- if (eta2 >= 0.14) "LARGE" else if (eta2 >= 0.06) "MEDIUM" else if (eta2 >= 0.01) "small" else "negligible"
        cat(sprintf("\nEffect: %s\n", size))
      }, error=function(e) cat("Effect size error:", e$message, "\n"))
    })

    output$loocv_out <- renderPrint({
      m <- aov_model(); req(!is.character(m))
      tryCatch({
        cv <- .loocv_lm(m)
        cat(sprintf("LOOCV RMSE : %.4f\nLOOCV MAE  : %.4f\nLOOCV R²   : %.4f\n",
                    cv$LOOCV_RMSE, cv$LOOCV_MAE, cv$LOOCV_R2))
        cat("\n(Exact hat-matrix shortcut — no model refits.)\n")
      }, error=function(e) cat("LOOCV error:", e$message, "\n"))
    })

    output$dl_summary <- downloadHandler(
      filename = function() paste0("anova_results_", Sys.Date(), ".csv"),
      content  = function(file) {
        m <- aov_model(); req(!is.character(m))
        sm <- as.data.frame(summary(m)[[1]])
        sm <- cbind(Term = rownames(sm), sm)
        write.csv(sm, file, row.names = FALSE)
      }
    )

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        m <- aov_model()
        if (is.character(m)) return(paste("ANOVA —", m))
        tk <- tryCatch(paste(utils::capture.output(TukeyHSD(m)), collapse = "\n"), error = function(e) "n/a")
        paste0("One-way ANOVA: ", input$y, " by ", input$x, "\n\nANOVA table:\n",
               paste(utils::capture.output(summary(m)), collapse = "\n"),
               "\n\nTukey HSD:\n", tk)
      }),
      plot = function() plot_aov_diagnostics(aov_model(), input$view_mode, input$zoom_target)
    )
  })
}
