# ==========================================================================
# MODULE: Random Forest  (canvas + tools contract)
# rfToolsUI / rfCanvasUI / rfServer(id, dataset_pool, active_dataset)
# Training is button-triggered (run); PDP is a second button (run_pdp).
# ==========================================================================

rfToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "Random Forest Setup"),
    selectInput(ns("target"), "Target Variable (Y):", choices = NULL),
    pickerInput(ns("predictors"), "Predictors (X):", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    hr(),
    sliderInput(ns("ntree"), "Number of Trees (ntree):", min = 100, max = 2000, value = 500, step = 100),
    checkboxInput(ns("run_cv"), "Run 10-Fold CV (May be slow)", value = FALSE),
    actionButton(ns("run"), "Train Random Forest", class = "btn-primary", width = "100%")
  )
}

rfCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(
      card_header(class = "bg-light", "Model Summary"),
      div(style = "overflow-y: auto; height: 230px; padding: 5px;", verbatimTextOutput(ns("summary")))
    ),
    # Variable importance gets its own full-width, tall panel so labels/points are readable.
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Variable Importance",
                  div(class = "d-flex gap-2",
                    downloadButton(ns("dl_importance"), "CSV", class = "btn-sm btn-outline-secondary"))),
      div(style = "padding: 5px;", plotOutput(ns("varimp"), height = "460px"))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "bg-light", "Precision / Recall / F1 (OOB)"),
        div(style = "padding: 5px;", DTOutput(ns("prf_dt")))
      ),
      card(
        card_header(class = "bg-light", "OOB Validation Confusion Matrix"),
        div(style = "height: 260px; padding: 5px;", plotOutput(ns("oob_conf_plot"), height = "240px")),
        div(style = "padding: 5px 10px;", tags$b(textOutput(ns("oob_val_acc"))))
      )
    ),
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Partial Dependence Plots (PDP)"),
      div(class = "d-flex align-items-end gap-2",
          selectInput(ns("pdp_var"), "Select Predictor for PDP:", choices = NULL),
          div(style = "margin-bottom: 16px;", actionButton(ns("run_pdp"), "Generate PDP", class = "btn-info"))
      ),
      div(style = "padding: 5px;", plotOutput(ns("pdp_plot"), height = "400px"))
    )
  )
}

rfServer <- function(id, dataset_pool, active_dataset) {
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
      cols <- names(df)
      updateSelectInput(session, "target", choices = cols, selected = isolate(input$target))
      updatePickerInput(session, "predictors", choices = cols, selected = isolate(input$predictors))
      updateSelectInput(session, "pdp_var", choices = cols, selected = isolate(input$pdp_var))
    })

    rf_model_obj <- reactiveVal(NULL)

    observeEvent(input$run, {
      req(active_dataset(), input$target, input$predictors)
      df <- active_data()
      valid_cols <- c(input$target, input$predictors)
      df <- df[complete.cases(df[, valid_cols, drop = FALSE]), ]
      if (nrow(df) < 5) {
        showNotification("Not enough complete rows to train Random Forest.", type = "error")
        return()
      }
      # Backtick-quote every name so columns with digits/dots/spaces (e.g. VMI
      # codes) don't break formula parsing ("unexpected input" error).
      form_str <- paste0("`", input$target, "` ~ ",
                         paste(sprintf("`%s`", input$predictors), collapse = " + "))
      withProgress(message = 'Training Random Forest...', value = 0, {
        tryCatch({
          incProgress(0.5, detail = paste(input$ntree, "trees"))
          p <- length(input$predictors)
          default_mtry <- if (is.numeric(df[[input$target]])) max(floor(p / 3), 1) else floor(sqrt(p))
          rf_fit <- randomForest::randomForest(as.formula(form_str), data = df, ntree = input$ntree, mtry = default_mtry, importance = TRUE)
          cv_res <- NULL
          if (input$run_cv) {
            incProgress(0.8, detail = "Running 10-fold CV")
            cv_res <- randomForest::rfcv(df[, input$predictors, drop = FALSE], df[[input$target]], cv.fold = 10)
          }
          rf_model_obj(list(model = rf_fit, data = df, cv = cv_res, target = input$target))
          showNotification("Random Forest trained successfully!", type = "message")
        }, error = function(e) {
          showNotification(paste("Error training RF:", e$message), type = "error")
        })
      })
    })

    output$summary <- renderPrint({
      obj <- rf_model_obj()
      if (is.null(obj)) return(cat("Awaiting model training..."))
      op <- options(width = 1000)
      on.exit(options(op))
      print(obj$model)
      if (!is.null(obj$cv)) {
        cat("\n\n--- 10-Fold CV Error by Number of Variables ---\n")
        print(obj$cv$error.cv)
      }
      cat("\n--- Prediction Accuracy (OOB) ---\n")
      tryCatch({
        if (obj$model$type == "regression") {
          oob_pred <- obj$model$predicted
          obs      <- obj$data[[obj$target]]
          keep     <- !is.na(oob_pred)
          m        <- uef_evaluation(oob_pred[keep], obs[keep])
          cat(sprintf("RMSE   : %.4f\nR²     : %.4f\nBias   : %.4f\nRelBias: %.4f\nRRMSE  : %.4f\n",
                      m$RMSE, m$R2, m$Bias, m$RelBias, m$RRMSE))
        } else {
          oob_err <- obj$model$err.rate[obj$model$ntree, "OOB"]
          cat(sprintf("OOB Classification Error: %.4f  (Accuracy: %.4f)\n", oob_err, 1 - oob_err))
          cat("RMSE/Bias/RRMSE are not applicable for classification targets.\n")
        }
      }, error = function(e) cat("Metrics error:", e$message, "\n"))
    })

    output$prf_dt <- renderDT({
      obj <- rf_model_obj()
      if (is.null(obj)) return(DT::datatable(data.frame(Message = "Train a model first.")))
      tryCatch({
        mdl <- obj$model
        if (mdl$type == "regression") {
          oob_pred <- mdl$predicted
          obs      <- obj$data[[obj$target]]
          keep     <- !is.na(oob_pred)
          m <- uef_evaluation(oob_pred[keep], obs[keep])
          .reg_metrics_dt(list(`OOB (≈LOOCV)` = list(
            RMSE = m$RMSE, MAE = round(mean(abs(obs[keep] - oob_pred[keep])), 4),
            R2 = m$R2, RRMSE = m$RRMSE, Bias = m$Bias, RelBias = m$RelBias
          )))
        } else {
          actual    <- obj$data[[obj$target]]
          oob_preds <- mdl$predicted
          keep      <- !is.na(oob_preds)
          acc       <- 1 - mdl$err.rate[mdl$ntree, "OOB"]
          .prf_dt(.clf_prf(as.character(actual[keep]),
                           as.character(oob_preds[keep])), acc)
        }
      }, error = function(e) DT::datatable(data.frame(Error = e$message)))
    })

    output$oob_conf_plot <- renderPlot({
      obj <- rf_model_obj()
      if (is.null(obj)) { show_placeholder("Train a model first."); return() }
      mdl <- obj$model
      if (mdl$type != "classification") {
        show_placeholder("OOB Validation CM only available for classification targets.")
        return()
      }
      oob_preds <- mdl$predicted
      actual    <- obj$data[[obj$target]]
      keep      <- !is.na(oob_preds)
      cm <- table(Predicted = as.character(oob_preds[keep]),
                  Actual    = as.character(actual[keep]))
      print(.plot_conf_matrix(cm, title = "OOB Validation Confusion Matrix"))
    })

    output$oob_val_acc <- renderText({
      obj <- rf_model_obj()
      if (is.null(obj) || obj$model$type != "classification") return("")
      acc <- (1 - obj$model$err.rate[obj$model$ntree, "OOB"]) * 100
      paste("OOB Accuracy:", round(acc, 2), "%")
    })

    varimp_fn <- function() {
      obj <- rf_model_obj()
      if (is.null(obj)) { show_placeholder("Train a model to see variable importance."); return() }
      randomForest::varImpPlot(obj$model, main = paste("Variable Importance for", obj$target))
    }
    output$varimp <- renderPlot({ varimp_fn() })
    output$dl_importance <- downloadHandler(
      filename = function() paste0("rf_importance_", Sys.Date(), ".csv"),
      content  = function(file) {
        obj <- rf_model_obj(); req(!is.null(obj))
        imp <- as.data.frame(randomForest::importance(obj$model))
        imp <- cbind(variable = rownames(imp), imp)
        write.csv(imp, file, row.names = FALSE)
      }
    )
    

    pdp_plot_obj <- reactiveVal(NULL)

    observeEvent(input$run_pdp, {
      req(rf_model_obj(), input$pdp_var)
      obj <- rf_model_obj()
      if (!(input$pdp_var %in% rownames(obj$model$importance))) {
        showNotification("Selected variable is not a predictor in the model.", type = "error")
        return()
      }
      withProgress(message = 'Generating PDP...', detail = input$pdp_var, value = 0.5, {
        tryCatch({
          p <- pdp::partial(obj$model, pred.var = input$pdp_var, train = obj$data)
          p_plot <- pdp::plotPartial(p, main = paste("Partial Dependence on", input$pdp_var))
          pdp_plot_obj(p_plot)
        }, error = function(e) {
          showNotification(paste("Error generating PDP:", e$message), type = "error")
        })
      })
    })

    output$pdp_plot <- renderPlot({
      p <- pdp_plot_obj()
      if (is.null(p)) { show_placeholder("Select a predictor and click 'Generate PDP'."); return() }
      print(p)
    })
    

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        obj <- rf_model_obj()
        if (is.null(obj)) return("Random Forest — not trained yet.")
        paste0("Random Forest. Target: ", obj$target, "\n\n",
               paste(utils::capture.output(print(obj$model)), collapse = "\n"))
      }),
      plot = function() varimp_fn()
    )
  })
}
