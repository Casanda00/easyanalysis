# ==========================================================================
# MODULE: Descriptive Statistics & Correlation
# descriptiveCanvasUI / descriptiveToolsUI / descriptiveServer
# ==========================================================================

descriptiveToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Descriptive Statistics", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "desc_plot",
      accordion_panel("Distribution Plot", value = "desc_plot", icon = icon("chart-bar"),
        uiOutput(ns("plot_var_ui")),
        selectInput(ns("plot_type"), "Distribution plot type", width = "100%",
          choices = c("Histogram + Density" = "hist",
                      "Density" = "density",
                      "Dot / Strip" = "dot"))
      ),
      accordion_panel("Correlation", value = "desc_cor", icon = icon("table-cells"),
        uiOutput(ns("cor_vars_ui")),
        selectInput(ns("cor_method"), "Method", width = "100%",
          choices = c("Pearson" = "pearson",
                      "Spearman" = "spearman",
                      "Kendall" = "kendall"))
      ),
      accordion_panel("Export", value = "desc_exp", icon = icon("download"),
        downloadButton(ns("dl_summary"), "Summary CSV", class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_cormat"), "Correlation CSV", class = "btn-sm btn-outline-success w-100")
      )
    )
  )
}

descriptiveCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Summary",
      DTOutput(ns("summary_tbl"), height = "calc(100vh - 180px)")
    ),
    nav_panel("Distributions",
      layout_columns(col_widths = c(6, 6),
        card(card_header("Distribution"), plotOutput(ns("dist_plot"), height = "400px")),
        card(card_header("Boxplot"), plotOutput(ns("box_plot"), height = "400px"))
      )
    ),
    nav_panel("Correlation Heatmap",
      card(plotOutput(ns("cor_heat"), height = "calc(100vh - 220px)"))
    ),
    nav_panel("Scatter Matrix",
      card(plotOutput(ns("pairs_plot"), height = "calc(100vh - 220px)"))
    )
  )
}

descriptiveServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds))
      dataset_pool[[ds]]
    })

    num_cols <- reactive({
      df <- active_data(); req(!is.null(df))
      names(df)[sapply(df, is.numeric)]
    })

    output$plot_var_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) == 0) return(tags$p(class="small text-warning","No numeric columns."))
      selectInput(ns("plot_var"), "Variable", choices = nms, width = "100%")
    })

    output$cor_vars_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) < 2) return(tags$p(class="small text-warning","Need ≥ 2 numeric columns."))
      selectInput(ns("cor_vars"), "Include variables", choices = nms,
                  selected = nms, multiple = TRUE, width = "100%")
    })

    .skew <- function(x) {
      x <- x[!is.na(x)]; n <- length(x)
      if (n < 3) return(NA_real_)
      m <- mean(x); s <- sd(x)
      if (s == 0) return(0)
      mean(((x - m) / s)^3)
    }
    .kurt <- function(x) {
      x <- x[!is.na(x)]; n <- length(x)
      if (n < 4) return(NA_real_)
      m <- mean(x); s <- sd(x)
      if (s == 0) return(0)
      mean(((x - m) / s)^4) - 3
    }
    .mode_val <- function(x) {
      x <- x[!is.na(x)]; if (length(x) == 0) return(NA_real_)
      u <- unique(x); u[which.max(tabulate(match(x, u)))]
    }

    summary_df <- reactive({
      df <- active_data(); req(!is.null(df))
      nms <- num_cols(); req(length(nms) > 0)
      do.call(rbind, lapply(nms, function(v) {
        x <- df[[v]]; xc <- as.numeric(x[!is.na(x)])
        data.frame(
          Variable = v, N = length(xc), Missing = sum(is.na(x)),
          Mean = round(mean(xc), 4), Median = round(median(xc), 4),
          Mode = round(.mode_val(xc), 4),
          SD = round(sd(xc), 4), Variance = round(var(xc), 4),
          Min = round(min(xc), 4), Q1 = round(quantile(xc, .25), 4),
          Q3 = round(quantile(xc, .75), 4), Max = round(max(xc), 4),
          Skewness = round(.skew(xc), 4), Kurtosis = round(.kurt(xc), 4),
          stringsAsFactors = FALSE
        )
      }))
    })

    output$summary_tbl <- renderDT({
      df <- summary_df(); req(!is.null(df))
      datatable(df, rownames = FALSE, options = list(
        scrollX = TRUE, pageLength = 25,
        columnDefs = list(list(className = "dt-right",
          targets = seq_len(ncol(df) - 1)))
      ))
    })

    output$dist_plot <- renderPlot({
      v <- input$plot_var; req(isTruthy(v))
      df <- active_data(); req(!is.null(df))
      x <- as.numeric(df[[v]]); x <- x[!is.na(x)]; req(length(x) > 1)
      pt <- input$plot_type %||% "hist"
      if (pt == "hist") {
        hist(x, col = "#4caf5088", border = "white", main = v, xlab = v, freq = FALSE,
             breaks = "Sturges")
        lines(density(x), col = "#2e7d32", lwd = 2)
      } else if (pt == "density") {
        d <- density(x); plot(d, main = v, xlab = v, col = "#2e7d32", lwd = 2)
        polygon(d, col = "#4caf5033", border = NA)
      } else if (pt %in% c("box", "dot")) {
        stripchart(x, method = "jitter", vertical = TRUE, pch = 16,
                   col = "#4caf5066", cex = 0.7, main = v, ylab = v)
      }
    })

    output$box_plot <- renderPlot({
      v <- input$plot_var; req(isTruthy(v))
      df <- active_data(); req(!is.null(df))
      x <- as.numeric(df[[v]]); x <- x[!is.na(x)]; req(length(x) > 1)
      boxplot(x, col = "#4caf5088", border = "#2e7d32", main = v, ylab = v, notch = FALSE)
      stripchart(x, method = "jitter", add = TRUE, vertical = TRUE,
                 col = "#2e7d3255", pch = 16, cex = 0.6)
    })

    cor_mat <- reactive({
      df <- active_data(); req(!is.null(df))
      vars <- input$cor_vars; req(isTruthy(vars), length(vars) >= 2)
      nd <- df[, intersect(vars, num_cols()), drop = FALSE]
      req(ncol(nd) >= 2)
      cor(nd, method = input$cor_method %||% "pearson", use = "pairwise.complete.obs")
    })

    output$cor_heat <- renderPlot({
      cm <- tryCatch(cor_mat(), error = function(e) NULL); req(!is.null(cm))
      n <- ncol(cm); vnames <- colnames(cm)
      df_long <- data.frame(
        Var1  = factor(rep(vnames, each = n), levels = vnames),
        Var2  = factor(rep(vnames, times = n), levels = rev(vnames)),
        value = as.vector(cm)
      )
      ggplot(df_long, aes(x = Var1, y = Var2, fill = value)) +
        geom_tile(color = "white", linewidth = 0.5) +
        geom_text(aes(label = sprintf("%.2f", value)), size = 3) +
        scale_fill_gradient2(low = "#d73027", mid = "white", high = "#1a9850",
                             midpoint = 0, limits = c(-1, 1),
                             name = tools::toTitleCase(input$cor_method %||% "pearson")) +
        labs(title = paste(tools::toTitleCase(input$cor_method %||% "pearson"),
                           "Correlation Matrix"), x = NULL, y = NULL) +
        theme_minimal(base_size = 11) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              panel.grid = element_blank(), legend.position = "right")
    })

    output$pairs_plot <- renderPlot({
      df <- active_data(); req(!is.null(df))
      vars <- input$cor_vars; req(isTruthy(vars), length(vars) >= 2)
      nd <- df[, intersect(vars, num_cols()), drop = FALSE]
      req(ncol(nd) >= 2)
      pairs(nd, col = "#2e7d3266", pch = 16, cex = 0.5,
            panel = function(x, y, ...) {
              points(x, y, col = "#2e7d3266", pch = 16, cex = 0.5)
              abline(lm(y ~ x), col = "#e53935", lwd = 1.5)
            },
            upper.panel = function(x, y, ...) {
              r <- cor(x, y, use = "complete.obs")
              usr <- par("usr"); on.exit(par(usr))
              par(usr = c(0,1,0,1))
              text(0.5, 0.5, sprintf("r=%.2f", r), cex = 1.2,
                   col = if (abs(r) > 0.7) "#c62828" else "#2e7d32")
            })
    })

    output$dl_summary <- downloadHandler(
      filename = function() "descriptive_summary.csv",
      content  = function(f) { df <- summary_df(); req(!is.null(df)); write.csv(df, f, row.names = FALSE) }
    )

    output$dl_cormat <- downloadHandler(
      filename = function() "correlation_matrix.csv",
      content  = function(f) {
        cm <- tryCatch(cor_mat(), error = function(e) NULL); req(!is.null(cm))
        write.csv(as.data.frame(cm), f)
      }
    )

    list(
      context = reactive({
        df <- tryCatch(summary_df(), error = function(e) NULL)
        if (is.null(df)) return("Descriptive Statistics: no data loaded.")
        paste0("Descriptive Statistics | ", nrow(df), " numeric variables\n",
          paste(apply(df, 1, function(r)
            sprintf("%s: n=%s, mean=%.3f, sd=%.3f, skew=%.3f",
                    r["Variable"], r["N"],
                    as.numeric(r["Mean"]), as.numeric(r["SD"]), as.numeric(r["Skewness"]))),
            collapse = "\n"))
      }),
      plot = function() {
        v <- isolate(input$plot_var); if (!isTruthy(v)) return(invisible())
        df <- isolate(active_data()); if (is.null(df)) return(invisible())
        x <- as.numeric(df[[v]]); x <- x[!is.na(x)]
        if (length(x) < 2) return(invisible())
        hist(x, col = "#4caf5088", border = "white", main = v, xlab = v, freq = FALSE)
        lines(density(x), col = "#2e7d32", lwd = 2)
      }
    )
  })
}
