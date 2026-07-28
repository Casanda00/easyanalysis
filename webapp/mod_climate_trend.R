# mod_climate_trend.R — Climate Trend Analysis
# Apply Mann-Kendall test + Sen's slope pixel-by-pixel on a temporal raster stack.
# Mirrors the exercise: extract a target band from each year → trend::mk.test + sens.slope.
# Results (p-value, slope, significant-slope rasters) saved to raster_pool.

climateTrendCanvasUI <- function(id) {
  ns <- NS(id)
  leafletOutput(ns("map"), width = "100%", height = "100%")
}

climateTrendToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    open = "Data",
    accordion_panel("Data",
      uiOutput(ns("raster_sel_ui")),
      uiOutput(ns("band_info_ui")),
      hr(class = "my-2"),
      numericInput(ns("target_band"), "Band to extract per time step (e.g. 11 = November)",
                   value = 11, min = 1, step = 1),
      div(class = "alert alert-light p-2 mb-0",
        tags$small(
          icon("circle-info"), " If the raster has ", tags$b("12 × N layers"),
          " (monthly × years), band 11 is extracted from each 12-band block.",
          " If it already has one layer per year, all layers are used directly."
        )
      )
    ),
    accordion_panel("Analysis",
      numericInput(ns("sig_thresh"), "Significance threshold (p)", value=0.05,
                   min=0.001, max=0.5, step=0.001),
      actionButton(ns("run_btn"), tagList(icon("play"), " Run Mann-Kendall + Sen's Slope"),
                   class="btn-success w-100"),
      uiOutput(ns("run_status"))
    ),
    accordion_panel("Display",
      uiOutput(ns("lyr_sel_ui"))
    ),
    accordion_panel("Export",
      downloadButton(ns("dl_pval"),  tagList(icon("download"), " P-values (.tif)"),
                     class="btn-sm btn-outline-secondary w-100"),
      downloadButton(ns("dl_slope"), tagList(icon("download"), " Sen's slope (.tif)"),
                     class="btn-sm btn-outline-secondary w-100 mt-1"),
      downloadButton(ns("dl_sig"),   tagList(icon("download"), " Significant slope (.tif)"),
                     class="btn-sm btn-outline-secondary w-100 mt-1"),
      hr(class="my-2"),
      textInput(ns("pool_nm_out"), "Name prefix in Raster Pool", value="climate_trend"),
      actionButton(ns("to_pool"), tagList(icon("map"), " Save all to Raster Pool"),
                   class="btn-sm btn-outline-primary w-100 mt-1")
    )
  )
}

climateTrendServer <- function(id, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      r_pvalue = NULL,
      r_slope  = NULL,
      r_sig    = NULL,
      n_steps  = 0L,
      disp_lyr = "sig_slope"
    )

    # ---- Raster selector ----------------------------------------------------
    output$raster_sel_ui <- renderUI({
      nms <- names(reactiveValuesToList(raster_pool))
      if (!length(nms))
        return(p(class="text-muted small", "No rasters in pool. Upload via Add Data."))
      selectInput(ns("raster_src"), "Multi-band raster stack", choices=nms)
    })

    output$band_info_ui <- renderUI({
      nm <- input$raster_src %||% ""
      if (!nzchar(nm)) return(NULL)
      r <- raster_pool[[nm]]
      if (is.null(r)) return(NULL)
      n <- terra::nlyr(r)
      p_msg <- if (n %% 12 == 0 && n >= 24)
        paste0(n, " layers detected → ", n %/% 12, " years of monthly data (12 bands/year).")
      else
        paste0(n, " layers detected → treated as ", n, " individual time steps.")
      p(class="text-muted small", p_msg)
    })

    # ---- Run analysis -------------------------------------------------------
    observeEvent(input$run_btn, {
      nm <- input$raster_src %||% ""
      req(nzchar(nm))
      r_in <- raster_pool[[nm]]
      req(!is.null(r_in))

      if (!.ensure_pkg("trend", quietly=TRUE)) {
        showNotification(
          "Package 'trend' is not installed. Run: install.packages('trend')",
          type="error", duration=8)
        return()
      }

      n_lyr <- terra::nlyr(r_in)
      band  <- max(1L, min(as.integer(input$target_band %||% 11), n_lyr))

      # Determine which layers to stack
      sel <- if (n_lyr %% 12 == 0 && n_lyr >= 24)
        seq(band, n_lyr, by = 12)   # monthly data: one band per year
      else
        seq_len(n_lyr)              # already annual

      if (length(sel) < 4) {
        showNotification("Need at least 4 time steps for a trend test.", type="error")
        return()
      }

      stk <- r_in[[sel]]
      rv$n_steps <- length(sel)

      withProgress(message=paste0("Mann-Kendall on ", length(sel)," time steps…"), value=0.1, {

        mk_fn <- function(x) {
          if (all(is.na(x))) return(c(NA_real_, NA_real_))
          tryCatch({
            mk  <- trend::mk.test(x)
            sen <- trend::sens.slope(x)
            c(pvalue=as.numeric(mk$p.value), slope=as.numeric(sen$estimates))
          }, error=function(e) c(NA_real_, NA_real_))
        }

        result <- tryCatch(terra::app(stk, mk_fn),
                           error=function(e) { showNotification(e$message,type="error"); NULL })
        if (is.null(result)) return()

        names(result) <- c("pvalue","slope")
        setProgress(0.9)

        thresh       <- input$sig_thresh %||% 0.05
        rv$r_pvalue  <- result[["pvalue"]]
        rv$r_slope   <- result[["slope"]]
        rv$r_sig     <- terra::ifel(result[["pvalue"]] < thresh, result[["slope"]], NA)

        setProgress(1)
        showNotification(
          paste0("Trend analysis done: ", length(sel), " time steps processed."),
          type="message", duration=4)
      })
    })

    output$run_status <- renderUI({
      if (rv$n_steps == 0) return(NULL)
      p(class="text-muted small mt-1",
        icon("check-circle"), paste(rv$n_steps, "time steps analysed."))
    })

    # ---- Display selector ---------------------------------------------------
    output$lyr_sel_ui <- renderUI({
      req(!is.null(rv$r_sig))
      selectInput(ns("disp"), "Layer to display",
        choices=c("Significant slope (p<thresh)"="sig_slope",
                  "Sen's slope — all pixels"="slope",
                  "Mann-Kendall p-value"="pvalue"),
        selected=rv$disp_lyr)
    })
    observeEvent(input$disp, { rv$disp_lyr <- input$disp %||% "sig_slope" })

    # ---- Base map -----------------------------------------------------------
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
      lyr <- rv$disp_lyr
      r <- switch(lyr,
        sig_slope = rv$r_sig,
        slope     = rv$r_slope,
        pvalue    = rv$r_pvalue,
        NULL
      )
      req(!is.null(r))

      r_wgs <- tryCatch(.to_wgs84(r), error=function(e) NULL)
      if (is.null(r_wgs)) return()
      r_st <- tryCatch(stars::st_as_stars(r_wgs), error=function(e) NULL)
      if (is.null(r_st)) return()

      pal_name <- if (lyr == "pvalue") "YlOrRd" else "RdBu"
      use_rev  <- lyr != "pvalue"

      leafletProxy("map", session=session) %>%
        clearImages() %>% clearControls() %>%
        leafem::addGeoRaster(
          x            = r_st,
          group        = lyr,
          opacity      = 0.85,
          colorOptions = leafem::colorOptions(
            palette  = if (use_rev) rev(hcl.colors(256,"RdBu")) else hcl.colors(256,"YlOrRd"),
            na.color = "transparent"
          )
        ) %>%
        fitBounds(terra::xmin(r_wgs), terra::ymin(r_wgs),
                  terra::xmax(r_wgs), terra::ymax(r_wgs))
    })

    # ---- Downloads ----------------------------------------------------------
    .dl_tif <- function(r_fn, fname) {
      downloadHandler(
        filename = function() fname,
        content  = function(f) { r <- r_fn(); req(!is.null(r)); terra::writeRaster(r,f,overwrite=TRUE) }
      )
    }

    output$dl_pval  <- .dl_tif(reactive(rv$r_pvalue), "mk_pvalue.tif")
    output$dl_slope <- .dl_tif(reactive(rv$r_slope),  "sens_slope.tif")
    output$dl_sig   <- .dl_tif(reactive(rv$r_sig),    "sig_slope.tif")

    observeEvent(input$to_pool, {
      req(!is.null(rv$r_pvalue))
      nm <- trimws(input$pool_nm_out %||% "climate_trend")
      if (!nzchar(nm)) nm <- "climate_trend"
      raster_pool[[paste0(nm,"_pvalue")]] <- rv$r_pvalue
      raster_pool[[paste0(nm,"_slope")]]  <- rv$r_slope
      raster_pool[[paste0(nm,"_sig")]]    <- rv$r_sig
      showNotification(
        paste0("Saved '", nm, "_pvalue', '_slope', '_sig' to Raster Pool.\n",
               "Use Raster & Vector → Extract Zonal Statistics to feed values into model screens."),
        type="message", duration=6)
    })

    list(
      context = reactive({ list(n_steps=rv$n_steps) }),
      plot    = function() NULL
    )
  })
}
