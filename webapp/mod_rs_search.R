# =============================================================================
# mod_rs_search.R  --  Satellite Data Search & Download
# Canvas : leaflet map (60 vh) + scrollable results table below
# Tools  : Data Source | Search | Results | Access | Credentials | Map Export
#
# Sensors covered:
#   Sentinel-1 GRD / S-2 L2A / S-2 L1C / S-3 OLCI / S-5P (via CDSE STAC)
#   Sentinel-2 L2A (Element84 AWS, no-auth)
#   Landsat 8/9 / 7 / 4-5 / MSS  (Element84 Landsat C2L2, filtered by platform)
#   MODIS MOD09A1 / MOD13A1 / MOD11A2 / MOD14A1 / MOD10A1 / MYD13A2
#       (NASA CMR STAC LPCLOUD)
#
# Streaming:  terra::rast("/vsicurl/URL") clips cloud COG to AOI → raster_pool
# Auth:       CDSE OAuth2 password grant (client_id = "cdse-public")
# Map export: ggplot2 + ggspatial + stars → PNG / PDF layout
# =============================================================================

# ---- Sensor catalog --------------------------------------------------------

.SENSORS <- list(
  # Sentinel via CDSE (public search; download/stream free after login)
  "Sentinel-1 GRD (C-band SAR)"      = list(ep="cdse", col="SENTINEL-1-GRD",      cloud=FALSE, pfilt=NULL, desc="All-weather SAR. IW/EW/SM modes, VV/VH polarisation. 5-40m."),
  "Sentinel-2 L2A — CDSE"            = list(ep="cdse", col="SENTINEL-2-L2A",       cloud=TRUE,  pfilt=NULL, desc="13-band surface reflectance. 10/20/60m. Free via CDSE login."),
  "Sentinel-2 L1C — CDSE"            = list(ep="cdse", col="SENTINEL-2-L1C",       cloud=TRUE,  pfilt=NULL, desc="Top-of-atmosphere reflectance, 10-60m. Requires atmospheric correction."),
  "Sentinel-3 OLCI (ocean/land)"     = list(ep="cdse", col="SENTINEL-3-OLCI-L1B",  cloud=TRUE,  pfilt=NULL, desc="21-band ocean & land colour, 300m. Full-resolution radiances."),
  "Sentinel-5P (NO2 / CO / O3 / CH4)"= list(ep="cdse", col="SENTINEL-5P-L2",       cloud=FALSE, pfilt=NULL, desc="Atmospheric composition at 5.5x3.5 km. NO2, O3, SO2, CO, CH4, HCHO."),
  # Sentinel-2 via Element84 (no auth at all)
  "Sentinel-2 L2A — AWS (no-auth)"   = list(ep="e84",  col="sentinel-2-l2a",       cloud=TRUE,  pfilt=NULL, desc="Same S-2 L2A product served as public COGs from AWS. No credentials needed."),
  # Landsat via Element84 — filtered by platform after search
  "Landsat 8/9 OLI (C2L2)"          = list(ep="e84",  col="landsat-c2-l2",         cloud=TRUE,  pfilt=c("LANDSAT_8","LANDSAT_9"), desc="30m surface reflectance, 2013-present. OLI/TIRS."),
  "Landsat 7 ETM+ (C2L2)"           = list(ep="e84",  col="landsat-c2-l2",         cloud=TRUE,  pfilt="LANDSAT_7",               desc="30m, 1999-2022. SLC-Off gaps after May 2003."),
  "Landsat 4-5 TM (C2L2)"           = list(ep="e84",  col="landsat-c2-l2",         cloud=TRUE,  pfilt=c("LANDSAT_4","LANDSAT_5"), desc="30m, 1982-2012. Thermal band 120m."),
  "Landsat 1-5 MSS (C2L1)"          = list(ep="e84",  col="landsat-c2-l1",         cloud=TRUE,  pfilt=c("LANDSAT_1","LANDSAT_2","LANDSAT_3","LANDSAT_4","LANDSAT_5"), desc="60-80m historic imagery, 1972-2001."),
  # MODIS via NASA CMR STAC (public search)
  "MODIS Surface Reflectance MOD09A1"= list(ep="nasa", col="MOD09A1.v061",   cloud=FALSE, pfilt=NULL, desc="8-day 500m surface reflectance, 7 bands. Terra."),
  "MODIS NDVI / EVI MOD13A1"         = list(ep="nasa", col="MOD13A1.v061",   cloud=FALSE, pfilt=NULL, desc="16-day 500m NDVI and EVI composites. Terra."),
  "MODIS LST MOD11A2"                = list(ep="nasa", col="MOD11A2.v061",   cloud=FALSE, pfilt=NULL, desc="8-day 1 km land surface temperature, day & night. Terra."),
  "MODIS Fire MOD14A1"               = list(ep="nasa", col="MOD14A1.v061",   cloud=FALSE, pfilt=NULL, desc="Daily 1 km active fire/fire radiative power. Terra."),
  "MODIS Snow MOD10A1"               = list(ep="nasa", col="MOD10A1.v061",   cloud=FALSE, pfilt=NULL, desc="Daily 500m fractional snow cover (NDSI). Terra."),
  "MODIS NDVI MYD13A2 (Aqua)"        = list(ep="nasa", col="MYD13A2.v061",   cloud=FALSE, pfilt=NULL, desc="16-day 1 km NDVI/EVI from Aqua. Pair with MOD13 for 8-day composites.")
)

.ENDPOINTS <- c(
  cdse = "https://stac.dataspace.copernicus.eu/v1",
  e84  = "https://earth-search.aws.element84.com/v1",
  nasa = "https://cmr.earthdata.nasa.gov/stac/LPCLOUD"
)

# ---- Module-local helpers --------------------------------------------------

.rs_parse_draw <- function(feat) {
  if (is.null(feat)) return(NULL)
  coords <- feat$geometry$coordinates[[1]]
  mat <- do.call(rbind, lapply(coords, function(p) c(as.numeric(p[[1]]), as.numeric(p[[2]]))))
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(mat)), crs = 4326))
}

.cdse_token <- function(username, password) {
  resp <- httr::POST(
    "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token",
    body   = list(grant_type="password", username=username,
                  password=password, client_id="cdse-public"),
    encode = "form"
  )
  if (httr::status_code(resp) != 200L)
    stop(paste("CDSE auth failed (", httr::status_code(resp), "):"),
         httr::content(resp, "text", encoding = "UTF-8"))
  tok <- httr::content(resp, as = "parsed")$access_token
  if (is.null(tok)) stop("CDSE returned no access_token.")
  tok
}

.features_to_df <- function(features) {
  if (length(features) == 0) return(data.frame())
  rows <- lapply(seq_along(features), function(i) {
    f  <- features[[i]]
    p  <- f$properties
    cc <- p[["eo:cloud_cover"]] %||% p[["cloudCover"]] %||% NA_real_
    plt <- p[["platform"]] %||% p[["constellation"]] %||% p[["sat:orbit_state"]] %||% ""
    data.frame(
      idx       = i,
      id        = f$id,
      date      = substr(p$datetime %||% p$start_datetime %||% "", 1, 10),
      cloud_pct = if (is.numeric(cc)) round(as.numeric(cc), 1) else NA_real_,
      platform  = as.character(plt),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# ---- Canvas UI -------------------------------------------------------------

rsSearchCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    # Map (60 vh)
    div(
      style = "height:60vh; position:relative; width:100%;",
      leafletOutput(ns("map"), width = "100%", height = "100%"),
      absolutePanel(
        top = 10, right = 60,
        style = paste0(
          "z-index:800; background:rgba(255,255,255,.9); padding:8px 12px;",
          " border-radius:6px; font-size:12px; min-width:200px; max-width:300px;",
          " box-shadow:0 2px 8px rgba(0,0,0,.15); pointer-events:none;"
        ),
        uiOutput(ns("map_overlay"))
      )
    ),
    # Results table (appears after search)
    uiOutput(ns("results_panel"))
  )
}

# ---- Tools UI --------------------------------------------------------------

rsSearchToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Download Spatial Data", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "source",

      # 1. Data Source
      accordion_panel("Data Source", value = "source", icon = icon("satellite"),
        selectInput(ns("sensor"), "Sensor / Product",
          choices  = names(.SENSORS),
          selected = "Sentinel-2 L2A — AWS (no-auth)"
        ),
        uiOutput(ns("sensor_desc"))
      ),

      # 2. Search
      accordion_panel("Search", value = "search", icon = icon("magnifying-glass"),
        tags$p(class = "small text-muted mb-1",
          "1. Draw a bounding box on the map.  2. Set date range.  3. Search."),
        fluidRow(
          column(6, dateInput(ns("date_from"), "From", value = Sys.Date() - 90)),
          column(6, dateInput(ns("date_to"),   "To",   value = Sys.Date()))
        ),
        uiOutput(ns("cloud_ui")),
        numericInput(ns("max_results"), "Max results", value = 20, min = 1, max = 500, step = 10),
        actionButton(ns("run_search"), "Search Catalog",
          class = "btn-primary btn-sm w-100 mt-1", icon = icon("search"))
      ),

      # 3. Results (scene picker)
      accordion_panel("Results", value = "results", icon = icon("list"),
        uiOutput(ns("result_summary")),
        uiOutput(ns("scene_picker"))
      ),

      # 4. Access / Stream
      accordion_panel("Access & Download", value = "access", icon = icon("cloud-arrow-down"),
        uiOutput(ns("asset_picker")),
        tags$hr(style = "margin:6px 0"),
        tags$b("Stream COG to Raster Pool"),
        tags$p(class = "small text-muted mb-1",
          "Reads only the AOI clip from the cloud. Result appears instantly in Raster Analysis."),
        actionButton(ns("stream_cog"), "Stream to Raster Pool",
          class = "btn-success btn-sm w-100", icon = icon("bolt")),
        verbatimTextOutput(ns("stream_log")),
        tags$hr(style = "margin:6px 0"),
        tags$b("Asset URL"),
        tags$p(class = "small text-muted mb-0", "Open in browser or copy for external tools."),
        uiOutput(ns("dl_link"))
      ),

      # 5. Credentials
      accordion_panel("Credentials", value = "creds", icon = icon("key"),
        tags$p(class = "small text-muted",
          "Sentinel-1 / 3 / 5P streaming requires CDSE login.",
          " Free account: dataspace.copernicus.eu"),
        textInput(ns("cdse_user"), "CDSE Email"),
        passwordInput(ns("cdse_pass"), "CDSE Password"),
        actionButton(ns("auth_cdse"), "Authenticate",
          class = "btn-outline-secondary btn-sm w-100 mt-1"),
        uiOutput(ns("auth_status")),
        tags$hr(style = "margin:8px 0"),
        tags$p(class = "small text-muted",
          "NASA MODIS download (not streaming) requires Earthdata credentials at:",
          tags$a("urs.earthdata.nasa.gov", href="#", target="_blank"))
      ),

      # 6. Map Layout Export
      accordion_panel("Map Export", value = "export", icon = icon("print"),
        tags$p(class = "small text-muted mb-1",
          "Exports the most recently streamed raster as a print-ready map."),
        textInput(ns("map_title"),    "Title",    value = "Remote Sensing Map"),
        textInput(ns("map_subtitle"), "Subtitle", value = ""),
        textInput(ns("legend_lbl"),   "Legend label", value = "Value"),
        fluidRow(
          column(6, selectInput(ns("export_fmt"), "Format",
            choices = c("PNG" = "png", "PDF" = "pdf"), selected = "png")),
          column(6, numericInput(ns("export_dpi"), "DPI", value = 150, min = 72, max = 600))
        ),
        checkboxInput(ns("add_north"), "North arrow", value = TRUE),
        checkboxInput(ns("add_scale"), "Scale bar",   value = TRUE),
        checkboxInput(ns("add_grid"),  "Graticule",   value = FALSE),
        downloadButton(ns("dl_map"), "Export Map",
          class = "btn-sm btn-success w-100 mt-1")
      )
    )
  )
}

# ---- Server ----------------------------------------------------------------

rsSearchServer <- function(id, dataset_pool, active_dataset, raster_pool) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      drawn     = NULL,   # sf polygon from draw
      items     = NULL,   # rstac items result
      item_df   = NULL,   # data.frame summary
      cdse_tok  = NULL,   # CDSE bearer token
      last_rast = NULL    # most-recently streamed SpatRaster (for export)
    )

    # ---- Base map ----------------------------------------------------------
    output$map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("OpenStreetMap",     group = "OSM") %>%
        addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
        addProviderTiles("CartoDB.Positron",  group = "CartoDB") %>%
        addLayersControl(
          baseGroups = c("OSM", "Satellite", "CartoDB"),
          options    = layersControlOptions(collapsed = FALSE)
        ) %>%
        leaflet.extras::addDrawToolbar(
          targetGroup         = "drawn",
          polylineOptions     = FALSE,
          circleOptions       = FALSE,
          markerOptions       = FALSE,
          circleMarkerOptions = FALSE,
          rectangleOptions    = leaflet.extras::drawRectangleOptions(),
          polygonOptions      = leaflet.extras::drawPolygonOptions(),
          editOptions         = leaflet.extras::editToolbarOptions()
        ) %>%
        setView(lng = 25.7, lat = 62.5, zoom = 4)
    })

    observeEvent(input$map_draw_new_feature, {
      rv$drawn <- tryCatch(.rs_parse_draw(input$map_draw_new_feature), error = function(e) NULL)
    })
    observeEvent(input$map_draw_deleted_features, { rv$drawn <- NULL })

    # ---- Dynamic sidebar UI ------------------------------------------------

    output$sensor_desc <- renderUI({
      s <- .SENSORS[[input$sensor %||% ""]]
      if (is.null(s)) return(NULL)
      tags$p(class = "small text-muted mt-1 mb-0", s$desc)
    })

    output$cloud_ui <- renderUI({
      s <- .SENSORS[[input$sensor %||% ""]]
      if (!is.null(s) && isTRUE(s$cloud))
        sliderInput(ns("cloud_max"), "Max cloud cover (%)", min = 0, max = 100, value = 30)
    })

    output$map_overlay <- renderUI({
      df <- rv$item_df
      if (is.null(df)) {
        return(tags$p(class = "small text-muted fst-italic", "Draw AOI → Search"))
      }
      tags$div(
        tags$strong(nrow(df), " scene(s) found"),
        tags$p(style = "margin:0; font-size:11px; color:#555",
          substr(input$sensor %||% "", 1, 35)),
        tags$p(style = "margin:0; font-size:11px; color:#2e7d32",
          paste0(input$date_from, " – ", input$date_to))
      )
    })

    output$result_summary <- renderUI({
      df <- rv$item_df
      if (is.null(df))
        return(tags$p(class = "small text-muted fst-italic", "No search run yet."))
      tags$p(class = "small mb-1",
        tags$b(nrow(df)), " scenes — select one to access assets.")
    })

    output$scene_picker <- renderUI({
      df <- rv$item_df
      if (is.null(df) || nrow(df) == 0) return(NULL)
      lbl <- paste0(
        df$date,
        ifelse(!is.na(df$cloud_pct), paste0("  ☁ ", df$cloud_pct, "%"), ""),
        "  ", substr(df$id, 1, 22), "…"
      )
      radioButtons(ns("sel_scene"), NULL,
        choices  = setNames(as.character(df$idx), lbl),
        selected = as.character(df$idx[1])
      )
    })

    output$asset_picker <- renderUI({
      req(rv$items, input$sel_scene)
      idx   <- as.integer(input$sel_scene)
      feat  <- rv$items$features[[idx]]
      req(feat)
      nms   <- names(feat$assets)
      # Keep likely raster assets; exclude metadata/json/xml/overview
      rast  <- nms[!grepl("metadata|json|xml|thumbnail|overview|rendered|alternate|tilejson",
                           nms, ignore.case = TRUE)]
      if (length(rast) == 0) rast <- nms
      selectInput(ns("asset_key"), "Band / Asset", choices = rast)
    })

    output$dl_link <- renderUI({
      req(rv$items, input$sel_scene, input$asset_key)
      idx  <- as.integer(input$sel_scene)
      feat <- rv$items$features[[idx]]
      url  <- feat$assets[[input$asset_key]]$href
      if (is.null(url) || !nzchar(url))
        return(tags$p(class = "small text-muted", "No URL available."))
      tagList(
        tags$a(class = "btn btn-sm btn-outline-secondary w-100 mt-1",
          href = url, target = "_blank",
          icon("external-link-alt"), " Open / download in browser")
      )
    })

    output$auth_status <- renderUI({
      if (!is.null(rv$cdse_tok))
        tags$p(class = "small text-success mt-1 mb-0", "✓ CDSE authenticated")
      else
        tags$p(class = "small text-muted mt-1 mb-0", "Not authenticated.")
    })

    # ---- CDSE auth ---------------------------------------------------------
    observeEvent(input$auth_cdse, {
      req(input$cdse_user, input$cdse_pass)
      tryCatch({
        rv$cdse_tok <- .cdse_token(input$cdse_user, input$cdse_pass)
        showNotification("CDSE authenticated.", type = "message")
      }, error = function(e) {
        showNotification(paste("Auth error:", conditionMessage(e)), type = "error", duration = 8)
      })
    })

    # ---- Search ------------------------------------------------------------
    observeEvent(input$run_search, {
      s <- .SENSORS[[input$sensor %||% ""]]
      req(s)
      if (!.ensure_pkg("rstac", quietly = TRUE)) {
        showNotification("Install the 'rstac' package to use satellite search.", type = "error")
        return()
      }

      # Build bbox
      bbox <- if (!is.null(rv$drawn)) {
        bb <- sf::st_bbox(rv$drawn)
        c(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])
      } else {
        showNotification("No AOI drawn — searching globally (may be slow).", type = "warning")
        c(-180, -90, 180, 90)
      }

      dt_str <- paste0(
        format(as.Date(input$date_from), "%Y-%m-%dT00:00:00Z"), "/",
        format(as.Date(input$date_to),   "%Y-%m-%dT23:59:59Z")
      )

      withProgress(message = "Searching satellite catalog…", value = 0.5, {
        tryCatch({
          ep  <- .ENDPOINTS[[s$ep]]
          req_obj <- rstac::stac(ep) %>%
            rstac::stac_search(
              collections = s$col,
              bbox        = bbox,
              datetime    = dt_str,
              limit       = as.integer(input$max_results %||% 20)
            )

          # Include CDSE bearer token if available
          items <- if (s$ep == "cdse" && !is.null(rv$cdse_tok)) {
            rstac::get_request(req_obj,
              httr::add_headers(Authorization = paste0("Bearer ", rv$cdse_tok)))
          } else {
            rstac::get_request(req_obj)
          }

          # Cloud cover filter (client-side)
          if (isTRUE(s$cloud) && isTruthy(input$cloud_max)) {
            cloud_lim <- as.numeric(input$cloud_max)
            items <- rstac::items_filter(items, filter_fn = function(x) {
              cc <- x$properties[["eo:cloud_cover"]] %||%
                    x$properties[["cloudCover"]]     %||% 0
              as.numeric(cc) <= cloud_lim
            })
          }

          # Platform filter (Landsat variant separation)
          if (!is.null(s$pfilt)) {
            pf <- s$pfilt
            items <- rstac::items_filter(items, filter_fn = function(x) {
              plt <- toupper(x$properties$platform %||% x$properties$constellation %||% "")
              plt %in% pf
            })
          }

          rv$items   <- items
          rv$item_df <- .features_to_df(items$features)
          n          <- length(items$features)

          # Show footprints on map
          .add_footprints(items$features, session)

          showNotification(paste(n, "scene(s) found."), type = "message")
        }, error = function(e) {
          showNotification(paste("Search error:", conditionMessage(e)), type = "error", duration = 10)
        })
      })
    })

    # Draw bounding-box footprints for each result
    .add_footprints <- function(features, session) {
      lp <- leafletProxy("map", session = session) %>% clearGroup("footprints")
      for (feat in features) {
        bb <- feat$bbox
        if (is.null(bb) || length(bb) < 4) next
        dt  <- substr(feat$properties$datetime %||% feat$properties$start_datetime %||% "", 1, 10)
        cc  <- feat$properties[["eo:cloud_cover"]] %||% feat$properties[["cloudCover"]] %||% NA
        lbl <- paste0(feat$id, "\n", dt,
          if (!is.na(cc)) paste0("  ☁ ", round(as.numeric(cc), 1), "%") else "")
        lp <- lp %>% addRectangles(
          lng1 = bb[[1]], lat1 = bb[[2]], lng2 = bb[[3]], lat2 = bb[[4]],
          group       = "footprints",
          color       = "#e65100", weight = 1.5,
          fillColor   = "#ff9800", fillOpacity = 0.10,
          label       = lbl, layerId = paste0("fp_", feat$id)
        )
      }
    }

    # ---- Results table (canvas) --------------------------------------------
    output$results_panel <- renderUI({
      df <- rv$item_df
      if (is.null(df) || nrow(df) == 0) return(NULL)
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center bg-light",
          paste0("Results (", nrow(df), " scenes)"),
          tags$small(class = "text-muted", substr(input$sensor %||% "", 1, 40))
        ),
        DT::dataTableOutput(ns("results_dt"), height = "260px")
      )
    })

    output$results_dt <- DT::renderDataTable({
      df <- rv$item_df
      req(df)
      disp <- df[, c("date", "cloud_pct", "platform", "id"), drop = FALSE]
      colnames(disp) <- c("Date", "Cloud %", "Platform", "Scene ID")
      DT::datatable(disp,
        selection = "single",
        options   = list(pageLength = 10, scrollX = TRUE, dom = "tip"),
        rownames  = FALSE
      )
    })

    # Sync DT row click to scene radio
    observeEvent(input$results_dt_rows_selected, {
      sel <- input$results_dt_rows_selected
      df  <- rv$item_df
      if (!is.null(sel) && !is.null(df) && sel <= nrow(df)) {
        updateRadioButtons(session, "sel_scene", selected = as.character(df$idx[sel]))
        # Highlight selected footprint
        bb <- rv$items$features[[df$idx[sel]]]$bbox
        if (!is.null(bb) && length(bb) >= 4)
          leafletProxy("map", session = session) %>%
            fitBounds(lng1 = bb[[1]], lat1 = bb[[2]], lng2 = bb[[3]], lat2 = bb[[4]])
      }
    })

    # ---- COG Streaming -----------------------------------------------------
    stream_log_val <- reactiveVal("")
    output$stream_log <- renderText(stream_log_val())

    observeEvent(input$stream_cog, {
      req(rv$items, input$sel_scene, input$asset_key)
      idx   <- as.integer(input$sel_scene)
      feat  <- rv$items$features[[idx]]
      url   <- feat$assets[[input$asset_key]]$href
      if (!isTruthy(url)) {
        stream_log_val("No URL for this asset.")
        return()
      }
      stream_log_val("Connecting…")
      withProgress(message = "Streaming COG from cloud…", value = 0.5, {
        tryCatch({
          vsi_url <- if (startsWith(url, "http")) paste0("/vsicurl/", url) else url
          r <- terra::rast(vsi_url)

          # Crop to drawn AOI if present
          if (!is.null(rv$drawn)) {
            aoi_v <- terra::vect(sf::st_transform(rv$drawn, terra::crs(r)))
            r     <- terra::crop(r, aoi_v, mask = FALSE)
          }

          nm <- paste0(substr(feat$id, 1, 25), "_", input$asset_key)
          raster_pool[[nm]] <- r
          rv$last_rast      <- r

          msg <- paste0("'", nm, "' streamed (", ncol(r), "×", nrow(r), " px, ",
                        terra::nlyr(r), " band(s)). Switch to Raster Analysis to process.")
          stream_log_val(msg)
          showNotification(msg, type = "message", duration = 7)
        }, error = function(e) {
          err <- paste("Stream failed:", conditionMessage(e))
          stream_log_val(err)
          showNotification(paste(err, "— Authenticate in Credentials if needed."),
            type = "error", duration = 10)
        })
      })
    })

    # ---- Map layout export -------------------------------------------------
    output$dl_map <- downloadHandler(
      filename = function() {
        paste0("map_export_", Sys.Date(), ".", input$export_fmt %||% "png")
      },
      content = function(file) {
        r <- rv$last_rast
        if (is.null(r)) {
          # Placeholder if nothing streamed
          png(file, width = 800, height = 600)
          show_placeholder("Stream a scene first, then export the map.")
          dev.off()
          return()
        }

        if (!.ensure_pkg("ggspatial", quietly = TRUE))
          stop("Install 'ggspatial' for map export.")
        if (!.ensure_pkg("stars", quietly = TRUE))
          stop("Install 'stars' for map export.")

        # Project to WGS84 for display
        r1   <- tryCatch(terra::project(r[[1]], "EPSG:4326"), error = function(e) r[[1]])
        r_st <- stars::st_as_stars(r1)

        p <- ggplot2::ggplot() +
          stars::geom_stars(data = r_st, na.action = na.omit) +
          ggplot2::scale_fill_viridis_c(
            name     = trimws(input$legend_lbl %||% "Value"),
            na.value = NA
          ) +
          ggplot2::coord_sf()

        if (isTRUE(input$add_north))
          p <- p + ggspatial::annotation_north_arrow(
            location = "tr",
            height = unit(0.9, "cm"), width = unit(0.9, "cm"),
            style  = ggspatial::north_arrow_fancy_orienteering()
          )
        if (isTRUE(input$add_scale))
          p <- p + ggspatial::annotation_scale(location = "bl", width_hint = 0.25)
        if (isTRUE(input$add_grid))
          p <- p + ggplot2::theme(panel.grid.major = ggplot2::element_line(
            colour = "grey80", linewidth = 0.3))

        subtitle <- trimws(input$map_subtitle %||% "")
        p <- p +
          ggplot2::labs(
            title    = trimws(input$map_title %||% "Remote Sensing Map"),
            subtitle = if (nzchar(subtitle)) subtitle else NULL,
            x = "Longitude", y = "Latitude"
          ) +
          ggplot2::theme_bw(base_size = 11) +
          ggplot2::theme(legend.position = "right")

        ggplot2::ggsave(
          filename = file,
          plot     = p,
          dpi      = as.integer(input$export_dpi %||% 150L),
          width    = 10, height = 8, units = "in"
        )
      }
    )

    # ---- AI co-pilot context -----------------------------------------------
    list(
      context = reactive({
        df <- rv$item_df
        if (is.null(df))
          return("Satellite search module: no search run yet.")
        paste0(
          "Satellite search: ", input$sensor, "\n",
          "Date: ", input$date_from, " – ", input$date_to, "\n",
          "Results: ", nrow(df), " scene(s)\n",
          if (nrow(df) > 0) paste0(
            "First: ", df$date[1],
            if (!is.na(df$cloud_pct[1])) paste0(" cloud=", df$cloud_pct[1], "%"),
            "\n"
          ) else "",
          "Last stream: ", stream_log_val()
        )
      }),
      plot = function() NULL
    )
  })
}
