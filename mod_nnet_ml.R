# ==========================================================================
# MODULE: Neural Networks (nnet — single hidden layer)
# Regression & classification via nnet (already loaded in global.R)
# nnetMlCanvasUI / nnetMlToolsUI / nnetMlServer
# ==========================================================================

nnetMlToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Neural Networks", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "nn_data",
      accordion_panel("Data", value = "nn_data", icon = icon("table"),
        uiOutput(ns("y_ui")),
        uiOutput(ns("x_ui")),
        selectInput(ns("nn_type"), "Task type", width = "100%",
          choices = c("Regression (numeric Y)"    = "reg",
                      "Classification (factor Y)" = "class"))
      ),
      accordion_panel("Architecture", value = "nn_arch", icon = icon("brain"),
        numericInput(ns("size"),   "Hidden units (single layer)",
                     value = 5, min = 1, max = 200, width = "100%"),
        numericInput(ns("decay"),  "Weight decay (L2 regularization)",
                     value = 0.01, min = 0, max = 10, step = 0.01, width = "100%"),
        numericInput(ns("maxit"),  "Max iterations",
                     value = 300, min = 50, max = 5000, width = "100%"),
        numericInput(ns("n_init"), "Random restarts",
                     value = 3, min = 1, max = 20, width = "100%"),
        checkboxInput(ns("scale_x"), "Scale predictors (recommended)", value = TRUE)
      ),
      accordion_panel("Export", value = "nn_exp", icon = icon("download"),
        downloadButton(ns("dl_preds"), "Predictions CSV", class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_weights"), "Weights CSV", class = "btn-sm btn-outline-success w-100")
      )
    ),
    .cv_ui(ns),
    actionButton(ns("run_nn"), "Train Network",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

.NNET_VIEWS <- c(performance = "Performance", predictions = "Predictions", network_info = "Network Info")

nnetMlCanvasUI <- function(id) {
  ns <- NS(id)
  # Select-and-split (helpers.R): one selection fills the area, several split it.
  card(
    card_header(ea_view_header(ns, .NNET_VIEWS, tools = FALSE)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

nnetMlServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .NNET_VIEWS, function(k, solo) switch(k,
        performance = tagList(layout_columns(col_widths = c(6, 6),
        card(card_header("Metrics"),  verbatimTextOutput(ns("perf_out"))),
        card(card_header("Observed vs Predicted / Confusion"),
             plotOutput(ns("pred_plot"), height = "380px"))
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(
          card_header("Precision / Recall / F1 + Cross-Validation"),
          div(style = "padding: 5px;", DTOutput(ns("prf_cv_dt")))
        ),
        card(
          card_header("Validation Confusion Matrix"),
          div(style = "height: 280px; padding: 5px;", plotOutput(ns("val_conf_plot"), height = "255px")),
          div(style = "padding: 5px 10px;", tags$b(textOutput(ns("val_acc"))))
        )
      )),
        predictions = tagList(DTOutput(ns("pred_tbl"), height = "500px")),
        network_info = tagList(card(verbatimTextOutput(ns("net_info")))),
        NULL))
    })

    ns <- session$ns

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
      selectInput(ns("x_vars"), "Predictor variables (numeric X)", choices = num,
                  selected = setdiff(num, input$y_var), multiple = TRUE, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_nn, {
      df <- active_data(); req(!is.null(df))
      yv <- input$y_var;  req(isTruthy(yv))
      xv <- input$x_vars; req(isTruthy(xv), length(xv) >= 1)
      xv <- setdiff(xv, yv)
      req(length(xv) >= 1)

      nn_type <- input$nn_type %||% "reg"
      sub_df  <- df[, c(yv, xv), drop = FALSE]
      sub_df  <- sub_df[complete.cases(sub_df), ]
      req(nrow(sub_df) >= 10)

      X_raw <- as.matrix(sub_df[, xv, drop = FALSE])
      X_sc  <- if (isTRUE(input$scale_x)) scale(X_raw) else X_raw
      x_center <- if (isTRUE(input$scale_x)) attr(X_sc, "scaled:center") else rep(0, ncol(X_raw))
      x_scale  <- if (isTRUE(input$scale_x)) attr(X_sc, "scaled:scale")  else rep(1, ncol(X_raw))

      y_raw <- sub_df[[yv]]
      if (nn_type == "class") y_raw <- as.factor(y_raw)

      result <- tryCatch({
        size  <- as.integer(input$size  %||% 5L)
        decay <- as.numeric(input$decay %||% 0.01)
        maxit <- as.integer(input$maxit %||% 300L)
        nini  <- as.integer(input$n_init %||% 3L)
        linout <- nn_type == "reg"

        train_df <- as.data.frame(X_sc)
        names(train_df) <- xv
        train_df[[yv]] <- y_raw

        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = " + ")))
        best_fit <- NULL; best_val <- Inf
        for (i in seq_len(nini)) {
          fit_i <- nnet::nnet(fml, data = train_df, size = size, decay = decay,
                              maxit = maxit, linout = linout, trace = FALSE)
          val_i <- fit_i$value
          if (!is.null(val_i) && val_i < best_val) {
            best_fit <- fit_i; best_val <- val_i
          }
        }
        req(!is.null(best_fit))

        preds <- predict(best_fit, train_df, type = if (nn_type == "class") "class" else "raw")
        preds <- as.vector(preds)
        if (nn_type == "reg") preds <- as.numeric(preds)

        list(fit = best_fit, preds = preds, y = y_raw, df = train_df, yv = yv, xv = xv,
             nn_type = nn_type, x_center = x_center, x_scale = x_scale,
             scale_x = isTRUE(input$scale_x), final_val = best_val)
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("Neural network trained.", type = "message")
    })

    output$perf_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("Network: ", res$xv, "->", input$size, "->", res$yv, "\n")
      cat("Decay:", res$fit$decay, "| Final value:", round(res$final_val, 6), "\n\n")
      if (res$nn_type == "reg") {
        y_num <- as.numeric(res$y); p_num <- as.numeric(res$preds)
        rmse <- sqrt(mean((y_num - p_num)^2, na.rm=TRUE))
        r2   <- 1 - sum((y_num - p_num)^2) / sum((y_num - mean(y_num))^2)
        cat(sprintf("Train RMSE: %.4f\nTrain R²:   %.4f\n", rmse, r2))
      } else {
        cm  <- table(Predicted = res$preds, Observed = res$y)
        acc <- sum(diag(cm)) / sum(cm)
        cat(sprintf("Train Accuracy: %.4f (%.1f%%)\n\n", acc, 100*acc))
        print(cm)
      }
    })

    nnet_cv_result_r <- reactive({
      res <- result_r(); if (is.null(res) || res$nn_type != "class") return(NULL)
      tryCatch({
        df_cv <- res$df; yv <- res$yv; xv <- res$xv
        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
        n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
        set.seed(42); folds <- sample(rep_len(seq_len(k), n))
        all_p <- c(); all_a <- c()
        sz <- res$fit$n[2]; dc <- res$fit$decay
        for (fold in seq_len(k)) {
          tr <- df_cv[folds != fold, , drop = FALSE]
          te <- df_cv[folds == fold, , drop = FALSE]
          m <- tryCatch(nnet::nnet(fml, data = tr, size = sz, decay = dc,
                                   maxit = 200, trace = FALSE), error = function(e) NULL)
          if (is.null(m)) next
          p <- tryCatch(as.character(predict(m, newdata = te, type = "class")), error = function(e) NULL)
          if (is.null(p)) next
          all_p <- c(all_p, p); all_a <- c(all_a, as.character(te[[yv]]))
        }
        if (length(all_p) == 0) return(NULL)
        list(actual = all_a, predicted = all_p, lbl = lbl)
      }, error = function(e) NULL)
    })

    output$val_conf_plot <- renderPlot({
      cv <- nnet_cv_result_r()
      if (is.null(cv)) { show_placeholder("Awaiting classification CV results..."); return() }
      cm <- table(Predicted = cv$predicted, Actual = cv$actual)
      print(.plot_conf_matrix(cm, title = paste(cv$lbl, "— Validation Confusion Matrix")))
    })

    output$val_acc <- renderText({
      cv <- nnet_cv_result_r()
      if (is.null(cv)) return("")
      paste(cv$lbl, "Accuracy:", round(mean(cv$predicted == cv$actual, na.rm = TRUE) * 100, 2), "%")
    })

    output$prf_cv_dt <- renderDT({
      res <- result_r()
      if (is.null(res)) return(DT::datatable(data.frame(Message = "Train network first.")))
      tryCatch({
        if (res$nn_type == "class") {
          train_prf <- .clf_prf(as.character(res$y), as.character(res$preds))
          train_acc <- mean(as.character(res$y) == as.character(res$preds), na.rm = TRUE)
          cv <- nnet_cv_result_r()
          if (!is.null(cv)) {
            prf_list <- setNames(list(train_prf, .clf_prf(cv$actual, cv$predicted)),
                                 c("Training", cv$lbl))
            acc_list <- setNames(list(train_acc, mean(cv$predicted == cv$actual, na.rm = TRUE)),
                                 c("Training", cv$lbl))
          } else {
            prf_list <- list(Training = train_prf)
            acc_list <- list(Training = train_acc)
          }
          .prf_dt(prf_list, acc_list)
        } else {
          y_num <- as.numeric(res$y); p_num <- as.numeric(res$preds)
          e     <- y_num - p_num
          train_m <- list(RMSE = sqrt(mean(e^2)), MAE = mean(abs(e)),
                          R2 = 1 - sum(e^2) / sum((y_num - mean(y_num))^2))
          # k-fold CV for regression
          df_cv <- res$df; yv <- res$yv; xv <- res$xv
          fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
          n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
          set.seed(42); folds <- sample(rep_len(seq_len(k), n))
          all_p <- c(); all_a <- c()
          sz <- res$fit$n[2]; dc <- res$fit$decay
          for (fold in seq_len(k)) {
            tr <- df_cv[folds != fold, , drop = FALSE]
            te <- df_cv[folds == fold, , drop = FALSE]
            m <- tryCatch(nnet::nnet(fml, data = tr, size = sz, decay = dc,
                                     maxit = 200, linout = TRUE, trace = FALSE),
                          error = function(e) NULL)
            if (is.null(m)) next
            p <- tryCatch(as.numeric(predict(m, newdata = te)), error = function(e) NULL)
            if (is.null(p)) next
            all_p <- c(all_p, p); all_a <- c(all_a, as.numeric(te[[yv]]))
          }
          if (length(all_p) > 0) {
            e2 <- all_a - all_p
            cv_m <- list(RMSE = sqrt(mean(e2^2)), MAE = mean(abs(e2)),
                         R2 = 1 - sum(e2^2) / sum((all_a - mean(all_a))^2))
            .reg_metrics_dt(setNames(list(train_m, cv_m), c("Training", lbl)))
          } else {
            .reg_metrics_dt(list(Training = train_m))
          }
        }
      }, error = function(e) DT::datatable(data.frame(Error = e$message)))
    })

    output$pred_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train network first."); return() }
      if (res$nn_type == "reg") {
        plot(as.numeric(res$y), as.numeric(res$preds), pch = 16, col = "#2e7d3266",
             xlab = "Observed", ylab = "Predicted", main = "Observed vs Predicted")
        abline(0, 1, col = "#c62828", lwd = 2)
        grid(col = "grey92")
      } else {
        cm  <- table(Predicted = res$preds, Observed = res$y)
        image(t(cm[nrow(cm):1, ]), col = colorRampPalette(c("white","#4caf50"))(20),
              axes = FALSE, main = "Confusion Matrix (train)")
        axis(1, at = seq(0,1,length.out=ncol(cm)), labels = colnames(cm))
        axis(2, at = seq(0,1,length.out=nrow(cm)), labels = rev(rownames(cm)))
        for (i in seq_len(nrow(cm)))
          for (j in seq_len(ncol(cm)))
            text((j-1)/max(ncol(cm)-1,1), 1-(i-1)/max(nrow(cm)-1,1), cm[i,j], cex=1.2)
      }
    })

    output$pred_tbl <- renderDT({
      res <- result_r(); req(!is.null(res))
      df <- data.frame(Observed = res$y, Predicted = res$preds)
      if (res$nn_type == "reg") df$Residual <- as.numeric(res$y) - as.numeric(res$preds)
      datatable(df, rownames = FALSE, options = list(pageLength = 15, scrollX = TRUE))
    })

    output$net_info <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("=== Network Architecture ===\n")
      cat(sprintf("Input nodes:  %d (%s)\n", length(res$xv), paste(res$xv, collapse=", ")))
      cat(sprintf("Hidden units: %d\n", res$fit$n[2]))
      cat(sprintf("Output nodes: %d\n", res$fit$n[3]))
      cat(sprintf("Total weights: %d\n", length(res$fit$wts)))
      cat(sprintf("Activation: logistic (hidden), %s (output)\n",
                  if (res$nn_type == "reg") "linear" else "logistic/softmax"))
      cat(sprintf("\nConverged: %s\n", if (res$fit$convergence == 0) "Yes" else "No (increase maxit)"))
      cat(sprintf("Final value: %.6f\n\n", res$final_val))
      if (res$scale_x) {
        cat("Input scaling:\n")
        sc_df <- data.frame(Variable = res$xv,
                            Center = round(res$x_center, 4),
                            Scale  = round(res$x_scale, 4))
        print(sc_df, row.names = FALSE)
      }
    })

    output$dl_preds <- downloadHandler(
      filename = function() "nnet_predictions.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        df <- data.frame(Observed = res$y, Predicted = res$preds)
        write.csv(df, f, row.names = FALSE)
      }
    )

    output$dl_weights <- downloadHandler(
      filename = function() "nnet_weights.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        write.csv(data.frame(weight_index = seq_along(res$fit$wts),
                              value = res$fit$wts), f, row.names = FALSE)
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Neural Network: not trained yet.")
        perf <- if (res$nn_type == "reg") {
          sprintf("RMSE=%.4f", sqrt(mean((as.numeric(res$y)-as.numeric(res$preds))^2)))
        } else {
          sprintf("Acc=%.3f", mean(res$preds == as.character(res$y)))
        }
        paste0("Neural Network | ", length(res$xv), "->", res$fit$n[2], "->", res$fit$n[3],
               " | Y=", res$yv, " | ", perf)
      }),
      plot = function() {
        res <- isolate(result_r()); if (is.null(res)) return(invisible())
        if (res$nn_type == "reg")
          plot(as.numeric(res$y), as.numeric(res$preds), pch=16, col="#2e7d3266",
               xlab="Observed", ylab="Predicted", main="NN: Observed vs Predicted")
      }
    )
  })
}
