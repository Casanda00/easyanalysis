# sandbox.R — DA method test harness mirroring simple.R exactly
# Run: shiny::runApp("sandbox.R")
# No hidden preprocessing. Data is assumed clean. Errors are shown raw.

library(shiny)
library(bslib)
library(ggplot2)
library(MASS)

ui <- page_sidebar(
  title = "DA Sandbox (mirrors simple.R)",
  sidebar = sidebar(
    width = 300,
    fileInput("file", "Upload cleaned CSV", accept = ".csv"),
    uiOutput("target_ui"),
    uiOutput("predictors_ui"),
    hr(),
    selectInput("method", "DA Method", choices = c(
      "LDA"  = "LDA",
      "Weighted LDA (WLDA)" = "WLDA",
      "QDA"  = "QDA",
      "Regularized LDA (RLDA)" = "RLDA",
      "Kernel DA (KDA)" = "KDA",
      "Locally Linear DA (LLDA)" = "LLDA",
      "Maximum Margin (MMC)" = "MMC"
    )),
    conditionalPanel("input.method == 'WLDA'",
      selectInput("wlda_weight", "Weight scheme",
        choices = c("Inverse frequency (1/N)" = "inverse",
                    "Proportional (N/total)" = "proportional",
                    "Equal" = "equal"),
        selected = "inverse")
    ),
    conditionalPanel("input.method == 'KDA'",
      numericInput("kda_sigma", "Sigma (RBF width)", value = 0.01, min = 0.001, step = 0.001),
      numericInput("kda_C", "Cost C", value = 0.1, min = 0.01, step = 0.1)
    ),
    conditionalPanel("input.method == 'LLDA'",
      sliderInput("llda_k", "Neighbours k", min = 3, max = 30, value = 5)
    ),
    conditionalPanel("input.method == 'MMC'",
      numericInput("mmc_C", "Cost C", value = 1, min = 0.01, step = 0.1)
    ),
    hr(),
    actionButton("run", "Run", class = "btn-primary w-100")
  ),

  layout_columns(
    col_widths = c(6, 6),
    card(
      card_header("Confusion Matrix (Training)"),
      tableOutput("conf_matrix")
    ),
    card(
      card_header("Accuracy & Class-level Counts"),
      verbatimTextOutput("accuracy")
    )
  ),
  card(
    card_header("Raw R Output / Errors"),
    verbatimTextOutput("raw_out")
  ),

  # Decision boundary plots — only rendered when exactly 1 numeric predictor
  uiOutput("boundary_plots_ui")
)

server <- function(input, output, session) {

  data_r <- reactive({
    req(input$file)
    read.csv(input$file$datapath, stringsAsFactors = FALSE)
  })

  output$target_ui <- renderUI({
    df <- data_r()
    selectInput("target", "Target variable (Y)", choices = names(df))
  })

  output$predictors_ui <- renderUI({
    df <- data_r()
    selectizeInput("predictors", "Predictors (X)", choices = names(df),
                   multiple = TRUE, options = list(`actions-box` = TRUE))
  })

  result_r <- eventReactive(input$run, {
    req(data_r(), input$target, length(input$predictors) > 0)
    df      <- data_r()
    target  <- input$target
    preds   <- input$predictors
    method  <- input$method

    df[[target]] <- as.factor(df[[target]])
    df[[target]] <- droplevels(df[[target]])
    keep_cols    <- c(target, preds)
    df           <- df[complete.cases(df[, keep_cols, drop = FALSE]), keep_cols, drop = FALSE]

    form <- as.formula(paste(
      paste0("`", target, "`"), "~",
      paste(paste0("`", preds, "`"), collapse = " + ")
    ))

    log_lines <- character(0)
    log <- function(...) { log_lines <<- c(log_lines, paste0(...)) }

    log("Method : ", method)
    log("Formula: ", deparse(form))
    log("Rows   : ", nrow(df))
    log("Classes: ", paste(levels(df[[target]]), collapse = ", "))
    log("Class counts:\n", paste(capture.output(print(table(df[[target]]))), collapse = "\n"))
    log("")

    tryCatch({

      if (method == "LDA") {
        model      <- MASS::lda(form, data = df)
        pred_class <- predict(model)$class

      } else if (method == "WLDA") {
        class_counts <- table(df[[target]])
        N            <- nrow(df)
        weights      <- switch(input$wlda_weight,
          "inverse"      = as.numeric(1 / class_counts[df[[target]]]),
          "proportional" = as.numeric(class_counts[df[[target]]] / N),
          rep(1, N))
        model      <- MASS::lda(form, data = df, weights = weights)
        pred_class <- predict(model)$class

      } else if (method == "QDA") {
        model      <- MASS::qda(form, data = df)
        pred_class <- predict(model)$class

      } else if (method == "RLDA") {
        if (!requireNamespace("klaR", quietly = TRUE)) stop("Package 'klaR' not installed.")
        model      <- klaR::rda(form, data = df, gamma = seq(0, 1, 0.1), lambda = seq(0, 1, 0.1))
        pred_class <- predict(model)$class

      } else if (method == "KDA") {
        if (!requireNamespace("kernlab", quietly = TRUE)) stop("Package 'kernlab' not installed.")
        model      <- kernlab::ksvm(form, data = df, kernel = "rbfdot",
                                    kpar = list(sigma = input$kda_sigma),
                                    C = input$kda_C, prob.model = TRUE)
        pred_class <- kernlab::predict(model, df)

      } else if (method == "LLDA") {
        if (!requireNamespace("klaR", quietly = TRUE)) stop("Package 'klaR' not installed.")
        df_j <- df
        for (p in preds) if (is.numeric(df_j[[p]])) df_j[[p]] <- jitter(df_j[[p]], amount = 0.0001)
        model      <- klaR::loclda(form, data = df_j, k = input$llda_k)
        pred_class <- predict(model)$class

      } else if (method == "MMC") {
        if (!requireNamespace("kernlab", quietly = TRUE)) stop("Package 'kernlab' not installed.")
        model      <- kernlab::ksvm(form, data = df, kernel = "vanilladot", C = input$mmc_C)
        pred_class <- kernlab::predict(model, df)
      }

      actual <- df[[target]]
      cm     <- table(Predicted = as.character(pred_class), Actual = as.character(actual))
      acc    <- mean(as.character(pred_class) == as.character(actual)) * 100
      log(sprintf("Training Accuracy: %.2f%%", acc))

      list(model = model, data = df, target = target, preds = preds, method = method,
           pred_class = pred_class, cm = cm, acc = acc, log = log_lines, error = NULL)

    }, error = function(e) {
      log("ERROR: ", e$message)
      list(model = NULL, data = df, target = target, preds = preds, method = method,
           pred_class = NULL, cm = NULL, acc = NULL, log = log_lines, error = e$message)
    })
  })

  # ------------------------------------------------------------------
  # Pre-compute grid predictions for boundary plots (1 numeric pred only)
  # ------------------------------------------------------------------
  boundary_data_r <- reactive({
    res <- result_r()
    if (is.null(res) || !is.null(res$error) || is.null(res$model)) return(NULL)

    num_preds <- res$preds[sapply(res$data[, res$preds, drop = FALSE], is.numeric)]
    if (length(num_preds) != 1) return(NULL)
    px <- num_preds[1]

    grid_x  <- seq(min(res$data[[px]], na.rm = TRUE) - 0.5,
                   max(res$data[[px]], na.rm = TRUE) + 0.5, length.out = 500)
    grid_df <- setNames(data.frame(grid_x), px)
    # Fix all other predictors at median (numeric) or mode (categorical)
    for (p in res$preds) {
      if (p == px) next
      col <- res$data[[p]]
      if (is.numeric(col)) {
        grid_df[[p]] <- median(col, na.rm = TRUE)
      } else {
        mode_val <- names(sort(table(col), decreasing = TRUE))[1]
        grid_df[[p]] <- if (is.factor(col)) factor(mode_val, levels = levels(col)) else mode_val
      }
    }

    grid_pred <- tryCatch({
      if (res$method %in% c("KDA", "MMC"))
        as.character(kernlab::predict(res$model, newdata = grid_df))
      else
        as.character(predict(res$model, newdata = grid_df)$class)
    }, error = function(e) NULL)
    if (is.null(grid_pred)) return(NULL)

    # Boundary x positions (where predicted class changes)
    rle_p <- rle(grid_pred)
    bnd_x <- grid_x[cumsum(rle_p$lengths)[-length(rle_p$lengths)]]

    grid_data <- data.frame(x = grid_x, Predicted = as.factor(grid_pred))
    df_pts    <- data.frame(x = res$data[[px]], Actual = as.factor(res$data[[res$target]]))

    # Shared color palette keyed by class name
    all_cls      <- union(levels(df_pts$Actual), unique(grid_pred))
    pal_hex      <- viridisLite::viridis(length(all_cls), option = "D")
    class_colors <- setNames(pal_hex, all_cls)

    list(grid_data = grid_data, df_pts = df_pts, bnd_x = bnd_x,
         class_colors = class_colors, px = px, method = res$method)
  })

  # Show three separate plot cards only when boundary data is available
  output$boundary_plots_ui <- renderUI({
    res <- result_r()
    if (is.null(res) || !is.null(res$error)) return(NULL)

    num_preds <- res$preds[sapply(res$data[, res$preds, drop = FALSE], is.numeric)]
    if (length(num_preds) != 1) {
      return(card(card_header("Decision Boundary Plots"),
        p(class = "text-muted p-3",
          "Select exactly 1 numeric predictor to see decision boundary plots.")))
    }

    navset_card_tab(
      nav_panel("Scatter + Regions", plotOutput("plot_scatter", height = "520px")),
      nav_panel("Density Curves",    plotOutput("plot_c",       height = "520px")),
      nav_panel("Histogram by Class", plotOutput("plot_hist",   height = "520px"))
    )
  })

  # ------------------------------------------------------------------
  # Scatter + predicted region background (different shape per class)
  # ------------------------------------------------------------------
  output$plot_scatter <- renderPlot({
    bd <- boundary_data_r(); req(bd)

    shapes <- setNames(c(16, 17, 15, 18, 8, 3, 4)[seq_along(levels(bd$df_pts$Actual))],
                       levels(bd$df_pts$Actual))

    p <- ggplot() +
      geom_tile(data = bd$grid_data,
                aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
      geom_jitter(data = bd$df_pts,
                  aes(x = x, y = 0, color = Actual, shape = Actual),
                  height = 0.3, size = 2.5, alpha = 0.75) +
      scale_fill_manual(values = bd$class_colors, name = "Predicted") +
      scale_color_manual(values = bd$class_colors, name = "Actual") +
      scale_shape_manual(values = shapes, name = "Actual") +
      theme_minimal(base_size = 13) +
      theme(axis.text.y = element_blank(), axis.title.y = element_blank(),
            axis.ticks.y = element_blank(),
            panel.grid.major.y = element_blank(), panel.grid.minor.y = element_blank(),
            legend.position = "bottom") +
      labs(title = paste(bd$method, "— Decision Regions"),
           subtitle = "Background = predicted class  |  Points = actual class (shape + colour)",
           x = bd$px)
    if (length(bd$bnd_x) > 0)
      p <- p + geom_vline(xintercept = bd$bnd_x, linetype = "dashed",
                          color = "black", linewidth = 0.8)
    print(p)
  })

  # ------------------------------------------------------------------
  # Density curves overlaid on predicted region background (Option C)
  # ------------------------------------------------------------------
  output$plot_c <- renderPlot({
    bd <- boundary_data_r(); req(bd)

    subtitle <- if (length(bd$bnd_x) > 0)
      paste("Boundaries at x =", paste(round(bd$bnd_x, 2), collapse = ", ")) else ""

    print(
      ggplot() +
        geom_tile(data = bd$grid_data,
                  aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
        geom_density(data = bd$df_pts,
                     aes(x = x, fill = Actual, color = Actual),
                     alpha = 0.5, linewidth = 0.5) +
        scale_fill_manual(values = bd$class_colors) +
        scale_color_manual(values = bd$class_colors) +
        theme_minimal(base_size = 13) +
        theme(legend.position = "bottom") +
        labs(title = paste("Option C:", bd$method, "— Density Curves"),
             subtitle = subtitle, x = bd$px, y = "Density")
    )
  })

  # ------------------------------------------------------------------
  # Stacked histogram of predictor by actual class
  # ------------------------------------------------------------------
  output$plot_hist <- renderPlot({
    bd <- boundary_data_r(); req(bd)

    df_hist <- data.frame(x = bd$df_pts$x, Class = bd$df_pts$Actual)

    print(
      ggplot(df_hist, aes(x = x, fill = Class)) +
        geom_histogram(color = "darkgray", bins = 30, alpha = 0.85) +
        facet_wrap(~ Class, ncol = 1, scales = "free_y") +
        scale_fill_manual(values = bd$class_colors) +
        theme_minimal(base_size = 13) +
        theme(legend.position = "none",
              strip.background = element_rect(fill = "#e9ecef", color = NA),
              strip.text = element_text(face = "bold", size = 12),
              panel.spacing = unit(1, "lines")) +
        labs(title = paste("Histogram of", bd$px, "by Class —", bd$method),
             x = bd$px, y = "Count")
    )
  })

  # ------------------------------------------------------------------
  # Summary outputs
  # ------------------------------------------------------------------
  output$conf_matrix <- renderTable({
    res <- result_r()
    if (is.null(res$cm)) return(data.frame(Message = "No result — check Raw Output."))
    as.data.frame.matrix(res$cm)
  }, rownames = TRUE)

  output$accuracy <- renderPrint({
    res <- result_r()
    if (!is.null(res$error)) { cat("Failed — see Raw Output.\n"); return() }
    cat(sprintf("Training Accuracy: %.2f%%\n\nClass breakdown:\n", res$acc))
    for (cls in colnames(res$cm)) {
      n_actual  <- sum(res$cm[, cls])
      n_correct <- if (cls %in% rownames(res$cm)) res$cm[cls, cls] else 0
      cat(sprintf("  %-25s  n=%d  correct=%d  (%.0f%%)\n",
                  cls, n_actual, n_correct,
                  if (n_actual > 0) 100 * n_correct / n_actual else 0))
    }
  })

  output$raw_out <- renderPrint({
    res <- result_r()
    cat(paste(res$log, collapse = "\n"))
  })
}

shinyApp(ui, server)
