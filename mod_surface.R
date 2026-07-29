# ==========================================================================
# MODULE: Surface Models  --  RETIRED, NOT REGISTERED AS A TOOL
#
# This bundled DTM / DSM / CHM / nDSM behind one radio button, which meant you
# had to already know that a DTM lives inside a screen called "Surface models"
# before you could make one -- and its CHM was the same lidR::pitfree call that
# mod_lidar.R also had, so CHM existed twice.
#
# All four are now separate searchable tools in algorithms.R, run by mod_algo.R.
# The run logic there was ported from this file unchanged (tin() for DTM, p2r()
# for DSM, pitfree(thresholds) for CHM, DSM - DTM for nDSM).
#
# Kept only so that nothing still referring to surfaceServer/surfaceToolsUI
# breaks; global.R sources it, mod_workspace.R no longer registers it and
# server.R no longer binds it. Delete once nothing references it.
# ==========================================================================

surfaceToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Surface Model Generation", class = "text-uppercase text-muted small"),
    accordion(
      open = "input",

      accordion_panel("Input Data", value = "input",
        uiOutput(ns("las_selector_ui"))
      ),

      accordion_panel("Surface Type", value = "type",
        radioButtons(ns("surf_type"), NULL,
          choices  = c("DTM (Digital Terrain Model)"    = "dtm",
                       "DSM (Digital Surface Model)"    = "dsm",
                       "CHM (Canopy Height = DSM - DTM)"= "chm",
                       "nDSM (Normalized DSM)"          = "ndsm"),
          selected = "dtm")
      ),

      accordion_panel("Parameters", value = "params",
        sliderInput(ns("res"), "Resolution (m):", min = 0.1, max = 5, value = 1, step = 0.1),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'chm'", ns("surf_type")),
          textInput(ns("pitfree_thresh"), "Pitfree thresholds (comma-sep):", value = "0, 5, 10, 15, 20, 25")
        )
      ),

      accordion_panel("Output", value = "output",
        textInput(ns("output_name"), "Save to raster pool as:", placeholder = "e.g., dtm_2024"),
        actionButton(ns("run"), "Generate Surface", class = "btn-primary w-100"),
        hr(),
        downloadButton(ns("dl"), "Export GeoTIFF", class = "btn-sm btn-outline-success w-100")
      )
    )
  )
}

surfaceCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    style = "position:relative; height:calc(100vh - 72px); width:100%;",
    leafletOutput(ns("map"), width = "100%", height = "100%"),
    absolutePanel(
      top = 10, right = 60, style = "z-index:800; background:rgba(255,255,255,0.92);
                                      padding:8px 12px; border-radius:6px; min-width:180px;",
      uiOutput(ns("map_overlay"))
    )
  )
}

# ---- Server -----------------------------------------------------------------

surfaceServer <- function(id, las_pool = NULL, raster_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv_surf <- reactiveValues(result = NULL, result_name = NULL)

    # ---- Input selector: pick from las_pool ----
    output$las_selector_ui <- renderUI({
      nms <- if (!is.null(las_pool)) names(reactiveValuesToList(las_pool)) else character(0)
      if (length(nms) == 0)
        return(tags$p(class = "text-muted small",
                      "No LAS/LAZ files loaded. Upload via the Datasets panel."))
      tagList(
        selectInput(ns("las_source"), "Point cloud source:", choices = nms),
        tags$p(class = "text-muted small",
               "Upload more point clouds via Add Data in the Datasets panel.")
      )
    })

    # ---- Generate surface ----
    observeEvent(input$run, {
      req(input$las_source, las_pool, input$surf_type)
      las <- las_pool[[input$las_source]]
      if (is.null(las)) {
        showNotification("Selected LAS not found in pool.", type = "error")
        return()
      }
      nm <- trimws(input$output_name)
      if (!nzchar(nm)) nm <- paste0(input$surf_type, "_", format(Sys.time(), "%H%M%S"))
      res <- input$res

      withProgress(message = paste("Generating", toupper(input$surf_type), "..."), value = 0.3, {
        tryCatch({
          result <- switch(input$surf_type,

            dtm = {
              incProgress(0.4, detail = "Rasterizing terrain (TIN)...")
              lidR::rasterize_terrain(las, res = res, algorithm = lidR::tin())
            },

            dsm = {
              incProgress(0.4, detail = "Rasterizing canopy surface...")
              lidR::rasterize_canopy(las, res = res, algorithm = lidR::p2r())
            },

            chm = {
              thresh <- tryCatch(
                as.numeric(trimws(unlist(strsplit(input$pitfree_thresh, ",")))),
                error = function(e) c(0, 5, 10, 15, 20, 25)
              )
              thresh <- thresh[!is.na(thresh)]
              if (length(thresh) == 0) thresh <- c(0, 5, 10, 15, 20, 25)
              incProgress(0.4, detail = "Rasterizing canopy (pitfree)...")
              lidR::rasterize_canopy(las, res = res, algorithm = lidR::pitfree(thresholds = thresh))
            },

            ndsm = {
              incProgress(0.3, detail = "Computing DTM...")
              dtm <- lidR::rasterize_terrain(las, res = res, algorithm = lidR::tin())
              incProgress(0.6, detail = "Computing DSM...")
              dsm <- lidR::rasterize_canopy(las, res = res, algorithm = lidR::p2r())
              dsm - dtm
            }
          )

          rv_surf$result      <- result
          rv_surf$result_name <- nm
          if (!is.null(raster_pool)) raster_pool[[nm]] <- result
          showNotification(
            paste0(toupper(input$surf_type), " '", nm,
                   "' generated and saved to raster pool (", round(res, 2), " m res)."),
            type = "message"
          )
        }, error = function(e) {
          showNotification(paste("Generation error:", e$message), type = "error")
        })
      })
    })

    # ---- Leaflet map ----
    output$map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("OpenStreetMap",    group = "OSM") %>%
        addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
        addLayersControl(baseGroups = c("OSM", "Satellite"), position = "topright")
    })

    observe({
      r <- rv_surf$result
      if (is.null(r)) return()
      tryCatch({
        r_wgs <- .to_wgs84(r[[1]])
        bb    <- terra::ext(r_wgs)
        leafletProxy("map", session) %>%
          clearImages() %>%
          leafem::addGeoRaster(
            r_wgs,
            colorOptions = leafem::colorOptions(
              palette = viridisLite::viridis(128), na.color = "transparent"
            )
          ) %>%
          fitBounds(bb[1], bb[3], bb[2], bb[4])
      }, error = function(e) {
        showNotification(paste("Map display error:", e$message), type = "warning")
      })
    })

    output$map_overlay <- renderUI({
      r <- rv_surf$result
      if (is.null(r)) return(tags$p(class = "small text-muted", "Generate a surface to view it here."))
      nm   <- rv_surf$result_name
      vals <- terra::values(r[[1]], na.rm = TRUE)
      tagList(
        tags$strong(nm),
        tags$br(),
        tags$span(class = "small text-muted",
          sprintf("Min: %.2f  Max: %.2f\nRes: %.2f m", min(vals), max(vals), terra::res(r)[1]))
      )
    })

    # ---- Download ----
    output$dl <- downloadHandler(
      filename = function() paste0(rv_surf$result_name %||% "surface", "_", Sys.Date(), ".tif"),
      content  = function(file) {
        r <- rv_surf$result
        req(r)
        terra::writeRaster(r, file, overwrite = TRUE)
      }
    )

    # AI Co-Pilot context
    list(
      context = reactive({
        r <- rv_surf$result
        if (is.null(r)) return("Surface Models — no surface generated yet.")
        vals <- terra::values(r[[1]], na.rm = TRUE)
        paste0("Surface model '", rv_surf$result_name, "' (", toupper(input$surf_type), ").",
               "\nResolution: ", terra::res(r)[1], " m",
               "\nMin: ", round(min(vals), 2), "  Max: ", round(max(vals), 2),
               "\nSource LAS: ", input$las_source %||% "unknown")
      }),
      plot = function() NULL
    )
  })
}
