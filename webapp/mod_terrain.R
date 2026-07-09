# ==========================================================================
# MODULE: Terrain & Surface Analysis
# terrainCanvasUI / terrainToolsUI / terrainServer
# All operations via terra::terrain() and terra::shade()
# ==========================================================================

terrainToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Terrain Analysis", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "tin",

      accordion_panel("Input & Operation", value = "tin", icon = icon("mountain"),
        uiOutput(ns("dem_picker")),
        selectInput(ns("operation"), "Terrain Derivative", width = "100%",
          choices = c(
            "Slope (degrees)"              = "slope_deg",
            "Slope (percent rise)"         = "slope_pct",
            "Aspect"                       = "aspect",
            "Hillshade"                    = "hillshade",
            "Profile Curvature"            = "profc",
            "Plan Curvature"               = "planc",
            "TPI (Topographic Position)"   = "TPI",
            "TRI (Terrain Ruggedness)"     = "TRI",
            "Roughness"                    = "roughness"
          )
        ),
        conditionalPanel("input.operation == 'hillshade'", ns = ns,
          sliderInput(ns("hs_alt"),  "Sun altitude (°)",  min = 0, max = 90,  value = 45, step = 5),
          sliderInput(ns("hs_azim"), "Sun azimuth (°)",   min = 0, max = 360, value = 315, step = 5)
        ),
        textInput(ns("out_name"), "Output layer name", value = "terrain_result", width = "100%"),
        actionButton(ns("run"), "Compute", class = "btn-success w-100 mt-2", icon = icon("play"))
      ),

      accordion_panel("Export", value = "texp", icon = icon("download"),
        selectInput(ns("map_fmt"), "Format",
          choices = c("PNG" = "png", "JPEG" = "jpg", "PDF" = "pdf"), width = "100%"),
        numericInput(ns("map_dpi"), "DPI", value = 150, min = 72, max = 600, width = "100%"),
        radioButtons(ns("map_orient"), "Orientation",
          choices = c("Landscape" = "landscape", "Portrait" = "portrait"),
          selected = "landscape", inline = TRUE),
        downloadButton(ns("dl_map"), "Export Image", class = "btn-sm btn-outline-success w-100 mt-1"),
        hr(style = "margin:8px 0;"),
        downloadButton(ns("dl_raster"), "Download GeoTIFF",
          class = "btn-sm btn-success w-100")
      )
    )
  )
}

terrainCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(col_widths = c(8, 4),
      card(
        card_header("Terrain Map"),
        div(style = "padding:4px;",
          plotOutput(ns("preview"), height = "480px"))
      ),
      tagList(
        card(card_header("Layer Info"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("info")))),
        card(card_header("Statistics"),
          div(style = "padding:8px; font-size:13px;",
            verbatimTextOutput(ns("stats"))))
      )
    )
  )
}

terrainServer <- function(id, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    result_r <- reactiveVal(NULL)

    output$dem_picker <- renderUI({
      pool <- reactiveValuesToList(raster_pool)
      nms  <- names(pool)
      if (length(nms) == 0)
        return(tags$p(class = "small text-warning",
          "No rasters loaded. Upload a DEM via Add Data."))
      selectInput(ns("dem_layer"), "DEM (input raster):",
        choices = nms, width = "100%")
    })

    observeEvent(input$run, {
      pool <- reactiveValuesToList(raster_pool)
      dem_nm <- input$dem_layer
      req(isTruthy(dem_nm), dem_nm %in% names(pool))
      dem <- pool[[dem_nm]]

      result <- tryCatch({
        switch(input$operation,
          slope_deg = terra::terrain(dem, "slope",  unit = "degrees"),
          slope_pct = {
            s <- terra::terrain(dem, "slope", unit = "radians")
            tan(s) * 100
          },
          aspect    = terra::terrain(dem, "aspect", unit = "degrees"),
          hillshade = {
            sl <- terra::terrain(dem, "slope",  unit = "radians")
            as <- terra::terrain(dem, "aspect", unit = "radians")
            terra::shade(sl, as,
              angle     = as.numeric(input$hs_alt  %||% 45),
              direction = as.numeric(input$hs_azim %||% 315))
          },
          profc     = terra::terrain(dem, "profc"),
          planc     = terra::terrain(dem, "planc"),
          TPI       = terra::terrain(dem, "TPI"),
          TRI       = terra::terrain(dem, "TRI"),
          roughness = terra::terrain(dem, "roughness")
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 8)
        NULL
      })

      req(!is.null(result))
      out_nm <- trimws(input$out_name %||% "terrain_result")
      if (!nzchar(out_nm)) out_nm <- paste0(input$operation, "_result")
      names(result) <- out_nm
      raster_pool[[out_nm]] <- result
      result_r(list(raster = result, name = out_nm, op = input$operation))
      showNotification(paste0("'", out_nm, "' saved to layer pool."), type = "message")
    })

    output$preview <- renderPlot({
      res <- result_r()
      if (is.null(res)) {
        show_placeholder("Select a DEM and click Compute.")
        return()
      }
      pal <- if (res$op == "hillshade") grey.colors(256)
             else if (res$op == "aspect") rainbow(256)
             else terrain.colors(256)
      terra::plot(res$raster, col = pal, main = res$name,
                  mar = c(3.5, 3.5, 2, 7))
    })

    output$info <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      r <- res$raster
      d <- tryCatch(terra::crs(r, describe = TRUE), error = function(e) list(name = "?"))
      cat(sprintf(
        "Name    : %s\nOp      : %s\nDims    : %d × %d\nRes     : %.4f × %.4f\nCRS     : %s\n",
        res$name, res$op,
        nrow(r), ncol(r),
        terra::res(r)[1], terra::res(r)[2],
        d$name %||% "Unknown"
      ))
    })

    output$stats <- renderPrint({
      res <- result_r()
      if (is.null(res)) { cat("No result yet.\n"); return() }
      st <- tryCatch(
        terra::global(res$raster, fun = c("min","mean","max","sd"), na.rm = TRUE),
        error = function(e) NULL)
      if (is.null(st)) { cat("Stats unavailable.\n"); return() }
      cat(sprintf(
        "Min  : %.4f\nMean : %.4f\nMax  : %.4f\nSD   : %.4f\n",
        st$min, st$mean, st$max, st$sd))
    })

    output$dl_raster <- downloadHandler(
      filename = function() paste0(result_r()$name %||% "terrain", ".tif"),
      content  = function(file) {
        res <- result_r(); req(!is.null(res))
        terra::writeRaster(res$raster, file, overwrite = TRUE)
      }
    )

    output$dl_map <- downloadHandler(
      filename = function() {
        fmt <- input$map_fmt %||% "png"
        paste0(result_r()$name %||% "terrain", ".", fmt)
      },
      content = function(file) {
        res <- result_r(); req(!is.null(res))
        fmt  <- input$map_fmt   %||% "png"
        dpi  <- max(72L, min(600L, as.integer(input$map_dpi   %||% 150L)))
        ornt <- input$map_orient %||% "landscape"
        if (ornt == "landscape") { pw <- 11.69; ph <- 8.27 }
        else                     { pw <-  8.27; ph <- 11.69 }
        if (fmt == "pdf")       pdf(file, width = pw, height = ph)
        else if (fmt == "jpg")  jpeg(file, width = pw*dpi, height = ph*dpi, res = dpi, quality = 95)
        else                    png(file,  width = pw*dpi, height = ph*dpi, res = dpi)
        pal <- if (res$op == "hillshade") grey.colors(256)
               else if (res$op == "aspect") rainbow(256)
               else terrain.colors(256)
        terra::plot(res$raster, col = pal, main = res$name, mar = c(3.5, 3.5, 2, 7))
        dev.off()
      }
    )

    list(
      context = reactive({
        res <- result_r()
        if (is.null(res)) return("Terrain Analysis: no result computed yet.")
        paste0("Terrain Analysis | Op: ", res$op, " | Layer: ", res$name)
      }),
      plot = function() {
        res <- result_r()
        if (is.null(res)) return(invisible())
        pal <- if (res$op == "hillshade") grey.colors(256) else terrain.colors(256)
        terra::plot(res$raster, col = pal, main = res$name)
      }
    )
  })
}
