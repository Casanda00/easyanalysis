# ==========================================================================
# MODULE: Spatial & LiDAR  (canvas + tools contract)
# Two menu views (pointcloud / metrics) share ONE rv_lidar state, so this is a
# single module: two tools UI fns + one server. Wire both with the SAME id
# ("lidar"); the server binds once.
#   lidarPointcloudToolsUI  (LAS pre-processing + results)
#   lidarMetricsToolsUI     (metric extraction + model evaluation)
#   lidarServer(id, dataset_pool, las_pool, vector_pool)
#
# NO CANVAS. Both tools are map_based: the workspace map draws the point cloud
# and the 3D view has its own button (lidar3DOnlyUI), so a screen of its own
# meant two or three competing views of the same data (backlog D18). Outputs
# that are genuinely not map layers -- the LAS summary, the height/intensity
# histograms, the model-evaluation scatter -- render in the tool panel instead.
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
    actionButton(ns("clip_shp"), tagList(icon("scissors"), " Clip LAS to this shapefile"),
      class = "btn-warning w-100 mt-1"),
    hr(),
    markdown("**Sub-setting by coordinates** *(alternative to the shapefile clip above)*"),
    numericInput(ns("clip_xmin"), "X Min:", value = NA),
    numericInput(ns("clip_xmax"), "X Max:", value = NA),
    numericInput(ns("clip_ymin"), "Y Min:", value = NA),
    numericInput(ns("clip_ymax"), "Y Max:", value = NA),
    actionButton(ns("clip_las"), "Clip LAS by coordinates", class = "btn-outline-warning", width = "100%"),
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
      actionButton(ns("reset_view_filters"), "Reset", class = "btn-sm btn-outline-secondary")),
    # CRS fallback. It used to sit under this screen's own basemap; the basemap is
    # gone, so it lives with the controls.
    uiOutput(ns("manual_coords_ui")),
    tags$hr(class = "my-2"),
    # Results that are NOT layers, so they have nowhere on the map to go.
    accordion(open = FALSE,
      accordion_panel("Height & intensity distributions",
        div(class = "d-flex justify-content-end", ea_plot_appearance(fields = "title")),
        plotOutput(ns("las_hists"), height = "260px")),
      accordion_panel("LAS summary",
        div(style = "max-height:300px; overflow-y:auto;",
            verbatimTextOutput(ns("las_summary"))))
    )
  )
}

# The 3D VIEW in the workspace: the cloud and nothing else, reached from the "3D
# view" button on the map strip. This is now the ONLY place the 3D viewer and the
# static snapshot appear — the point-cloud screen used to carry its own copy of
# both plus a basemap, which is what "opens two views" meant (backlog D18).
lidar3DOnlyUI <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Interactive 3D point cloud"),
      rglwidgetOutput(ns("lidar_3d_viewer"), height = "560px")
    ),
    card(
      card_header(class = "d-flex justify-content-between align-items-center",
                  "Static snapshot (download / AI view)",
                  ea_plot_appearance(fields = c("title", "xlab", "ylab"))),
      div(class = "d-flex align-items-center gap-2 px-2",
          sliderInput(ns("snap_pts"), "Max display points (both 3D viewers):",
                      min = 10000, max = 5000000, value = 60000, step = 10000,
                      width = "320px")),
      plotOutput(ns("static_3d"), height = "430px")
    )
  )
}

# ---- CHM & ITD: NOT HERE ANY MORE ----
# Both are processing algorithms now (algorithms.R): "CHM (Canopy Height
# Model)" and "ITD (Individual Tree Detection)", each its own searchable
# tool whose result becomes a project layer. CHM was duplicated here and in
# Surface models with the same lidR call; ITD could not put its treetops on
# the map at all, which is why this screen carried a map of its own.

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
    actionButton(ns("run_eval"), "Calculate Error Metrics", class = "btn-success", width = "100%"),
    tags$hr(class = "my-2"),
    # The extracted metrics themselves go to dataset_pool, so they show up as a
    # table in the DATA view -- no need to repeat them here. Only the evaluation,
    # which is not a layer, renders in the panel.
    accordion(open = FALSE,
      accordion_panel("Model evaluation",
        div(style = "max-height:220px; overflow-y:auto;",
            verbatimTextOutput(ns("eval_metrics_out"))),
        div(class = "d-flex justify-content-end", ea_plot_appearance()),
        plotOutput(ns("eval_plot"), height = "260px"))
    )
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
        # isolate() the own-state read so this observer depends ONLY on las_pool
        # and can never re-invalidate itself when it sets rv_lidar$las.
        if (!identical(isolate(rv_lidar$las), new_las)) {
          rv_lidar$las     <- new_las
          rv_lidar$raw_las <- NULL
          # Let the "Max display points" slider reach the FULL loaded cloud, so
          # the user can crank it up to every point (default stays 60k for a
          # responsive 3D viewer). Cap the slider at the actual point count.
          npts <- tryCatch(nrow(new_las@data), error = function(e) NA_integer_)
          if (!is.na(npts) && npts > 10000) {
            updateSliderInput(session, "snap_pts",
              max = as.integer(min(npts, 5000000L)),
              value = as.integer(min(isolate(input$snap_pts) %||% 60000L, npts)))
          }
          showNotification(paste0("LiDAR '", latest_nm, "' ready (",
            format(npts, big.mark = ","), " pts). Slider now reaches the full cloud."),
            type = "message")
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

    # Clip the point cloud to the selected shapefile polygon (from vector_pool
    # via the Plot Shapefile picker). Matches CRS, then lidR::clip_roi.
    observeEvent(input$clip_shp, {
      req(rv_lidar$las)
      poly <- rv_lidar$plot_shp
      if (is.null(poly)) {
        showNotification("Select a shapefile in 'Plot Shapefile' first (upload one via Add Data).",
                         type = "warning"); return()
      }
      withProgress(message = "Clipping LAS to shapefile...", value = 0.5, {
        tryCatch({
          las_crs  <- sf::st_crs(rv_lidar$las)
          poly_crs <- sf::st_crs(poly)
          if (!is.na(las_crs) && !is.na(poly_crs) && las_crs != poly_crs)
            poly <- sf::st_transform(poly, las_crs)
          poly <- sf::st_zm(poly, drop = TRUE)          # drop any Z/M so clip_roi is happy
          clipped <- lidR::clip_roi(rv_lidar$las, poly)
          np <- tryCatch(nrow(clipped@data), error = function(e) 0L)
          if (is.null(clipped) || is.na(np) || np == 0) {
            showNotification(paste("Clip produced no points — check the shapefile overlaps",
              "the cloud and that both have a matching CRS."), type = "warning", duration = NULL)
            return()
          }
          rv_lidar$las <- clipped
          showNotification(paste0("LAS clipped to shapefile (", format(np, big.mark = ","), " pts)."),
                           type = "message")
        }, error = function(e)
          showNotification(paste("Shapefile clip failed:", e$message), type = "error", duration = NULL))
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
        xlab = ea_xlab("X"), ylab = ea_ylab("Y"), zlab = "Z (height)",
        main = ea_main(paste0("Point cloud (", length(idx), " pts, decimated)")))
    }
    output$static_3d <- renderPlot({ static3d_fn() })
    

    output$las_summary <- renderPrint({ req(rv_lidar$las); print(summary(rv_lidar$las)) })

    hists_fn <- function() {
      req(rv_lidar$las)
      ea_multi_par(mfrow = c(1, 2))
      hist(rv_lidar$las$Z, main = "Height (Z)", col = "lightblue", xlab = "Z")
      hist(rv_lidar$las$Intensity, main = "Intensity", col = "lightgreen", xlab = "Intensity")
      ea_fig_title()
    }
    output$las_hists <- renderPlot({ hists_fn() })
    

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
      plot(e$pred, e$obs,
           xlab = ea_xlab(paste("Predicted (", e$pred_name, ")")),
           ylab = ea_ylab(paste("Observed (", e$target, ")")),
           main = ea_main("Prediction Accuracy"), pch = 16, col = ea_col("blue"))
      abline(0, 1, col = "red", lwd = 2)
    }
    output$eval_plot <- renderPlot({ eval_plot_fn() })
    

    # Context (+ plot) for the AI Co-Pilot (shared across the 3 LiDAR views).
    list(
      context = reactive({
        parts <- c()
        if (!is.null(rv_lidar$las)) parts <- c(parts, "LAS point cloud loaded")
        if (!is.null(rv_lidar$dtm)) parts <- c(parts, "height-normalized (DTM)")
        if (!is.null(rv_lidar$itd_metrics)) parts <- c(parts, paste(ncol(rv_lidar$itd_metrics), "plot metrics extracted"))
        paste0("Spatial & LiDAR workflow. ",
               if (length(parts)) paste(parts, collapse = "; ") else "No LiDAR data loaded yet.")
      }),
      plot = function() {
        if (!is.null(isolate(eval_data()))) eval_plot_fn()
        else if (!is.null(rv_lidar$las)) static3d_fn()
        else show_placeholder("No LiDAR data loaded yet.")
      }
    )
  })
}
