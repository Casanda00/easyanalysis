# mod_annotator.R — Spatial Feature Annotator
# Draw, label, and export geo-referenced annotations on a leaflet map.
# Supports polygon (rotated boxes), rectangle, circle, polyline, marker.
# Export: GeoJSON, CSV (bbox), COCO JSON, GeoPackage, Pascal VOC XML.

annotatorCanvasUI <- function(id) {
  ns <- NS(id)
  leafletOutput(ns("map"), width = "100%", height = "100%")
}

annotatorToolsUI <- function(id) {
  ns <- NS(id)
  accordion(
    open = c("Source", "Label"),
    accordion_panel("Source",
      uiOutput(ns("pool_sel_ui")),
      actionButton(ns("load_bg"), tagList(icon("image"), " Load as background"),
                   class = "btn-sm btn-outline-secondary w-100 mt-1"),
      hr(class = "my-2"),
      div(class = "alert alert-light p-2 mb-0",
        tags$small(
          icon("circle-info"), " ",
          tags$b("Rotation tip:"), " use ", tags$b("Polygon"), " mode and click",
          " each corner (double-click to close) for rotated bounding boxes."
        )
      )
    ),
    accordion_panel("Label",
      textInput(ns("label"), "Class label", placeholder = "tree, road, building…"),
      fluidRow(
        column(6, selectInput(ns("color"), "Colour",
          choices = c("Green"="#43a047","Red"="#e53935","Blue"="#1e88e5",
                      "Orange"="#fb8c00","Purple"="#8e24aa","Yellow"="#fdd835"),
          selected = "#43a047")),
        column(6, numericInput(ns("conf"), "Confidence", value = 1, min=0, max=1, step=0.1))
      ),
      actionButton(ns("set_label"), tagList(icon("tag"), " Set active label"),
                   class = "btn-sm btn-success w-100"),
      uiOutput(ns("active_badge"))
    ),
    accordion_panel("Annotations",
      uiOutput(ns("anno_count")),
      DT::DTOutput(ns("anno_tbl"), height = "220px"),
      hr(class = "my-1"),
      fluidRow(
        column(6, actionButton(ns("del_sel"), tagList(icon("trash"), " Delete row"),
                               class = "btn-sm btn-outline-danger w-100")),
        column(6, actionButton(ns("clear_all"), tagList(icon("xmark"), " Clear all"),
                               class = "btn-sm btn-outline-danger w-100"))
      )
    ),
    accordion_panel("Export",
      selectInput(ns("fmt"), "Format", choices = c(
        "GeoJSON (.geojson)"      = "geojson",
        "CSV (bounding-box)"      = "csv",
        "COCO JSON (ML training)" = "coco",
        "GeoPackage (.gpkg)"      = "gpkg",
        "Pascal VOC XML"          = "voc"
      )),
      downloadButton(ns("dl"), tagList(icon("download"), " Download annotations"),
                     class = "btn-sm btn-success w-100 mt-1")
    )
  )
}

annotatorServer <- function(id, raster_pool = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      annotations = list(),
      next_id     = 1L,
      act_label   = "",
      act_color   = "#43a047",
      act_conf    = 1.0
    )

    # ---- Pool selector --------------------------------------------------------
    output$pool_sel_ui <- renderUI({
      nms <- if (!is.null(raster_pool)) names(reactiveValuesToList(raster_pool)) else character(0)
      if (!length(nms))
        return(p(class = "text-muted small", "No rasters loaded — annotate on the basemap."))
      selectInput(ns("pool_nm"), "Raster background", choices = c("(basemap only)" = "", nms))
    })

    # ---- Active label badge --------------------------------------------------
    output$active_badge <- renderUI({
      if (!nchar(rv$act_label))
        return(p(class = "text-muted small mt-1", "No label set."))
      div(class = "d-flex align-items-center gap-2 mt-2",
        div(style = paste0("width:12px;height:12px;border-radius:3px;background:",
                           rv$act_color, ";flex-shrink:0")),
        span(class = "small fw-semibold", rv$act_label),
        span(class = "text-muted small", paste0("conf=", rv$act_conf))
      )
    })

    observeEvent(input$set_label, {
      rv$act_label <- trimws(input$label %||% "")
      rv$act_color <- input$color  %||% "#43a047"
      rv$act_conf  <- input$conf   %||% 1.0
    })

    # ---- Draw toolbar helper --------------------------------------------------
    .add_draw <- function(mp) {
      leaflet.extras::addDrawToolbar(mp,
        targetGroup       = "annotations",
        polylineOptions   = leaflet.extras::drawPolylineOptions(repeatMode = FALSE),
        polygonOptions    = leaflet.extras::drawPolygonOptions(repeatMode = FALSE),
        rectangleOptions  = leaflet.extras::drawRectangleOptions(repeatMode = FALSE),
        circleOptions     = leaflet.extras::drawCircleOptions(repeatMode = FALSE),
        markerOptions     = leaflet.extras::drawMarkerOptions(),
        circleMarkerOptions = FALSE,
        editOptions       = leaflet.extras::editToolbarOptions()
      )
    }

    # ---- Base map ------------------------------------------------------------
    output$map <- renderLeaflet({
      .add_draw(
        leaflet() %>%
          addProviderTiles("OpenStreetMap",     group = "OSM") %>%
          addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
          addProviderTiles("CartoDB.Positron",  group = "CartoDB") %>%
          addLayersControl(baseGroups = c("OSM", "Satellite", "CartoDB"),
                           options = layersControlOptions(collapsed = TRUE)) %>%
          addScaleBar(position = "bottomright") %>%
          setView(lng = 25.7, lat = 62.5, zoom = 5)
      )
    })
    outputOptions(output, "map", suspendWhenHidden = FALSE)

    # ---- Load raster background ---------------------------------------------
    observeEvent(input$load_bg, {
      nm <- input$pool_nm %||% ""
      if (!nzchar(nm) || is.null(raster_pool)) return()
      r <- raster_pool[[nm]]
      if (is.null(r)) return()
      r1 <- tryCatch(.to_wgs84(r[[1]]), error = function(e) NULL)
      if (is.null(r1)) { showNotification("Cannot reproject raster to WGS84.", type = "warning"); return() }
      r_st <- tryCatch(stars::st_as_stars(r1), error = function(e) NULL)
      if (is.null(r_st)) return()
      leafletProxy("map", session = session) %>%
        clearImages() %>%
        leafem::addGeoRaster(x = r_st, group = nm, opacity = 0.85,
          colorOptions = leafem::colorOptions(palette = "greys", na.color = "transparent")) %>%
        fitBounds(terra::xmin(r1), terra::ymin(r1), terra::xmax(r1), terra::ymax(r1))
    })

    # ---- Capture drawn features ---------------------------------------------
    observeEvent(input$map_draw_new_feature, {
      feat <- input$map_draw_new_feature
      aid  <- paste0("ann_", rv$next_id)
      rv$next_id <- rv$next_id + 1L
      rv$annotations[[aid]] <- list(
        id        = aid,
        feature   = feat,
        label     = rv$act_label,
        color     = rv$act_color,
        conf      = rv$act_conf,
        geom_type = feat$geometry$type %||% "Unknown"
      )
    })

    # ---- Annotation count & table -------------------------------------------
    output$anno_count <- renderUI({
      n <- length(rv$annotations)
      p(class = "text-muted small mb-1",
        paste(n, if (n == 1) "annotation" else "annotations"))
    })

    output$anno_tbl <- DT::renderDT({
      anns <- rv$annotations
      if (!length(anns))
        return(DT::datatable(data.frame(ID=character(), Label=character(),
                                        Type=character(), Confidence=numeric()),
                             rownames = FALSE,
                             options = list(dom = "t")))
      df <- do.call(rbind, lapply(anns, function(a)
        data.frame(ID=a$id, Label=a$label, Type=a$geom_type,
                   Confidence=a$conf, stringsAsFactors=FALSE)))
      DT::datatable(df, selection="single", rownames=FALSE,
                    options=list(dom="t", pageLength=50, scrollY="190px", scrollCollapse=TRUE))
    })

    # ---- Delete selected row ------------------------------------------------
    observeEvent(input$del_sel, {
      sel <- input$anno_tbl_rows_selected
      if (!length(sel)) { showNotification("Select a row first.", type="warning", duration=2); return() }
      ids <- names(rv$annotations)
      if (sel <= length(ids)) rv$annotations[[ids[sel]]] <- NULL
    })

    # ---- Clear all ----------------------------------------------------------
    observeEvent(input$clear_all, {
      rv$annotations <- list()
      px <- leafletProxy("map", session = session)
      tryCatch(leaflet.extras::removeDrawToolbar(px, clearFeatures = TRUE), error = function(e) NULL)
      .add_draw(px)
    })

    # ---- Helpers ------------------------------------------------------------
    .build_gc <- function() {
      feats <- lapply(rv$annotations, function(a) list(
        type       = "Feature",
        geometry   = a$feature$geometry,
        properties = list(id=a$id, label=a$label, color=a$color,
                          confidence=a$conf, geom_type=a$geom_type)
      ))
      list(type = "FeatureCollection", features = feats)
    }

    .bbox_of <- function(a) {
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

    # ---- Download -----------------------------------------------------------
    output$dl <- downloadHandler(
      filename = function() switch(input$fmt %||% "geojson",
        geojson = "annotations.geojson",
        csv     = "annotations.csv",
        coco    = "annotations_coco.json",
        gpkg    = "annotations.gpkg",
        voc     = "annotations_voc.xml",
        "annotations.geojson"
      ),
      content = function(file) {
        anns <- rv$annotations
        fmt  <- input$fmt %||% "geojson"
        gc   <- .build_gc()

        if (fmt == "geojson") {
          writeLines(jsonlite::toJSON(gc, auto_unbox=TRUE, pretty=TRUE), file)

        } else if (fmt == "csv") {
          rows <- lapply(anns, function(a) {
            bb <- .bbox_of(a)
            data.frame(id=a$id, label=a$label, type=a$geom_type,
                       xmin=bb[1], ymin=bb[2], xmax=bb[3], ymax=bb[4],
                       confidence=a$conf, stringsAsFactors=FALSE)
          })
          write.csv(if (length(rows)) do.call(rbind, rows) else data.frame(),
                    file, row.names=FALSE)

        } else if (fmt == "coco") {
          cats     <- sort(unique(Filter(nchar, sapply(anns, `[[`, "label"))))
          cat_list <- lapply(seq_along(cats), function(i)
            list(id=i, name=cats[i], supercategory="object"))
          ann_list <- lapply(seq_along(anns), function(i) {
            a  <- anns[[i]]
            bb <- .bbox_of(a)
            ci <- match(a$label, cats) %||% 0L
            list(id=i, image_id=1L, category_id=as.integer(ci),
                 bbox = as.list(c(bb[1], bb[2], bb[3]-bb[1], bb[4]-bb[2])),
                 area = max(0, (bb[3]-bb[1])*(bb[4]-bb[2])),
                 segmentation = list(), iscrowd = 0L)
          })
          writeLines(jsonlite::toJSON(
            list(images      = list(list(id=1L, file_name="image.jpg", width=0L, height=0L)),
                 annotations = ann_list,
                 categories  = cat_list),
            auto_unbox=TRUE, pretty=TRUE), file)

        } else if (fmt == "gpkg") {
          gj_str <- jsonlite::toJSON(gc, auto_unbox=TRUE)
          tmp    <- tempfile(fileext=".geojson")
          writeLines(gj_str, tmp)
          sf_obj <- tryCatch(sf::st_read(tmp, quiet=TRUE), error=function(e) NULL)
          if (!is.null(sf_obj))
            sf::st_write(sf_obj, file, driver="GPKG", delete_dsn=TRUE, quiet=TRUE)
          else writeLines('{"type":"FeatureCollection","features":[]}', file)

        } else if (fmt == "voc") {
          lns <- c('<?xml version="1.0"?>', "<annotations>")
          for (a in anns) {
            bb <- .bbox_of(a)
            lns <- c(lns,
              "  <object>",
              paste0("    <name>",       a$label,  "</name>"),
              paste0("    <confidence>", a$conf,   "</confidence>"),
              "    <bndbox>",
              paste0("      <xmin>", round(bb[1],6), "</xmin>"),
              paste0("      <ymin>", round(bb[2],6), "</ymin>"),
              paste0("      <xmax>", round(bb[3],6), "</xmax>"),
              paste0("      <ymax>", round(bb[4],6), "</ymax>"),
              "    </bndbox>",
              "  </object>"
            )
          }
          writeLines(c(lns, "</annotations>"), file)
        }
      }
    )

    list(
      context = reactive({ list(n_annotations = length(rv$annotations)) }),
      plot    = function() NULL
    )
  })
}
