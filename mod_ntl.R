# mod_ntl.R — Night-time Lights Spatial Regression
# Fit OLS on spatial vector attributes; visualise measured / predicted / residual maps.
# Mirrors the exercise workflow: correlation → VIF → lm → spatial maps.

ntlCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(full_screen = TRUE,
    nav_panel("Spatial Maps",
      leafletOutput(ns("map"), width = "100%", height = "100%")
    ),
    nav_panel("Scatterplots",
      # Wrapped in a card purely so there is a header to hang the appearance
      # control on. It is a multi-panel figure (one panel per predictor), so per
      # helpers.R only an overall title applies -- axis labels and colour are
      # per-panel and are not read from the store.
      card(
        card_header(class = "d-flex justify-content-between align-items-center",
          "Response vs predictors", ea_plot_appearance(fields = "title")),
        plotOutput(ns("scatter"), height = "80vh")
      )
    ),
    nav_panel("Model Summary",
      div(class = "p-3 overflow-auto",
        h5("Pearson Correlation Matrix"),
        verbatimTextOutput(ns("corr_out")),
        h5(class = "mt-3", "VIF (Variance Inflation Factors)"),
        verbatimTextOutput(ns("vif_out")),
        h5(class = "mt-3", "Linear Model Summary"),
        verbatimTextOutput(ns("lm_out")),
        h5(class = "mt-3", "Evaluation Metrics"),
        uiOutput(ns("metrics_ui"))
      )
    )
  )
}

ntlToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    open = "Data",
    accordion_panel("Data",
      uiOutput(ns("src_ui")),
      p(class = "text-muted small", "Upload shapefiles via the global Add Data button."),
      hr(class = "my-2"),
      uiOutput(ns("response_ui")),
      uiOutput(ns("predictors_ui"))
    ),
    accordion_panel("Options",
      checkboxInput(ns("scale_vars"), "Scale predictors before fitting", value = TRUE),
      actionButton(ns("run_btn"), tagList(icon("play"), " Run Spatial Regression"),
                   class = "btn-success w-100")
    ),
    accordion_panel("Map Layer",
      uiOutput(ns("map_layer_ui"))
    ),
    accordion_panel("Export",
      downloadButton(ns("dl_csv"),  tagList(icon("table"),    " Predictions CSV"),
                     class = "btn-sm btn-outline-secondary w-100"),
      downloadButton(ns("dl_gpkg"), tagList(icon("map"),      " Spatial results (.gpkg)"),
                     class = "btn-sm btn-outline-secondary w-100 mt-1"),
      actionButton(ns("to_pool"),   tagList(icon("database"), " Send to Data Pool"),
                   class = "btn-sm btn-outline-primary w-100 mt-1")
    )
  )
}

ntlServer <- function(id, dataset_pool, active_dataset, vector_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      sf_data   = NULL,
      result_sf = NULL,
      lm_model  = NULL,
      corr      = NULL,
      vif_vals  = NULL,
      metrics   = NULL,
      map_layer = "measured"
    )

    # ---- Source selector ----------------------------------------------------
    output$src_ui <- renderUI({
      vp <- if (!is.null(vector_pool)) names(reactiveValuesToList(vector_pool)) else character(0)
      dp <- names(reactiveValuesToList(dataset_pool))
      ch <- c("(select data source)" = "")
      if (length(vp)) ch <- c(ch, setNames(paste0("v:", vp), paste0("[shapefile] ", vp)))
      if (length(dp)) ch <- c(ch, setNames(paste0("d:", dp), paste0("[table] ",    dp)))
      selectInput(ns("src"), "Data source", choices = ch)
    })

    observeEvent(input$src, {
      s <- input$src %||% ""
      if (!nzchar(s)) { rv$sf_data <- NULL; return() }
      if (startsWith(s, "v:")) {
        nm <- sub("^v:", "", s)
        rv$sf_data <- if (!is.null(vector_pool)) vector_pool[[nm]] else NULL
      } else if (startsWith(s, "d:")) {
        nm <- sub("^d:", "", s)
        rv$sf_data <- dataset_pool[[nm]]
      }
    })

    # ---- Variable selectors -------------------------------------------------
    .num_cols <- function() {
      d <- rv$sf_data
      if (is.null(d)) return(character(0))
      df <- if (inherits(d, "sf")) sf::st_drop_geometry(d) else as.data.frame(d)
      names(df)[sapply(df, is.numeric)]
    }

    output$response_ui <- renderUI({
      cols <- .num_cols()
      if (!length(cols)) return(NULL)
      selectInput(ns("response"), "Response variable (Y)", choices = cols)
    })

    output$predictors_ui <- renderUI({
      cols  <- .num_cols()
      resp  <- input$response %||% ""
      avail <- setdiff(cols, resp)
      if (!length(avail)) return(NULL)
      selectizeInput(ns("predictors"), "Predictor variables (X)",
                     choices = avail, selected = avail, multiple = TRUE,
                     options = list(placeholder = "Select predictors…"))
    })

    # ---- Correlation helper (Hmisc or base) --------------------------------
    .rcorr <- function(mat) {
      if (requireNamespace("Hmisc", quietly = TRUE))
        return(Hmisc::rcorr(mat, type = "pearson"))
      n <- ncol(mat)
      r <- cor(mat, use = "pairwise.complete.obs")
      P <- matrix(NA_real_, n, n, dimnames = dimnames(r))
      for (i in seq_len(n)) for (j in seq_len(n)) {
        if (i != j)
          P[i, j] <- tryCatch(cor.test(mat[,i], mat[,j], method="pearson")$p.value,
                               error = function(e) NA_real_)
      }
      list(r = r, P = P)
    }

    # ---- Run model ----------------------------------------------------------
    observeEvent(input$run_btn, {
      d     <- rv$sf_data
      resp  <- input$response   %||% ""
      preds <- input$predictors %||% character(0)
      req(!is.null(d), nzchar(resp), length(preds) > 0)

      df_full <- if (inherits(d, "sf")) sf::st_drop_geometry(d) else as.data.frame(d)
      req(resp %in% names(df_full))
      preds <- intersect(preds, names(df_full))
      req(length(preds) > 0)

      withProgress(message = "Fitting spatial regression…", value = 0.2, {

        df_m <- df_full[, c(resp, preds), drop = FALSE]
        df_m <- df_m[complete.cases(df_m), , drop = FALSE]

        # Correlation
        rv$corr <- tryCatch(.rcorr(as.matrix(df_m[, c(resp, preds)])),
                            error = function(e) NULL)

        # Scale predictors on training set if requested
        scale_info <- list()
        if (input$scale_vars) {
          for (p in preds) {
            mu <- mean(df_m[[p]], na.rm = TRUE)
            sg <- sd(df_m[[p]],   na.rm = TRUE)
            scale_info[[p]] <- c(mu, sg)
            df_m[[p]] <- (df_m[[p]] - mu) / max(sg, 1e-10)
          }
        }

        # Fit model
        fml <- as.formula(paste(resp, "~", paste(preds, collapse = " + ")))
        mdl <- tryCatch(lm(fml, data = df_m), error = function(e) NULL)
        if (is.null(mdl)) { showNotification("Model failed.", type="error"); return() }
        rv$lm_model <- mdl
        setProgress(0.5)

        # VIF
        rv$vif_vals <- if (length(preds) > 1)
          tryCatch(car::vif(mdl), error = function(e) NULL)
        else NULL

        # Predict on full data
        df_pred <- df_full[, c(resp, preds), drop = FALSE]
        if (input$scale_vars && length(scale_info)) {
          for (p in preds) {
            si <- scale_info[[p]]
            df_pred[[p]] <- (df_pred[[p]] - si[1]) / max(si[2], 1e-10)
          }
        }
        pred_vals <- tryCatch(predict(mdl, newdata = df_pred), error = function(e) NA_real_)
        resid_vals <- df_full[[resp]] - pred_vals
        sd_r <- sd(resid_vals, na.rm = TRUE)

        # Metrics
        obs_vals <- df_full[[resp]]
        rv$metrics <- tryCatch(uef_evaluation(pred_vals, obs_vals), error = function(e) NULL)

        # Write back to sf
        if (inherits(d, "sf")) {
          out <- d
          out$ntl_pred      <- pred_vals
          out$ntl_resid     <- resid_vals
          out$ntl_std_resid <- resid_vals / max(sd_r, 1e-10)
          rv$result_sf <- out
        }
        setProgress(1)
        showNotification("Regression complete.", type="message", duration=3)
      })
    })

    # ---- Map layer selector -------------------------------------------------
    output$map_layer_ui <- renderUI({
      req(inherits(rv$result_sf, "sf"))
      selectInput(ns("map_lyr"), "Display",
        choices = c("Measured"="measured","Predicted"="predicted",
                    "Standardised residuals"="std_resid"),
        selected = rv$map_layer)
    })
    observeEvent(input$map_lyr, { rv$map_layer <- input$map_lyr %||% "measured" })

    # ---- Leaflet map --------------------------------------------------------
    output$map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("OpenStreetMap",     group="OSM") %>%
        addProviderTiles("Esri.WorldImagery", group="Satellite") %>%
        addLayersControl(baseGroups=c("OSM","Satellite"),
                         options=layersControlOptions(collapsed=TRUE)) %>%
        setView(lng=25.7, lat=62.5, zoom=5)
    })
    outputOptions(output, "map", suspendWhenHidden=FALSE)

    observe({
      sf_d <- rv$result_sf
      lyr  <- rv$map_layer
      req(inherits(sf_d, "sf"))

      resp_col <- input$response %||% ""
      col_nm   <- switch(lyr,
        measured  = resp_col,
        predicted = "ntl_pred",
        std_resid = "ntl_std_resid"
      )
      if (!nzchar(col_nm %||% "") || !col_nm %in% names(sf_d)) return()

      v_wgs <- tryCatch(sf::st_transform(sf_d, 4326), error=function(e) NULL)
      if (is.null(v_wgs)) return()
      vals <- v_wgs[[col_nm]]

      if (lyr == "std_resid") {
        v_clamp <- pmax(pmin(vals, 2.5), -2.5)
        pal <- leaflet::colorNumeric(c("blue","white","red"), c(-2.5, 2.5), na.color="#ccc")
        leg_vals <- v_clamp
      } else {
        v_clamp  <- vals
        pal      <- leaflet::colorNumeric("plasma", vals, na.color="#ccc")
        leg_vals <- vals
      }

      # Popup
      popup_html <- paste0(
        "<b>", col_nm, ":</b> ", round(vals, 4),
        if (lyr != "measured" && nzchar(resp_col) && resp_col %in% names(v_wgs))
          paste0("<br><b>Measured:</b> ", round(v_wgs[[resp_col]], 4))
        else ""
      )

      bbox <- as.numeric(sf::st_bbox(v_wgs))
      leafletProxy("map", session=session) %>%
        clearShapes() %>% clearControls() %>%
        addPolygons(data=v_wgs, fillColor=pal(v_clamp), fillOpacity=0.8,
                    color="white", weight=0.5, popup=popup_html) %>%
        addLegend("bottomright", pal=pal, values=leg_vals,
                  title=col_nm, opacity=0.9) %>%
        fitBounds(bbox[1], bbox[2], bbox[3], bbox[4])
    })

    # ---- Scatterplots -------------------------------------------------------
    output$scatter <- renderPlot({
      d     <- rv$sf_data
      resp  <- input$response   %||% ""
      preds <- input$predictors %||% character(0)
      req(!is.null(d), nzchar(resp), length(preds) > 0)
      df <- if (inherits(d, "sf")) sf::st_drop_geometry(d) else as.data.frame(d)
      preds <- intersect(preds, names(df))
      req(nzchar(resp), resp %in% names(df), length(preds) > 0)
      n <- length(preds)
      ea_multi_par(mfrow=c(ceiling(n/2), min(n,2)), mar=c(4,4,2.5,1))
      for (p in preds) {
        if (!is.numeric(df[[p]]) || !is.numeric(df[[resp]])) next
        plot(df[[p]], df[[resp]], xlab=p, ylab=resp,
             main=paste(p, "vs", resp), pch=16, col="#2e7d3277", cex=0.7,
             cex.main=0.9)
        abline(lm(df[[resp]] ~ df[[p]], na.action=na.exclude), col="#1b5e20", lwd=1.5)
      }
      ea_fig_title()
    })

    # ---- Outputs ------------------------------------------------------------
    output$corr_out <- renderPrint({
      req(rv$corr)
      cat("Correlation coefficients (Pearson):\n")
      print(round(rv$corr$r, 3))
      cat("\nP-values:\n")
      print(round(rv$corr$P, 4))
    })

    output$vif_out <- renderPrint({
      vf <- rv$vif_vals
      if (is.null(vf)) { cat("VIF needs 2+ predictors."); return() }
      cat("VIF (>5 = moderate, >10 = serious multicollinearity):\n")
      print(round(vf, 3))
    })

    output$lm_out <- renderPrint({
      req(rv$lm_model)
      print(summary(rv$lm_model))
    })

    output$metrics_ui <- renderUI({
      m <- rv$metrics
      if (is.null(m)) return(NULL)
      tagList(
        div(class="row row-cols-2 g-2 mt-1",
          lapply(names(m), function(k)
            div(class="col",
              div(class="card card-body p-2 text-center",
                div(class="small text-muted", k),
                div(class="fw-bold fs-6", round(m[[k]], 4))
              )
            )
          )
        ),
        tags$hr(class="my-2"),
        tags$h6("LOOCV (hat-matrix, exact)", class="mt-2 mb-1 small text-muted text-uppercase"),
        verbatimTextOutput(ns("loocv_ntl_out"))
      )
    })

    output$loocv_ntl_out <- renderPrint({
      mdl <- rv$lm_model
      if (is.null(mdl)) { cat("Awaiting model.\n"); return() }
      tryCatch({
        cv <- .loocv_lm(mdl)
        cat(sprintf("LOOCV RMSE : %.4f\nLOOCV MAE  : %.4f\nLOOCV R²   : %.4f\n",
                    cv$LOOCV_RMSE, cv$LOOCV_MAE, cv$LOOCV_R2))
      }, error=function(e) cat("LOOCV error:", e$message, "\n"))
    })

    # ---- Downloads ----------------------------------------------------------
    output$dl_csv <- downloadHandler(
      filename = function() paste0("ntl_predictions_", Sys.Date(), ".csv"),
      content  = function(f) {
        req(!is.null(rv$result_sf))
        df_out <- if (inherits(rv$result_sf, "sf")) sf::st_drop_geometry(rv$result_sf)
                  else as.data.frame(rv$result_sf)
        write.csv(df_out, f, row.names=FALSE)
      }
    )

    output$dl_gpkg <- downloadHandler(
      filename = function() paste0("ntl_spatial_", Sys.Date(), ".gpkg"),
      content  = function(f) {
        req(inherits(rv$result_sf, "sf"))
        out <- tryCatch(sf::st_transform(rv$result_sf, 4326), error=function(e) rv$result_sf)
        sf::st_write(out, f, driver="GPKG", delete_dsn=TRUE, quiet=TRUE)
      }
    )

    observeEvent(input$to_pool, {
      req(!is.null(rv$result_sf))
      df_out <- if (inherits(rv$result_sf, "sf")) sf::st_drop_geometry(rv$result_sf)
                else as.data.frame(rv$result_sf)
      nm <- paste0("ntl_results_", format(Sys.time(), "%H%M%S"))
      dataset_pool[[nm]] <- df_out
      showNotification(paste0("'", nm, "' added to Data Pool — available in all model screens."),
                       type="message", duration=4)
    })

    list(
      context = reactive({
        mdl <- rv$lm_model
        if (is.null(mdl)) return(list())
        s <- summary(mdl)
        list(model="ntl_lm", r_sq=round(s$r.squared,4),
             adj_r_sq=round(s$adj.r.squared,4),
             response=input$response %||% "")
      }),
      plot = function() NULL
    )
  })
}
