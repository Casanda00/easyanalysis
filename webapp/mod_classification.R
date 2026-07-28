# ==========================================================================
# MODULE: Classification (one-vs-all logistic)  (canvas + tools contract)
# classificationToolsUI / classificationCanvasUI / classificationServer(...)
# Per-class binary glm; F1 / precision / recall; button-triggered.
# ==========================================================================

classificationToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "Classification Setup"),
    div(class = "small text-muted mb-2",
        "Method: one-vs-all binary logistic regression. For each class a separate ",
        tags$code("glm(family = binomial)"), " is fit (that class vs the rest); predictions ",
        "use the decision threshold below, and per-class Accuracy / Precision / Recall / F1 are reported. ",
        tags$em("Differs from the Logistic Regression screen, which fits one multinomial model.")),
    markdown("**1. Target & Predictors**"),
    selectInput(ns("target"), "Target Variable (Categorical):", choices = NULL),
    hr(),
    markdown("**Formula Editor**\n*Type freely or use the builder buttons below.*"),
    textAreaInput(ns("formula_text"), "Predictors (X):", value = "", rows = 3, placeholder = "e.g., ih5_dm + Nutrient_class"),
    div(style = "background-color: #f8f9fa; padding: 10px; border-radius: 5px; border: 1px solid #dee2e6;",
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
    markdown("**2. Classification Settings**"),
    sliderInput(ns("threshold"), "Decision Threshold:", min = 0.1, max = 0.9, value = 0.5, step = 0.05),
    hr(),
    markdown("**3. Exclude Classes (Optional)**"),
    pickerInput(ns("exclude_classes"), "Classes to Exclude:", choices = NULL, multiple = TRUE,
                options = list(`actions-box` = TRUE, `live-search` = TRUE, `none-selected-text` = "None excluded")),
    hr(),
    .cv_ui(ns),
    hr(),
    actionButton(ns("run"), "Run Classification", class = "btn-primary", width = "100%", icon = icon("play"))
  )
}

classificationCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Classification Performance (F1 Score by Class)"),
      div(style = "height: 450px; padding: 10px;", plotOutput(ns("f1_plot"), height = "430px"))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "bg-light", "Per-Class Metrics"),
        div(class = "formula-box", style = "padding: 10px; background-color: #e9ecef; border-bottom: 1px solid #dee2e6;", textOutput(ns("formula_display"))),
        div(style = "padding: 5px;", DTOutput(ns("metrics_dt")))
      ),
      card(
        card_header(class = "bg-light", "Per-Class Confusion (TP / FP / FN / TN)"),
        div(style = "height: 345px; padding: 5px;", plotOutput(ns("conf_plot"), height = "330px"))
      )
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "bg-light", "Cross-Validation (one-vs-all)"),
        div(style = "padding: 5px;", DTOutput(ns("cv_dt")))
      ),
      card(
        card_header(class = "bg-light", "Validation Confusion Matrix"),
        div(style = "height: 310px; padding: 5px;", plotOutput(ns("val_conf_plot"), height = "280px"))
      )
    )
  )
}

classificationServer <- function(id, dataset_pool, active_dataset) {
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
      cat_cols <- names(df)[sapply(df, is_safe_cat)]
      all_cols <- names(df)
      curr_y <- if (isTruthy(isolate(input$target)) && isolate(input$target) %in% cat_cols) isolate(input$target) else if (length(cat_cols) > 0) cat_cols[1] else NULL
      curr_build <- if (isTruthy(isolate(input$build_var)) && isolate(input$build_var) %in% all_cols) isolate(input$build_var) else all_cols[1]
      updateSelectInput(session, "target", choices = cat_cols, selected = curr_y)
      updateSelectInput(session, "build_var", choices = all_cols, selected = curr_build)
    })

    observeEvent(input$target, {
      df <- active_data(); req(df, input$target)
      if (input$target %in% names(df)) {
        classes <- unique(as.character(na.omit(df[[input$target]])))
        updatePickerInput(session, "exclude_classes", choices = classes, selected = character(0))
      }
    })

    observeEvent(input$btn_add_var, {
      var <- paste0("`", input$build_var, "`")
      term <- switch(input$build_trans, "raw" = var, "log" = paste0("log(", var, ")"), "sqrt" = paste0("sqrt(", var, ")"), "poly" = paste0("I(", var, "^2)"))
      current <- trimws(input$formula_text)
      updateTextAreaInput(session, "formula_text", value = if (nchar(current) > 0) paste(current, term) else term)
    })
    observeEvent(input$btn_add_plus, { current <- trimws(input$formula_text); if (nchar(current) > 0) updateTextAreaInput(session, "formula_text", value = paste(current, "+ ")) })
    observeEvent(input$btn_add_star, { current <- trimws(input$formula_text); if (nchar(current) > 0) updateTextAreaInput(session, "formula_text", value = paste(current, "* ")) })
    observeEvent(input$btn_clear, { updateTextAreaInput(session, "formula_text", value = "") })

    formula_str <- reactive({
      x_side <- trimws(input$formula_text)
      if (nchar(x_side) == 0) return("target ~ ...")
      paste("target ~", x_side)
    })

    output$formula_display <- renderText({
      if (!isTruthy(input$target)) return("Awaiting target variable...")
      x_side <- trimws(input$formula_text)
      if (nchar(x_side) == 0) return(paste(input$target, "~ ..."))
      paste(input$target, "~", x_side)
    })

    clf_results <- reactiveVal(NULL)
    clf_confusion <- reactiveVal(NULL)

    observeEvent(input$run, {
      df <- active_data()
      if (is.null(df)) { showNotification("Please upload a dataset first.", type = "warning"); return() }
      req(input$target)
      form_str_template <- formula_str()
      if (grepl("\\.\\.\\.", form_str_template)) { showNotification("Please build a formula with predictor variables first.", type = "warning"); return() }

      threshold <- input$threshold
      exclude <- input$exclude_classes
      data_filtered <- df
      if (length(exclude) > 0) {
        data_filtered <- data_filtered[!data_filtered[[input$target]] %in% exclude, , drop = FALSE]
        data_filtered[[input$target]] <- droplevels(as.factor(data_filtered[[input$target]]))
      }
      classes <- unique(as.character(na.omit(data_filtered[[input$target]])))
      if (length(classes) < 2) { showNotification("Need at least 2 classes after exclusions.", type = "error"); return() }

      all_pred_vars <- tryCatch(all.vars(as.formula(form_str_template))[-1], error = function(e) { showNotification(paste("Formula error:", e$message), type = "error"); NULL })
      if (is.null(all_pred_vars)) return()
      needed_cols <- c(input$target, all_pred_vars)
      missing <- setdiff(needed_cols, names(data_filtered))
      if (length(missing) > 0) { showNotification(paste("Variables not found:", paste(missing, collapse = ", ")), type = "error"); return() }

      clean_df <- data_filtered[, needed_cols, drop = FALSE]
      clean_df <- clean_df[complete.cases(clean_df), , drop = FALSE]
      if (nrow(clean_df) < 10) { showNotification("Insufficient complete cases (< 10).", type = "error"); return() }

      withProgress(message = 'Running Classification...', value = 0, {
        results_list <- list(); confusion_list <- list(); n_classes <- length(classes)
        for (i in seq_along(classes)) {
          cl <- classes[i]
          incProgress(1 / n_classes, detail = paste("Processing class:", cl))
          tryCatch({
            clean_df$target <- ifelse(as.character(clean_df[[input$target]]) == cl, 1, 0)
            model <- glm(as.formula(form_str_template), data = clean_df, family = binomial)
            probs <- predict(model, type = "response")
            preds <- ifelse(probs > threshold, 1, 0)
            TP <- sum(preds == 1 & clean_df$target == 1); TN <- sum(preds == 0 & clean_df$target == 0)
            FP <- sum(preds == 1 & clean_df$target == 0); FN <- sum(preds == 0 & clean_df$target == 1)
            accuracy <- (TP + TN) / (TP + TN + FP + FN)
            precision <- ifelse((TP + FP) == 0, NA, TP / (TP + FP))
            recall <- ifelse((TP + FN) == 0, NA, TP / (TP + FN))
            f1 <- ifelse(is.na(precision) | is.na(recall) | (precision + recall) == 0, NA, 2 * (precision * recall) / (precision + recall))
            results_list[[cl]] <- data.frame(Class = cl, N = sum(clean_df$target == 1), Accuracy = round(accuracy, 4), Precision = round(precision, 4), Recall = round(recall, 4), F1 = round(f1, 4), stringsAsFactors = FALSE)
            confusion_list[[cl]] <- data.frame(Class = cl, TP = TP, TN = TN, FP = FP, FN = FN, stringsAsFactors = FALSE)
          }, error = function(e) {
            results_list[[cl]] <<- data.frame(Class = cl, N = NA, Accuracy = NA, Precision = NA, Recall = NA, F1 = NA, stringsAsFactors = FALSE)
            confusion_list[[cl]] <<- data.frame(Class = cl, TP = NA, TN = NA, FP = NA, FN = NA, stringsAsFactors = FALSE)
          })
        }
        clf_results(do.call(rbind, results_list))
        clf_confusion(do.call(rbind, confusion_list))
      })
      showNotification(paste("Classification complete!", length(classes), "classes evaluated."), type = "message")
    })

    f1_plot_fn <- function() {
      res <- clf_results()
      if (is.null(res)) { show_placeholder("Click 'Run Classification' to begin analysis."); return() }
      print(ggplot(res, aes(x = reorder(Class, -F1), y = F1)) +
              geom_bar(stat = "identity", fill = "steelblue", width = 0.7) +
              geom_text(aes(label = ifelse(is.na(F1), "NA", sprintf("%.3f", F1))), vjust = -0.5, size = 4, fontface = "bold") +
              ylim(0, min(1.15, max(res$F1, na.rm = TRUE) * 1.2)) + theme_minimal(base_size = 14) +
              labs(title = "One-vs-All Classification: F1 Score by Class", x = "Class", y = "F1 Score") +
              theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 12)))
    }

    output$f1_plot <- renderPlot({ f1_plot_fn() })

    output$metrics_dt <- renderDT({
      res <- clf_results()
      if (is.null(res))
        return(DT::datatable(data.frame(Message = "Run Classification first.")))
      df <- res
      for (col in c("Accuracy", "Precision", "Recall", "F1"))
        df[[col]] <- ifelse(is.na(df[[col]]), "—", sprintf("%.3f", df[[col]]))
      DT::datatable(df, rownames = FALSE,
        caption = sprintf("Threshold: %.2f", isolate(input$threshold) %||% 0.5),
        options = list(dom = "t", paging = FALSE, ordering = FALSE, scrollX = FALSE),
        class = "compact stripe") |>
        DT::formatStyle("F1", background = DT::styleColorBar(c(0, 1), "#d1e7dd"),
                        backgroundSize = "98% 88%", backgroundRepeat = "no-repeat",
                        backgroundPosition = "center")
    })

    output$conf_plot <- renderPlot({
      conf <- clf_confusion()
      if (is.null(conf)) { show_placeholder("Awaiting classification results..."); return() }
      df_long <- do.call(rbind, lapply(seq_len(nrow(conf)), function(i) {
        cl <- conf$Class[i]
        data.frame(
          Class   = rep(cl, 4),
          Metric  = c("TP", "FP", "FN", "TN"),
          Count   = c(conf$TP[i], conf$FP[i], conf$FN[i], conf$TN[i]),
          stringsAsFactors = FALSE
        )
      }))
      df_long$Metric <- factor(df_long$Metric, levels = c("TP", "FP", "FN", "TN"))
      fill_map <- c(TP = "#d1e7dd", FP = "#f8d7da", FN = "#fff3cd", TN = "#cfe2ff")
      print(
        ggplot(df_long, aes(x = Metric, y = Count, fill = Metric)) +
          geom_col(show.legend = FALSE) +
          geom_text(aes(label = Count), vjust = -0.3, size = 3.5, fontface = "bold") +
          scale_fill_manual(values = fill_map) +
          facet_wrap(~Class, scales = "free_y") +
          labs(title = "Per-Class Confusion Components", x = NULL, y = "Count") +
          theme_minimal(base_size = 12) +
          theme(panel.grid.major.x = element_blank(),
                strip.text = element_text(face = "bold"))
      )
    })

    clf_cv_result_r <- reactive({
      res <- clf_results(); if (is.null(res)) return(NULL)
      df  <- active_data(); if (is.null(df)) return(NULL)
      tgt     <- input$target;          if (!isTruthy(tgt)) return(NULL)
      fml_str <- formula_str();         if (!isTruthy(fml_str)) return(NULL)
      excl    <- input$exclude_classes %||% character(0)
      tryCatch({
        df_f <- df
        if (length(excl) > 0) df_f <- df_f[!df_f[[tgt]] %in% excl, , drop = FALSE]
        pv <- tryCatch(all.vars(as.formula(fml_str))[-1], error = function(e) NULL)
        if (length(pv) == 0) return(NULL)
        sub  <- df_f[, c(tgt, pv), drop = FALSE]
        sub  <- sub[complete.cases(sub), , drop = FALSE]
        classes <- unique(as.character(sub[[tgt]]))
        if (length(classes) < 2) return(NULL)
        n <- nrow(sub); k <- .cv_k(input, sub); lbl <- .cv_label(k, n)
        set.seed(42); folds <- sample(rep_len(seq_len(k), n))
        all_p <- character(n); all_a <- as.character(sub[[tgt]])
        for (fold in seq_len(k)) {
          tr <- sub[folds != fold, , drop = FALSE]
          te <- sub[folds == fold, , drop = FALSE]
          probs_mat <- vapply(classes, function(cl) {
            tr_bin <- tr
            tr_bin$._target_ <- as.integer(as.character(tr_bin[[tgt]]) == cl)
            fml2 <- as.formula(paste("._target_ ~", paste(pv, collapse = "+")))
            m <- tryCatch(glm(fml2, data = tr_bin, family = binomial), error = function(e) NULL)
            if (is.null(m)) return(rep(0.5, nrow(te)))
            tryCatch(predict(m, newdata = te, type = "response"), error = function(e) rep(0.5, nrow(te)))
          }, numeric(nrow(te)))
          pred_cls <- classes[apply(probs_mat, 1, which.max)]
          all_p[folds == fold] <- pred_cls
        }
        list(actual = all_a, predicted = all_p, lbl = lbl)
      }, error = function(e) NULL)
    })

    output$cv_dt <- renderDT({
      cv <- clf_cv_result_r()
      if (is.null(cv)) return(DT::datatable(data.frame(Message = "Awaiting CV...")))
      acc <- mean(cv$predicted == cv$actual, na.rm = TRUE)
      .prf_dt(.clf_prf(cv$actual, cv$predicted), acc)
    })

    output$val_conf_plot <- renderPlot({
      cv <- clf_cv_result_r()
      if (is.null(cv)) { show_placeholder("Awaiting CV results..."); return() }
      cm <- table(Predicted = cv$predicted, Actual = cv$actual)
      print(.plot_conf_matrix(cm, title = paste(cv$lbl, "— Validation Confusion Matrix")))
    })

    

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        res <- clf_results()
        if (is.null(res)) return(paste0("One-vs-all Classification (binary logistic per class). Target: ",
                                        input$target, " — not run yet."))
        paste0("One-vs-all Classification (binary logistic per class). Target: ", input$target,
               " ; threshold: ", input$threshold, "\n\nPer-class metrics:\n",
               paste(utils::capture.output(print(res, row.names = FALSE)), collapse = "\n"))
      }),
      plot = function() f1_plot_fn()
    )
  })
}
