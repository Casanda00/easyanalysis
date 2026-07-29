# mod_gam.R — Generalized Additive Models (GAM)
# Fits mgcv::gam with smooth terms; compares to lm; visualises smooths.
# Also supports full multi-predictor GAM (e.g. reflectance ~ s(dist) + s(angle) + s(cc)).
# Mirrors the exercise workflow: lm vs GAM adj.R² comparison → plot smooths → interpret.

.GAM_VIEWS <- c(smooth_plots = "Smooth Plots", model_comparis = "Model Comparison", gam_summary = "GAM Summary", cv_metrics = "CV & Metrics")
.GAM_VIEWS_PLOT <- c("smooth_plots")  # views whose body actually renders a plot


gamCanvasUI <- function(id) {
  ns <- NS(id)
  # Select-and-split (helpers.R): one selection fills the area, several split it.
  card(
    card_header(ea_view_header(ns, .GAM_VIEWS)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

gamToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    open = "Data",
    accordion_panel("Data",
      uiOutput(ns("response_ui")),
      uiOutput(ns("predictors_ui"))
    ),
    accordion_panel("GAM Options",
      numericInput(ns("k_basis"), "Basis dimension k (smoothness)",
                   value=10, min=3, max=50, step=1),
      selectInput(ns("smooth_type"), "Smooth type",
        choices=c("Thin-plate spline (default)"="tp",
                  "Cubic regression spline"="cr",
                  "P-spline"="ps"),
        selected="tp"),
      selectInput(ns("method"), "Estimation method",
        choices=c("REML (recommended)"="REML","GCV.Cp"="GCV.Cp","ML"="ML"),
        selected="REML"),
      hr(class="my-2"),
      checkboxInput(ns("auto_screen"),
                    "Auto-screen: only show smooths where GAM gain > 0.1 adj.R²",
                    value=FALSE),
      .cv_ui(ns),
      actionButton(ns("run_btn"), tagList(icon("play"), " Fit GAM"),
                   class="btn-success w-100")
    ),
    accordion_panel("Export",
      downloadButton(ns("dl_comp"), tagList(icon("table"),    " Comparison CSV"),
                     class="btn-sm btn-outline-secondary w-100"),
      actionButton(ns("to_pool"),   tagList(icon("database"), " Predictions to Data Pool"),
                   class="btn-sm btn-outline-primary w-100 mt-1")
    )
  )
}

gamServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- names(.GAM_VIEWS)[1]
      if (any(picked %in% .GAM_VIEWS_PLOT)) ea_plot_appearance()
    })
    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .GAM_VIEWS, function(k, solo) switch(k,
        smooth_plots = tagList(plotOutput(ns("smooth_plot"), height = if (solo) "80vh" else "100%")),
        model_comparis = tagList(div(class = "p-3",
        h5("lm vs GAM — Adjusted R²"),
        DT::DTOutput(ns("comparison_tbl")),
        hr(),
        uiOutput(ns("gain_summary_ui"))
      )),
        gam_summary = tagList(div(class = "p-3 overflow-auto",
        verbatimTextOutput(ns("gam_summary"))
      )),
        cv_metrics = tagList(div(class = "p-3 overflow-auto",
        verbatimTextOutput(ns("cv_metrics_out"))
      )),
        NULL))
    })

    ns <- session$ns

    rv <- reactiveValues(
      gam_model   = NULL,
      lm_model    = NULL,
      comparison  = NULL,   # data.frame with lm_adj_r2, gam_r2, gain
      pred_df     = NULL
    )

    # ---- Active dataset (from left rail, same as all other modules) ----------
    .df <- reactive({
      d <- active_dataset()
      if (is.null(d)) return(NULL)
      if (inherits(d, "sf")) sf::st_drop_geometry(d) else as.data.frame(d)
    })

    .num_cols <- reactive({
      df <- .df()
      if (is.null(df)) return(character(0))
      names(df)[sapply(df, is.numeric)]
    })

    # ---- Package check ------------------------------------------------------
    .has_mgcv <- function() {
      if (!requireNamespace("mgcv", quietly=TRUE)) {
        showNotification("Package 'mgcv' not installed. Run: install.packages('mgcv')",
                         type="error", duration=8)
        return(FALSE)
      }
      TRUE
    }

    output$response_ui <- renderUI({
      cols <- .num_cols()
      if (!length(cols)) return(NULL)
      selectInput(ns("response"), "Response variable (Y)", choices=cols)
    })

    output$predictors_ui <- renderUI({
      cols  <- .num_cols()
      resp  <- input$response %||% ""
      avail <- setdiff(cols, resp)
      if (!length(avail)) return(NULL)
      selectizeInput(ns("predictors"), "Predictor variables (X)",
                     choices=avail, selected=head(avail, 4), multiple=TRUE,
                     options=list(placeholder="Select predictors…"))
    })

    # ---- Fit GAM ------------------------------------------------------------
    observeEvent(input$run_btn, {
      if (!.has_mgcv()) return()
      df   <- .df()
      resp <- input$response   %||% ""
      preds <- input$predictors %||% character(0)
      req(!is.null(df), nzchar(resp), length(preds) > 0)

      df_m <- df[, c(resp, preds), drop=FALSE]
      df_m <- df_m[complete.cases(df_m), , drop=FALSE]
      req(nrow(df_m) > 10)

      k   <- max(3L, min(as.integer(input$k_basis %||% 10), nrow(df_m) - 2L))
      bs  <- input$smooth_type %||% "tp"
      mth <- input$method %||% "REML"

      withProgress(message="Fitting GAM…", value=0.2, {

        # Linear model for comparison
        lm_fml <- as.formula(paste0("`", resp, "` ~ ", paste0("`", preds, "`", collapse="+")))
        lm_mdl <- tryCatch(lm(lm_fml, data=df_m), error=function(e) NULL)
        rv$lm_model <- lm_mdl
        lm_adj_r2 <- if (!is.null(lm_mdl)) summary(lm_mdl)$adj.r.squared else NA_real_

        # GAM with s() for each predictor (backtick names for odd column names)
        s_terms <- paste0("mgcv::s(`", preds, "`, k=", k, ", bs='", bs, "')", collapse=" + ")
        gam_fml <- as.formula(paste0("`", resp, "` ~ ", s_terms))
        gam_mdl <- tryCatch(
          mgcv::gam(gam_fml, data=df_m, method=mth),
          error=function(e) { showNotification(e$message, type="error"); NULL }
        )
        if (is.null(gam_mdl)) return()
        rv$gam_model <- gam_mdl
        setProgress(0.7)

        gam_r2 <- summary(gam_mdl)$r.sq

        # Per-predictor comparison (one predictor at a time vs response)
        comp_rows <- lapply(preds, function(p) {
          df_p  <- df_m[, c(resp, p), drop=FALSE]
          lm_p  <- tryCatch(lm(as.formula(paste(resp,"~",p)), data=df_p),
                            error=function(e) NULL)
          gam_p <- tryCatch(
            mgcv::gam(as.formula(paste0(resp,"~mgcv::s(",p,",k=",k,",bs='",bs,"')")),
                      data=df_p, method=mth),
            error=function(e) NULL
          )
          lm_r2  <- if (!is.null(lm_p))  summary(lm_p)$adj.r.squared else NA_real_
          gam_r2 <- if (!is.null(gam_p)) summary(gam_p)$r.sq          else NA_real_
          gain   <- gam_r2 - lm_r2
          data.frame(Predictor=p, lm_adj_R2=round(lm_r2,4),
                     GAM_R2=round(gam_r2,4), Gain=round(gain,4),
                     Nonlinear=ifelse(!is.na(gain) & gain > 0.1, "Yes", "No"),
                     stringsAsFactors=FALSE)
        })
        rv$comparison <- do.call(rbind, comp_rows)

        # Predicted values
        rv$pred_df <- data.frame(
          observed  = df_m[[resp]],
          lm_pred   = if (!is.null(lm_mdl)) predict(lm_mdl) else NA_real_,
          gam_pred  = predict(gam_mdl)
        )

        setProgress(1)
        showNotification(
          paste0("GAM fitted. Full-model R² = ", round(gam_r2,4),
                 "  (lm adj.R² = ", round(lm_adj_r2,4), ")"),
          type="message", duration=5)
      })
    })

    # ---- Smooth plots -------------------------------------------------------
    output$smooth_plot <- renderPlot({
      gam_mdl <- rv$gam_model
      if (is.null(gam_mdl)) {
        plot.new()
        text(0.5, 0.5, "Fit a GAM first.", cex=1.4, col="grey50")
        return()
      }
      preds <- input$predictors %||% character(0)
      auto  <- input$auto_screen %||% FALSE
      comp  <- rv$comparison

      show_preds <- preds
      if (auto && !is.null(comp)) {
        show_preds <- comp$Predictor[comp$Nonlinear == "Yes"]
        if (!length(show_preds)) {
          plot.new()
          text(0.5, 0.5, "No smooth shows nonlinear gain > 0.10 adj.R².", cex=1.2, col="grey50")
          return()
        }
      }
      n <- length(show_preds)
      par(mfrow=c(ceiling(n/2), min(n,2)), mar=c(4,4,3,1))
      tryCatch({
        # Build minimal GAM for each predictor to draw individual smooth
        df_m <- tryCatch(.df(), error=function(e) NULL)
        resp <- input$response %||% ""
        k    <- max(3L, as.integer(input$k_basis %||% 10))
        bs   <- input$smooth_type %||% "tp"
        mth  <- input$method %||% "REML"
        if (is.null(df_m) || !nzchar(resp)) { mgcv::plot.gam(gam_mdl, pages=1, residuals=TRUE); return() }
        df_m <- df_m[, c(resp, show_preds), drop=FALSE]
        df_m <- df_m[complete.cases(df_m), , drop=FALSE]
        for (p in show_preds) {
          df_p  <- df_m[, c(resp, p), drop=FALSE]
          gam_p <- tryCatch(
            mgcv::gam(as.formula(paste0(resp,"~mgcv::s(",p,",k=",k,",bs='",bs,"')")),
                      data=df_p, method=mth),
            error=function(e) NULL)
          if (is.null(gam_p)) next
          lm_p  <- tryCatch(lm(as.formula(paste(resp,"~",p)), data=df_p), error=function(e) NULL)
          lm_r2 <- if (!is.null(lm_p)) round(summary(lm_p)$adj.r.squared, 3) else NA
          g_r2  <- round(summary(gam_p)$r.sq, 3)
          mgcv::plot.gam(gam_p, residuals=TRUE, pch=16, cex=0.4, shade=TRUE,
                         shade.col="#2e7d3233",
                         main=paste0(p, " → ", resp,
                                     "   lm adj.R²=", lm_r2, "  GAM R²=", g_r2),
                         xlab=p, ylab=paste("s(", p, ")"))
          if (!is.null(lm_p)) {
            x_seq <- seq(min(df_p[[p]], na.rm=TRUE), max(df_p[[p]], na.rm=TRUE), length.out=200)
            abline(lm_p, col="#1b5e20", lty=2, lwd=1.5)
          }
        }
      }, error=function(e) { plot.new(); text(0.5,0.5,e$message,col="red") })
    })

    # ---- Comparison table ---------------------------------------------------
    output$comparison_tbl <- DT::renderDT({
      comp <- rv$comparison
      if (is.null(comp)) return(DT::datatable(data.frame(), options=list(dom="t")))
      DT::datatable(comp, rownames=FALSE,
        options=list(dom="t", pageLength=20),
        selection="none") %>%
        DT::formatStyle("Nonlinear",
          backgroundColor = DT::styleEqual(c("Yes","No"),c("#c8e6c9","#fff9c4")))
    })

    output$gain_summary_ui <- renderUI({
      comp <- rv$comparison
      if (is.null(comp)) return(NULL)
      nl <- comp[comp$Nonlinear == "Yes", "Predictor"]
      if (!length(nl))
        return(p(class="text-muted", "No predictor shows a substantial nonlinear effect (GAM gain > 0.10)."))
      div(class="alert alert-success p-2",
        icon("chart-line"), " ",
        strong("Nonlinear relationships detected for: "),
        paste(nl, collapse=", "), ".",
        " The GAM smooth explains substantially more variance than a straight line for these predictors."
      )
    })

    # ---- GAM summary text ---------------------------------------------------
    output$gam_summary <- renderPrint({
      req(rv$gam_model)
      print(summary(rv$gam_model))
    })

    # ---- CV & metrics -------------------------------------------------------
    output$cv_metrics_out <- renderPrint({
      gam_mdl <- rv$gam_model; req(!is.null(gam_mdl))
      df_cv   <- rv$pred_df;   req(!is.null(df_cv))
      tryCatch({
        yv  <- gam_mdl$formula[[2]]
        obs <- df_cv[["observed"]]
        prd <- df_cv[["gam_pred"]]
        e   <- obs - prd
        cat("=== GAM Training Metrics ===\n")
        cat(sprintf("GCV score  : %.6f  (in-built penalised CV)\n",
                    gam_mdl$gcv.ubre))
        cat(sprintf("Train RMSE : %.4f\nTrain MAE  : %.4f\nTrain R²   : %.4f\n\n",
                    sqrt(mean(e^2, na.rm=TRUE)), mean(abs(e), na.rm=TRUE),
                    summary(gam_mdl)$r.sq))
        preds <- input$predictors; yvar <- input$response
        req(isTruthy(preds), isTruthy(yvar), length(preds) >= 1)
        df0  <- .df()
        k_b  <- max(3L, as.integer(input$k_basis %||% 4))
        req(!is.null(df0))
        sub  <- df0[, c(yvar, preds), drop=FALSE]
        sub  <- sub[complete.cases(sub),, drop=FALSE]
        req(nrow(sub) >= 20)
        n <- nrow(sub); cv_k_val <- .cv_k(input, sub)
        lbl <- .cv_label(cv_k_val, n)
        cat(sprintf("=== %s ===\n", lbl))
        set.seed(42)
        folds <- sample(rep_len(seq_len(cv_k_val), n))
        all_p <- c(); all_a <- c()
        for (fold in seq_len(cv_k_val)) {
          tr <- sub[folds!=fold,,drop=FALSE]; te <- sub[folds==fold,,drop=FALSE]
          fml_cv <- as.formula(paste(yvar, "~",
                    paste(sprintf("s(%s, k=%d)", preds, k_b), collapse="+")))
          m <- tryCatch(mgcv::gam(fml_cv, data=tr, method="REML"),
                        error=function(e) NULL)
          if (is.null(m)) next
          p <- tryCatch(as.numeric(predict(m, newdata=te)), error=function(e) NULL)
          if (is.null(p)) next
          all_p <- c(all_p, p); all_a <- c(all_a, as.numeric(te[[yvar]]))
        }
        if (length(all_p) > 0) {
          e2 <- all_a - all_p
          cat(sprintf("CV RMSE : %.4f\nCV MAE  : %.4f\nCV R²   : %.4f\n",
                      sqrt(mean(e2^2)), mean(abs(e2)),
                      1-sum(e2^2)/sum((all_a-mean(all_a))^2)))
        } else {
          cat("CV failed (fold models did not converge).\n")
        }
      }, error=function(e) cat("CV error:", e$message, "\n"))
    })

    # ---- Downloads ----------------------------------------------------------
    output$dl_comp <- downloadHandler(
      filename = function() paste0("gam_comparison_", Sys.Date(), ".csv"),
      content  = function(f) {
        comp <- rv$comparison
        write.csv(if (!is.null(comp)) comp else data.frame(), f, row.names=FALSE)
      }
    )

    

    observeEvent(input$to_pool, {
      req(!is.null(rv$pred_df))
      nm <- paste0("gam_predictions_", format(Sys.time(),"%H%M%S"))
      dataset_pool[[nm]] <- rv$pred_df
      showNotification(paste0("'", nm, "' with observed/lm_pred/gam_pred added to Data Pool."),
                       type="message", duration=4)
    })

    list(
      context = reactive({
        mdl <- rv$gam_model
        if (is.null(mdl)) return(list())
        s <- summary(mdl)
        list(model="gam", r_sq=round(s$r.sq,4), response=input$response %||% "")
      }),
      plot = function() {
        gam_mdl <- rv$gam_model
        if (is.null(gam_mdl)) return(NULL)
        tryCatch({
          mgcv::plot.gam(gam_mdl, pages=1, residuals=TRUE)
          recordPlot()
        }, error=function(e) NULL)
      }
    )
  })
}
