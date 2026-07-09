# ==========================================================================
# MODULE: Spatial & LiDAR  (canvas + tools contract)
# Three menu views (pointcloud / chm_itd / metrics) share ONE rv_lidar state,
# so this is a single module: six UI fns (3 tools + 3 canvas) + one server.
#   lidarPointcloudToolsUI / lidarPointcloudCanvasUI
#   lidarChmToolsUI        / lidarChmCanvasUI
#   lidarMetricsToolsUI    / lidarMetricsCanvasUI
#   lidarServer(id, dataset_pool)
# Wire all six with the SAME id ("lidar"); the server binds once.
# Extracted plot metrics are written to dataset_pool so the left rail picks them up.
# ==========================================================================

# ---- Point Cloud & 3D ----
lidarPointcloudToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "LiDAR Pre-Processing"),
    tags$p(class = "text-muted small", "Upload LAS/LAZ files via ‘Add Data’ in the Datasets panel."),
    tags$hr(class = "my-2"),
    markdown("**Plot Shapefile**"),
    uiOutput(ns("shp_source_ui")),
    hr(),
    markdown("**Sub-setting & Memory Limits**"),
    numericInput(ns("clip_xmin"), "X Min:", value = NA),
    numericInput(ns("clip_xmax"), "X Max:", value = NA),
    numericInput(ns("clip_ymin"), "Y Min:", value = NA),
    numericInput(ns("clip_ymax"), "Y Max:", value = NA),
    actionButton(ns("clip_las"), "Clip LAS File", class = "btn-warning", width = "100%"),
    hr(),
    markdown("**Height Normalization (DTM)**"),
    sliderInput(ns("dtm_res"), "DTM Resolution:", min = 0.5, max = 5, value = 1, step = 0.5),
    actionButton(ns("run_norm"), "Normalize Height (Z)", class = "btn-primary", width = "100%"),
    hr(),
    markdown("**Outlier & Noise Filter**"),
    sliderInput(ns("int_max"), "Max Intensity Cutoff:", min = 100, max = 1000, value = 300, step = 50),
    actionButton(ns("run_filter"), "Filter Noise", class = "btn-primary", width = "100%"),
    hr(),
    markdown("**3D View Filters**"),
    tags$p(class = "text-muted small mb-1", "Filters are applied to the 3D viewer; original data is unchanged."),
    uiOutput(ns("filter_z_ui")),
    uiOutput(ns("filter_intensity_ui")),
    uiOutput(ns("filter_class_ui")),
    div(class = "d-flex gap-2 mt-1",
      actionButton(ns("apply_view_filters"), "Apply Filters", class = "btn-sm btn-primary flex-fill"),
      actionButton(ns("reset_view_filters"), "Reset", class = "btn-sm btn-outline-secondary"))
  )
}

lidarPointcloudCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    # Top row: basemap (left) side-by-side with 3D viewer (right)
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header(class = "bg-light", "LAS Location (Basemap)"),
        div(style = "height: 460px;",
            leafletOutput(ns("location_map"), width = "100%", height = "100%")),
        uiOutput(ns("manual_coords_ui"))
      ),
      card(
        card_header(class = "bg-light", "Interactive 3D Point Cloud Viewer"),
        rglwidgetOutput(ns("lidar_3d_viewer"), height = "460px")
      )
    ),
    # Headless static render: works on shinyapps.io (no WebGL screenshot needed),
    # is downloadable, and is the image the AI Co-Pilot can actually see.
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Static 3D Snapshot (download / AI view)",
                  downloadButton(ns("download_3d"), "Download Plot", class = "btn-sm btn-outline-success")),
      div(class = "d-flex align-items-center gap-2 px-2",
          sliderInput(ns("snap_pts"), "Max display points (both 3D viewers):", min = 10000, max = 200000, value = 60000, step = 10000, width = "320px")),
      plotOutput(ns("static_3d"), height = "430px")
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_header(class = "bg-light", "LAS Summary"), verbatimTextOutput(ns("las_summary"))),
      card(card_header(class = "d-flex justify-content-between align-items-center bg-light", "Elevation & Intensity Distributions",
                       downloadButton(ns("download_hists"), "Download Plot", class = "btn-sm btn-outline-success")),
           plotOutput(ns("las_hists")))
    )
  )
}

# ---- CHM & ITD ----
lidarChmToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "Canopy Height Model"),
    sliderInput(ns("chm_res"), "CHM Resolution:", min = 0.1, max = 2, value = 0.5, step = 0.1),
    textInput(ns("pitfree_thresh"), "Pitfree Thresholds (comma-sep):", value = "0, 5, 10, 15, 20, 25"),
    actionButton(ns("run_chm"), "Generate CHM", class = "btn-primary", width = "100%"),
    hr(),
    markdown("**Individual Tree Detection (ITD)**"),
    markdown("*LMF Window Size: `a + b * height^2`*"),
    numericInput(ns("lmf_a"), "Parameter a:", value = 1.2),
    numericInput(ns("lmf_b"), "Parameter b:", value = 0.003),
    actionButton(ns("run_itd"), "Detect Trees", class = "btn-primary", width = "100%")
  )
}

lidarChmCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(card_header(class = "d-flex justify-content-between align-items-center bg-light", "2D CHM & Detected Trees",
                     downloadButton(ns("download_chm"), "Download Plot", class = "btn-sm btn-outline-success")),
         plotOutput(ns("chm_plot"), height = "500px")),
    card(card_header(class = "bg-light", "ITD Output Table"), DT::dataTableOutput(ns("itd_table")))
  )
}

# ---- Metric Extraction & Evaluation ----
lidarMetricsToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "Area-Based & Model Evaluation"),
    actionButton(ns("extract_metrics"), "Extract Plot Metrics", class = "btn-primary", width = "100%"),
    hr(),
    markdown("**Evaluate Volume Models**"),
    selectInput(ns("eval_target"), "Observed Variable (e.g., v):", choices = NULL),
    selectInput(ns("eval_pred"), "Predicted Variable (e.g., v_itd):", choices = NULL),
    actionButton(ns("run_eval"), "Calculate Error Metrics", class = "btn-success", width = "100%")
  )
}

lidarMetricsCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(card_header(class = "bg-light", "Extracted Plot Predictors"), DT::dataTableOutput(ns("metrics_table"))),
    card(card_header(class = "d-flex justify-content-between align-items-center bg-light", "Model Evaluation (RMSE, Bias)",
                     downloadButton(ns("download_eval"), "Download Plot", class = "btn-sm btn-outline-success")),
         verbatimTextOutput(ns("eval_metrics_out")), plotOutput(ns("eval_plot")))
  )
}

lidarServer <- function(id, dataset_pool, las_pool = NULL, vector_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rv_lidar <- reactiveValues(raw_las = NULL, las = NULL, dtm = NULL, chm = NULL, tops = NULL, plot_shp = NULL, itd_metrics = NULL)

    # Auto-load newest LAS from the centralized las_pool (set by the global upload handler).
    if (!is.null(las_pool)) {
      observe({
        pool <- reactiveValuesToList(las_pool)
        if (length(pool) == 0) return()
        latest_nm <- tail(names(pool), 1)
        new_las   <- pool[[latest_nm]]
        if (!identical(rv_lidar$las, new_las)) {
          rv_lidar$las     <- new_las
          rv_lidar$raw_las <- NULL
          showNotification(paste0("LiDAR '", latest_nm, "' ready in Point Cloud view."), type = "message")
        }
      })
    }

    # ---- Plot shapefile: pick from vector_pool (uploaded via left rail "Add Data") ----
    output$shp_source_ui <- renderUI({
      nms <- if (!is.null(vector_pool)) {
        tryCatch(names(reactiveValuesToList(vector_pool)) %||% character(0), error = function(e) character(0))
      } else character(0)
      if (length(nms) == 0)
        return(tags$p(class = "text-muted small",
                      "No vector files loaded. Upload a shapefile (.shp) via Add Data in the Datasets panel."))
      selectInput(ns("shp_source"), NULL, choices = c("(none)" = "", nms))
    })

    observe({
      src <- input$shp_source
      if (!isTruthy(src) || is.null(vector_pool)) return()
      vec <- tryCatch(vector_pool[[src]], error = function(e) NULL)
      if (!is.null(vec)) rv_lidar$plot_shp <- vec
    })

    observeEvent(input$clip_las, {
      req(rv_lidar$las)
      xmin <- input$clip_xmin; xmax <- input$clip_xmax; ymin <- input$clip_ymin; ymax <- input$clip_ymax
      if (is.na(xmin) || is.na(xmax) || is.na(ymin) || is.na(ymax)) { showNotification("Please provide all 4 coordinates.", type = "warning"); return() }
      withProgress(message = 'Clipping LAS...', value = 0.5, {
        rv_lidar$las <- lidR::clip_rectangle(rv_lidar$las, xmin, ymin, xmax, ymax)
        showNotification("LAS file clipped.", type = "message")
      })
    })

    observeEvent(input$run_norm, {
      req(rv_lidar$las)
      withProgress(message = 'Normalizing Height (DTM)...', value = 0, {
        incProgress(0.2, detail = "Rasterizing Terrain...")
        rv_lidar$dtm <- lidR::rasterize_terrain(rv_lidar$las, res = input$dtm_res, algorithm = lidR::tin())
        incProgress(0.5, detail = "Subtracting DTM from LAS...")
        rv_lidar$las <- rv_lidar$las - rv_lidar$dtm
        rv_lidar$las$Z[rv_lidar$las$Z < 0] <- 0
        incProgress(0.9)
        showNotification("Height normalization complete.", type = "message")
      })
    })

    observeEvent(input$run_filter, {
      req(rv_lidar$las)
      withProgress(message = 'Filtering Noise...', value = 0.5, {
        tmp <- lidR::classify_noise(rv_lidar$las, lidR::ivf(res = 5, n = 2))
        tmp <- lidR::filter_poi(tmp, Classification != lidR::LASNOISE)
        tmp <- lidR::filter_poi(tmp, Intensity < input$int_max)
        rv_lidar$las <- tmp
        showNotification("Noise filtered.", type = "message")
      })
    })

    observeEvent(input$run_chm, {
      req(rv_lidar$las)
      withProgress(message = 'Generating CHM...', value = 0.5, {
        thresh <- as.numeric(trimws(unlist(strsplit(input$pitfree_thresh, ","))))
        rv_lidar$chm <- lidR::rasterize_canopy(rv_lidar$las, res = input$chm_res, algorithm = lidR::pitfree(thresholds = thresh))
        showNotification("CHM Generated.", type = "message")
      })
    })

    observeEvent(input$run_itd, {
      req(rv_lidar$chm)
      withProgress(message = 'Detecting Trees...', value = 0.5, {
        f_win <- function(height) { input$lmf_a + input$lmf_b * height^2 }
        rv_lidar$tops <- lidR::locate_trees(rv_lidar$chm, lidR::lmf(f_win))
        rv_lidar$tops$h <- 1.2 + rv_lidar$tops$Z * 1.01
        showNotification("Individual Tree Detection complete.", type = "message")
      })
    })

    # ---- LAS location basemap ----
    # Build a WGS84 polygon from the LAS point extents.
    # Uses raw X/Y min-max (no @-slot accessors — works for both terra and raster extent types).
    # Returns NULL when CRS is missing so the fallback CRS UI shows instead.
    las_bbox_wgs84 <- reactive({
      req(rv_lidar$las)
      tryCatch({
        las     <- rv_lidar$las
        crs_obj <- sf::st_crs(las)
        if (is.na(crs_obj)) return(NULL)
        d <- las@data
        if (nrow(d) == 0) return(NULL)
        xmin <- min(d$X, na.rm = TRUE); xmax <- max(d$X, na.rm = TRUE)
        ymin <- min(d$Y, na.rm = TRUE); ymax <- max(d$Y, na.rm = TRUE)
        poly_sf <- sf::st_sf(geometry = sf::st_sfc(
          sf::st_polygon(list(matrix(c(
            xmin, ymin, xmax, ymin, xmax, ymax,
            xmin, ymax, xmin, ymin
          ), ncol = 2, byrow = TRUE))),
          crs = crs_obj
        ))
        sf::st_transform(poly_sf, 4326)
      }, error = function(e) NULL)
    })

    output$manual_coords_ui <- renderUI({
      if (!is.null(las_bbox_wgs84())) return(NULL)
      if (is.null(rv_lidar$las)) return(NULL)
      tagList(
        tags$div(class = "px-2 pt-2",
          tags$p(class = "text-muted small mb-1",
            "CRS not embedded. Option 1: assign an EPSG code to geolocate automatically."),
          div(class = "d-flex gap-2 align-items-end mb-2",
            textInput(ns("epsg_code"), "EPSG Code:", value = "3067",
                      placeholder = "e.g. 3067 (Finland ETRS-TM35FIN)", width = "200px"),
            div(style = "margin-bottom: 1px;",
              actionButton(ns("apply_epsg"), "Apply CRS", class = "btn-sm btn-primary"))),
          tags$p(class = "text-muted small mb-0",
            HTML("<b>Option 2:</b> Use the draw toolbar (&#9632;) on the map to mark the area of interest."))
        )
      )
    })

    observeEvent(input$apply_epsg, {
      req(rv_lidar$las, input$epsg_code)
      code <- suppressWarnings(as.integer(trimws(input$epsg_code)))
      if (is.na(code)) {
        showNotification("Enter a valid numeric EPSG code (e.g. 3067).", type = "warning"); return()
      }
      tryCatch({
        lidR::crs(rv_lidar$las) <- sf::st_crs(code)
        showNotification(paste0("CRS set to EPSG:", code, ". Basemap will update."), type = "message")
      }, error = function(e) showNotification(paste("CRS error:", e$message), type = "error"))
    })

    observeEvent(input$location_map_draw_new_feature, {
      feat <- input$location_map_draw_new_feature
      if (is.null(feat) || is.null(feat$geometry)) return()
      tryCatch({
        coords <- do.call(rbind, lapply(feat$geometry$coordinates[[1]], function(p) c(p[[1]], p[[2]])))
        lon_c <- mean(coords[, 1], na.rm = TRUE)
        lat_c <- mean(coords[, 2], na.rm = TRUE)
        leafletProxy("location_map", session) %>%
          addMarkers(lng = lon_c, lat = lat_c,
                     popup = paste0("AOI centre: ", round(lat_c, 4), "°N, ", round(lon_c, 4), "°E"))
        showNotification(paste0("AOI drawn at ", round(lat_c, 4), "°N, ", round(lon_c, 4), "°E"), type = "message")
      }, error = function(e) NULL)
    })

    output$location_map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("OpenStreetMap", group = "OSM") %>%
        addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
        addLayersControl(baseGroups = c("OSM", "Satellite"), position = "topright") %>%
        leaflet.extras::addDrawToolbar(
          targetGroup   = "drawn",
          rectangleOptions = leaflet.extras::drawRectangleOptions(shapeOptions = leaflet.extras::drawShapeOptions(color = "#e65100")),
          polylineOptions  = FALSE,
          circleOptions    = FALSE,
          markerOptions    = leaflet.extras::drawMarkerOptions(),
          circleMarkerOptions = FALSE,
          editOptions = leaflet.extras::editToolbarOptions()
        ) %>%
        setView(lng = 27, lat = 63, zoom = 5)
    })

    observe({
      bbox <- las_bbox_wgs84()
      if (is.null(bbox)) return()
      bb <- sf::st_bbox(bbox)
      leafletProxy("location_map", session) %>%
        clearShapes() %>% clearMarkers() %>% clearPopups() %>%
        addPolygons(data = bbox, color = "#2e7d32", weight = 2, fillOpacity = 0.15,
                    popup = paste0("LAS extent<br>Lon: ", round(bb["xmin"], 4), " – ", round(bb["xmax"], 4),
                                   "<br>Lat: ", round(bb["ymin"], 4), " – ", round(bb["ymax"], 4))) %>%
        fitBounds(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])
    })

    # ---- 3D View Filters ----
    # Track active filter values as a list (updated by Apply button)
    view_filters <- reactiveVal(list(z = NULL, intensity = NULL, classes = NULL))

    # Dynamic filter UIs (ranges populated from loaded LAS)
    output$filter_z_ui <- renderUI({
      las <- rv_lidar$las
      if (is.null(las) || !"Z" %in% names(las@data)) return(NULL)
      z_range <- range(las@data$Z, na.rm = TRUE)
      sliderInput(ns("filter_z"), "Height (Z) range:",
                  min = floor(z_range[1]), max = ceiling(z_range[2]),
                  value = c(floor(z_range[1]), ceiling(z_range[2])), step = 0.5)
    })

    output$filter_intensity_ui <- renderUI({
      las <- rv_lidar$las
      if (is.null(las) || !"Intensity" %in% names(las@data)) return(NULL)
      i_range <- range(las@data$Intensity, na.rm = TRUE)
      sliderInput(ns("filter_intensity"), "Intensity range:",
                  min = 0L, max = max(1L, as.integer(i_range[2])),
                  value = c(0L, as.integer(i_range[2])), step = 1L)
    })

    output$filter_class_ui <- renderUI({
      las <- rv_lidar$las
      if (is.null(las) || !"Classification" %in% names(las@data)) return(NULL)
      cls_present <- sort(unique(las@data$Classification))
      cls_labels <- c("0"="Unclassified","1"="Unassigned","2"="Ground",
                      "3"="Low Veg","4"="Medium Veg","5"="High Veg",
                      "6"="Building","7"="Noise","8"="Model Key","9"="Water",
                      "10"="Rail","11"="Road","17"="Bridge","18"="High Noise")
      choices <- setNames(as.character(cls_present),
                          paste0(cls_present, " – ",
                                 cls_labels[as.character(cls_present)] %||% "Other"))
      checkboxGroupInput(ns("filter_class"), "Classification:",
                         choices  = choices,
                         selected = as.character(cls_present),
                         inline   = FALSE)
    })

    # Capture filter values when Apply is clicked
    observeEvent(input$apply_view_filters, {
      view_filters(list(
        z         = input$filter_z,
        intensity = input$filter_intensity,
        classes   = if (length(input$filter_class) > 0) as.integer(input$filter_class) else NULL
      ))
    })

    observeEvent(input$reset_view_filters, {
      view_filters(list(z = NULL, intensity = NULL, classes = NULL))
    })

    # Apply active filters to LAS for display
    filtered_las_display <- reactive({
      las <- rv_lidar$las
      req(las)
      flt <- view_filters()
      d   <- las@data
      keep <- rep(TRUE, nrow(d))
      if (!is.null(flt$z) && length(flt$z) == 2 && "Z" %in% names(d))
        keep <- keep & d$Z >= flt$z[1] & d$Z <= flt$z[2]
      if (!is.null(flt$intensity) && length(flt$intensity) == 2 && "Intensity" %in% names(d))
        keep <- keep & d$Intensity >= flt$intensity[1] & d$Intensity <= flt$intensity[2]
      if (!is.null(flt$classes) && length(flt$classes) > 0 && "Classification" %in% names(d))
        keep <- keep & d$Classification %in% flt$classes
      las@data <- d[keep, , drop = FALSE]
      las
    })

    output$lidar_3d_viewer <- renderRglwidget({
      req(rv_lidar$las)
      tryCatch({
        las_full <- filtered_las_display()
        n   <- nrow(las_full@data)
        cap <- min(n, as.integer(input$snap_pts %||% 60000L))
        las_disp <- if (n > cap) {
          idx <- sort(sample.int(n, cap))
          las_full@data <- las_full@data[idx]
          las_full
        } else {
          las_full
        }
        rgl::clear3d()
        lidR::plot(las_disp, color = "Z", bg = "white", size = 2, clear_artifacts = FALSE)
        rgl::rglwidget()
      }, error = function(e) {
        showNotification("Interactive 3D viewer unavailable on this server. See the static snapshot below.", type = "warning")
        NULL
      })
    })

    # Static, decimated 3D scatter (headless-safe) for download + AI vision.
    static3d_fn <- function() {
      if (is.null(rv_lidar$las)) { show_placeholder("Load a .laz file to see the 3D snapshot."); return() }
      las_d <- tryCatch(filtered_las_display(), error = function(e) rv_lidar$las)
      d <- las_d@data
      n <- nrow(d)
      cap <- if (isTruthy(input$snap_pts)) input$snap_pts else 60000
      idx <- if (n > cap) sample(n, cap) else seq_len(n)
      z <- d$Z[idx]
      zr <- range(z, na.rm = TRUE)
      bins <- if (diff(zr) > 0) cut(z, breaks = 50, labels = FALSE) else rep(1L, length(z))
      cols <- grDevices::terrain.colors(50)[bins]
      scatterplot3d::scatterplot3d(d$X[idx], d$Y[idx], z, color = cols, pch = 20, cex.symbols = 0.3,
        xlab = "X", ylab = "Y", zlab = "Z (height)", main = paste0("Point cloud (", length(idx), " pts, decimated)"))
    }
    output$static_3d <- renderPlot({ static3d_fn() })
    output$download_3d <- downloadHandler(
      filename = function() { paste0("pointcloud_3d_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 900, height = 800); static3d_fn(); dev.off() }
    )

    output$las_summary <- renderPrint({ req(rv_lidar$las); print(summary(rv_lidar$las)) })

    hists_fn <- function() {
      req(rv_lidar$las)
      par(mfrow = c(1, 2))
      hist(rv_lidar$las$Z, main = "Height (Z)", col = "lightblue", xlab = "Z")
      hist(rv_lidar$las$Intensity, main = "Intensity", col = "lightgreen", xlab = "Intensity")
    }
    output$las_hists <- renderPlot({ hists_fn() })
    output$download_hists <- downloadHandler(
      filename = function() { paste0("las_distributions_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 900, height = 450); hists_fn(); dev.off() }
    )

    chm_fn <- function() {
      req(rv_lidar$chm)
      terra::plot(rv_lidar$chm, main = "Canopy Height Model (CHM)")
      if (!is.null(rv_lidar$plot_shp)) plot(sf::st_geometry(rv_lidar$plot_shp), add = TRUE, border = "white", lwd = 2)
      if (!is.null(rv_lidar$tops)) plot(sf::st_geometry(rv_lidar$tops), add = TRUE, col = "red", pch = 16, cex = 0.5)
    }
    output$chm_plot <- renderPlot({ chm_fn() })
    output$download_chm <- downloadHandler(
      filename = function() { paste0("chm_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 800, height = 800); chm_fn(); dev.off() }
    )

    output$itd_table <- DT::renderDataTable({
      req(rv_lidar$tops)
      DT::datatable(sf::st_drop_geometry(rv_lidar$tops), options = list(pageLength = 10, scrollX = TRUE))
    })

    observeEvent(input$extract_metrics, {
      req(rv_lidar$las, rv_lidar$plot_shp)
      withProgress(message = 'Extracting Plot Metrics...', value = 0.5, {
        tryCatch({
          d <- lidR::polygon_metrics(rv_lidar$las, ~lidR::stdmetrics(X, Y, Z, Intensity, ReturnNumber, Classification, dz = 1), rv_lidar$plot_shp)
          d <- cbind(rv_lidar$plot_shp, d)
          d_df <- sf::st_set_geometry(d, NULL)
          rv_lidar$itd_metrics <- d_df
          dataset_pool[["LiDAR_Plot_Metrics"]] <- d_df  # appears in the left Datasets rail
          updateSelectInput(session, "eval_target", choices = names(d_df))
          updateSelectInput(session, "eval_pred", choices = names(d_df))
          showNotification("Metrics extracted and added to the Datasets rail!", type = "message")
        }, error = function(e) showNotification(paste("Metric extraction failed:", e$message), type = "error"))
      })
    })

    output$metrics_table <- DT::renderDataTable({
      req(rv_lidar$itd_metrics)
      DT::datatable(rv_lidar$itd_metrics, options = list(pageLength = 10, scrollX = TRUE))
    })

    eval_data <- reactiveVal(NULL)
    observeEvent(input$run_eval, {
      req(rv_lidar$itd_metrics, input$eval_target, input$eval_pred)
      eval_data(list(obs = rv_lidar$itd_metrics[[input$eval_target]],
                     pred = rv_lidar$itd_metrics[[input$eval_pred]],
                     target = input$eval_target, pred_name = input$eval_pred))
    })

    output$eval_metrics_out <- renderPrint({
      e <- eval_data()
      if (is.null(e)) return(cat("Run 'Calculate Error Metrics' to evaluate."))
      if (is.null(e$obs) || is.null(e$pred)) { cat("Variables not found."); return() }
      print(uef_evaluation(e$pred, e$obs))
    })

    eval_plot_fn <- function() {
      e <- eval_data()
      if (is.null(e) || is.null(e$obs) || is.null(e$pred)) { show_placeholder("Run 'Calculate Error Metrics'."); return() }
      plot(e$pred, e$obs, xlab = paste("Predicted (", e$pred_name, ")"), ylab = paste("Observed (", e$target, ")"), main = "Prediction Accuracy", pch = 16, col = "blue")
      abline(0, 1, col = "red", lwd = 2)
    }
    output$eval_plot <- renderPlot({ eval_plot_fn() })
    output$download_eval <- downloadHandler(
      filename = function() { paste0("model_evaluation_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 700, height = 600); eval_plot_fn(); dev.off() }
    )

    # Context (+ plot) for the AI Co-Pilot (shared across the 3 LiDAR views).
    list(
      context = reactive({
        parts <- c()
        if (!is.null(rv_lidar$las)) parts <- c(parts, "LAS point cloud loaded")
        if (!is.null(rv_lidar$dtm)) parts <- c(parts, "height-normalized (DTM)")
        if (!is.null(rv_lidar$chm)) parts <- c(parts, "CHM generated")
        if (!is.null(rv_lidar$tops)) parts <- c(parts, paste(nrow(rv_lidar$tops), "trees detected"))
        if (!is.null(rv_lidar$itd_metrics)) parts <- c(parts, paste(ncol(rv_lidar$itd_metrics), "plot metrics extracted"))
        paste0("Spatial & LiDAR workflow. ",
               if (length(parts)) paste(parts, collapse = "; ") else "No LiDAR data loaded yet.")
      }),
      plot = function() {
        if (!is.null(isolate(eval_data()))) eval_plot_fn()
        else if (!is.null(rv_lidar$chm)) chm_fn()
        else if (!is.null(rv_lidar$las)) static3d_fn()
        else show_placeholder("No LiDAR data loaded yet.")
      }
    )
  })
}
