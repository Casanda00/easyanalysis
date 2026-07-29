# ==========================================================================
# MODULE: Support Vector Machines (e1071)
# Regression & classification with SVM
# svmCanvasUI / svmToolsUI / svmServer
# Requires: e1071 (install.packages("e1071"))
# ==========================================================================

svmToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Support Vector Machines", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "svm_data",
      accordion_panel("Data", value = "svm_data", icon = icon("table"),
        uiOutput(ns("y_ui")),
        uiOutput(ns("x_ui")),
        selectInput(ns("svm_type"), "Task type", width = "100%",
          choices = c("Regression (eps-SVR)"          = "eps-regression",
                      "Classification (C-classif.)"   = "C-classification",
                      "Nu-Classification"              = "nu-classification"))
      ),
      accordion_panel("Kernel & Params", value = "svm_params", icon = icon("sliders"),
        selectInput(ns("kernel"), "Kernel", width = "100%",
          choices = c("Radial (RBF)"   = "radial",
                      "Linear"          = "linear",
                      "Polynomial"      = "polynomial",
                      "Sigmoid"         = "sigmoid")),
        numericInput(ns("cost"), "Cost (C)", value = 1, min = 0.001, step = 0.5, width = "100%"),
        conditionalPanel("input.kernel == 'radial' || input.kernel == 'polynomial' || input.kernel == 'sigmoid'",
          ns = ns,
          numericInput(ns("gamma"), "Gamma (leave 0 = 1/n_features)",
                       value = 0, min = 0, step = 0.01, width = "100%")
        ),
        conditionalPanel("input.kernel == 'polynomial'", ns = ns,
          numericInput(ns("degree"), "Polynomial degree", value = 3, min = 1, max = 10, width = "100%")
        ),
        conditionalPanel("input.svm_type == 'eps-regression'", ns = ns,
          numericInput(ns("epsilon"), "Epsilon (ε-insensitive tube)",
                       value = 0.1, min = 0, step = 0.01, width = "100%")
        ),
        checkboxInput(ns("scale_x"), "Scale predictors", value = TRUE),
        checkboxInput(ns("cross_val"), "5-fold cross-validation", value = FALSE)
      ),
      accordion_panel("Export", value = "svm_exp", icon = icon("download"),
        downloadButton(ns("dl_preds"), "Predictions CSV", class = "btn-sm btn-success w-100")
      )
    ),
    .cv_ui(ns),
    actionButton(ns("run_svm"), "Train SVM",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

svmCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Performance",
      layout_columns(col_widths = c(6, 6),
        card(card_header("Metrics"), verbatimTextOutput(ns("perf_out"))),
        card(card_header("Predictions"), plotOutput(ns("pred_plot"), height = "380px"))
      ),
      layout_columns(col_widths = c(6, 6),
        card(
          card_header("Precision / Recall / F1 + Cross-Validation"),
          div(style = "padding: 5px;", DTOutput(ns("prf_cv_dt")))
        ),
        card(
          card_header("Validation Confusion Matrix"),
          div(style = "height: 280px; padding: 5px;", plotOutput(ns("val_conf_plot"), height = "255px")),
          div(style = "padding: 5px 10px;", tags$b(textOutput(ns("val_acc"))))
        )
      )
    ),
    nav_panel("Support Vectors",
      layout_columns(col_widths = c(6, 6),
        card(card_header("SV Summary"), verbatimTextOutput(ns("sv_info"))),
        card(card_header("SV Distribution"), plotOutput(ns("sv_plot"), height = "380px"))
      )
    ),
    nav_panel("Prediction Table",
      DTOutput(ns("pred_tbl"), height = "500px")
    )
  )
}

svmServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    if (!requireNamespace("e1071", quietly = TRUE)) {
      msg <- "Package 'e1071' required.\nRun: install.packages('e1071')"
      output$pred_plot <- renderPlot(show_placeholder(msg))
      output$perf_out  <- renderPrint(cat(msg, "\n"))
      return(list(context = reactive("SVM: e1071 package missing."), plot = function() invisible()))
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
      selectInput(ns("x_vars"), "Predictor variables (numeric X)", choices = num,
                  selected = setdiff(num, input$y_var), multiple = TRUE, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_svm, {
      df <- active_data(); req(!is.null(df))
      yv <- input$y_var;  req(isTruthy(yv))
      xv <- input$x_vars; req(isTruthy(xv), length(xv) >= 1)
      xv <- setdiff(xv, yv)
      req(length(xv) >= 1)

      svm_type <- input$svm_type %||% "C-classification"
      sub_df   <- df[, c(yv, xv), drop = FALSE]
      sub_df   <- sub_df[complete.cases(sub_df), ]
      req(nrow(sub_df) >= 10)

      y_val <- if (grepl("classification", svm_type)) as.factor(sub_df[[yv]])
               else as.numeric(sub_df[[yv]])
      sub_df[[yv]] <- y_val

      gamma_val <- as.numeric(input$gamma %||% 0)
      if (gamma_val <= 0) gamma_val <- 1 / length(xv)

      result <- tryCatch({
        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = " + ")))
        cross_k <- if (isTRUE(input$cross_val)) 5L else 0L

        fit <- e1071::svm(fml, data = sub_df,
          type    = svm_type,
          kernel  = input$kernel  %||% "radial",
          cost    = as.numeric(input$cost    %||% 1),
          gamma   = gamma_val,
          degree  = as.integer(input$degree  %||% 3L),
          epsilon = as.numeric(input$epsilon %||% 0.1),
          scale   = isTRUE(input$scale_x),
          cross   = cross_k)

        preds <- predict(fit, sub_df)

        list(fit = fit, preds = preds, y = sub_df[[yv]], df = sub_df, yv = yv, xv = xv,
             svm_type = svm_type, cross_k = cross_k)
      }, error = function(e) {
        showNotification(paste("SVM error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("SVM trained.", type = "message")
    })

    output$perf_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      is_reg <- grepl("regression", res$svm_type)
      cat("SVM Type:   ", res$svm_type, "\n")
      cat("Kernel:     ", input$kernel, "\n")
      cat("Cost (C):   ", input$cost, "\n")
      cat("N support vectors:", nrow(res$fit$SV), "\n\n")
      if (is_reg) {
        y_num <- as.numeric(res$y); p_num <- as.numeric(res$preds)
        rmse <- sqrt(mean((y_num - p_num)^2, na.rm=TRUE))
        r2   <- 1 - sum((y_num - p_num)^2) / sum((y_num - mean(y_num))^2)
        cat(sprintf("Train RMSE: %.4f\nTrain R²:   %.4f\n", rmse, r2))
        if (res$cross_k > 0 && !is.null(res$fit$tot.MSE))
          cat(sprintf("CV RMSE:    %.4f\n", sqrt(res$fit$tot.MSE)))
      } else {
        cm  <- table(Predicted = res$preds, Observed = res$y)
        acc <- sum(diag(cm)) / sum(cm)
        cat(sprintf("Train Accuracy: %.4f (%.1f%%)\n\n", acc, 100*acc))
        print(cm)
        if (res$cross_k > 0 && !is.null(res$fit$tot.accuracy))
          cat(sprintf("\nCV Accuracy: %.4f\n", res$fit$tot.accuracy/100))
      }
    })

    svm_cv_result_r <- reactive({
      res <- result_r(); if (is.null(res)) return(NULL)
      if (grepl("regression", res$svm_type)) return(NULL)
      tryCatch({
        df_cv <- res$df; yv <- res$yv; xv <- res$xv
        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
        n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
        set.seed(42); folds <- sample(rep_len(seq_len(k), n))
        all_p <- c(); all_a <- c()
        for (fold in seq_len(k)) {
          tr <- df_cv[folds != fold, , drop = FALSE]
          te <- df_cv[folds == fold, , drop = FALSE]
          m <- tryCatch(e1071::svm(fml, data = tr, type = res$svm_type,
                                   kernel = res$fit$kernel, cost = res$fit$cost,
                                   scale = TRUE), error = function(e) NULL)
          if (is.null(m)) next
          p <- tryCatch(as.character(predict(m, newdata = te)), error = function(e) NULL)
          if (is.null(p)) next
          all_p <- c(all_p, p); all_a <- c(all_a, as.character(te[[yv]]))
        }
        if (length(all_p) == 0) return(NULL)
        list(actual = all_a, predicted = all_p, lbl = lbl)
      }, error = function(e) NULL)
    })

    output$val_conf_plot <- renderPlot({
      cv <- svm_cv_result_r()
      if (is.null(cv)) { show_placeholder("Awaiting SVM classification CV results..."); return() }
      cm <- table(Predicted = cv$predicted, Actual = cv$actual)
      print(.plot_conf_matrix(cm, title = paste(cv$lbl, "— Validation Confusion Matrix")))
    })

    output$val_acc <- renderText({
      cv <- svm_cv_result_r()
      if (is.null(cv)) return("")
      paste(cv$lbl, "Accuracy:", round(mean(cv$predicted == cv$actual, na.rm = TRUE) * 100, 2), "%")
    })

    output$prf_cv_dt <- renderDT({
      res <- result_r()
      if (is.null(res)) return(DT::datatable(data.frame(Message = "Train SVM first.")))
      is_reg <- grepl("regression", res$svm_type)
      tryCatch({
        if (!is_reg) {
          train_prf <- .clf_prf(as.character(res$y), as.character(res$preds))
          train_acc <- mean(as.character(res$y) == as.character(res$preds), na.rm = TRUE)
          cv <- svm_cv_result_r()
          if (!is.null(cv)) {
            prf_list <- setNames(list(train_prf, .clf_prf(cv$actual, cv$predicted)),
                                 c("Training", cv$lbl))
            acc_list <- setNames(list(train_acc, mean(cv$predicted == cv$actual, na.rm = TRUE)),
                                 c("Training", cv$lbl))
          } else {
            prf_list <- list(Training = train_prf); acc_list <- list(Training = train_acc)
          }
          .prf_dt(prf_list, acc_list)
        } else {
          y_num <- as.numeric(res$y); p_num <- as.numeric(res$preds)
          e <- y_num - p_num
          train_m <- list(RMSE = sqrt(mean(e^2)), MAE = mean(abs(e)),
                          R2 = 1 - sum(e^2) / sum((y_num - mean(y_num))^2))
          df_cv <- res$df; yv <- res$yv; xv <- res$xv
          fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
          n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
          set.seed(42); folds <- sample(rep_len(seq_len(k), n))
          all_p <- c(); all_a <- c()
          for (fold in seq_len(k)) {
            tr <- df_cv[folds != fold, , drop = FALSE]
            te <- df_cv[folds == fold, , drop = FALSE]
            m <- tryCatch(e1071::svm(fml, data = tr, type = res$svm_type,
                                     kernel = res$fit$kernel, scale = TRUE),
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
      if (is.null(res)) { show_placeholder("Train SVM first."); return() }
      is_reg <- grepl("regression", res$svm_type)
      if (is_reg) {
        plot(as.numeric(res$y), as.numeric(res$preds), pch = 16, col = "#2e7d3266",
             xlab = "Observed", ylab = "Predicted", main = "Observed vs Predicted")
        abline(0, 1, col = "#c62828", lwd = 2)
        grid(col = "grey92")
      } else {
        cm <- table(Predicted = res$preds, Observed = res$y)
        image(t(cm[nrow(cm):1, ]), col = colorRampPalette(c("white","#4caf50"))(20),
              axes = FALSE, main = "Confusion Matrix (train)")
        axis(1, at = seq(0,1,length.out=ncol(cm)), labels = colnames(cm))
        axis(2, at = seq(0,1,length.out=nrow(cm)), labels = rev(rownames(cm)))
        for (i in seq_len(nrow(cm)))
          for (j in seq_len(ncol(cm)))
            text((j-1)/max(ncol(cm)-1,1), 1-(i-1)/max(nrow(cm)-1,1), cm[i,j], cex=1.2)
      }
    })

    output$sv_info <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("Total support vectors:", nrow(res$fit$SV), "\n")
      if (!is.null(res$fit$nSV)) {
        cat("By class:\n")
        for (i in seq_along(res$fit$nSV))
          cat(sprintf("  %s: %d SVs\n", res$fit$levels[i], res$fit$nSV[i]))
      }
      cat("\nKernel parameters:\n")
      cat(sprintf("  kernel: %s\n  cost:   %.3f\n  gamma:  %.4f\n",
                  res$fit$kernel, res$fit$cost, res$fit$gamma))
    })

    output$sv_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train SVM first."); return() }
      xv <- res$xv
      if (length(xv) >= 2) {
        sv_idx <- res$fit$index
        x1 <- as.numeric(res$fit$SV[, 1])
        x2 <- as.numeric(res$fit$SV[, 2])
        plot(x1, x2, pch = 4, col = "#c62828", cex = 1.2,
             xlab = paste("SV dim 1"), ylab = paste("SV dim 2"),
             main = paste("Support Vectors (", nrow(res$fit$SV), ")"))
        grid(col = "grey92")
      } else {
        hist(as.numeric(res$fit$SV[, 1]), col = "#4caf5088", main = ea_main("Support Vectors"),
             xlab = "SV values", border = "white")
      }
    })

    output$pred_tbl <- renderDT({
      res <- result_r(); req(!is.null(res))
      df <- data.frame(Observed = res$y, Predicted = res$preds)
      if (grepl("regression", res$svm_type))
        df$Residual <- as.numeric(res$y) - as.numeric(res$preds)
      datatable(df, rownames = FALSE, options = list(pageLength = 15, scrollX = TRUE))
    })

    output$dl_preds <- downloadHandler(
      filename = function() "svm_predictions.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        write.csv(data.frame(Observed = res$y, Predicted = res$preds), f, row.names = FALSE)
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("SVM: not trained yet.")
        is_reg <- grepl("regression", res$svm_type)
        perf <- if (is_reg) {
          sprintf("RMSE=%.4f", sqrt(mean((as.numeric(res$y)-as.numeric(res$preds))^2)))
        } else {
          sprintf("Acc=%.3f", mean(res$preds == res$y))
        }
        paste0("SVM | kernel=", input$kernel, " | C=", input$cost,
               " | SVs=", nrow(res$fit$SV), " | ", perf)
      }),
      plot = function() {
        res <- isolate(result_r()); if (is.null(res)) return(invisible())
        if (grepl("regression", res$svm_type))
          plot(as.numeric(res$y), as.numeric(res$preds), pch=16, col="#2e7d3266",
               xlab="Observed", ylab="Predicted", main="SVM: Obs vs Pred")
      }
    )
  })
}
