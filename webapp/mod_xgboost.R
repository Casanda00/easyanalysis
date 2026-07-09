# ==========================================================================
# MODULE: XGBoost
# Gradient boosted trees — regression & classification
# xgboostCanvasUI / xgboostToolsUI / xgboostServer
# Requires: xgboost (install.packages("xgboost"))
# ==========================================================================

xgboostToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("XGBoost", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "xgb_data",
      accordion_panel("Data", value = "xgb_data", icon = icon("table"),
        uiOutput(ns("y_ui")),
        uiOutput(ns("x_ui")),
        selectInput(ns("obj_type"), "Task type", width = "100%",
          choices = c("Regression"           = "reg",
                      "Binary Classification" = "bin",
                      "Multiclass"            = "multi"))
      ),
      accordion_panel("Hyperparameters", value = "xgb_params", icon = icon("sliders"),
        numericInput(ns("nrounds"),  "Boosting rounds",  value = 100,  min = 10,  max = 5000, width = "100%"),
        numericInput(ns("eta"),      "Learning rate (η)", value = 0.1,  min = 0.001, max = 1, step = 0.01, width = "100%"),
        numericInput(ns("max_depth"),"Max tree depth",   value = 6,    min = 1,   max = 20,  width = "100%"),
        numericInput(ns("subsample"),"Row subsample",    value = 0.8,  min = 0.1, max = 1,   step = 0.05, width = "100%"),
        numericInput(ns("colsample"),"Col subsample",    value = 0.8,  min = 0.1, max = 1,   step = 0.05, width = "100%"),
        numericInput(ns("min_child"),"Min child weight", value = 1,    min = 0,   max = 100, width = "100%"),
        checkboxInput(ns("use_cv"),  "Cross-validation (xgb.cv)", value = TRUE),
        conditionalPanel("input.use_cv", ns = ns,
          numericInput(ns("nfold"), "CV folds", value = 5, min = 2, max = 20, width = "100%")
        )
      ),
      accordion_panel("Export", value = "xgb_exp", icon = icon("download"),
        downloadButton(ns("dl_importance"), "Importance CSV", class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_preds"),     "Predictions CSV", class = "btn-sm btn-outline-success w-100")
      )
    ),
    actionButton(ns("run_xgb"), "Train XGBoost",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

xgboostCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Training Curve",
      layout_columns(col_widths = c(8, 4),
        card(plotOutput(ns("cv_plot"), height = "400px")),
        card(card_header("Performance"), verbatimTextOutput(ns("perf_out")))
      )
    ),
    nav_panel("Feature Importance",
      layout_columns(col_widths = c(8, 4),
        card(plotOutput(ns("imp_plot"), height = "440px")),
        card(card_header("Top Variables"), DTOutput(ns("imp_tbl")))
      )
    ),
    nav_panel("Predictions",
      layout_columns(col_widths = c(7, 5),
        card(plotOutput(ns("pred_plot"), height = "400px")),
        card(card_header("Prediction Table"), DTOutput(ns("pred_tbl")))
      )
    )
  )
}

xgboostServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    if (!requireNamespace("xgboost", quietly = TRUE)) {
      msg <- "Package 'xgboost' is required.\nRun: install.packages('xgboost')"
      output$cv_plot  <- renderPlot(show_placeholder(msg))
      output$imp_plot <- renderPlot(show_placeholder(msg))
      return(list(context = reactive("XGBoost: package missing."), plot = function() invisible()))
    }

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    output$y_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      selectInput(ns("y_var"), "Response variable (Y)", choices = names(df), width = "100%")
    })

    output$x_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      num <- names(df)[sapply(df, is.numeric)]
      if (length(num) == 0) return(tags$p(class = "small text-warning", "No numeric predictors."))
      selectInput(ns("x_vars"), "Predictor variables (X)", choices = num,
                  selected = setdiff(num, input$y_var), multiple = TRUE, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_xgb, {
      df <- active_data(); req(!is.null(df))
      yv <- input$y_var;  req(isTruthy(yv))
      xv <- input$x_vars; req(isTruthy(xv), length(xv) >= 1)
      obj_type <- input$obj_type %||% "reg"

      sub_df <- df[, c(yv, xv), drop = FALSE]
      sub_df <- sub_df[complete.cases(sub_df), ]
      req(nrow(sub_df) >= 10)

      y_raw <- sub_df[[yv]]
      X_mat <- as.matrix(sub_df[, xv, drop = FALSE])

      # Encode y
      y_enc <- if (obj_type == "reg") {
        as.numeric(y_raw)
      } else {
        lv <- as.integer(as.factor(y_raw)) - 1L
        lv
      }
      n_class <- if (obj_type == "multi") length(unique(y_enc)) else NULL

      params <- list(
        booster          = "gbtree",
        objective        = switch(obj_type,
          reg   = "reg:squarederror",
          bin   = "binary:logistic",
          multi = "multi:softmax"),
        eta              = as.numeric(input$eta %||% 0.1),
        max_depth        = as.integer(input$max_depth %||% 6L),
        subsample        = as.numeric(input$subsample %||% 0.8),
        colsample_bytree = as.numeric(input$colsample %||% 0.8),
        min_child_weight = as.numeric(input$min_child %||% 1),
        eval_metric      = switch(obj_type, reg = "rmse", bin = "logloss", multi = "merror")
      )
      if (obj_type == "multi") params$num_class <- n_class

      nrounds <- as.integer(input$nrounds %||% 100L)
      nfold   <- as.integer(input$nfold   %||% 5L)

      result <- tryCatch({
        dtrain <- xgboost::xgb.DMatrix(data = X_mat, label = y_enc)

        cv_hist <- NULL
        best_nrounds <- nrounds
        if (isTRUE(input$use_cv)) {
          cv_res <- xgboost::xgb.cv(params = params, data = dtrain, nrounds = nrounds,
                                     nfold = nfold, verbose = 0, early_stopping_rounds = 15)
          cv_hist <- cv_res$evaluation_log
          best_nrounds <- cv_res$best_iteration
        }

        final <- xgboost::xgboost(data = dtrain, params = params,
                                   nrounds = best_nrounds, verbose = 0)

        preds_raw <- predict(final, dtrain)
        preds <- if (obj_type == "reg") preds_raw
                 else if (obj_type == "bin") round(preds_raw)
                 else preds_raw

        imp <- xgboost::xgb.importance(model = final, feature_names = xv)

        list(model = final, cv_hist = cv_hist, best_nrounds = best_nrounds,
             preds = preds, preds_raw = preds_raw, y_enc = y_enc, y_raw = y_raw,
             imp = imp, params = params, obj_type = obj_type,
             xv = xv, yv = yv, n_class = n_class)
      }, error = function(e) {
        showNotification(paste("XGBoost error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("XGBoost training complete.", type = "message")
    })

    output$cv_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Configure and click Train XGBoost."); return() }
      if (!is.null(res$cv_hist)) {
        cv <- res$cv_hist
        metric_train <- names(cv)[grep("train.*mean", names(cv))][1]
        metric_test  <- names(cv)[grep("test.*mean",  names(cv))][1]
        ylim <- range(c(cv[[metric_train]], cv[[metric_test]]), na.rm = TRUE)
        plot(cv$iter, cv[[metric_train]], type = "l", col = "#2e7d32", lwd = 2,
             xlab = "Round", ylab = "Loss", main = "CV Training Curve", ylim = ylim)
        lines(cv$iter, cv[[metric_test]], col = "#c62828", lwd = 2, lty = 2)
        abline(v = res$best_nrounds, col = "grey40", lty = 3)
        legend("topright", c("Train","CV Test","Best round"),
               col = c("#2e7d32","#c62828","grey40"), lwd = c(2,2,1),
               lty = c(1,2,3), bty = "n", cex = 0.85)
        grid(col = "grey92")
      } else {
        plot.new()
        text(0.5, 0.5, paste("Trained for", res$best_nrounds, "rounds\n(CV disabled)"),
             cex = 1.3, col = "grey40")
      }
    })

    output$perf_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat(sprintf("Best rounds: %d\n", res$best_nrounds))
      cat(sprintf("Objective:   %s\n\n", res$params$objective))
      if (res$obj_type == "reg") {
        rmse <- sqrt(mean((res$y_enc - res$preds)^2, na.rm = TRUE))
        ss_tot <- sum((res$y_enc - mean(res$y_enc))^2)
        ss_res <- sum((res$y_enc - res$preds)^2)
        r2 <- 1 - ss_res / ss_tot
        cat(sprintf("Train RMSE : %.4f\nTrain R²   : %.4f\n", rmse, r2))
        cat(sprintf("Train MAE  : %.4f\n", mean(abs(res$y_enc - res$preds))))
      } else {
        # Decode predictions back to original labels
        lv   <- levels(as.factor(res$y_raw))
        act  <- as.character(res$y_raw)
        pred <- if (res$obj_type == "bin") lv[res$preds + 1L]
                else lv[as.integer(res$preds) + 1L]
        acc  <- mean(pred == act, na.rm = TRUE)
        cat(sprintf("Train Accuracy: %.4f (%.1f%%)\n\n", acc, 100*acc))
        prf <- .clf_prf(act, pred)
        .print_prf(prf)
      }
    })

    output$imp_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train model first."); return() }
      imp <- res$imp; req(!is.null(imp), nrow(imp) > 0)
      nshow <- min(nrow(imp), 20)
      imp_show <- imp[seq_len(nshow), ]
      barplot(rev(imp_show$Gain),
              names.arg = rev(imp_show$Feature),
              horiz = TRUE, col = "#4caf5099", border = "#2e7d32",
              xlab = "Gain", main = "Feature Importance (Gain)",
              las = 1, cex.names = 0.8)
      grid(nx = 5, ny = NA, col = "grey92")
    })

    output$imp_tbl <- renderDT({
      res <- result_r(); req(!is.null(res), !is.null(res$imp))
      df <- as.data.frame(res$imp)
      df[, sapply(df, is.numeric)] <- round(df[, sapply(df, is.numeric)], 4)
      datatable(df, rownames = FALSE, options = list(pageLength = 15, scrollX = TRUE))
    })

    output$pred_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train model first."); return() }
      if (res$obj_type == "reg") {
        plot(res$y_enc, res$preds, pch = 16, col = "#2e7d3266",
             xlab = "Observed", ylab = "Predicted",
             main = "Observed vs Predicted (train)")
        abline(0, 1, col = "#c62828", lwd = 2)
        grid(col = "grey92")
      } else {
        cm <- table(Predicted = res$preds, Observed = res$y_enc)
        image(t(cm[nrow(cm):1, ]), col = colorRampPalette(c("white","#4caf50"))(20),
              axes = FALSE, main = "Confusion Matrix (train)")
        axis(1, at = seq(0, 1, length.out = ncol(cm)), labels = colnames(cm))
        axis(2, at = seq(0, 1, length.out = nrow(cm)), labels = rev(rownames(cm)))
        for (i in seq_len(nrow(cm)))
          for (j in seq_len(ncol(cm)))
            text((j-1)/(ncol(cm)-1), 1-(i-1)/(nrow(cm)-1), cm[i,j], cex = 1.2)
      }
    })

    output$pred_tbl <- renderDT({
      res <- result_r(); req(!is.null(res))
      df <- data.frame(Observed = res$y_raw, Predicted = res$preds_raw)
      if (res$obj_type != "reg") df$`Pred Class` <- res$preds
      datatable(df, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })

    output$dl_importance <- downloadHandler(
      filename = function() "xgboost_importance.csv",
      content  = function(f) { res <- result_r(); req(!is.null(res)); write.csv(res$imp, f, row.names = FALSE) }
    )

    output$dl_preds <- downloadHandler(
      filename = function() "xgboost_predictions.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        df <- data.frame(Observed = res$y_raw, Predicted_raw = res$preds_raw, Predicted = res$preds)
        write.csv(df, f, row.names = FALSE)
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("XGBoost: not trained yet.")
        rmse_txt <- if (res$obj_type == "reg")
          sprintf(", RMSE=%.4f", sqrt(mean((res$y_enc - res$preds)^2)))
        else sprintf(", Acc=%.3f", mean(res$preds == res$y_enc))
        paste0("XGBoost | Y=", res$yv, " | X=", paste(res$xv, collapse=","),
               " | rounds=", res$best_nrounds, rmse_txt)
      }),
      plot = function() {
        res <- isolate(result_r()); if (is.null(res)) return(invisible())
        imp <- res$imp; req(!is.null(imp))
        nshow <- min(nrow(imp), 15)
        barplot(rev(imp$Gain[seq_len(nshow)]), names.arg = rev(imp$Feature[seq_len(nshow)]),
                horiz = TRUE, col = "#4caf5099", xlab = "Gain",
                main = "XGBoost Feature Importance", las = 1, cex.names = 0.8)
      }
    )
  })
}
