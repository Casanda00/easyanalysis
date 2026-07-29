# ==========================================================================
# MODULE: Discriminant Analysis  (canvas + tools contract)  -- the big one
# daToolsUI / daCanvasUI / daServer(id, dataset_pool, active_dataset)
# Two modes: (1) Assumption Checks (ellipses/boxplots/Q-Q/density/stat tests)
#            (2) Run Model (9 methods: LDA/WLDA/QDA/RLDA/KDA/LLDA/MMC/RF/NN)
# Optional pkgs (klaR/kernlab/heplots/ggord) are guarded by requireNamespace().
# ==========================================================================

daToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "DA Controls"),
    selectInput(ns("main_mode"), "Analysis Mode:", choices = c("1. Assumption Checks", "2. Run Model"), selected = "1. Assumption Checks"),
    selectInput(ns("category"), "Target Variable (Y):", choices = NULL),
    hr(),

    conditionalPanel(
      condition = "input.main_mode == '1. Assumption Checks'", ns = ns,
      selectInput(ns("view"), "Select Diagnostic View:",
        choices = c("1. Covariance Ellipses", "2. Equal Variance (Boxplots)", "3. Normality (Q-Q Plots)", "4. Distribution Density", "5. Statistical Tests"),
        selected = "1. Covariance Ellipses"),
      hr(),
      conditionalPanel(
        condition = "input.view == '1. Covariance Ellipses'", ns = ns,
        markdown("**Ellipses Parameters**"),
        selectInput(ns("ellipses_x"), "X-Axis Variable:", choices = NULL),
        selectInput(ns("ellipses_y"), "Y-Axis Variable:", choices = NULL)
      ),
      conditionalPanel(
        condition = "input.view == '2. Equal Variance (Boxplots)'", ns = ns,
        markdown("**Boxplot Parameters**"),
        selectInput(ns("box_y"), "Analyze Variable:", choices = NULL)
      ),
      conditionalPanel(
        condition = "input.view == '3. Normality (Q-Q Plots)' || input.view == '4. Distribution Density'", ns = ns,
        markdown("**Distribution Parameters**"),
        selectInput(ns("norm_var"), "Assess Normality of:", choices = NULL)
      ),
      conditionalPanel(
        condition = "input.view == '5. Statistical Tests'", ns = ns,
        markdown("**Statistical Parameters**"),
        selectInput(ns("stat_test_type"), "Select Test:", choices = c("Shapiro-Wilk (Normality)", "Box's M (Equal Covariance)")),
        conditionalPanel(
          condition = "input.stat_test_type == 'Shapiro-Wilk (Normality)'", ns = ns,
          selectInput(ns("stat_shapiro_var"), "Numeric Variable:", choices = NULL),
          selectInput(ns("stat_shapiro_group"), "Group Level:", choices = NULL)
        ),
        conditionalPanel(
          condition = "input.stat_test_type == 'Box\\'s M (Equal Covariance)'", ns = ns,
          selectInput(ns("stat_boxm_vars"), "Variables to Include:", choices = NULL, multiple = TRUE)
        )
      )
    ),

    conditionalPanel(
      condition = "input.main_mode == '2. Run Model'", ns = ns,
      selectInput(ns("method_type"), "Discriminant Method:",
        choices = c("LDA (Linear)" = "LDA", "Weighted LDA" = "WLDA", "QDA (Quadratic)" = "QDA",
                    "Regularized LDA (rda)" = "RLDA", "Kernel DA (SVM-RBF)" = "KDA", "Locally Linear DA" = "LLDA",
                    "Maximum Margin (Linear SVM)" = "MMC"),
        selected = "LDA"),
      markdown("**Formula Editor**\n*Type freely or use the builder buttons below.*"),
      textAreaInput(ns("lda_formula_text"), "Predictors (X):", value = "", rows = 3, placeholder = "e.g., Sepal.Length + Sepal.Width"),
      div(style = "background-color: #f8f9fa; padding: 10px; border-radius: 5px; border: 1px solid #dee2e6;",
          markdown("**Quick Builder**"),
          selectInput(ns("lda_build_var"), "Select Variable:", choices = NULL),
          fluidRow(
            column(6, actionButton(ns("lda_btn_add_var"), "Insert", class = "btn-primary btn-sm", width = "100%", style = "margin-bottom:5px;")),
            column(6, actionButton(ns("lda_btn_add_plus"), " + ", class = "btn-secondary btn-sm", width = "100%", style = "margin-bottom:5px;"))
          ),
          actionButton(ns("lda_btn_clear"), "Clear Formula", class = "btn-outline-danger btn-sm", width = "100%")
      ),
      hr(),
      conditionalPanel(
        condition = "input.method_type == 'WLDA'", ns = ns,
        markdown("**Weighted LDA Parameters**"),
        selectInput(ns("wlda_weight_type"), "Weighting Scheme:", choices = c("Inverse Frequency (1/N)" = "inverse", "Proportional (N)" = "proportional", "Equal Weights" = "equal"), selected = "inverse")
      ),
      conditionalPanel(
        condition = "input.method_type == 'KDA'", ns = ns,
        markdown("**Kernel DA Parameters**"),
        numericInput(ns("kda_sigma"), "Sigma (RBF width):", value = 0.01, min = 0.001, max = 10, step = 0.01),
        numericInput(ns("kda_C"), "Cost (C):", value = 0.1, min = 0.01, max = 100, step = 0.1)
      ),
      conditionalPanel(
        condition = "input.method_type == 'LLDA'", ns = ns,
        markdown("**Locally Linear DA Parameters**"),
        sliderInput(ns("llda_k"), "Number of Neighbors (k):", min = 3, max = 30, value = 5, step = 1)
      ),
      conditionalPanel(
        condition = "input.method_type == 'MMC'", ns = ns,
        markdown("**Maximum Margin Parameters**"),
        numericInput(ns("mmc_C"), "Cost (C):", value = 1, min = 0.01, max = 100, step = 0.1)
      ),
      hr(),
      selectInput(ns("lda_selected_plots"), "Select Diagnostics to View:",
        choices = c("Scatter + Regions", "Class Density", "LD Scatter/Density", "Stacked Histogram",
                    "Biplot (ggord)", "Pairs Plot", "Partition Plot (partimat)", "Variable Importance"),
        selected = c("Scatter + Regions", "Class Density"), multiple = TRUE),
      hr(),
      .cv_ui(ns),
      hr(style = "margin:10px 0;"),
      actionButton(ns("run_model"), "Run Model",
        class = "btn-success w-100", icon = icon("play"))
    )
  )
}

daCanvasUI <- function(id) {
  ns <- NS(id)
  uiOutput(ns("dynamic_content"))
}

daServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset()
      if (is.null(ds)) return(NULL)
      dataset_pool[[ds]]
    })

    # ---- Populate selectors ----
    observe({
      df <- active_data()
      req(df)
      num_cols <- names(df)[sapply(df, is.numeric)]
      cat_cols <- names(df)[sapply(df, is_safe_cat)]
      all_cols <- names(df)
      curr_cat <- if (isTruthy(isolate(input$category)) && isolate(input$category) %in% cat_cols) isolate(input$category) else if (length(cat_cols) > 0) cat_cols[1] else NULL
      updateSelectInput(session, "category", choices = cat_cols, selected = curr_cat)
      n1 <- if (length(num_cols) > 0) num_cols[1] else NULL
      n2 <- if (length(num_cols) > 1) num_cols[2] else n1
      updateSelectInput(session, "ellipses_x", choices = num_cols, selected = n1)
      updateSelectInput(session, "ellipses_y", choices = num_cols, selected = n2)
      updateSelectInput(session, "box_y", choices = num_cols, selected = n1)
      updateSelectInput(session, "norm_var", choices = num_cols, selected = n1)
      updateSelectInput(session, "stat_shapiro_var", choices = num_cols, selected = n1)
      if (isTruthy(curr_cat) && curr_cat %in% names(df)) {
        grp_levels <- unique(as.character(na.omit(df[[curr_cat]])))
        curr_grp <- if (isTruthy(isolate(input$stat_shapiro_group)) && isolate(input$stat_shapiro_group) %in% grp_levels) isolate(input$stat_shapiro_group) else grp_levels[1]
        updateSelectInput(session, "stat_shapiro_group", choices = grp_levels, selected = curr_grp)
      }
      curr_boxm <- if (isTruthy(isolate(input$stat_boxm_vars)) && all(isolate(input$stat_boxm_vars) %in% num_cols)) isolate(input$stat_boxm_vars) else if (length(num_cols) >= 2) num_cols[1:2] else num_cols
      updateSelectInput(session, "stat_boxm_vars", choices = num_cols, selected = curr_boxm)
      curr_build <- if (isTruthy(isolate(input$lda_build_var)) && isolate(input$lda_build_var) %in% all_cols) isolate(input$lda_build_var) else all_cols[1]
      updateSelectInput(session, "lda_build_var", choices = all_cols, selected = curr_build)
    })

    # ---- Formula builder ----
    observeEvent(input$lda_btn_add_var, {
      var <- paste0("`", input$lda_build_var, "`")
      current <- trimws(input$lda_formula_text)
      updateTextAreaInput(session, "lda_formula_text", value = if (nchar(current) > 0) paste(current, var) else var)
    })
    observeEvent(input$lda_btn_add_plus, { current <- trimws(input$lda_formula_text); if (nchar(current) > 0) updateTextAreaInput(session, "lda_formula_text", value = paste(current, "+ ")) })
    observeEvent(input$lda_btn_clear, { updateTextAreaInput(session, "lda_formula_text", value = "") })

    lda_formula_str <- reactive({
      if (!isTruthy(input$category)) return("Y ~ ...")
      safe_y <- paste0("`", input$category, "`")
      x_side <- trimws(input$lda_formula_text)
      if (nchar(x_side) == 0) return(paste(safe_y, "~ ..."))
      paste(safe_y, "~", x_side)
    })

    # ---- Model fitting (9 methods) ----
    # Button-triggered: DA fits (esp. KDA/LLDA/MMC) are expensive and run on the
    # user's own machine in the browser build (UX rule #14).
    model_obj <- eventReactive(input$run_model, ignoreNULL = FALSE, {
      req(active_dataset(), input$category)
      df <- active_data()
      form_str <- lda_formula_str()
      if (grepl("\\.\\.\\.", form_str)) return("Awaiting Predictors: Please build a formula.")
      all_vars <- all.vars(as.formula(form_str))
      missing_vars <- setdiff(all_vars, names(df))
      if (length(missing_vars) > 0) return(paste("Error: Variables not found:", paste(missing_vars, collapse = ", ")))
      clean_df <- df[, all_vars, drop = FALSE]
      clean_df <- clean_df[complete.cases(clean_df), , drop = FALSE]
      if (nrow(clean_df) < 10) return("Data Error: Insufficient complete cases.")
      clean_df[[input$category]] <- as.factor(clean_df[[input$category]])
      clean_df[[input$category]] <- droplevels(clean_df[[input$category]])
      if (length(unique(clean_df[[input$category]])) < 2) return("Data Error: Target requires >= 2 distinct levels.")
      method <- if (isTruthy(input$method_type)) input$method_type else "LDA"
      predictors <- all_vars[-1]
      # Rare-class guard: drop classes with too few rows (mirrors simple.R data_filtered step).
      # QDA needs p+2 per class; LDA/RLDA/WLDA need >=2; LLDA needs k+1.
      num_pred_cols <- sum(sapply(clean_df[, predictors, drop = FALSE], is.numeric))
      min_n <- switch(method,
        "QDA"  = max(num_pred_cols + 2L, 3L),
        "LLDA" = {k <- if (isTruthy(input$llda_k)) input$llda_k else 5L; k + 1L},
        2L)
      cls_counts  <- table(clean_df[[input$category]])
      rare_cls    <- names(cls_counts[cls_counts < min_n])
      if (length(rare_cls) > 0) {
        clean_df <- clean_df[!clean_df[[input$category]] %in% rare_cls, , drop = FALSE]
        clean_df[[input$category]] <- droplevels(clean_df[[input$category]])
        showNotification(
          paste0("Auto-dropped ", length(rare_cls), " class(es) with too few rows for ", method,
                 " (need >= ", min_n, "): ", paste(rare_cls, collapse = ", "),
                 ". Use the Data module to remove or merge them to avoid this."),
          type = "warning", duration = 8)
        if (length(unique(clean_df[[input$category]])) < 2)
          return("Data Error: After dropping rare classes, fewer than 2 classes remain.")
      }
      tryCatch({
        if (method == "LDA") {
          model <- MASS::lda(as.formula(form_str), data = clean_df); preds <- predict(model)
          list(model = model, data = clean_df, preds = preds, pred_class = preds$class, target_var = input$category, predictors = predictors, method_name = "LDA", has_ld = TRUE, ld_scores = as.data.frame(preds$x))
        } else if (method == "WLDA") {
          class_counts <- table(clean_df[[input$category]]); N <- nrow(clean_df)
          weights <- switch(if (isTruthy(input$wlda_weight_type)) input$wlda_weight_type else "inverse",
                            "inverse" = as.numeric(1 / class_counts[clean_df[[input$category]]]),
                            "proportional" = as.numeric(class_counts[clean_df[[input$category]]] / N),
                            rep(1, N))
          model <- MASS::lda(as.formula(form_str), data = clean_df, weights = weights); preds <- predict(model)
          list(model = model, data = clean_df, preds = preds, pred_class = preds$class, target_var = input$category, predictors = predictors, method_name = "Weighted LDA", has_ld = TRUE, ld_scores = as.data.frame(preds$x))
        } else if (method == "QDA") {
          model <- MASS::qda(as.formula(form_str), data = clean_df); preds <- predict(model)
          list(model = model, data = clean_df, preds = preds, pred_class = preds$class, target_var = input$category, predictors = predictors, method_name = "QDA", has_ld = FALSE, ld_scores = NULL)
        } else if (method == "RLDA") {
          if (!requireNamespace("klaR", quietly = TRUE)) return("Package 'klaR' required. Install with: install.packages('klaR')")
          model <- klaR::rda(as.formula(form_str), data = clean_df, gamma = seq(0, 1, 0.1), lambda = seq(0, 1, 0.1)); preds <- predict(model)
          list(model = model, data = clean_df, preds = preds, pred_class = preds$class, target_var = input$category, predictors = predictors, method_name = "Regularized LDA", has_ld = FALSE, ld_scores = NULL)
        } else if (method == "KDA") {
          if (!requireNamespace("kernlab", quietly = TRUE)) return("Package 'kernlab' required. Install with: install.packages('kernlab')")
          sigma_val <- if (isTruthy(input$kda_sigma)) input$kda_sigma else 0.01
          C_val <- if (isTruthy(input$kda_C)) input$kda_C else 0.1
          model <- kernlab::ksvm(as.formula(form_str), data = clean_df, kernel = "rbfdot", kpar = list(sigma = sigma_val), C = C_val, prob.model = TRUE)
          pred_class <- kernlab::predict(model, clean_df)
          list(model = model, data = clean_df, preds = NULL, pred_class = pred_class, target_var = input$category, predictors = predictors, method_name = "Kernel DA (SVM-RBF)", has_ld = FALSE, ld_scores = NULL)
        } else if (method == "LLDA") {
          if (!requireNamespace("klaR", quietly = TRUE)) return("Package 'klaR' required. Install with: install.packages('klaR')")
          k_val <- if (isTruthy(input$llda_k)) input$llda_k else 5
          clean_df_j <- clean_df
          for (p in predictors) if (is.numeric(clean_df_j[[p]])) clean_df_j[[p]] <- jitter(clean_df_j[[p]], amount = 0.0001)
          num_p <- predictors[sapply(clean_df_j[, predictors, drop = FALSE], is.numeric)]
          cat_p <- setdiff(predictors, num_p)
          # loclda inverts a LOCAL covariance; with >1 collinear predictor that is
          # singular ("dgesv: exactly singular"). On failure, decorrelate the numeric
          # predictors via PCA (orthogonal, so never collinear) and refit on the PCs.
          model <- tryCatch(klaR::loclda(as.formula(form_str), data = clean_df_j, k = k_val),
                            error = function(e) e)
          llda_pca <- FALSE
          if (inherits(model, "error")) {
            if (length(num_p) < 2) stop(model)          # not a collinearity case -> friendly handler
            pc   <- prcomp(clean_df_j[, num_p, drop = FALSE], center = TRUE, scale. = TRUE)
            keep <- which(pc$sdev > 1e-4 * pc$sdev[1])  # drop near-zero-variance directions
            pcs  <- as.data.frame(pc$x[, keep, drop = FALSE]); names(pcs) <- paste0("PC", seq_along(keep))
            dat2 <- cbind(pcs, clean_df_j[, c(input$category, cat_p), drop = FALSE])
            form2 <- paste0("`", input$category, "` ~ ",
                            paste(c(names(pcs), sprintf("`%s`", cat_p)), collapse = " + "))
            model <- klaR::loclda(as.formula(form2), data = dat2, k = k_val)  # may re-raise -> handler
            preds <- predict(model, dat2); llda_pca <- TRUE
          } else {
            preds <- predict(model)
          }
          list(model = model, data = clean_df, preds = preds, pred_class = preds$class, target_var = input$category, predictors = predictors,
               method_name = if (llda_pca) "Locally Linear DA (PCA-decorrelated)" else "Locally Linear DA", has_ld = FALSE, ld_scores = NULL)
        } else if (method == "MMC") {
          if (!requireNamespace("kernlab", quietly = TRUE)) return("Package 'kernlab' required. Install with: install.packages('kernlab')")
          C_val <- if (isTruthy(input$mmc_C)) input$mmc_C else 1
          model <- kernlab::ksvm(as.formula(form_str), data = clean_df, kernel = "vanilladot", C = C_val)
          pred_class <- kernlab::predict(model, clean_df)
          list(model = model, data = clean_df, preds = NULL, pred_class = pred_class, target_var = input$category, predictors = predictors, method_name = "Maximum Margin (Linear SVM)", has_ld = FALSE, ld_scores = NULL)
        } else return("Unknown method selected.")
      }, error = function(e) {
        msg <- e$message
        if (grepl("singular|dgesv|collinear|rank", msg, ignore.case = TRUE)) {
          return(paste0("Model could not be fit: the predictors are collinear / a class has too few samples ",
                        "(matrix is singular). Try: fewer or less-correlated predictors, more data per class, ",
                        "or a method that tolerates this (e.g. Regularized LDA).\n\n[", msg, "]"))
        }
        paste("Model Error:", msg)
      })
    })

    # ---- Assumption-check plots ----
    da_plot_ellipses_fn <- function() {
      if (is.null(active_data())) return(show_placeholder("Awaiting dataset..."))
      if (!isTruthy(input$category) || !isTruthy(input$ellipses_x) || !isTruthy(input$ellipses_y)) return(show_placeholder("Awaiting Variable Selection..."))
      df <- active_data()
      df <- df[complete.cases(df[, c(input$ellipses_x, input$ellipses_y, input$category)]), ]
      if (nrow(df) == 0) return(show_placeholder("No valid data"))
      df[[input$category]] <- as.factor(df[[input$category]])
      print(ggplot(df, aes(x = .data[[input$ellipses_x]], y = .data[[input$ellipses_y]], col = .data[[input$category]])) +
              geom_point(size = 2, alpha = 0.7) + stat_ellipse(linewidth = 1) + theme_minimal(base_size = 14) + theme(legend.position = "bottom"))
    }
    da_plot_box_fn <- function() {
      if (is.null(active_data())) return(show_placeholder("Awaiting dataset..."))
      if (!isTruthy(input$category) || !isTruthy(input$box_y)) return(show_placeholder("Awaiting Variable Selection..."))
      df <- active_data()
      df <- df[complete.cases(df[, c(input$box_y, input$category)]), ]
      if (nrow(df) == 0) return(show_placeholder("No valid data"))
      df[[input$category]] <- as.factor(df[[input$category]])
      print(ggplot(df, aes(x = .data[[input$category]], y = .data[[input$box_y]], fill = .data[[input$category]])) +
              geom_boxplot(alpha = 0.5, outlier.size = 2, outlier.colour = "red") + theme_minimal(base_size = 14) + theme(legend.position = "none"))
    }
    da_plot_qq_fn <- function() {
      if (is.null(active_data())) return(show_placeholder("Awaiting dataset..."))
      if (!isTruthy(input$category) || !isTruthy(input$norm_var)) return(show_placeholder("Awaiting Variable Selection..."))
      df <- active_data()
      df <- df[complete.cases(df[, c(input$norm_var, input$category)]), ]
      if (nrow(df) == 0) return(show_placeholder("No valid data"))
      df[[input$category]] <- as.factor(df[[input$category]])
      print(ggplot(df, aes(sample = .data[[input$norm_var]], col = .data[[input$category]])) +
              stat_qq(size = 2, alpha = 0.7) + stat_qq_line(col = "black", linetype = "dashed") +
              facet_wrap(as.formula(paste("~", paste0("`", input$category, "`")))) + theme_minimal(base_size = 14) +
              labs(x = "Theoretical Quantiles", y = "Sample Quantiles") + theme(legend.position = "none"))
    }
    da_plot_density_fn <- function() {
      if (is.null(active_data())) return(show_placeholder("Awaiting dataset..."))
      if (!isTruthy(input$category) || !isTruthy(input$norm_var)) return(show_placeholder("Awaiting Variable Selection..."))
      df <- active_data()
      df <- df[complete.cases(df[, c(input$norm_var, input$category)]), ]
      if (nrow(df) == 0) return(show_placeholder("No valid data"))
      df[[input$category]] <- as.factor(df[[input$category]])
      print(ggplot(df, aes(x = .data[[input$norm_var]], fill = .data[[input$category]], col = .data[[input$category]])) +
              geom_density(alpha = 0.3, linewidth = 1) + theme_minimal(base_size = 14) + labs(y = "Density") + theme(legend.position = "bottom"))
    }

    output$plot_ellipses <- renderPlot({ da_plot_ellipses_fn() })
    output$plot_box <- renderPlot({ da_plot_box_fn() })
    output$plot_qq <- renderPlot({ da_plot_qq_fn() })
    output$plot_density <- renderPlot({ da_plot_density_fn() })

    output$stat_test_results <- renderPrint({
      if (is.null(active_data())) return(cat("Awaiting dataset..."))
      req(input$view == "5. Statistical Tests", input$stat_test_type, input$category)
      df <- active_data()
      if (input$stat_test_type == "Shapiro-Wilk (Normality)") {
        req(input$stat_shapiro_var, input$stat_shapiro_group)
        sub_data <- na.omit(df[[input$stat_shapiro_var]][df[[input$category]] == input$stat_shapiro_group])
        if (length(sub_data) < 3) cat("Error: Not enough data points to run Shapiro-Wilk (requires at least 3).")
        else { cat("=== Shapiro-Wilk Normality Test ===\nVariable:", input$stat_shapiro_var, "\nGroup:", input$stat_shapiro_group, "\n\n"); print(shapiro.test(sub_data)) }
      } else if (input$stat_test_type == "Box's M (Equal Covariance)") {
        req(input$stat_boxm_vars)
        if (length(input$stat_boxm_vars) < 2) cat("Error: Box's M test requires at least 2 numeric variables.")
        else if (!requireNamespace("heplots", quietly = TRUE)) cat("Error: 'heplots' package is required.\nPlease run install.packages('heplots').")
        else {
          cat("=== Box's M-Test for Homogeneity of Covariance Matrices ===\nVariables Included:", paste(input$stat_boxm_vars, collapse = ", "), "\nGrouping Variable:", input$category, "\n\n")
          test_data <- df[complete.cases(df[, c(input$stat_boxm_vars, input$category)]), ]
          print(heplots::boxM(test_data[, input$stat_boxm_vars], test_data[[input$category]]))
        }
      }
    })

    

    # ---- Model diagnostic plots ----
    plot_lda_single <- function(m, plot_name) {
      if (is.character(m)) { show_placeholder(m); return() }
      if (plot_name == "Pairs Plot") {
        old_par <- par(mar = c(2, 2, 2, 2)); on.exit(par(old_par))
        num_preds <- m$predictors[sapply(m$data[, m$predictors, drop = FALSE], is.numeric)]
        if (length(num_preds) < 2) { show_placeholder("Need at least 2 numeric predictors for pairs plot."); return() }
        pairs(m$data[, num_preds, drop = FALSE], main = ea_main(paste("Pairs Plot -", m$method_name)), col = as.numeric(m$data[[m$target_var]]), pch = 16)
      } else if (plot_name == "Stacked Histogram") {
        if (isTRUE(m$has_ld) && !is.null(m$ld_scores) && ncol(m$ld_scores) >= 1) {
          df_plot <- data.frame(Class = m$data[[m$target_var]], LD1 = m$ld_scores[, 1])
          print(ggplot(df_plot, aes(x = LD1, fill = Class)) + geom_histogram(color = "darkgray", bins = 30, alpha = 0.8) +
                  facet_wrap(~ Class, ncol = 1, scales = "free_y") + theme_minimal(base_size = 14) +
                  labs(title = paste("Stacked Histogram of LD1 Scores -", m$method_name), x = "LD1 Score", y = "Count") +
                  theme(legend.position = "none", strip.background = element_rect(fill = "#e9ecef", color = NA), strip.text = element_text(face = "bold", size = 12), panel.spacing = unit(1, "lines")))
        } else {
          # No LD scores (LLDA, KDA, QDA, etc.): histogram of predictor(s) by actual class
          num_preds <- m$predictors[sapply(m$data[, m$predictors, drop = FALSE], is.numeric)]
          if (length(num_preds) == 0) { show_placeholder("No numeric predictors for histogram."); return() }
          px <- num_preds[1]
          df_plot <- data.frame(x = m$data[[px]], Class = as.factor(m$data[[m$target_var]]),
                                Predicted = as.factor(m$pred_class))
          print(
            ggplot(df_plot, aes(x = x, fill = Class)) +
              geom_histogram(color = "darkgray", bins = 30, alpha = 0.8) +
              facet_wrap(~ Class, ncol = 1, scales = "free_y") +
              labs(title = paste("Histogram of", px, "by Class —", m$method_name),
                   x = px, y = "Count") +
              theme_minimal(base_size = 14) +
              theme(legend.position = "none",
                    strip.background = element_rect(fill = "#e9ecef", color = NA),
                    strip.text = element_text(face = "bold", size = 12),
                    panel.spacing = unit(1, "lines"))
          )
        }
      } else if (plot_name == "Biplot (ggord)") {
        if (!isTRUE(m$has_ld)) { show_placeholder(paste("Biplot not available for", m$method_name, ". Only for LDA/Weighted LDA.")); return() }
        if (requireNamespace("ggord", quietly = TRUE)) tryCatch(print(ggord::ggord(m$model)), error = function(e) show_placeholder(paste("ggord error:", e$message)))
        else show_placeholder("Please install 'ggord' from GitHub: remotes::install_github('fawda123/ggord')")
      } else if (plot_name == "Partition Plot (partimat)") {
        if (requireNamespace("klaR", quietly = TRUE)) tryCatch({
          num_preds <- m$predictors[sapply(m$data[, m$predictors, drop = FALSE], is.numeric)]
          if (length(num_preds) < 2) { show_placeholder("Need at least 2 numeric predictors."); return() }
          vars <- if (length(num_preds) > 4) num_preds[1:4] else num_preds
          form <- as.formula(paste(paste0("`", m$target_var, "`"), "~", paste(paste0("`", vars, "`"), collapse = "+")))
          klaR::partimat(form, data = m$data, method = "lda")
        }, error = function(e) show_placeholder(paste("partimat error:", e$message)))
        else show_placeholder("Please install 'klaR' package to view Partition Plots.")
      } else if (plot_name == "LD Scatter/Density") {
        if (isTRUE(m$has_ld) && !is.null(m$ld_scores)) {
          df_plot <- cbind(data.frame(Class = m$data[[m$target_var]]), m$ld_scores)
          if (ncol(m$ld_scores) == 1) print(ggplot(df_plot, aes(x = LD1, fill = Class)) + geom_density(alpha = 0.5) + theme_minimal(base_size = 14) + labs(title = paste("Score Density (LD1) -", m$method_name)))
          else print(ggplot(df_plot, aes(x = LD1, y = LD2, color = Class)) + geom_point(size = 3, alpha = 0.8) + stat_ellipse() + theme_minimal(base_size = 14) + labs(title = paste("Scatter (LD1 vs LD2) -", m$method_name)))
        } else {
          num_preds <- m$predictors[sapply(m$data[, m$predictors, drop = FALSE], is.numeric)]
          if (length(num_preds) < 2) {
            show_placeholder("For 1 predictor, use 'Decision Regions', 'Class Lanes', or 'Class Density'.")
            return()
          }
          pca_res <- prcomp(scale(m$data[, num_preds, drop = FALSE]), center = FALSE, scale. = FALSE)
          df_plot <- data.frame(PC1 = pca_res$x[, 1], PC2 = pca_res$x[, min(2, ncol(pca_res$x))],
                                Predicted = as.factor(m$pred_class), Actual = m$data[[m$target_var]])
          print(ggplot(df_plot, aes(x = PC1, y = PC2, color = Predicted, shape = Actual)) +
                  geom_point(size = 3, alpha = 0.8) +
                  stat_ellipse(aes(group = Predicted), linetype = "dashed") +
                  theme_minimal(base_size = 14) +
                  labs(title = paste("PCA Projection —", m$method_name), x = "PC1", y = "PC2"))
        }
      } else if (plot_name %in% c("Scatter + Regions", "Decision Regions", "Class Lanes", "Class Density")) {
        num_preds <- m$predictors[sapply(m$data[, m$predictors, drop = FALSE], is.numeric)]
        if (length(num_preds) == 0) { show_placeholder("No numeric predictors."); return() }
        # These 1-D decision plots need a single axis. With >1 predictor there's no
        # single axis, so fall back to the PCA/LD 2-D projection instead of erroring.
        if (length(num_preds) > 1)  { plot_lda_single(m, "LD Scatter/Density"); return() }
        px      <- num_preds[1]
        grid_x  <- seq(min(m$data[[px]], na.rm = TRUE) - 0.5,
                        max(m$data[[px]], na.rm = TRUE) + 0.5, length.out = 500)
        grid_df <- setNames(data.frame(grid_x), px)
        for (.p in m$predictors) {
          if (.p == px) next
          .col <- m$data[[.p]]
          if (is.numeric(.col)) {
            grid_df[[.p]] <- median(.col, na.rm = TRUE)
          } else {
            .mode <- names(sort(table(.col), decreasing = TRUE))[1]
            grid_df[[.p]] <- if (is.factor(.col)) factor(.mode, levels = levels(.col)) else .mode
          }
        }
        grid_pred <- tryCatch({
          mn <- m$method_name
          if (mn %in% c("Kernel DA (SVM-RBF)", "Maximum Margin (Linear SVM)"))
            as.character(kernlab::predict(m$model, newdata = grid_df))
          else
            as.character(predict(m$model, newdata = grid_df)$class)
        }, error = function(e) NULL)
        if (is.null(grid_pred)) { show_placeholder("Could not compute decision regions."); return() }
        # Boundary x positions
        rle_p     <- rle(grid_pred)
        bnd_x     <- grid_x[cumsum(rle_p$lengths)[-length(rle_p$lengths)]]
        grid_data <- data.frame(x = grid_x, Predicted = as.factor(grid_pred))
        df_pts    <- data.frame(x = m$data[[px]], Actual = as.factor(m$data[[m$target_var]]))
        # Shared manual color palette keyed by class name (covers both Predicted and Actual)
        all_cls      <- union(levels(df_pts$Actual), unique(grid_pred))
        pal_hex      <- viridisLite::viridis(length(all_cls), option = "D")
        class_colors <- setNames(pal_hex, all_cls)

        if (plot_name == "Scatter + Regions") {
          shapes_vec <- setNames(
            c(16, 17, 15, 18, 8, 3, 4)[seq_along(levels(df_pts$Actual))],
            levels(df_pts$Actual))
          p <- ggplot() +
            geom_tile(data = grid_data,
                      aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
            geom_jitter(data = df_pts,
                        aes(x = x, y = 0, color = Actual, shape = Actual),
                        height = 0.3, size = 2.5, alpha = 0.75) +
            scale_fill_manual(values = class_colors, name = "Predicted") +
            scale_color_manual(values = class_colors, name = "Actual") +
            scale_shape_manual(values = shapes_vec, name = "Actual") +
            theme_minimal(base_size = 14) +
            theme(axis.text.y = element_blank(), axis.title.y = element_blank(),
                  axis.ticks.y = element_blank(),
                  panel.grid.major.y = element_blank(), panel.grid.minor.y = element_blank(),
                  legend.position = "bottom") +
            labs(title    = paste(m$method_name, "— Decision Regions"),
                 subtitle = "Background = predicted class  |  Points = actual class (shape + colour)",
                 x = px)
          if (length(bnd_x) > 0)
            p <- p + geom_vline(xintercept = bnd_x, linetype = "dashed",
                                color = "black", linewidth = 0.8)
          print(p)

        } else if (plot_name == "Decision Regions") {
          # Option A: background regions + explicit boundaries + rug (your original style)
          p <- ggplot() +
            geom_tile(data = grid_data, aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
            geom_rug(data = df_pts, aes(x = x, color = Actual),
                     sides = "b", length = unit(0.1, "npc"), linewidth = 0.5) +
            scale_fill_manual(values = class_colors, name = paste(m$method_name, "Prediction")) +
            scale_color_manual(values = class_colors, name = "Actual Data") +
            theme_minimal(base_size = 14) +
            theme(axis.text.y = element_blank(), axis.title.y = element_blank(),
                  axis.ticks.y = element_blank(),
                  panel.grid.major.y = element_blank(), panel.grid.minor.y = element_blank()) +
            labs(title    = paste(m$method_name, "— Decision Regions"),
                 subtitle = "Background = predicted class  |  Rug ticks = actual class",
                 x = px)
          if (length(bnd_x) > 0)
            p <- p + geom_vline(xintercept = bnd_x, linetype = "dashed",
                                color = "black", linewidth = 0.8)
          print(p)

        } else if (plot_name == "Class Lanes") {
          # Option B: each actual class in its own horizontal lane
          lvls     <- levels(df_pts$Actual)
          n_cls    <- length(lvls)
          mid_y    <- (n_cls + 1) / 2
          df_lanes <- data.frame(x      = m$data[[px]],
                                 Actual = as.factor(m$data[[m$target_var]]),
                                 lane_y = as.numeric(as.factor(m$data[[m$target_var]])))
          print(
            ggplot() +
              geom_tile(data = grid_data,
                        aes(x = x, y = mid_y, height = n_cls + 0.5, fill = Predicted), alpha = 0.2) +
              geom_point(data = df_lanes,
                         aes(x = x, y = lane_y, color = Actual),
                         size = 2, alpha = 0.8, shape = 16) +
              scale_fill_manual(values = class_colors, name = paste(m$method_name, "Prediction")) +
              scale_color_manual(values = class_colors, name = "Actual Class") +
              scale_y_continuous(breaks = seq_along(lvls), labels = lvls,
                                 limits = c(0.5, n_cls + 0.5)) +
              theme_minimal(base_size = 14) +
              theme(panel.grid.minor.y = element_blank()) +
              labs(title    = paste(m$method_name, "— Class Lanes"),
                   subtitle = "Background = predicted region  |  Each row = one actual class",
                   x = px, y = "Actual Class")
          )

        } else {
          # Class Density: density curves only, no background
          print(
            ggplot(df_pts, aes(x = x, fill = Actual, color = Actual)) +
              geom_density(alpha = 0.5, linewidth = 0.8) +
              scale_fill_manual(values = class_colors) +
              scale_color_manual(values = class_colors) +
              theme_minimal(base_size = 14) +
              theme(legend.position = "bottom") +
              labs(title = paste(m$method_name, "— Class Density"),
                   x = px, y = "Density")
          )
        }

      } else if (plot_name == "Variable Importance") {
        if (isTRUE(m$has_importance) && m$method_name == "Random Forest") {
          old_par <- par(mar = c(4, 8, 3, 2)); on.exit(par(old_par)); randomForest::varImpPlot(m$model, main = "Variable Importance (Random Forest)")
        } else if (isTRUE(m$has_ld)) {
          scaling <- m$model$scaling
          df_imp <- data.frame(Variable = rownames(scaling), Importance = abs(scaling[, 1]))
          df_imp <- df_imp[order(df_imp$Importance, decreasing = TRUE), ]
          print(ggplot(df_imp, aes(x = reorder(Variable, Importance), y = Importance)) + geom_bar(stat = "identity", fill = "steelblue") + coord_flip() + theme_minimal(base_size = 14) + labs(title = paste("Variable Importance -", m$method_name), x = "", y = "|LD1 Loading|"))
        } else show_placeholder(paste("Variable importance not available for", m$method_name))
      }
    }

    output$lda_formula_display <- renderText({ lda_formula_str() })

    output$lda_summary <- renderPrint({
      res <- model_obj()
      if (is.character(res)) cat(res)
      else {
        cat("Method:", res$method_name, "\n\n")
        tryCatch({
          if (res$method_name %in% c("LDA", "Weighted LDA", "QDA")) { print(res$model$call); cat("\n"); print(res$model) }
          else if (res$method_name == "Neural Network") print(summary(res$model))
          else print(res$model)
        }, error = function(e) cat("Summary not available:", e$message))
      }
    })

    output$conf_plot_da <- renderPlot({
      res <- model_obj()
      if (is.character(res)) { show_placeholder("Awaiting valid model..."); return() }
      cm <- table(Predicted = res$pred_class, Actual = res$data[[input$category]])
      print(.plot_conf_matrix(cm, title = paste(res$method_name, "— Training Confusion Matrix")))
    })

    output$lda_accuracy <- renderPrint({
      res <- model_obj()
      if (is.character(res)) return(invisible(NULL))
      pred    <- as.character(res$pred_class)
      actual  <- as.character(res$data[[input$category]])
      acc     <- mean(pred == actual) * 100
      classes <- levels(as.factor(actual))
      cat(sprintf("Training Accuracy: %.2f%%\n\nClass breakdown:\n", acc))
      for (cls in classes) {
        n_act <- sum(actual == cls)
        n_cor <- sum(pred == cls & actual == cls)
        pct   <- if (n_act > 0) round(100 * n_cor / n_act) else 0
        cat(sprintf("  %-28s  n=%-5d  correct=%-5d  (%d%%)\n", cls, n_act, n_cor, pct))
      }
    })

    output$val_acc_da <- renderPrint({
      cv <- da_cv_result_r()
      if (is.null(cv)) return(invisible(NULL))
      pred    <- as.character(cv$predicted)
      actual  <- as.character(cv$actual)
      keep    <- !is.na(pred) & !is.na(actual)
      pred    <- pred[keep]; actual <- actual[keep]
      acc     <- mean(pred == actual) * 100
      classes <- sort(unique(actual))
      cat(sprintf("%s Accuracy: %.2f%%\n\nClass breakdown:\n", cv$lbl, acc))
      for (cls in classes) {
        n_act <- sum(actual == cls)
        n_cor <- sum(pred == cls & actual == cls)
        pct   <- if (n_act > 0) round(100 * n_cor / n_act) else 0
        cat(sprintf("  %-28s  n=%-5d  correct=%-5d  (%d%%)\n", cls, n_act, n_cor, pct))
      }
    })

    da_cv_result_r <- reactive({
      res <- model_obj()
      if (is.character(res) || is.null(res)) return(NULL)
      tryCatch({
        mn   <- res$method_name
        data <- res$data; tv <- res$target_var; pvars <- res$predictors
        fml  <- as.formula(paste(paste0("`", tv, "`"), "~",
                                 paste(paste0("`", pvars, "`"), collapse = "+")))
        if (mn %in% c("LDA", "Weighted LDA")) {
          loo <- MASS::lda(fml, data = data, CV = TRUE)
          list(actual    = as.character(data[[tv]]),
               predicted = as.character(loo$class),
               lbl       = "LOOCV")
        } else {
          n <- nrow(data); k <- .cv_k(input, data); lbl <- .cv_label(k, n)
          set.seed(42); folds <- sample(rep_len(seq_len(k), n))
          all_p <- c(); all_a <- c()
          for (fold in seq_len(k)) {
            tr <- data[folds != fold, , drop = FALSE]
            te <- data[folds == fold, , drop = FALSE]
            m <- tryCatch({
              if (mn == "QDA")
                MASS::qda(fml, data = tr)
              else if (mn == "Regularized LDA" && requireNamespace("klaR", quietly = TRUE))
                klaR::rda(fml, data = tr, gamma = seq(0,1,0.1), lambda = seq(0,1,0.1))
              else if (mn %in% c("Kernel DA (SVM-RBF)", "Maximum Margin (Linear SVM)") &&
                       requireNamespace("kernlab", quietly = TRUE))
                kernlab::ksvm(fml, data = tr,
                              kernel = if (mn == "Kernel DA (SVM-RBF)") "rbfdot" else "vanilladot")
              else if (mn == "Locally Linear DA" && requireNamespace("klaR", quietly = TRUE)) {
                tr_j <- tr
                for (p in pvars) if (is.numeric(tr_j[[p]])) tr_j[[p]] <- jitter(tr_j[[p]], amount = 0.0001)
                klaR::loclda(fml, data = tr_j, k = 5)
              }
              else MASS::lda(fml, data = tr)
            }, error = function(e) NULL)
            if (is.null(m)) next
            p <- tryCatch({
              if (mn %in% c("Kernel DA (SVM-RBF)", "Maximum Margin (Linear SVM)"))
                as.character(kernlab::predict(m, newdata = te))
              else
                as.character(predict(m, newdata = te)$class)
            }, error = function(e) NULL)
            if (is.null(p)) next
            all_p <- c(all_p, p)
            all_a <- c(all_a, as.character(te[[tv]]))
          }
          if (length(all_p) == 0) return(NULL)
          list(actual = all_a, predicted = all_p, lbl = lbl)
        }
      }, error = function(e) NULL)
    })

    output$prf_loocv_dt <- renderDT({
      res <- model_obj()
      if (is.character(res) || is.null(res))
        return(DT::datatable(data.frame(Message = "Awaiting model.")))
      tryCatch({
        train_prf <- .clf_prf(as.character(res$data[[res$target_var]]),
                              as.character(res$pred_class))
        train_acc <- mean(as.character(res$pred_class) ==
                          as.character(res$data[[res$target_var]]), na.rm = TRUE)
        cv <- da_cv_result_r()
        if (!is.null(cv)) {
          cv_prf <- .clf_prf(cv$actual, cv$predicted)
          cv_acc <- mean(cv$predicted == cv$actual, na.rm = TRUE)
          prf_list <- setNames(list(train_prf, cv_prf), c("Training", cv$lbl))
          acc_list <- setNames(list(train_acc, cv_acc), c("Training", cv$lbl))
        } else {
          prf_list <- list(Training = train_prf)
          acc_list <- list(Training = train_acc)
        }
        .prf_dt(prf_list, acc_list)
      }, error = function(e) DT::datatable(data.frame(Error = e$message)))
    })

    output$val_conf_plot_da <- renderPlot({
      cv <- da_cv_result_r()
      if (is.null(cv)) { show_placeholder("Awaiting CV results..."); return() }
      cm <- table(Predicted = cv$predicted, Actual = cv$actual)
      print(.plot_conf_matrix(cm, title = paste(cv$lbl, "— Validation Confusion Matrix")))
    })

    output$lda_plot_scatter_regions <- renderPlot({ plot_lda_single(model_obj(), "Scatter + Regions") })
    output$lda_plot_class_density   <- renderPlot({ plot_lda_single(model_obj(), "Class Density") })
    output$lda_plot_pairs    <- renderPlot({ plot_lda_single(model_obj(), "Pairs Plot") })
    output$lda_plot_hist     <- renderPlot({ plot_lda_single(model_obj(), "Stacked Histogram") })
    output$lda_plot_biplot   <- renderPlot({ plot_lda_single(model_obj(), "Biplot (ggord)") })
    output$lda_plot_partimat <- renderPlot({ plot_lda_single(model_obj(), "Partition Plot (partimat)") })
    output$lda_plot_scatter  <- renderPlot({ plot_lda_single(model_obj(), "LD Scatter/Density") })
    output$lda_plot_importance <- renderPlot({ plot_lda_single(model_obj(), "Variable Importance") })

    output$lda_single_selector <- renderUI({
      req(input$lda_selected_plots)
      selectInput(ns("lda_single_plot_choice"), "Select Plot to View:", choices = input$lda_selected_plots, width = "200px")
    })
    output$lda_single_plot <- renderPlot({ req(input$lda_single_plot_choice); plot_lda_single(model_obj(), input$lda_single_plot_choice) })

    output$dynamic_lda_plot_ui <- renderUI({
      req(input$lda_view_mode)
      if (input$lda_view_mode == "Single Plot") {
        plotOutput(ns("lda_single_plot"), height = "500px")
      } else {
        sel <- input$lda_selected_plots
        if (length(sel) == 0) return(markdown("*Please select plots from the sidebar.*"))
        ui_list <- list()
        if ("Scatter + Regions" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_scatter_regions"), height = "450px")))
        if ("Class Density" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_class_density"), height = "450px")))
        if ("Pairs Plot" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_pairs"), height = "450px")))
        if ("Stacked Histogram" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_hist"), height = "450px")))
        if ("Biplot (ggord)" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_biplot"), height = "450px")))
        if ("Partition Plot (partimat)" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_partimat"), height = "450px")))
        if ("LD Scatter/Density" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_scatter"), height = "450px")))
        if ("Variable Importance" %in% sel) ui_list <- append(ui_list, list(plotOutput(ns("lda_plot_importance"), height = "450px")))
        col_count <- ifelse(length(sel) == 1, 12, 6)
        do.call(layout_columns, c(ui_list, list(col_widths = col_count)))
      }
    })

    

    # ---- The dynamic canvas (assumption checks vs run model) ----
    output$dynamic_content <- renderUI({
      mode <- input$main_mode
      if (!isTruthy(mode)) return(div(style = "padding:20px;", h4("Loading analysis modules...", class = "text-muted")))
      if (mode == "1. Assumption Checks") {
        view <- input$view
        if (!isTruthy(view)) return(div(style = "padding:20px;", h4("Loading diagnostic views...", class = "text-muted")))
        make_header <- function(title) card_header(class = "d-flex justify-content-between align-items-center bg-light", title)
        if (view == "1. Covariance Ellipses") card(make_header("Covariance Ellipses"), plotOutput(ns("plot_ellipses"), height = "500px"))
        else if (view == "2. Equal Variance (Boxplots)") card(make_header("Equal Variance Check"), plotOutput(ns("plot_box"), height = "500px"))
        else if (view == "3. Normality (Q-Q Plots)") card(make_header("Multivariate Normality (Q-Q)"), plotOutput(ns("plot_qq"), height = "500px"))
        else if (view == "4. Distribution Density") card(make_header("Density Overlap"), plotOutput(ns("plot_density"), height = "500px"))
        else if (view == "5. Statistical Tests") card(card_header(class = "bg-dark text-white", "Statistical Assumption Checks"), div(style = "padding: 15px; background-color: #f8f9fa; height: 400px; overflow-y: auto;", verbatimTextOutput(ns("stat_test_results"))))
      } else {
        div(
          card(
            card_header(class = "d-flex justify-content-between align-items-center bg-light", "Discriminant Diagnostics",
                        div(class = "d-flex align-items-center gap-2 header-controls",
                            radioGroupButtons(ns("lda_view_mode"), label = NULL, choices = c("Grid View", "Single Plot"), selected = "Grid View", size = "sm", status = "primary"),
                            uiOutput(ns("lda_single_selector")))),
            div(style = "overflow-y: auto; height: 520px; padding: 5px;", uiOutput(ns("dynamic_lda_plot_ui")))
          ),
          layout_columns(
            col_widths = c(6, 6),
            card(
              card_header(class = "bg-light", "Model Summary"),
              div(class = "formula-box", style = "padding: 10px; background-color: #e9ecef; border-bottom: 1px solid #dee2e6;", textOutput(ns("lda_formula_display"))),
              div(style = "overflow-y: auto; height: 300px; padding: 5px;", verbatimTextOutput(ns("lda_summary")))
            ),
            card(
              card_header(class = "bg-light", "Confusion Matrix & Accuracy"),
              div(style = "height: 240px; padding: 5px;", plotOutput(ns("conf_plot_da"), height = "220px")),
              div(style = "padding: 2px 8px;", verbatimTextOutput(ns("lda_accuracy")))
            )
          ),
          layout_columns(
            col_widths = c(6, 6),
            card(
              card_header(class = "bg-light", "Precision / Recall / F1 + Cross-Validation"),
              div(style = "padding: 5px;", DTOutput(ns("prf_loocv_dt")))
            ),
            card(
              card_header(class = "bg-light", "Validation Confusion Matrix"),
              div(style = "height: 240px; padding: 5px;", plotOutput(ns("val_conf_plot_da"), height = "220px")),
              div(style = "padding: 2px 8px;", verbatimTextOutput(ns("val_acc_da")))
            )
          )
        )
      }
    })

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        if (isTruthy(input$main_mode) && input$main_mode == "1. Assumption Checks")
          return(paste0("Discriminant Analysis — assumption checks. View: ", input$view, " ; grouping variable: ", input$category))
        res <- model_obj()
        if (is.character(res)) return(paste("Discriminant Analysis —", res))
        cm <- table(Predicted = res$pred_class, Actual = res$data[[input$category]])
        acc <- mean(as.character(res$pred_class) == as.character(res$data[[input$category]])) * 100
        paste0("Discriminant Analysis. Method: ", res$method_name, " ; Target: ", input$category,
               " ; Accuracy: ", round(acc, 2), "%\n\nConfusion matrix:\n",
               paste(utils::capture.output(cm), collapse = "\n"))
      }),
      plot = function() {
        if (isTruthy(input$main_mode) && input$main_mode == "1. Assumption Checks") {
          switch(input$view,
            "1. Covariance Ellipses" = da_plot_ellipses_fn(),
            "2. Equal Variance (Boxplots)" = da_plot_box_fn(),
            "3. Normality (Q-Q Plots)" = da_plot_qq_fn(),
            "4. Distribution Density" = da_plot_density_fn(),
            show_placeholder("Statistical test view (no plot)."))
        } else {
          sel <- if (length(input$lda_selected_plots)) input$lda_selected_plots[[1]] else "LD Scatter/Density"
          plot_lda_single(model_obj(), sel)
        }
      }
    )
  })
}
