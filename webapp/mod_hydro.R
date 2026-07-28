# ==========================================================================
# MODULE: Hydrological Analysis
# hydroCanvasUI / hydroToolsUI / hydroServer
# Uses terra + optional whitebox (detected at runtime)
# ==========================================================================

hydroToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Hydrological Analysis", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "hyd_in",

      accordion_panel("Input & Operation", value = "hyd_in", icon = icon("water"),
        uiOutput(ns("dem_picker")),
        selectInput(ns("operation"), "Operation", width = "100%",
          choices = c(
            "Topographic Wetness Index (TWI)"           = "twi",
            "Flow Direction (D8 approximate)"           = "flowdir",
            "Slope-based Stream Extraction"             = "streams",
            "Slope × Contributing Area"                 = "sca",
            "Fill Depressions (whitebox — if installed)"= "fill_wb",
            "Flow Accumulation (whitebox — if installed)"= "flowacc_wb"
          )
        ),
        conditionalPanel("input.operation == 'streams'", ns = ns,
          sliderInput(ns("slope_thr"), "Slope threshold (°) for stream pixels",
            min = 1, max = 30, value = 8, step = 1)
        ),
        textInput(ns("out_name"), "Output layer name", value = "hydro_result", width = "100%"),
        actionButton(ns("run"), "Compute", class = "btn-success w-100 mt-2", icon = icon("play"))
      ),

      accordion_panel("Export", value = "hyd_exp", icon = icon("download"),
        selectInput(ns("map_fmt"), "Format",
          choices = c("PNG" = "png", "JPEG" = "jpg", "PDF" = "pdf"), width = "100%"),
        numericInput(ns("map_dpi"), "DPI", value = 150, min = 72, max = 600, width = "100%"),
        radioButtons(ns("map_orient"), "Orientation",
          choices = c("Landscape" = "landscape", "Portrait" = "portrait"),
          selected = "landscape", inline = TRUE),
        div(style = "display:flex;gap:6px;margin-top:4px;",
          downloadButton(ns("dl_map"),    "Image",   class = "btn-sm btn-outline-success flex-fill"),
          downloadButton(ns("dl_raster"), "GeoTIFF", class = "btn-sm btn-success flex-fill")
        )
      )
    )
  )
}

hydroCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(8, 4),
      card(
        card_header("Hydrology Map"),
        plotOutput(ns("preview"), height = "480px")
      ),
      tagList(
        card(card_header("Method Notes"),
          div(style = "padding:8px; font-size:12px; color:#555;",
            uiOutput(ns("method_note")))),
        card(card_header("Statistics"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("stats"))))
      )
    )
  )
}

hydroServer <- function(id, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    result_r <- reactiveVal(NULL)

    output$dem_picker <- renderUI({
      pool <- reactiveValuesToList(raster_pool)
      nms  <- names(pool)
      if (length(nms) == 0)
        return(tags$p(class = "small text-warning",
          "Upload a DEM raster via Add Data."))
      selectInput(ns("dem_layer"), "DEM (input raster):",
        choices = nms, width = "100%")
    })

    output$method_note <- renderUI({
      switch(input$operation %||% "twi",
        twi = tags$p("TWI = ln( A / tan(β) ) where A = upslope contributing area (approximated as cell area × 1) and β = local slope (radians). Higher values → wetter topography."),
        flowdir = tags$p("D8 approximation: steepest descent among 8 neighbours (terra::terrain 'flowdir'). Values encode cardinal direction (1=E, 2=NE, … 128=SE)."),
        streams = tags$p("Pixels with slope above the threshold are marked as likely stream channels. Not a true flow-routing approach; use whitebox for rigorous stream networks."),
        sca     = tags$p("Slope × Contributing Area: slope (radians) × cell area (m²). A proxy for erosion potential (RUSLE-like)."),
        fill_wb = tags$p("Fills topographic depressions (pits) in the DEM using Wang & Liu (2006) algorithm via whitebox. Requires 'whitebox' package."),
        flowacc_wb = tags$p("D8 flow accumulation via whitebox. Requires 'whitebox' package and a depression-filled DEM. Counts upstream cells.")
      )
    })

    observeEvent(input$run, {
      pool <- reactiveValuesToList(raster_pool)
      nm   <- input$dem_layer
      req(isTruthy(nm), nm %in% names(pool))
      dem <- pool[[nm]]

      result <- tryCatch({
        op <- input$operation %||% "twi"

        if (op %in% c("fill_wb", "flowacc_wb")) {
          if (!.ensure_pkg("whitebox", quietly = TRUE))
            stop("Package 'whitebox' is not installed. Run: install.packages('whitebox'); whitebox::install_whitebox()")
          tmp_dem  <- tempfile(fileext = ".tif")
          tmp_out  <- tempfile(fileext = ".tif")
          terra::writeRaster(dem, tmp_dem, overwrite = TRUE)
          if (op == "fill_wb") {
            whitebox::wbt_fill_depressions(tmp_dem, tmp_out)
          } else {
            tmp_fill <- tempfile(fileext = ".tif")
            whitebox::wbt_fill_depressions(tmp_dem, tmp_fill)
            whitebox::wbt_d8_flow_accumulation(tmp_fill, tmp_out, out_type = "cells")
          }
          terra::rast(tmp_out)

        } else switch(op,
          twi = {
            sl  <- terra::terrain(dem, "slope", unit = "radians")
            # Approximate contributing area = cell area (very rough; no routing)
            ca  <- prod(terra::res(dem))
            log(ca / (tan(sl) + 1e-6))
          },
          flowdir = terra::terrain(dem, "flowdir"),
          streams = {
            sl  <- terra::terrain(dem, "slope", unit = "degrees")
            thr <- as.numeric(input$slope_thr %||% 8)
            sl >= thr
          },
          sca = {
            sl <- terra::terrain(dem, "slope", unit = "radians")
            ca <- prod(terra::res(dem))
            sl * ca
          }
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      req(!is.null(result))
      out_nm <- trimws(input$out_name %||% "hydro_result")
      if (!nzchar(out_nm)) out_nm <- paste0(input$operation, "_result")
      names(result) <- out_nm
      raster_pool[[out_nm]] <- result
      result_r(list(raster = result, name = out_nm, op = input$operation))
      showNotification(paste0("'", out_nm, "' saved to layer pool."), type = "message")
    })

    .hydro_pal <- function(op) {
      switch(op,
        twi      = colorRampPalette(c("#d7191c","#fdae61","#ffffbf","#74add1","#313695"))(256),
        flowdir  = viridisLite::viridis(256),
        streams  = c("#f5f5f5", "#2171b5"),
        sca      = viridisLite::plasma(256),
        viridisLite::viridis(256)
      )
    }

    output$preview <- renderPlot({
      res <- result_r()
      if (is.null(res)) {
        show_placeholder("Select a DEM and click Compute.")
        return()
      }
      terra::plot(res$raster, col = .hydro_pal(res$op),
                  main = res$name, mar = c(3.5, 3.5, 2, 7))
    })

    output$stats <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      st <- tryCatch(
        terra::global(res$raster, fun = c("min","mean","max","sd"), na.rm = TRUE),
        error = function(e) NULL)
      if (is.null(st)) return()
      cat(sprintf("Min  : %.4f\nMean : %.4f\nMax  : %.4f\nSD   : %.4f\n",
                  st$min, st$mean, st$max, st$sd))
    })

    output$dl_raster <- downloadHandler(
      filename = function() paste0(result_r()$name %||% "hydro", ".tif"),
      content  = function(file) {
        res <- result_r(); req(!is.null(res))
        terra::writeRaster(res$raster, file, overwrite = TRUE)
      }
    )

    output$dl_map <- downloadHandler(
      filename = function() {
        fmt <- input$map_fmt %||% "png"
        paste0(result_r()$name %||% "hydro", ".", fmt)
      },
      content = function(file) {
        res <- result_r(); req(!is.null(res))
        fmt  <- input$map_fmt    %||% "png"
        dpi  <- max(72L, min(600L, as.integer(input$map_dpi   %||% 150L)))
        ornt <- input$map_orient %||% "landscape"
        if (ornt == "landscape") { pw <- 11.69; ph <- 8.27 }
        else                     { pw <-  8.27; ph <- 11.69 }
        if (fmt == "pdf")      pdf(file, width = pw, height = ph)
        else if (fmt == "jpg") jpeg(file, width=pw*dpi, height=ph*dpi, res=dpi, quality=95)
        else                   png(file, width=pw*dpi, height=ph*dpi, res=dpi)
        terra::plot(res$raster, col = .hydro_pal(res$op),
                    main = res$name, mar = c(3.5, 3.5, 2, 7))
        dev.off()
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Hydrological Analysis: no result yet.")
        paste0("Hydrology | Op: ", res$op, " | Layer: ", res$name)
      }),
      plot = function() {
        res <- result_r()
        if (is.null(res)) return(invisible())
        terra::plot(res$raster, col = .hydro_pal(res$op), main = res$name)
      }
    )
  })
}
