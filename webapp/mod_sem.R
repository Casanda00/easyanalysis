# ==========================================================================
# MODULE: SEM, Path Analysis & Mediation/Moderation
# semCanvasUI / semToolsUI / semServer
# Requires: lavaan, mediation (install separately)
# ==========================================================================

semToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("SEM & Mediation", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "sem_about",
      accordion_panel("About", value = "sem_about", icon = icon("info-circle"),
        tags$div(class = "small text-muted",
          tags$p("This panel will support:"),
          tags$ul(
            tags$li("Structural Equation Modeling (lavaan)"),
            tags$li("Path analysis"),
            tags$li("Mediation analysis (mediation package)"),
            tags$li("Moderation analysis (interaction terms)"),
            tags$li("Moderated mediation")
          ),
          tags$hr(style="margin:6px 0;"),
          tags$p(class = "fw-bold", "Required packages:"),
          tags$code("install.packages(c('lavaan', 'mediation', 'semPlot'))")
        )
      ),
      accordion_panel("Quick Mediation (base R)", value = "sem_med", icon = icon("play"),
        tags$p(class = "small text-muted",
          "Simple mediation via causal-steps approach (Baron & Kenny) — no extra packages needed."),
        uiOutput(ns("y_ui")),
        uiOutput(ns("m_ui")),
        uiOutput(ns("x_ui"))
      )
    ),
    actionButton(ns("run_med"), "Run Mediation (Baron & Kenny)",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

semCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Mediation Results",
      layout_columns(col_widths = c(7, 5),
        card(card_header("Baron & Kenny Steps"), verbatimTextOutput(ns("med_out"))),
        card(card_header("Effect Summary"), uiOutput(ns("med_summary_ui")))
      )
    ),
    nav_panel("lavaan SEM",
      card(
        card_header("lavaan — Structural Equation Modeling"),
        tags$div(class = "p-4",
          tags$p(class = "text-muted",
            "Full SEM with latent variables requires the lavaan package."),
          tags$pre(class = "small bg-light p-3 rounded", style="font-size:11px;",
'# Example lavaan syntax:
model <- "
  # Measurement model (latent variables)
  ability =~ x1 + x2 + x3
  speed   =~ x4 + x5

  # Structural model (regressions)
  speed ~ ability
  outcome ~ speed + ability
"
fit <- lavaan::sem(model, data = your_data)
summary(fit, fit.measures = TRUE, standardized = TRUE)'),
          tags$br(),
          tags$p("Install and use in your R console for now. Full UI integration coming soon."),
          tags$code("install.packages('lavaan')")
        )
      )
    ),
    nav_panel("Moderation",
      card(
        card_header("Moderation Analysis (Interaction)"),
        tags$div(class = "p-4",
          tags$p(class = "text-muted",
            "Moderation is tested by including an interaction term in regression."),
          tags$pre(class = "small bg-light p-3 rounded", style="font-size:11px;",
'# Moderation: does Z moderate the X -> Y effect?
fit <- lm(Y ~ X * Z, data = df)   # X:Z = interaction
summary(fit)
# If X:Z coefficient is significant -> moderation confirmed'),
          tags$br(),
          tags$p("Use the Regression screen with an interaction term (X*Z) as a predictor."),
          tags$p("Full moderation diagnostics panel coming in next build.")
        )
      )
    )
  )
}

semServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    num_cols <- reactive({
      df <- active_data(); req(!is.null(df))
      names(df)[sapply(df, is.numeric)]
    })

    output$y_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) == 0) return(tags$p(class="small text-warning","No numeric columns."))
      selectInput(ns("y_var"), "Outcome (Y)", choices = nms, width = "100%")
    })

    output$m_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) < 2) return(NULL)
      selectInput(ns("m_var"), "Mediator (M)", choices = nms, width = "100%")
    })

    output$x_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) < 2) return(NULL)
      selectInput(ns("x_var"), "Predictor (X)", choices = nms, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_med, {
      df <- active_data(); req(!is.null(df))
      yv <- input$y_var; req(isTruthy(yv))
      mv <- input$m_var; req(isTruthy(mv))
      xv <- input$x_var; req(isTruthy(xv))
      req(length(unique(c(xv, mv, yv))) == 3)

      sub <- df[, c(xv, mv, yv)]; sub <- sub[complete.cases(sub), ]
      req(nrow(sub) >= 10)

      result <- tryCatch({
        # Step 1: X -> Y (total effect, path c)
        step1 <- lm(as.formula(paste(yv, "~", xv)), data = sub)
        # Step 2: X -> M (path a)
        step2 <- lm(as.formula(paste(mv, "~", xv)), data = sub)
        # Step 3: X + M -> Y (paths b and c')
        step3 <- lm(as.formula(paste(yv, "~", xv, "+", mv)), data = sub)

        # Effects
        c_total  <- coef(step1)[[xv]]
        a        <- coef(step2)[[xv]]
        b        <- coef(step3)[[mv]]
        c_prime  <- coef(step3)[[xv]]
        ab       <- a * b   # indirect effect (Sobel)

        # Sobel test
        se_a  <- summary(step2)$coefficients[xv, "Std. Error"]
        se_b  <- summary(step3)$coefficients[mv, "Std. Error"]
        se_ab <- sqrt(b^2 * se_a^2 + a^2 * se_b^2)
        z_sob <- ab / se_ab
        p_sob <- 2 * (1 - pnorm(abs(z_sob)))

        list(step1=step1, step2=step2, step3=step3,
             c_total=c_total, a=a, b=b, c_prime=c_prime, ab=ab,
             z_sob=z_sob, p_sob=p_sob, se_ab=se_ab,
             xv=xv, mv=mv, yv=yv)
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("Mediation analysis complete.", type = "message")
    })

    output$med_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("=== Baron & Kenny Mediation Analysis ===\n")
      cat(sprintf("X = %s  |  M = %s  |  Y = %s\n\n", res$xv, res$mv, res$yv))

      cat("Step 1: X -> Y (total effect, path c)\n")
      print(summary(res$step1)$coefficients)

      cat("\nStep 2: X -> M (path a)\n")
      print(summary(res$step2)$coefficients)

      cat("\nStep 3: X + M -> Y (paths b and c')\n")
      print(summary(res$step3)$coefficients)

      cat("\n=== Indirect Effect (a × b) ===\n")
      cat(sprintf("a (X->M):          %.4f\n", res$a))
      cat(sprintf("b (M->Y | X):      %.4f\n", res$b))
      cat(sprintf("Indirect (ab):     %.4f (SE=%.4f)\n", res$ab, res$se_ab))
      cat(sprintf("Sobel z:           %.4f  p=%.4f\n", res$z_sob, res$p_sob))
      cat(sprintf("Direct c':         %.4f\n", res$c_prime))
      cat(sprintf("Total c:           %.4f\n", res$c_total))
      cat(sprintf("Prop. mediated:    %.1f%%\n", 100 * res$ab / res$c_total))
    })

    output$med_summary_ui <- renderUI({
      res <- result_r()
      if (is.null(res)) return(tags$p(class = "text-muted p-3", "Run mediation to see results."))
      is_med <- res$p_sob < 0.05
      prop_med <- round(100 * res$ab / res$c_total, 1)
      tagList(
        tags$div(class = if (is_med) "alert alert-success py-2" else "alert alert-secondary py-2",
          tags$strong(if (is_med) "Significant mediation" else "No significant mediation"),
          tags$span(sprintf(" (Sobel p = %.4f)", res$p_sob))
        ),
        tags$table(class = "table table-sm table-borderless small",
          tags$tbody(
            tags$tr(tags$th("Path a (X→M)"), tags$td(round(res$a, 4))),
            tags$tr(tags$th("Path b (M→Y)"), tags$td(round(res$b, 4))),
            tags$tr(tags$th("Indirect (ab)"), tags$td(round(res$ab, 4))),
            tags$tr(tags$th("Direct (c')"), tags$td(round(res$c_prime, 4))),
            tags$tr(tags$th("Total (c)"), tags$td(round(res$c_total, 4))),
            tags$tr(tags$th("% Mediated"), tags$td(paste0(prop_med, "%")))
          )
        )
      )
    })

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("SEM & Mediation: not yet run.")
        paste0("Mediation Analysis | X=", res$xv, " -> M=", res$mv, " -> Y=", res$yv,
               sprintf("\nIndirect (ab)=%.4f, Sobel p=%.4f", res$ab, res$p_sob))
      }),
      plot = function() invisible()
    )
  })
}
