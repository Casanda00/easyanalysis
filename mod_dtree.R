# ==========================================================================
# MODULE: Decision Trees (rpart)
# Regression trees & classification trees
# dtreeCanvasUI / dtreeToolsUI / dtreeServer
# Requires: rpart (R recommended package — pre-installed)
# ==========================================================================

dtreeToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Decision Trees", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "dt_data",
      accordion_panel("Data", value = "dt_data", icon = icon("table"),
        uiOutput(ns("y_ui")),
        uiOutput(ns("x_ui")),
        selectInput(ns("tree_type"), "Tree type", width = "100%",
          choices = c("Regression (numeric Y)"     = "anova",
                      "Classification (factor Y)"  = "class"))
      ),
      accordion_panel("Tree Controls", value = "dt_ctrl", icon = icon("sliders"),
        numericInput(ns("maxdepth"),  "Max depth",    value = 5,    min = 1, max = 30, width = "100%"),
        numericInput(ns("minsplit"),  "Min split (n to try split)", value = 20, min = 1, width = "100%"),
        numericInput(ns("minbucket"), "Min bucket (n in leaf)",     value = 7,  min = 1, width = "100%"),
        numericInput(ns("cp"),        "Complexity parameter (cp)",
                     value = 0.01, min = 0, max = 1, step = 0.001, width = "100%"),
        checkboxInput(ns("use_cv"), "Prune via cross-validation", value = TRUE)
      ),
      accordion_panel("Export", value = "dt_exp", icon = icon("download"),
        downloadButton(ns("dl_rules"), "Rules (text)",  class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_preds"), "Predictions CSV", class = "btn-sm btn-outline-success w-100")
      )
    ),
    .cv_ui(ns),
    actionButton(ns("run_tree"), "Grow Tree",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

dtreeCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Tree Diagram",     plotOutput(ns("tree_plot"),    height = "520px")),
    nav_panel("CP / Pruning",     plotOutput(ns("cp_plot"),      height = "380px")),
    nav_panel("Variable Importance", plotOutput(ns("imp_plot"),  height = "400px")),
    nav_panel("Performance",
      layout_columns(col_widths = c(6, 6),
        card(card_header("Summary"), verbatimTextOutput(ns("perf_out"))),
        card(card_header("Confusion / Residuals"), plotOutput(ns("resid_plot"), height = "340px"))
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
    )
  )
}

dtreeServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    if (!requireNamespace("rpart", quietly = TRUE)) {
      msg <- "Package 'rpart' required.\nRun: install.packages('rpart')"
      output$tree_plot <- renderPlot(show_placeholder(msg))
      return(list(context = reactive("Decision Trees: rpart missing."), plot = function() invisible()))
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
      selectInput(ns("x_vars"), "Predictor variables (X)", choices = names(df),
                  selected = names(df), multiple = TRUE, width = "100%")
    })

    result_r <- reactiveVal(NULL)

    observeEvent(input$run_tree, {
      df <- active_data(); req(!is.null(df))
      yv <- input$y_var;  req(isTruthy(yv))
      xv <- input$x_vars; req(isTruthy(xv), length(xv) >= 1)
      xv <- setdiff(xv, yv)
      req(length(xv) >= 1)

      sub_df <- df[, c(yv, xv), drop = FALSE]
      sub_df <- sub_df[complete.cases(sub_df), ]
      req(nrow(sub_df) >= 10)

      method <- input$tree_type %||% "anova"
      if (method == "class") sub_df[[yv]] <- as.factor(sub_df[[yv]])

      ctrl <- rpart::rpart.control(
        maxdepth  = as.integer(input$maxdepth  %||% 5L),
        minsplit  = as.integer(input$minsplit  %||% 20L),
        minbucket = as.integer(input$minbucket %||% 7L),
        cp        = as.numeric(input$cp        %||% 0.01),
        xval      = if (isTRUE(input$use_cv)) 10L else 0L
      )

      result <- tryCatch({
        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = " + ")))
        fit  <- rpart::rpart(fml, data = sub_df, method = method, control = ctrl)

        # Prune to best cp if CV was used
        if (isTRUE(input$use_cv) && nrow(fit$cptable) > 1) {
          best_cp <- fit$cptable[which.min(fit$cptable[,"xerror"]), "CP"]
          fit <- rpart::prune(fit, cp = best_cp)
        }

        preds <- predict(fit, sub_df, type = if (method == "class") "class" else "vector")

        list(fit = fit, preds = preds, y = sub_df[[yv]], df = sub_df, yv = yv, xv = xv, method = method)
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      result_r(result)
      if (!is.null(result)) showNotification("Tree grown.", type = "message")
    })

    output$tree_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Configure variables and click Grow Tree."); return() }
      if (nrow(res$fit$frame) <= 1) {
        show_placeholder("Tree has only a root node — try reducing cp or maxdepth.")
        return()
      }
      plot(res$fit, uniform = TRUE, compress = TRUE, margin = 0.05,
           main = paste("Decision Tree:", res$yv))
      text(res$fit, use.n = TRUE, all = FALSE, cex = 0.75,
           fancy = FALSE, splits = TRUE)
    })

    output$cp_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train tree first."); return() }
      if (nrow(res$fit$cptable) < 2) {
        show_placeholder("CP table has only one row (no pruning candidates)."); return()
      }
      rpart::plotcp(res$fit, col = "#2e7d32", lwd = 2)
    })

    output$imp_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train tree first."); return() }
      imp <- res$fit$variable.importance
      if (is.null(imp) || length(imp) == 0) {
        show_placeholder("No variable importance (stump tree?)."); return()
      }
      imp <- sort(imp)
      barplot(imp, horiz = TRUE, col = "#4caf5099", border = "#2e7d32",
              xlab = "Relative Importance", main = "Variable Importance",
              las = 1, cex.names = 0.85)
      grid(nx = 5, ny = NA, col = "grey92")
    })

    output$perf_out <- renderPrint({
      res <- result_r(); req(!is.null(res))
      cat("Tree size:", nrow(res$fit$frame), "nodes\n")
      cat("Leaves:   ", sum(res$fit$frame$var == "<leaf>"), "\n\n")
      if (res$method == "anova") {
        rmse <- sqrt(mean((as.numeric(res$y) - as.numeric(res$preds))^2, na.rm = TRUE))
        ss_tot <- sum((as.numeric(res$y) - mean(as.numeric(res$y)))^2)
        ss_res <- sum((as.numeric(res$y) - as.numeric(res$preds))^2)
        r2  <- 1 - ss_res / ss_tot
        cat(sprintf("Train RMSE: %.4f\nTrain R²:   %.4f\n", rmse, r2))
        cat("\nRoot node error:", round(res$fit$cptable[1,"rel error"], 4), "\n")
      } else {
        cm  <- table(Predicted = res$preds, Observed = res$y)
        acc <- sum(diag(cm)) / sum(cm)
        cat(sprintf("Train Accuracy: %.4f (%.1f%%)\n\n", acc, 100*acc))
        print(cm)
      }
    })

    output$resid_plot <- renderPlot({
      res <- result_r()
      if (is.null(res)) { show_placeholder("Train tree first."); return() }
      if (res$method == "anova") {
        resids <- as.numeric(res$y) - as.numeric(res$preds)
        plot(as.numeric(res$preds), resids, pch = 16, col = "#2e7d3266",
             xlab = "Fitted", ylab = "Residual", main = "Residuals vs Fitted")
        abline(h = 0, col = "#c62828", lwd = 1.5, lty = 2)
        grid(col = "grey92")
      } else {
        cm  <- table(Predicted = res$preds, Observed = res$y)
        image(t(cm[nrow(cm):1, ]), col = colorRampPalette(c("white","#4caf50"))(20),
              axes = FALSE, main = "Confusion Matrix (train)")
        axis(1, at = seq(0,1,length.out=ncol(cm)), labels = colnames(cm))
        axis(2, at = seq(0,1,length.out=nrow(cm)), labels = rev(rownames(cm)))
        for (i in seq_len(nrow(cm)))
          for (j in seq_len(ncol(cm)))
            text((j-1)/max(ncol(cm)-1,1), 1-(i-1)/max(nrow(cm)-1,1), cm[i,j], cex = 1.2)
      }
    })

    dtree_cv_result_r <- reactive({
      res <- result_r(); if (is.null(res) || res$method != "class") return(NULL)
      tryCatch({
        df_cv <- res$df; yv <- res$yv; xv <- res$xv
        fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
        n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
        set.seed(42); folds <- sample(rep_len(seq_len(k), n))
        all_p <- c(); all_a <- c()
        for (fold in seq_len(k)) {
          tr <- df_cv[folds != fold, , drop = FALSE]
          te <- df_cv[folds == fold, , drop = FALSE]
          m <- tryCatch(rpart::rpart(fml, data = tr, method = "class"), error = function(e) NULL)
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
      cv <- dtree_cv_result_r()
      if (is.null(cv)) { show_placeholder("Awaiting classification CV results..."); return() }
      cm <- table(Predicted = cv$predicted, Actual = cv$actual)
      print(.plot_conf_matrix(cm, title = paste(cv$lbl, "— Validation Confusion Matrix")))
    })

    output$val_acc <- renderText({
      cv <- dtree_cv_result_r()
      if (is.null(cv)) return("")
      paste(cv$lbl, "Accuracy:", round(mean(cv$predicted == cv$actual, na.rm = TRUE) * 100, 2), "%")
    })

    output$prf_cv_dt <- renderDT({
      res <- result_r()
      if (is.null(res)) return(DT::datatable(data.frame(Message = "Grow a tree first.")))
      tryCatch({
        if (res$method != "anova") {
          train_prf <- .clf_prf(as.character(res$y), as.character(res$preds))
          train_acc <- mean(as.character(res$y) == as.character(res$preds), na.rm = TRUE)
          cv <- dtree_cv_result_r()
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
          e <- as.numeric(res$y) - as.numeric(res$preds)
          train_m <- list(RMSE = sqrt(mean(e^2)), MAE = mean(abs(e)),
                          R2 = 1 - sum(e^2) / sum((as.numeric(res$y) - mean(as.numeric(res$y)))^2))
          df_cv <- res$df; yv <- res$yv; xv <- res$xv
          fml <- as.formula(paste0("`", yv, "` ~ ", paste0("`", xv, "`", collapse = "+")))
          n <- nrow(df_cv); k <- .cv_k(input, df_cv); lbl <- .cv_label(k, n)
          set.seed(42); folds <- sample(rep_len(seq_len(k), n))
          all_p <- c(); all_a <- c()
          for (fold in seq_len(k)) {
            tr <- df_cv[folds != fold, , drop = FALSE]
            te <- df_cv[folds == fold, , drop = FALSE]
            m <- tryCatch(rpart::rpart(fml, data = tr, method = "anova"), error = function(e) NULL)
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

    output$dl_rules <- downloadHandler(
      filename = function() paste0("dtree_rules_", input$y_var %||% "y", ".txt"),
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        writeLines(capture.output(print(res$fit)), f)
      }
    )

    output$dl_preds <- downloadHandler(
      filename = function() "dtree_predictions.csv",
      content  = function(f) {
        res <- result_r(); req(!is.null(res))
        write.csv(data.frame(Observed = res$y, Predicted = res$preds), f, row.names = FALSE)
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Decision Trees: not trained yet.")
        paste0("Decision Tree | Y=", res$yv, " | X=", paste(res$xv, collapse=","),
               " | nodes=", nrow(res$fit$frame),
               " | leaves=", sum(res$fit$frame$var == "<leaf>"))
      }),
      plot = function() {
        res <- isolate(result_r()); if (is.null(res)) return(invisible())
        plot(res$fit, uniform = TRUE, compress = TRUE, margin = 0.05)
        text(res$fit, use.n = TRUE, cex = 0.75)
      }
    )
  })
}
