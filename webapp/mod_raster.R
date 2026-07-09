# =============================================================================
# mod_raster.R  --  Spatial Analysis (QGIS-like unified module)
# Canvas : full-height leaflet map + floating layer manager overlay
# Tools  : Symbology | Raster Operations | Vector Operations | Export
# =============================================================================

# ---- Module-local helpers ---------------------------------------------------

.parse_draw <- function(feat) {
  if (is.null(feat)) return(NULL)
  coords <- feat$geometry$coordinates[[1]]
  mat    <- do.call(rbind, lapply(coords, function(p) c(as.numeric(p[[1]]), as.numeric(p[[2]]))))
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(mat)), crs = 4326))
}

.read_vector <- function(files) {
  if (is.null(files) || nrow(files) == 0) return(NULL)
  ext <- tolower(tools::file_ext(files$name[1]))
  if (ext %in% c("gpkg", "geojson", "json")) return(sf::st_read(files$datapath[1], quiet = TRUE))
  tmp <- file.path(tempdir(), paste0("shp_", as.integer(Sys.time())))
  dir.create(tmp, showWarnings = FALSE)
  for (i in seq_len(nrow(files)))
    file.copy(files$datapath[i], file.path(tmp, files$name[i]), overwrite = TRUE)
  shp_name <- files$name[grep("\\.shp$", files$name, ignore.case = TRUE)]
  if (length(shp_name) == 0) stop("No .shp file found in upload.")
  sf::st_read(file.path(tmp, shp_name[1]), quiet = TRUE)
}

.to_wgs84 <- function(r1) {
  if (nchar(terra::crs(r1)) == 0) terra::crs(r1) <- "EPSG:4326"
  if (!terra::same.crs(r1, "EPSG:4326")) r1 <- terra::project(r1, "EPSG:4326")
  r1
}

.pal_colors <- function(name, n = 128) {
  switch(name,
    viridis  = viridisLite::viridis(n),
    magma    = viridisLite::magma(n),
    plasma   = viridisLite::plasma(n),
    inferno  = viridisLite::inferno(n),
    RdYlGn   = colorRampPalette(c("#d73027", "#ffffbf", "#1a9850"))(n),
    terrain  = terrain.colors(n),
    Greens   = colorRampPalette(c("#f7fcf5", "#00441b"))(n),
    Greys    = colorRampPalette(c("#ffffff", "#000000"))(n),
    viridisLite::viridis(n)
  )
}

.bbox_wgs84 <- function(ly) {
  tryCatch({
    if (ly$type == "raster") {
      r1 <- .to_wgs84(ly$data[[1]])
      e  <- terra::ext(r1)
      c(e[1], e[3], e[2], e[4])
    } else {
      v4 <- sf::st_transform(ly$data, 4326)
      bb <- sf::st_bbox(v4)
      c(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])
    }
  }, error = function(e) NULL)
}

# ---- Canvas UI --------------------------------------------------------------

rasterCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    style = "position:relative; height:calc(100vh - 72px); width:100%;",
    leafletOutput(ns("map"), width = "100%", height = "100%"),

    # Floating layer manager panel (top-left, overlaid on the map)
    absolutePanel(
      top = 10, left = 10, width = "250px",
      style = paste0(
        "z-index:800; border-radius:8px; overflow:hidden;",
        " box-shadow:0 2px 10px rgba(0,0,0,.28);"
      ),
      # Header (green bar, click to collapse)
      div(
        style = paste0(
          "background:#2e7d32; color:#fff; padding:6px 10px;",
          " display:flex; align-items:center; justify-content:space-between;",
          " cursor:pointer; user-select:none;"
        ),
        onclick = paste0(
          "var b=this.nextElementSibling;",
          " b.style.display=(b.style.display==='none'?'block':'none');"
        ),
        tags$span(
          style = "font-size:12px; font-weight:600; display:flex; align-items:center; gap:6px;",
          icon("layer-group", style = "font-size:11px;"), " Layers"
        ),
        tags$div(
          style = "display:flex; gap:6px;",
          tags$span(
            title = "Zoom to all layers",
            style = "cursor:pointer; font-size:12px; opacity:.85;",
            onclick = sprintf(
              "event.stopPropagation(); Shiny.setInputValue('%s', Date.now(), {priority:'event'});",
              ns("zoom_all")
            ),
            icon("compress")
          ),
          tags$span(
            title = "Add layer from data pool",
            style = "cursor:pointer; font-size:16px; font-weight:700; opacity:.85; line-height:1;",
            onclick = sprintf(
              "event.stopPropagation(); Shiny.setInputValue('%s', Date.now(), {priority:'event'});",
              ns("add_layer_btn")
            ),
            "+"
          )
        )
      ),
      # Body (layer list)
      div(
        style = paste0(
          "display:block; background:rgba(255,255,255,.96);",
          " max-height:calc(100vh - 210px); overflow-y:auto;"
        ),
        uiOutput(ns("layer_list_ui"))
      )
    ),

    # Map status bar (bottom-left, above leaflet attribution)
    absolutePanel(
      bottom = 28, left = 10,
      style = paste0(
        "z-index:700; background:rgba(255,255,255,.88); padding:3px 10px;",
        " border-radius:5px; font-size:11px; pointer-events:none;",
        " box-shadow:0 1px 4px rgba(0,0,0,.12); max-width:65%;"
      ),
      uiOutput(ns("map_status"))
    )
  )
}

# ---- Tools UI ---------------------------------------------------------------

rasterToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Spatial Analysis", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "symbology",

      accordion_panel(
        "Symbology", value = "symbology", icon = icon("palette"),
        uiOutput(ns("sym_ui"))
      ),

      accordion_panel(
        "Raster Operations", value = "ops", icon = icon("gear"),
        selectInput(ns("operation"), "Operation",
          choices = c(
            "Crop to drawn shape"  = "crop_draw",
            "Clip to vector layer" = "clip_vec",
            "Mosaic rasters"       = "mosaic",
            "Reproject / CRS"      = "reproject",
            "Resample resolution"  = "resample",
            "Band Calculator"      = "bandcalc",
            "Spectral Index"       = "spectral",
            "Zonal Statistics"     = "zonal"
          )
        ),
        tags$hr(style = "margin:6px 0"),
        uiOutput(ns("op_params")),
        actionButton(ns("run_op"), "Run Operation",
          class = "btn-success btn-sm w-100 mt-2", icon = icon("play")),
        div(style = "margin-top:6px; font-size:12px;",
          verbatimTextOutput(ns("op_log")))
      ),

      accordion_panel(
        "Vector Operations", value = "vec_ops", icon = icon("draw-polygon"),
        uiOutput(ns("vec_ops_ui"))
      ),

      accordion_panel(
        "Annotations", value = "annotations", icon = icon("pen"),
        radioButtons(ns("draw_mode"), "Draw mode",
          choices  = c("Operations" = "ops", "Annotate" = "annotate"),
          selected = "ops", inline = TRUE),
        conditionalPanel("input.draw_mode === 'annotate'", ns = ns,
          textInput(ns("anno_label"), "Class label", placeholder = "tree, road, building…"),
          fluidRow(
            column(6, selectInput(ns("anno_color"), "Colour",
              choices = c("Green"="#43a047","Red"="#e53935","Blue"="#1e88e5",
                          "Orange"="#fb8c00","Purple"="#8e24aa"),
              selected = "#43a047")),
            column(6, numericInput(ns("anno_conf"), "Confidence",
                                   value=1, min=0, max=1, step=0.1))
          ),
          actionButton(ns("set_anno_label"), tagList(icon("tag"), " Set label"),
                       class="btn-sm btn-success w-100 mb-2"),
          uiOutput(ns("anno_badge")),
          hr(class="my-2"),
          uiOutput(ns("pending_ui")),
          hr(class="my-2"),
          uiOutput(ns("anno_count")),
          DT::DTOutput(ns("anno_tbl"), height="200px"),
          hr(class="my-1"),
          fluidRow(
            column(6, actionButton(ns("del_anno"), tagList(icon("trash"), " Delete"),
                                   class="btn-sm btn-outline-danger w-100")),
            column(6, actionButton(ns("clear_anno"), tagList(icon("xmark"), " Clear all"),
                                   class="btn-sm btn-outline-danger w-100"))
          ),
          hr(class="my-2"),
          selectInput(ns("anno_fmt"), "Export format",
            choices = c("GeoJSON (.geojson)"="geojson","CSV (bounding-box)"="csv",
                        "COCO JSON (ML training)"="coco","GeoPackage (.gpkg)"="gpkg",
                        "Pascal VOC XML"="voc")),
          downloadButton(ns("dl_anno"), tagList(icon("download"), " Download annotations"),
                         class="btn-sm btn-success w-100 mt-1")
        )
      ),

      accordion_panel(
        "Export", value = "export", icon = icon("download"),

        tags$p(class = "text-uppercase fw-bold small mb-1",
               style = "font-size:10px;letter-spacing:.7px;color:#2e7d32;",
               "Export Layer Data"),
        uiOutput(ns("export_ui")),
        downloadButton(ns("dl"), "Download Layer",
          class = "btn-sm btn-success w-100 mt-1"),

        hr(style = "margin:10px 0;"),

        tags$p(class = "text-uppercase fw-bold small mb-1",
               style = "font-size:10px;letter-spacing:.7px;color:#2e7d32;",
               "Export Map Image"),
        selectInput(ns("map_fmt"), "Format",
          choices = c("PNG (.png)" = "png", "JPEG (.jpg)" = "jpg", "PDF (.pdf)" = "pdf"),
          width = "100%"),
        numericInput(ns("map_dpi"), "Resolution (DPI)",
          value = 150, min = 72, max = 600, step = 1, width = "100%"),
        radioButtons(ns("map_orient"), "Orientation",
          choices  = c("Landscape" = "landscape", "Portrait" = "portrait"),
          selected = "landscape", inline = TRUE),
        downloadButton(ns("dl_map"), "Export Map Image",
          class = "btn-sm btn-outline-success w-100 mt-1")
      )
    )
  )
}

# ---- Server -----------------------------------------------------------------

rasterServer <- function(id, dataset_pool, active_dataset,
                         raster_pool = NULL, vector_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      layers      = list(),
      active      = NULL,
      drawn       = NULL,
      excluded    = character(0),
      op_log      = "",
      vec_log     = "",
      anno         = list(),
      anno_next    = 1L,
      anno_label   = "",
      anno_color   = "#43a047",
      anno_conf    = 1.0,
      anno_pending = NULL
    )

    # ---- Local rendering helpers --------------------------------------------

    .render_layer <- function(nm) {
      ly <- rv$layers[[nm]]
      if (is.null(ly) || !ly$visible) return()

      if (ly$type == "raster") {
        bi <- max(1L, min(as.integer(ly$band %||% 1L), terra::nlyr(ly$data)))
        r1 <- tryCatch(.to_wgs84(ly$data[[bi]]), error = function(e) NULL)
        if (is.null(r1)) return()
        # leafem::addGeoRaster needs a stars object (not SpatRaster directly)
        r1_st <- tryCatch(stars::st_as_stars(r1), error = function(e) NULL)
        if (is.null(r1_st)) return()
        pal <- .pal_colors(ly$palette %||% "viridis")
        leafletProxy("map", session = session) %>%
          clearGroup(nm) %>%
          leafem::addGeoRaster(
            x            = r1_st,
            group        = nm,
            opacity      = ly$opacity %||% 0.8,
            colorOptions = leafem::colorOptions(palette = pal, na.color = "transparent")
          )
      } else {
        v  <- tryCatch(sf::st_transform(ly$data, 4326), error = function(e) NULL)
        if (is.null(v)) return()
        gt <- as.character(unique(sf::st_geometry_type(v)))
        op <- ly$opacity %||% 0.8
        px <- leafletProxy("map", session = session) %>% clearGroup(nm)
        fi <- ly$fill_opacity %||% 0   # default: transparent fill so underlying rasters show
        if (any(gt %in% c("POLYGON", "MULTIPOLYGON")))
          px <- px %>% addPolygons(
            data = v, group = nm,
            color = "#2e7d32", weight = 1.5,
            fillColor = "#4caf50", fillOpacity = fi, opacity = op,
            highlightOptions = highlightOptions(color = "#1b5e20", weight = 3, bringToFront = TRUE)
          )
        else if (any(gt %in% c("LINESTRING", "MULTILINESTRING")))
          px <- px %>% addPolylines(
            data = v, group = nm, color = "#2e7d32", weight = 2, opacity = op
          )
        else
          px <- px %>% addCircleMarkers(
            data = v, group = nm,
            radius = 6, color = "#2e7d32", fillColor = "#4caf50",
            fillOpacity = max(fi, 0.5), opacity = op, weight = 2
          )
      }
    }

    .zoom_to <- function(nm) {
      ly <- rv$layers[[nm]]
      if (is.null(ly)) return()
      bbox <- .bbox_wgs84(ly)
      if (!is.null(bbox))
        leafletProxy("map", session = session) %>%
          fitBounds(bbox[1], bbox[2], bbox[3], bbox[4])
    }

    .add_from_pool <- function(nm, type, data) {
      if (nm %in% rv$excluded || nm %in% names(rv$layers)) return()
      rv$layers[[nm]] <- if (type == "raster")
        list(type = "raster", data = data, visible = TRUE,
             opacity = 0.8, palette = "viridis", band = 1L)
      else
        list(type = "vector", data = data, visible = TRUE, opacity = 0.8)
      rv$active <- nm
      .render_layer(nm)
      .zoom_to(nm)
    }

    # ---- Pool sync (auto-add new uploads) -----------------------------------

    if (!is.null(raster_pool)) {
      observe({
        pool <- reactiveValuesToList(raster_pool)
        for (nm in names(pool)) {
          if (inherits(pool[[nm]], "SpatRaster"))
            .add_from_pool(nm, "raster", pool[[nm]])
        }
      })
    }

    if (!is.null(vector_pool)) {
      observe({
        pool <- reactiveValuesToList(vector_pool)
        for (nm in names(pool)) {
          if (inherits(pool[[nm]], "sf"))
            .add_from_pool(nm, "vector", pool[[nm]])
        }
      })
    }

    # ---- Base map -----------------------------------------------------------

    output$map <- renderLeaflet({
      leaflet() %>%
        addProviderTiles("OpenStreetMap",     group = "OSM") %>%
        addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
        addProviderTiles("CartoDB.Positron",  group = "CartoDB") %>%
        addLayersControl(
          baseGroups = c("OSM", "Satellite", "CartoDB"),
          options    = layersControlOptions(collapsed = FALSE)
        ) %>%
        addScaleBar(position = "bottomright") %>%
        leaflet.extras::addDrawToolbar(
          targetGroup         = "drawn",
          polylineOptions     = FALSE,
          circleOptions       = FALSE,
          markerOptions       = FALSE,
          circleMarkerOptions = FALSE,
          rectangleOptions    = leaflet.extras::drawRectangleOptions(
            shapeOptions = leaflet.extras::drawShapeOptions(
              fillOpacity = 0.04, color = "#2e7d32", weight = 2
            )
          ),
          polygonOptions      = leaflet.extras::drawPolygonOptions(
            shapeOptions = leaflet.extras::drawShapeOptions(
              fillOpacity = 0.04, color = "#2e7d32", weight = 2
            )
          ),
          editOptions         = leaflet.extras::editToolbarOptions()
        ) %>%
        setView(lng = 25.7, lat = 62.5, zoom = 5)
    })
    # Render even while the panel is hidden so leafletProxy calls always succeed
    outputOptions(output, "map", suspendWhenHidden = FALSE)

    # ---- Layer manager UI ---------------------------------------------------

    output$layer_list_ui <- renderUI({
      lys <- rv$layers
      if (length(lys) == 0)
        return(div(
          style = "padding:10px; font-size:12px; color:#6c757d; font-style:italic;",
          "No layers. Upload files via Add Data in the left rail."
        ))
      act <- rv$active
      nms <- rev(names(lys))  # newest at top
      lapply(nms, function(nm) {
        ly     <- lys[[nm]]
        is_act <- !is.null(act) && act == nm
        t_icon <- if (ly$type == "raster") "\U0001F5FA️" else "\U0001F4CD"
        eye    <- if (ly$visible) "&#128065;" else "&#128584;"
        div(
          style = paste0(
            "padding:5px 8px; border-bottom:1px solid #e8e8e8; cursor:pointer;",
            if (is_act) " background:#e8f5e9;" else " background:#fff;"
          ),
          onclick = sprintf(
            "Shiny.setInputValue('%s','%s',{priority:'event'})",
            ns("active_layer"), nm
          ),
          # Row 1: controls + name
          div(
            style = "display:flex; align-items:center; gap:4px;",
            tags$span(
              title   = "Toggle visibility",
              style   = "cursor:pointer; font-size:13px; flex-shrink:0; line-height:1;",
              onclick = sprintf(
                "event.stopPropagation(); Shiny.setInputValue('%s','%s',{priority:'event'});",
                ns("layer_toggle"), nm
              ),
              HTML(eye)
            ),
            tags$span(style = "font-size:10px; flex-shrink:0;", t_icon),
            tags$span(
              title = nm,
              style = "flex:1; font-size:12px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;",
              nm
            ),
            tags$span(
              title   = "Zoom to layer",
              style   = "cursor:pointer; font-size:11px; color:#2e7d32; flex-shrink:0; padding:1px 3px;",
              onclick = sprintf(
                "event.stopPropagation(); Shiny.setInputValue('%s','%s',{priority:'event'});",
                ns("layer_zoom"), nm
              ),
              icon("crosshairs")
            ),
            tags$span(
              title   = "Remove from map",
              style   = "cursor:pointer; font-size:14px; color:#dc3545; flex-shrink:0; padding:0 3px; font-weight:bold; line-height:1;",
              onclick = sprintf(
                "event.stopPropagation(); Shiny.setInputValue('%s','%s',{priority:'event'});",
                ns("layer_remove"), nm
              ),
              HTML("&times;")
            )
          ),
          # Row 2: opacity slider
          tags$input(
            type    = "range", min = "0", max = "1", step = "0.05",
            value   = as.character(ly$opacity %||% 0.8),
            style   = "width:100%; margin-top:3px; accent-color:#2e7d32; height:4px;",
            oninput = sprintf(
              "event.stopPropagation(); Shiny.setInputValue('%s',{name:'%s',val:parseFloat(this.value)},{priority:'event'});",
              ns("layer_opacity"), nm
            )
          )
        )
      })
    })

    # Layer manager event handlers
    observeEvent(input$active_layer, {
      if (isTruthy(input$active_layer) && input$active_layer %in% names(rv$layers))
        rv$active <- input$active_layer
    })

    observeEvent(input$layer_toggle, {
      nm <- input$layer_toggle
      if (!nm %in% names(rv$layers)) return()
      rv$layers[[nm]]$visible <- !rv$layers[[nm]]$visible
      if (!rv$layers[[nm]]$visible)
        leafletProxy("map", session = session) %>% clearGroup(nm)
      else
        .render_layer(nm)
    })

    observeEvent(input$layer_zoom, {
      nm <- input$layer_zoom
      if (nm %in% names(rv$layers)) .zoom_to(nm)
    })

    observeEvent(input$layer_remove, {
      nm <- input$layer_remove
      rv$excluded <- c(rv$excluded, nm)
      leafletProxy("map", session = session) %>% clearGroup(nm)
      rv$layers[[nm]] <- NULL
      remaining <- names(rv$layers)
      if (!is.null(rv$active) && rv$active == nm)
        rv$active <- if (length(remaining) > 0) remaining[length(remaining)] else NULL
    })

    observeEvent(input$layer_opacity, {
      info <- input$layer_opacity
      nm   <- info$name
      val  <- as.numeric(info$val)
      if (!nm %in% names(rv$layers)) return()
      rv$layers[[nm]]$opacity <- val
      if (isTRUE(rv$layers[[nm]]$visible)) .render_layer(nm)
    })

    observeEvent(input$zoom_all, {
      lys    <- rv$layers
      if (length(lys) == 0) return()
      bboxes <- Filter(Negate(is.null), lapply(lys, .bbox_wgs84))
      if (length(bboxes) == 0) return()
      mat <- do.call(rbind, bboxes)
      leafletProxy("map", session = session) %>%
        fitBounds(min(mat[, 1]), min(mat[, 2]), max(mat[, 3]), max(mat[, 4]))
    })

    observeEvent(input$add_layer_btn, {
      rp <- if (!is.null(raster_pool)) names(reactiveValuesToList(raster_pool)) else character(0)
      vp <- if (!is.null(vector_pool)) names(reactiveValuesToList(vector_pool)) else character(0)
      available <- setdiff(c(rp, vp), names(rv$layers))
      if (length(available) == 0) {
        showNotification("All uploaded data is already on the map.", type = "message", duration = 3)
        return()
      }
      showModal(modalDialog(
        title  = "Add Layer to Map",
        selectInput(ns("add_layer_pick"), "Select a layer", choices = available),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_add_layer"), "Add to Map", class = "btn-success")
        ),
        size = "s", easyClose = TRUE
      ))
    })

    observeEvent(input$confirm_add_layer, {
      nm <- input$add_layer_pick
      req(nm)
      removeModal()
      rv$excluded <- setdiff(rv$excluded, nm)
      rp <- if (!is.null(raster_pool)) reactiveValuesToList(raster_pool) else list()
      vp <- if (!is.null(vector_pool)) reactiveValuesToList(vector_pool) else list()
      if      (nm %in% names(rp)) .add_from_pool(nm, "raster", rp[[nm]])
      else if (nm %in% names(vp)) .add_from_pool(nm, "vector", vp[[nm]])
    })

    # ---- Symbology panel ----------------------------------------------------

    output$sym_ui <- renderUI({
      nm <- rv$active
      if (is.null(nm) || !nm %in% names(rv$layers))
        return(tags$p(class = "small text-muted fst-italic",
                      "Click a layer in the panel above to configure it."))
      ly <- rv$layers[[nm]]

      if (ly$type == "raster") {
        r   <- ly$data
        nb  <- terra::nlyr(r)
        bns <- names(r)
        if (is.null(bns) || !all(nzchar(bns))) bns <- paste0("Band ", seq_len(nb))
        tagList(
          tags$p(class = "small fw-semibold mb-2",
                 "\U0001F5FA️ ", nm),
          selectInput(ns("sym_palette"), "Colour palette",
            choices = c(
              "Viridis"         = "viridis",
              "Magma"           = "magma",
              "Plasma"          = "plasma",
              "Inferno"         = "inferno",
              "Red-Yellow-Green"= "RdYlGn",
              "Terrain"         = "terrain",
              "Greens"          = "Greens",
              "Greys"           = "Greys"
            ),
            selected = ly$palette %||% "viridis"
          ),
          if (nb > 1)
            selectInput(ns("sym_band"), "Display band",
              choices  = setNames(seq_len(nb), bns),
              selected = ly$band %||% 1L
            ),
          sliderInput(ns("sym_opacity"), "Opacity",
            min = 0.1, max = 1, value = ly$opacity %||% 0.8, step = 0.05),
          actionButton(ns("apply_sym"), "Apply",
            class = "btn-success btn-sm w-100 mt-1", icon = icon("check"))
        )
      } else {
        geom_t <- paste(unique(sf::st_geometry_type(ly$data)), collapse = "/")
        crs_lbl <- tryCatch({
          cs <- sf::st_crs(ly$data)
          if (!is.na(cs) && !is.null(cs$input)) cs$input else "Unknown CRS"
        }, error = function(e) "Unknown CRS")
        tagList(
          tags$p(class = "small fw-semibold mb-1", "\U0001F4CD ", nm),
          tags$p(class = "small text-muted mb-1",
            paste0(nrow(ly$data), " features | ", geom_t)),
          tags$p(class = "small text-muted mb-2", crs_lbl),
          sliderInput(ns("sym_opacity"), "Border opacity",
            min = 0.1, max = 1, value = ly$opacity %||% 0.8, step = 0.05),
          sliderInput(ns("sym_fill_opacity"), "Fill opacity",
            min = 0, max = 1, value = ly$fill_opacity %||% 0, step = 0.05),
          tags$p(class = "small text-muted fst-italic",
            "Fill opacity = 0 keeps polygons transparent so rasters show through."),
          actionButton(ns("apply_sym"), "Apply",
            class = "btn-success btn-sm w-100 mt-1", icon = icon("check"))
        )
      }
    })

    observeEvent(input$apply_sym, {
      nm <- rv$active
      if (is.null(nm) || !nm %in% names(rv$layers)) return()
      ly <- rv$layers[[nm]]
      if (ly$type == "raster") {
        rv$layers[[nm]]$palette <- input$sym_palette %||% "viridis"
        if (isTruthy(input$sym_band))
          rv$layers[[nm]]$band <- as.integer(input$sym_band)
      }
      if (isTruthy(input$sym_opacity))
        rv$layers[[nm]]$opacity <- as.numeric(input$sym_opacity)
      if (ly$type == "vector" && !is.null(input$sym_fill_opacity))
        rv$layers[[nm]]$fill_opacity <- as.numeric(input$sym_fill_opacity)
      if (isTRUE(rv$layers[[nm]]$visible)) .render_layer(nm)
    })

    # ---- Map status overlay -------------------------------------------------

    output$map_status <- renderUI({
      nm <- rv$active
      if (is.null(nm) || !nm %in% names(rv$layers))
        return(tags$span(style = "color:#6c757d;", "No active layer"))
      ly <- rv$layers[[nm]]
      if (ly$type == "raster") {
        r <- ly$data
        crs_nm <- tryCatch({
          d <- terra::crs(r, describe = TRUE)
          lbl <- d$name %||% ""
          if (nzchar(lbl)) lbl else (d$code %||% "?")
        }, error = function(e) "Unknown CRS")
        v <- tryCatch(
          terra::global(r[[1]], fun = c("min", "max"), na.rm = TRUE),
          error = function(e) data.frame(min = NA, max = NA)
        )
        tags$span(
          tags$b(nm), " │ ",
          paste0(ncol(r), "×", nrow(r)), " │ ",
          paste0(round(terra::res(r)[1], 3), "m"), " │ ",
          paste0(round(v$min, 2), "–", round(v$max, 2)), " │ ",
          crs_nm
        )
      } else {
        crs_nm <- tryCatch({
          cs <- sf::st_crs(ly$data)
          if (!is.na(cs) && !is.null(cs$input)) cs$input else "Unknown CRS"
        }, error = function(e) "Unknown CRS")
        geom_t <- paste(unique(sf::st_geometry_type(ly$data)), collapse = "/")
        tags$span(
          tags$b(nm), " │ ",
          paste(nrow(ly$data), "features"), " │ ",
          geom_t, " │ ", crs_nm
        )
      }
    })

    # ---- Active raster accessors (for operations) ---------------------------

    active_raster <- reactive({
      nm <- rv$active
      if (is.null(nm)) return(NULL)
      ly <- rv$layers[[nm]]
      if (is.null(ly) || ly$type != "raster") return(NULL)
      ly$data
    })

    active_raster_name <- reactive({
      nm <- rv$active
      if (is.null(nm)) return(NULL)
      ly <- rv$layers[[nm]]
      if (is.null(ly) || ly$type != "raster") return(NULL)
      nm
    })

    # ---- Raster operation params UI -----------------------------------------

    output$op_params <- renderUI({
      req(input$operation)
      nms_r <- names(Filter(function(ly) ly$type == "raster", rv$layers))
      nms_v <- names(Filter(function(ly) ly$type == "vector", rv$layers))

      switch(input$operation,

        crop_draw = tags$p(class = "small text-muted mt-1",
          "Draw a rectangle or polygon on the map, then click Run."),

        clip_vec = if (length(nms_v) > 0)
          selectInput(ns("clip_layer"), "Clip mask (vector on map)", choices = nms_v)
        else
          tags$p(class = "small text-warning mt-1",
            "No vector layers on map. Upload a shapefile or GeoPackage."),

        mosaic = if (length(nms_r) < 2)
          tags$p(class = "small text-warning", "Upload at least 2 rasters to mosaic.")
        else
          checkboxGroupInput(ns("mosaic_layers"), "Layers to mosaic",
            choices = nms_r, selected = nms_r),

        reproject = tagList(
          textInput(ns("target_crs"), "Target CRS", value = "EPSG:4326",
            placeholder = "e.g. EPSG:3067"),
          tags$p(class = "small text-muted", "EPSG:3067 = Finnish TM35FIN national grid")
        ),

        resample = tagList(
          fluidRow(
            column(6, numericInput(ns("res_x"), "X res (m)", value = 10, min = 1e-6, step = 1)),
            column(6, numericInput(ns("res_y"), "Y res (m)", value = 10, min = 1e-6, step = 1))
          ),
          selectInput(ns("resample_method"), "Method",
            choices = c("bilinear", "near", "cubic", "cubicspline", "lanczos"))
        ),

        bandcalc = tagList(
          tags$p(class = "small text-muted",
            "Use b1, b2 … for bands of the active raster."),
          textAreaInput(ns("formula"), "Formula", value = "(b4-b3)/(b4+b3)", rows = 2),
          textInput(ns("result_nm"), "Output layer name", value = "band_calc")
        ),

        spectral = tagList(
          tags$p(class = "small text-muted",
            "Preset spectral indices for multi-band rasters (e.g. Sentinel-2)."),
          selectInput(ns("spectral_idx"), "Index",
            choices = c(
              "NDVI: (NIR−Red)/(NIR+Red)"          = "ndvi",
              "NDWI: (Green−NIR)/(Green+NIR)"      = "ndwi",
              "NBR:  (NIR−SWIR)/(NIR+SWIR)"        = "nbr",
              "NDRE: (RedEdge−Red)/(RedEdge+Red)"  = "ndre"
            )
          ),
          uiOutput(ns("spectral_band_sel"))
        ),

        zonal = tagList(
          if (length(nms_v) > 0)
            selectInput(ns("zonal_layer"), "Zone polygons (vector layer)", choices = nms_v)
          else
            tags$p(class = "small text-warning mt-1", "No vector layers on map."),
          selectInput(ns("zonal_stat"), "Summary statistic",
            choices = c("mean", "sum", "min", "max", "sd", "count", "median")),
          textInput(ns("zone_id_col"), "Zone ID column (blank = row index)", value = "")
        )
      )
    })

    output$spectral_band_sel <- renderUI({
      r  <- active_raster(); req(r)
      nb  <- terra::nlyr(r)
      bns <- names(r)
      if (is.null(bns) || !all(nzchar(bns))) bns <- paste0("Band ", seq_len(nb))
      ch  <- setNames(seq_len(nb), bns)
      idx <- input$spectral_idx %||% "ndvi"
      switch(idx,
        ndvi = tagList(
          selectInput(ns("sp_nir"), "NIR band",  choices = ch, selected = min(4L, nb)),
          selectInput(ns("sp_red"), "Red band",  choices = ch, selected = min(3L, nb))
        ),
        ndwi = tagList(
          selectInput(ns("sp_green"), "Green band", choices = ch, selected = min(2L, nb)),
          selectInput(ns("sp_nir"),   "NIR band",   choices = ch, selected = min(4L, nb))
        ),
        nbr  = tagList(
          selectInput(ns("sp_nir"),  "NIR band",  choices = ch, selected = min(4L, nb)),
          selectInput(ns("sp_swir"), "SWIR band", choices = ch, selected = min(6L, nb))
        ),
        ndre = tagList(
          selectInput(ns("sp_re"),  "RedEdge band", choices = ch, selected = min(5L, nb)),
          selectInput(ns("sp_red"), "Red band",     choices = ch, selected = min(3L, nb))
        )
      )
    })

    output$op_log <- renderText(rv$op_log)

    # ---- Run raster operation -----------------------------------------------

    observeEvent(input$run_op, {
      r  <- active_raster(); req(r)
      nm <- active_raster_name()
      rv$op_log <- "Running…"

      result <- tryCatch({
        switch(input$operation,

          crop_draw = {
            if (is.null(rv$drawn)) stop("Draw a shape on the map first.")
            mask <- sf::st_transform(rv$drawn, terra::crs(r))
            terra::crop(r, terra::vect(mask), mask = TRUE)
          },

          clip_vec = {
            req(input$clip_layer)
            vec <- rv$layers[[input$clip_layer]]$data; req(vec)
            vec <- sf::st_transform(vec, terra::crs(r))
            terra::crop(r, terra::vect(vec), mask = TRUE)
          },

          mosaic = {
            lys <- input$mosaic_layers
            if (length(lys) < 2) stop("Select at least 2 layers.")
            terra::mosaic(terra::sprc(lapply(lys, function(n) rv$layers[[n]]$data)))
          },

          reproject = {
            crs_str <- trimws(input$target_crs %||% "")
            if (!nzchar(crs_str)) stop("Enter a target CRS (e.g. EPSG:3067).")
            terra::project(r, crs_str)
          },

          resample = {
            req(input$res_x, input$res_y)
            tmpl <- terra::rast(
              ext = terra::ext(r), crs = terra::crs(r),
              res = c(as.numeric(input$res_x), as.numeric(input$res_y))
            )
            terra::resample(r, tmpl, method = input$resample_method)
          },

          bandcalc = {
            f <- trimws(input$formula %||% "")
            if (!nzchar(f)) stop("Enter a formula.")
            env <- list2env(
              setNames(lapply(seq_len(terra::nlyr(r)), function(i) r[[i]]),
                       paste0("b", seq_len(terra::nlyr(r)))),
              parent = globalenv()
            )
            res <- eval(parse(text = f), envir = env)
            if (!inherits(res, "SpatRaster")) stop("Formula did not produce a raster.")
            res_nm <- trimws(input$result_nm %||% "band_calc")
            names(res) <- if (nzchar(res_nm)) res_nm else "band_calc"
            res
          },

          spectral = {
            idx <- input$spectral_idx %||% "ndvi"
            b   <- function(inp) r[[as.integer(inp %||% 1L)]]
            res <- switch(idx,
              ndvi = { nir <- b(input$sp_nir); red <- b(input$sp_red); (nir - red) / (nir + red) },
              ndwi = { grn <- b(input$sp_green); nir <- b(input$sp_nir); (grn - nir) / (grn + nir) },
              nbr  = { nir <- b(input$sp_nir); sw <- b(input$sp_swir); (nir - sw) / (nir + sw) },
              ndre = { re  <- b(input$sp_re);  red <- b(input$sp_red); (re - red) / (re + red) }
            )
            names(res) <- toupper(idx)
            res
          },

          zonal = {
            req(input$zonal_layer)
            if (!requireNamespace("exactextractr", quietly = TRUE))
              stop("Install 'exactextractr' for zonal statistics.")
            zones <- rv$layers[[input$zonal_layer]]$data; req(zones)
            zones <- sf::st_transform(zones, terra::crs(r))
            stat  <- exactextractr::exact_extract(r[[1]], zones,
                                                  fun = input$zonal_stat, progress = FALSE)
            id_col <- trimws(input$zone_id_col %||% "")
            df <- if (nzchar(id_col) && id_col %in% names(sf::st_drop_geometry(zones)))
              data.frame(zone = sf::st_drop_geometry(zones)[[id_col]], value = stat)
            else
              data.frame(zone_id = seq_along(stat), value = stat)
            colnames(df)[2] <- paste0(input$zonal_stat, "_", nm)
            pool_nm <- paste0("zonal_", nm)
            dataset_pool[[pool_nm]] <- df
            showNotification(paste0("Zonal stats saved as '", pool_nm, "'."),
                             type = "message", duration = 4)
            NULL
          }
        )
      }, error = function(e) {
        msg <- conditionMessage(e)
        rv$op_log <- paste("Error:", msg)
        showNotification(msg, type = "error", duration = 8)
        NULL
      })

      if (!is.null(result) && inherits(result, "SpatRaster")) {
        res_nm <- switch(input$operation,
          bandcalc = if (isTruthy(input$result_nm)) trimws(input$result_nm) else "band_calc",
          spectral = paste0(nm, "_", toupper(input$spectral_idx %||% "idx")),
          paste0(nm, "_", input$operation)
        )
        rv$layers[[res_nm]] <- list(type = "raster", data = result, visible = TRUE,
                                    opacity = 0.8, palette = "viridis", band = 1L)
        rv$active <- res_nm
        if (!is.null(raster_pool)) raster_pool[[res_nm]] <- result
        rv$op_log <- paste0("Done → '", res_nm, "' (", ncol(result), "×", nrow(result), ")")
        .render_layer(res_nm)
        .zoom_to(res_nm)
      } else if (is.null(result) && !startsWith(rv$op_log, "Error")) {
        rv$op_log <- "Done."
      }
    })

    # ---- Vector operations --------------------------------------------------

    output$vec_ops_ui <- renderUI({
      nms_v <- names(Filter(function(ly) ly$type == "vector", rv$layers))
      if (length(nms_v) == 0)
        return(tags$p(class = "small text-muted fst-italic",
          "No vector layers on map. Upload a shapefile or GeoPackage."))
      tagList(
        selectInput(ns("vec_source"), "Input vector layer", choices = nms_v),
        selectInput(ns("vec_op"), "Operation",
          choices = c(
            "Buffer"             = "buffer",
            "Dissolve"           = "dissolve",
            "Clip to drawn shape"= "vec_clip",
            "Centroid points"    = "centroid"
          )
        ),
        uiOutput(ns("vec_op_params")),
        textInput(ns("vec_res_nm"), "Output layer name", value = "result"),
        actionButton(ns("run_vec_op"), "Run",
          class = "btn-success btn-sm w-100 mt-2", icon = icon("play")),
        div(style = "margin-top:6px; font-size:12px;",
          verbatimTextOutput(ns("vec_op_log")))
      )
    })

    output$vec_op_params <- renderUI({
      switch(input$vec_op %||% "buffer",
        buffer = tagList(
          numericInput(ns("buf_dist"), "Buffer distance (map units)", value = 100, min = 0, step = 10),
          tags$p(class = "small text-muted", "Units match the layer CRS (e.g. metres for EPSG:3067).")
        ),
        dissolve = {
          ly <- rv$layers[[input$vec_source %||% ""]]
          fields <- if (!is.null(ly) && ly$type == "vector")
            c("(merge all)" = "", names(sf::st_drop_geometry(ly$data)))
          else c("(no layer selected)" = "")
          selectInput(ns("dissolve_by"), "Dissolve by field", choices = fields)
        },
        vec_clip = tags$p(class = "small text-muted",
          "Draw a polygon on the map first, then click Run."),
        centroid = NULL
      )
    })

    output$vec_op_log <- renderText(rv$vec_log)

    observeEvent(input$run_vec_op, {
      ly_nm <- input$vec_source; req(ly_nm)
      ly    <- rv$layers[[ly_nm]]; req(ly, ly$type == "vector")
      v     <- ly$data
      rv$vec_log <- "Running…"

      result <- tryCatch({
        switch(input$vec_op %||% "buffer",

          buffer = sf::st_buffer(v, dist = as.numeric(input$buf_dist %||% 100)),

          dissolve = {
            by <- input$dissolve_by %||% ""
            if (nzchar(by) && by %in% names(sf::st_drop_geometry(v))) {
              grps  <- split(seq_len(nrow(v)), sf::st_drop_geometry(v)[[by]])
              parts <- lapply(names(grps), function(g) {
                sub_sf <- v[grps[[g]], ]
                sf::st_sf(
                  data.frame(setNames(list(g), by), stringsAsFactors = FALSE),
                  geometry = sf::st_union(sub_sf)
                )
              })
              do.call(rbind, parts)
            } else {
              sf::st_sf(geometry = sf::st_union(v))
            }
          },

          vec_clip = {
            if (is.null(rv$drawn)) stop("Draw a polygon on the map first.")
            clip_sf <- sf::st_transform(rv$drawn, sf::st_crs(v))
            sf::st_intersection(v, clip_sf)
          },

          centroid = sf::st_centroid(v)
        )
      }, error = function(e) {
        rv$vec_log <- paste("Error:", conditionMessage(e))
        showNotification(conditionMessage(e), type = "error", duration = 6)
        NULL
      })

      if (!is.null(result)) {
        if (!inherits(result, "sf")) result <- sf::st_as_sf(result)
        res_nm <- trimws(input$vec_res_nm %||% paste0(ly_nm, "_", input$vec_op))
        if (!nzchar(res_nm)) res_nm <- paste0(ly_nm, "_", input$vec_op)
        rv$layers[[res_nm]] <- list(type = "vector", data = result,
                                    visible = TRUE, opacity = 0.8)
        rv$active <- res_nm
        if (!is.null(vector_pool)) vector_pool[[res_nm]] <- result
        rv$vec_log <- paste0("Done → '", res_nm, "' (", nrow(result), " features)")
        .render_layer(res_nm)
        .zoom_to(res_nm)
      }
    })

    # ---- Export -------------------------------------------------------------

    output$export_ui <- renderUI({
      all_nms <- names(rv$layers)
      if (length(all_nms) == 0)
        return(tags$p(class = "small text-muted", "No layers loaded."))
      act <- rv$active %||% all_nms[1]
      tagList(
        selectInput(ns("export_layer"), "Layer to export",
          choices  = all_nms,
          selected = if (act %in% all_nms) act else all_nms[1]
        ),
        uiOutput(ns("export_fmt_ui"))
      )
    })

    output$export_fmt_ui <- renderUI({
      nm <- input$export_layer %||% rv$active
      if (is.null(nm) || !nm %in% names(rv$layers)) return(NULL)
      if (rv$layers[[nm]]$type == "raster")
        selectInput(ns("export_format"), "Format",
          choices = c("GeoTIFF (.tif)" = "tif", "ASCII Grid (.asc)" = "asc"))
      else
        selectInput(ns("export_format"), "Format",
          choices = c(
            "GeoPackage (.gpkg)"   = "gpkg",
            "GeoJSON (.geojson)"   = "geojson",
            "Shapefile (.shp)"     = "shp"
          ))
    })

    output$dl <- downloadHandler(
      filename = function() {
        nm  <- input$export_layer %||% rv$active %||% "layer"
        fmt <- input$export_format %||% "tif"
        paste0(nm, "_export.", fmt)
      },
      content = function(file) {
        nm <- input$export_layer %||% rv$active; req(nm)
        ly <- rv$layers[[nm]]; req(ly)
        if (ly$type == "raster") {
          terra::writeRaster(ly$data, file, overwrite = TRUE)
        } else {
          drv <- switch(input$export_format %||% "gpkg",
            geojson = "GeoJSON",
            shp     = "ESRI Shapefile",
            "GPKG"
          )
          sf::st_write(ly$data, file, driver = drv, delete_dsn = TRUE, quiet = TRUE)
        }
      }
    )

    # ---- Map image export ---------------------------------------------------

    output$dl_map <- downloadHandler(
      filename = function() {
        fmt <- input$map_fmt %||% "png"
        paste0("map_", Sys.Date(), ".", fmt)
      },
      content = function(file) {
        vis <- Filter(function(ly) isTRUE(ly$visible), rv$layers)
        if (length(vis) == 0) { file.create(file); return() }

        fmt   <- input$map_fmt    %||% "png"
        dpi   <- max(72L, min(600L, as.integer(input$map_dpi %||% 150L)))
        ornt  <- input$map_orient %||% "landscape"
        if (ornt == "landscape") { pw <- 11.69; ph <- 8.27 }
        else                     { pw <-  8.27; ph <- 11.69 }

        if (fmt == "pdf") {
          pdf(file, width = pw, height = ph)
        } else if (fmt == "jpg") {
          jpeg(file, width = pw * dpi, height = ph * dpi, res = dpi, quality = 95)
        } else {
          png(file, width = pw * dpi, height = ph * dpi, res = dpi)
        }

        rast_lys <- Filter(function(ly) ly$type == "raster", vis)
        vec_lys  <- Filter(function(ly) ly$type == "vector",  vis)

        if (length(rast_lys) > 0) {
          first_nm <- names(rast_lys)[1]
          rl <- rast_lys[[first_nm]]
          bi <- max(1L, min(as.integer(rl$band %||% 1L), terra::nlyr(rl$data)))
          pal <- .pal_colors(rl$palette %||% "viridis")
          terra::plot(rl$data[[bi]], col = pal, main = first_nm,
                      mar = c(3.5, 3.5, 2, 7))
          for (i in seq_along(rast_lys)[-1]) {
            rl2 <- rast_lys[[i]]
            bi2 <- max(1L, min(as.integer(rl2$band %||% 1L), terra::nlyr(rl2$data)))
            terra::plot(rl2$data[[bi2]], add = TRUE, legend = FALSE)
          }
          for (i in seq_along(vec_lys)) {
            v4 <- tryCatch(
              sf::st_transform(vec_lys[[i]]$data, terra::crs(rl$data)),
              error = function(e) NULL)
            if (!is.null(v4))
              plot(sf::st_geometry(v4), add = TRUE,
                   border = "#1b5e20", col = NA, lwd = 1.5)
          }
        } else if (length(vec_lys) > 0) {
          plot(sf::st_geometry(vec_lys[[1]]$data),
               border = "#2e7d32", col = "#4caf5033",
               main   = names(vec_lys)[1])
          for (i in seq_along(vec_lys)[-1])
            plot(sf::st_geometry(vec_lys[[i]]$data),
                 add = TRUE, border = "#c62828", col = NA, lwd = 1.5)
        }
        dev.off()
      }
    )

    # ---- Draw capture -------------------------------------------------------

    observeEvent(input$map_draw_new_feature, {
      feat <- input$map_draw_new_feature
      if (isTRUE(input$draw_mode == "annotate")) {
        rv$anno_pending <- list(
          feature   = feat,
          label     = rv$anno_label,
          color     = rv$anno_color,
          conf      = rv$anno_conf,
          geom_type = feat$geometry$type %||% "Unknown"
        )
        updateSliderInput(session, "anno_rotate", value = 0)
      } else {
        rv$drawn <- tryCatch(.parse_draw(feat), error = function(e) NULL)
      }
    })
    observeEvent(input$map_draw_deleted_features, {
      if (!isTRUE(input$draw_mode == "annotate")) rv$drawn <- NULL
    })

    # ---- Annotation server logic --------------------------------------------

    observeEvent(input$set_anno_label, {
      rv$anno_label <- trimws(input$anno_label %||% "")
      rv$anno_color <- input$anno_color %||% "#43a047"
      rv$anno_conf  <- input$anno_conf  %||% 1.0
    })

    # ---- Rotation helper -----------------------------------------------------
    .rotate_feature <- function(feat, angle_deg) {
      if (abs(angle_deg) < 0.01) return(feat)
      gt <- feat$geometry$type %||% ""
      if (gt != "Polygon") return(feat)
      coords <- feat$geometry$coordinates[[1]]
      mat <- do.call(rbind, lapply(coords, function(p)
        c(as.numeric(p[[1]]), as.numeric(p[[2]]))))
      cx <- mean(mat[,1], na.rm=TRUE); cy <- mean(mat[,2], na.rm=TRUE)
      theta <- angle_deg * pi / 180
      rot <- t(apply(mat, 1, function(p) {
        dx <- p[1]-cx; dy <- p[2]-cy
        c(cx + dx*cos(theta) - dy*sin(theta),
          cy + dx*sin(theta) + dy*cos(theta))
      }))
      feat$geometry$coordinates[[1]] <- lapply(seq_len(nrow(rot)),
                                                function(i) list(rot[i,1], rot[i,2]))
      feat
    }

    # ---- Pending annotation UI -----------------------------------------------
    output$pending_ui <- renderUI({
      p <- rv$anno_pending
      if (is.null(p))
        return(p(class="text-muted small",
                 "Draw a shape on the map — it will appear here for review."))
      div(
        div(class="alert alert-info p-2 mb-2",
          tags$small(icon("draw-polygon"), " ",
            tags$b(p$geom_type), " drawn. Rotate if needed, then confirm.")
        ),
        sliderInput(ns("anno_rotate"), "Rotation (°)",
                    min=-180, max=180, value=0, step=1, ticks=FALSE, width="100%"),
        fluidRow(class="g-1",
          column(6, actionButton(ns("confirm_anno"), tagList(icon("check"), " Confirm"),
                                 class="btn-sm btn-success w-100")),
          column(6, actionButton(ns("discard_anno"), tagList(icon("xmark"), " Discard"),
                                 class="btn-sm btn-outline-danger w-100"))
        )
      )
    })

    # Live rotation preview on map
    observe({
      p     <- rv$anno_pending
      angle <- input$anno_rotate %||% 0
      proxy <- leafletProxy("map", session=session)
      if (is.null(p)) { proxy %>% clearGroup("anno_preview"); return() }
      feat_rot <- tryCatch(.rotate_feature(p$feature, angle),
                           error = function(e) p$feature)
      gt <- feat_rot$geometry$type %||% ""
      if (gt == "Polygon") {
        coords <- feat_rot$geometry$coordinates[[1]]
        lngs   <- as.numeric(sapply(coords, `[[`, 1))
        lats   <- as.numeric(sapply(coords, `[[`, 2))
        proxy %>% clearGroup("anno_preview") %>%
          addPolygons(lng=lngs, lat=lats, group="anno_preview",
                      fillColor=p$color, fillOpacity=0.25,
                      color=p$color, weight=2, opacity=0.9)
      }
    })

    observeEvent(input$confirm_anno, {
      p <- rv$anno_pending; req(!is.null(p))
      angle      <- input$anno_rotate %||% 0
      feat_final <- tryCatch(.rotate_feature(p$feature, angle), error=function(e) p$feature)
      aid        <- paste0("ann_", rv$anno_next)
      rv$anno_next <- rv$anno_next + 1L
      rv$anno[[aid]] <- list(
        id        = aid,
        feature   = feat_final,
        label     = p$label,
        color     = p$color,
        conf      = p$conf,
        geom_type = feat_final$geometry$type %||% p$geom_type
      )
      rv$anno_pending <- NULL
      leafletProxy("map", session=session) %>% clearGroup("anno_preview")
      showNotification(
        paste0("Annotation '", if (nzchar(p$label)) p$label else "unlabelled", "' saved."),
        type="message", duration=2)
    })

    observeEvent(input$discard_anno, {
      rv$anno_pending <- NULL
      leafletProxy("map", session=session) %>% clearGroup("anno_preview")
    })

    output$anno_badge <- renderUI({
      if (!nchar(rv$anno_label))
        return(p(class="text-muted small mt-1", "No label set."))
      div(class="d-flex align-items-center gap-2 mt-1",
        div(style=paste0("width:10px;height:10px;border-radius:2px;background:",
                         rv$anno_color, ";flex-shrink:0")),
        span(class="small fw-semibold", rv$anno_label),
        span(class="text-muted small", paste0("conf=", rv$anno_conf))
      )
    })

    output$anno_count <- renderUI({
      n <- length(rv$anno)
      p(class="text-muted small mb-1",
        paste(n, if (n == 1) "annotation" else "annotations"))
    })

    output$anno_tbl <- DT::renderDT({
      anns <- rv$anno
      if (!length(anns))
        return(DT::datatable(
          data.frame(ID=character(),Label=character(),Type=character(),Confidence=numeric()),
          rownames=FALSE, options=list(dom="t")))
      df <- do.call(rbind, lapply(anns, function(a)
        data.frame(ID=a$id, Label=a$label, Type=a$geom_type,
                   Confidence=a$conf, stringsAsFactors=FALSE)))
      DT::datatable(df, selection="single", rownames=FALSE,
                    options=list(dom="t", pageLength=50,
                                 scrollY="180px", scrollCollapse=TRUE))
    })

    observeEvent(input$del_anno, {
      sel <- input$anno_tbl_rows_selected
      if (!length(sel)) { showNotification("Select a row first.", type="warning", duration=2); return() }
      ids <- names(rv$anno)
      if (sel <= length(ids)) rv$anno[[ids[sel]]] <- NULL
    })

    observeEvent(input$clear_anno, {
      rv$anno <- list()
    })

    .anno_bbox <- function(a) {
      coords <- a$feature$geometry$coordinates
      gt     <- a$geom_type
      tryCatch({
        if (gt == "Point")
          c(coords[[1]], coords[[2]], coords[[1]], coords[[2]])
        else if (gt == "Polygon") {
          pts <- do.call(rbind, lapply(coords[[1]], function(p) c(p[[1]], p[[2]])))
          c(min(pts[,1]), min(pts[,2]), max(pts[,1]), max(pts[,2]))
        } else if (gt == "LineString") {
          pts <- do.call(rbind, lapply(coords, function(p) c(p[[1]], p[[2]])))
          c(min(pts[,1]), min(pts[,2]), max(pts[,1]), max(pts[,2]))
        } else rep(NA_real_, 4)
      }, error = function(e) rep(NA_real_, 4))
    }

    output$dl_anno <- downloadHandler(
      filename = function() switch(input$anno_fmt %||% "geojson",
        geojson="annotations.geojson", csv="annotations.csv",
        coco="annotations_coco.json",  gpkg="annotations.gpkg",
        voc="annotations_voc.xml",     "annotations.geojson"),
      content  = function(file) {
        anns <- rv$anno
        fmt  <- input$anno_fmt %||% "geojson"
        feats <- lapply(anns, function(a) list(
          type       = "Feature",
          geometry   = a$feature$geometry,
          properties = list(id=a$id, label=a$label, color=a$color,
                            confidence=a$conf, geom_type=a$geom_type)))
        gc <- list(type="FeatureCollection", features=feats)

        if (fmt == "geojson") {
          writeLines(jsonlite::toJSON(gc, auto_unbox=TRUE, pretty=TRUE), file)
        } else if (fmt == "csv") {
          rows <- lapply(anns, function(a) {
            bb <- .anno_bbox(a)
            data.frame(id=a$id, label=a$label, type=a$geom_type,
                       xmin=bb[1], ymin=bb[2], xmax=bb[3], ymax=bb[4],
                       confidence=a$conf, stringsAsFactors=FALSE)
          })
          write.csv(if (length(rows)) do.call(rbind, rows) else data.frame(),
                    file, row.names=FALSE)
        } else if (fmt == "coco") {
          cats  <- sort(unique(Filter(nchar, sapply(anns, `[[`, "label"))))
          clist <- lapply(seq_along(cats), function(i)
            list(id=i, name=cats[i], supercategory="object"))
          alist <- lapply(seq_along(anns), function(i) {
            a <- anns[[i]]; bb <- .anno_bbox(a)
            ci <- match(a$label, cats) %||% 0L
            list(id=i, image_id=1L, category_id=as.integer(ci),
                 bbox=as.list(c(bb[1],bb[2],bb[3]-bb[1],bb[4]-bb[2])),
                 area=max(0,(bb[3]-bb[1])*(bb[4]-bb[2])),
                 segmentation=list(), iscrowd=0L)
          })
          writeLines(jsonlite::toJSON(
            list(images=list(list(id=1L,file_name="image.jpg",width=0L,height=0L)),
                 annotations=alist, categories=clist),
            auto_unbox=TRUE, pretty=TRUE), file)
        } else if (fmt == "gpkg") {
          gj <- jsonlite::toJSON(gc, auto_unbox=TRUE)
          tmp <- tempfile(fileext=".geojson")
          writeLines(gj, tmp)
          sf_obj <- tryCatch(sf::st_read(tmp, quiet=TRUE), error=function(e) NULL)
          if (!is.null(sf_obj))
            sf::st_write(sf_obj, file, driver="GPKG", delete_dsn=TRUE, quiet=TRUE)
        } else if (fmt == "voc") {
          lns <- c('<?xml version="1.0"?>', "<annotations>")
          for (a in anns) {
            bb <- .anno_bbox(a)
            lns <- c(lns, "  <object>",
              paste0("    <name>",a$label,"</name>"),
              paste0("    <confidence>",a$conf,"</confidence>"),
              "    <bndbox>",
              paste0("      <xmin>",round(bb[1],6),"</xmin>"),
              paste0("      <ymin>",round(bb[2],6),"</ymin>"),
              paste0("      <xmax>",round(bb[3],6),"</xmax>"),
              paste0("      <ymax>",round(bb[4],6),"</ymax>"),
              "    </bndbox>", "  </object>")
          }
          writeLines(c(lns, "</annotations>"), file)
        }
      }
    )

    # ---- AI co-pilot context ------------------------------------------------
    list(
      context = reactive({
        nm <- rv$active
        if (is.null(nm) || !nm %in% names(rv$layers))
          return("Spatial Analysis: no active layer.")
        ly <- rv$layers[[nm]]
        all_lyr <- paste(names(rv$layers), collapse = ", ")
        if (ly$type == "raster") {
          r <- ly$data
          crs_nm <- tryCatch({
            d <- terra::crs(r, describe = TRUE)
            lbl <- d$name %||% ""; if (nzchar(lbl)) lbl else (d$code %||% "?")
          }, error = function(e) "Unknown CRS")
          v <- tryCatch(
            terra::global(r[[1]], fun = c("min","max","mean"), na.rm = TRUE),
            error = function(e) data.frame(min=NA, max=NA, mean=NA)
          )
          paste0(
            "Spatial Analysis | Active raster: ", nm, "\n",
            "CRS: ", crs_nm, " | Dims: ", nrow(r), "×", ncol(r),
            " | Bands: ", terra::nlyr(r), "\n",
            "Resolution: ", paste(round(terra::res(r), 5), collapse = "×"), "\n",
            "Band 1 — min:", round(v$min, 4), " max:", round(v$max, 4),
            " mean:", round(v$mean, 4), "\n",
            "All layers on map: ", all_lyr
          )
        } else {
          crs_nm <- tryCatch(sf::st_crs(ly$data)$input %||% "Unknown", error = function(e) "Unknown")
          paste0(
            "Spatial Analysis | Active vector: ", nm, "\n",
            "Features: ", nrow(ly$data),
            " | Geometry: ", paste(unique(sf::st_geometry_type(ly$data)), collapse = "/"), "\n",
            "CRS: ", crs_nm, "\n",
            "All layers on map: ", all_lyr
          )
        }
      }),
      plot = function() NULL
    )
  })
}
