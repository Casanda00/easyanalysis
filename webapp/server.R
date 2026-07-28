# ==========================================================================
# server.R  --  GeoLibre-inspired shell
# Owns the global concerns: dataset pools, upload, the active-dataset
# selection (left rail), view switching (menubar -> both navsets), the status
# bar, and the View Data modal. Components plug in below.
# ==========================================================================

server <- function(input, output, session) {

  # Shared data state (re-used by every component).
  raw_pool     <- reactiveValues()   # untouched uploads (tabular)
  dataset_pool <- reactiveValues()   # working/edited tabular datasets
  raster_pool  <- reactiveValues()   # shared SpatRaster objects
  las_pool     <- reactiveValues()   # LAS/LAZ point clouds (decimated at read)
  vector_pool  <- reactiveValues()   # sf vector objects

  dataset_names <- reactive({ names(reactiveValuesToList(dataset_pool)) })

  # Currently-active dataset (set by clicking the left rail, or newest upload).
  active_ds <- reactiveVal(NULL)
  observeEvent(input$active_dataset, { active_ds(input$active_dataset) })
  # Bumped whenever a dataset is deleted, to force datasets_list to re-render:
  # reactiveValuesToList() reliably reacts to key ADDS but not always to key
  # REMOVALS in this webR build, so a deleted item's name lingered in the list.
  ds_refresh <- reactiveVal(0)

  # Programmatic view navigation (used by upload handler; same effect as menubar click).
  .switch_view <- function(v) {
    nav_select("canvas_view", v)
    nav_select("tools_view",  v)
  }

  active_dataset <- reactive({
    ds <- active_ds()
    if (!isTruthy(ds) || !(ds %in% names(dataset_pool))) return(NULL)
    ds
  })

  observeEvent(active_ds(), {
    nm <- active_ds()
    req(isTruthy(nm), nm %in% names(dataset_pool))
    df <- dataset_pool[[nm]]
    msgs <- .quality_check(df)
    for (m in msgs)
      showNotification(HTML(paste0("<b>Data Quality:</b> ", m)),
                       type = "warning", duration = 8)
  }, ignoreInit = TRUE)

  # ---- Upload (global, left rail — handles all file types) ----
  observeEvent(input$upload_files, {
    req(input$upload_files)
    files <- input$upload_files

    # Shapefile detection: group all .shp/.shx/.dbf/.prj parts by stem and write to tempdir.
    shp_stems <- unique(tools::file_path_sans_ext(files$name[tolower(tools::file_ext(files$name)) %in% c("shp","shx","dbf","prj","cpg")]))
    shp_tmpdir <- if (length(shp_stems) > 0) {
      d <- file.path(tempdir(), paste0("shp_", as.integer(Sys.time())))
      dir.create(d, showWarnings = FALSE)
      for (i in seq_len(nrow(files))) {
        if (tolower(tools::file_ext(files$name[i])) %in% c("shp","shx","dbf","prj","cpg"))
          file.copy(files$datapath[i], file.path(d, files$name[i]), overwrite = TRUE)
      }
      d
    } else NULL

    for (i in seq_len(nrow(files))) {
      fname <- files$name[i]
      fpath <- files$datapath[i]
      ext   <- tolower(tools::file_ext(fname))

      # Skip companion shapefile parts (handled via the .shp entry below)
      if (ext %in% c("shx","dbf","prj","cpg")) next

      # Guard: in the browser build an upload must have reached webR's virtual
      # filesystem as a real, non-empty file before terra/lidR/sf can read it.
      fsize <- tryCatch(file.info(fpath)$size, error = function(e) NA)
      if (isTRUE(is.na(fsize)) || isTRUE(fsize == 0)) {
        showNotification(
          paste0("Could not read '", fname, "' — the uploaded file is empty or unreadable ",
                 "(0 bytes at ", fpath, "). For large .laz/.tif this can be a browser upload limit."),
          type = "error", duration = NULL)
        next
      }

      tryCatch({
        if (ext %in% c("csv","xlsx","xls","txt")) {
          # ---- Tabular ----
          sep <- input$setting_csv_sep %||% ","
          df <- if (ext == "csv")                 read.csv(fpath, sep = sep)
                else if (ext %in% c("xlsx","xls")) as.data.frame(readxl::read_excel(fpath))
                else                                read.delim(fpath)
          clean_df <- init_data(df)
          raw_pool[[fname]] <- clean_df
          dataset_pool[[fname]] <- clean_df
          active_ds(fname)

        } else if (ext %in% c("tif","tiff","img","asc","nc","grd")) {
          # ---- Raster ----
          nm <- tools::file_path_sans_ext(fname)
          existing <- names(reactiveValuesToList(raster_pool))
          if (nm %in% existing) nm <- make.unique(c(existing, nm), sep = "_")[length(existing) + 1L]
          raster_pool[[nm]] <- terra::rast(fpath)
          .switch_view("raster")
          showNotification(paste0("Raster '", nm, "' loaded — switching to Spatial Analysis."), type = "message")

        } else if (ext %in% c("las","laz")) {
          # ---- LiDAR ----
          # Read the FULL cloud so the user can access all points; only decimate
          # at read for very large files, as a browser-memory safety net (each
          # point carries several attributes; ~5M pts is already several hundred
          # MB in the wasm heap). Display decimation (the snap_pts slider) is
          # separate and handles 3D-viewer performance.
          hdr       <- lidR::readLASheader(fpath)
          total_pts <- hdr@PHB[["Number of point records"]]
          cap       <- 5000000L   # was 500k; raised so full plot-level clouds load
          filt      <- if (!is.na(total_pts) && total_pts > cap)
            paste("-keep_random_fraction", round(cap / total_pts, 6)) else ""
          las <- lidR::readLAS(fpath, filter = filt)
          loaded <- nrow(las@data)
          las_pool[[fname]] <- las
          .switch_view("pointcloud")
          msg <- if (!is.na(total_pts) && total_pts > cap)
            paste0("LAS '", fname, "': ", format(loaded, big.mark=","), " of ",
                   format(total_pts, big.mark=","), " pts loaded (sampled to a ",
                   format(cap, big.mark=","), "-pt memory cap).")
          else paste0("LAS '", fname, "' loaded — full cloud, ",
                      format(loaded, big.mark=","), " pts.")
          showNotification(msg, type = "message")

        } else if (ext %in% c("gpkg","geojson","json")) {
          # ---- Vector (single-file) ----
          vec <- sf::st_read(fpath, quiet = TRUE)
          vector_pool[[fname]] <- vec
          .switch_view("raster")
          showNotification(paste0("Vector '", fname, "' loaded — switching to Spatial Analysis."), type = "message")

        } else if (ext == "shp" && !is.null(shp_tmpdir)) {
          # ---- Shapefile (multi-file; all parts already copied to tempdir) ----
          shp_path <- file.path(shp_tmpdir, fname)
          if (file.exists(shp_path)) {
            Sys.setenv(SHAPE_RESTORE_SHX = "YES")
            vec <- sf::st_read(shp_path, quiet = TRUE)
            Sys.unsetenv("SHAPE_RESTORE_SHX")
            vector_pool[[fname]] <- vec
            .switch_view("raster")
            showNotification(paste0("Shapefile '", fname, "' loaded — switching to Spatial Analysis."), type = "message")
          }

        } else {
          showNotification(paste("Skipped unsupported file:", fname), type = "warning")
        }
      }, error = function(e) {
        # Persistent (duration=NULL) so the real cause stays on screen for
        # spatial files — these are the hard ones to diagnose remotely.
        showNotification(
          HTML(paste0("<b>Error loading ", fname, "</b><br>", htmltools::htmlEscape(e$message))),
          type = "error", duration = NULL)
      })
    }
  })

  # ---- New Dataset modal (left rail button) ----
  # ---- New Dataset modal: rhandsontable spreadsheet ----
  new_ds_df <- reactiveVal({
    df <- as.data.frame(matrix("", nrow = 10, ncol = 5), stringsAsFactors = FALSE)
    names(df) <- paste0("Column", 1:5); df
  })

  observeEvent(input$new_dataset, {
    cur_names <- paste(names(new_ds_df()), collapse = ", ")
    showModal(modalDialog(
      title = "Create New Dataset",
      # Row 1: dataset name
      tags$div(class = "mb-2",
        textInput("new_ds_name", "Dataset Name:", placeholder = "e.g., my_data", width = "100%")),
      # Row 2: column names editable field
      tags$div(class = "mb-2",
        tags$label("Column Names (comma-separated):", class = "form-label small fw-semibold"),
        div(class = "d-flex gap-2",
          textInput("new_ds_col_names", NULL, value = cur_names, width = "100%",
                    placeholder = "col1, col2, col3..."),
          div(style = "flex-shrink:0; margin-top:0;",
            actionButton("new_ds_apply_names", "Apply", class = "btn-sm btn-outline-primary")))),
      # Row 3: grid size + resize
      tags$div(class = "d-flex gap-2 mb-2",
        numericInput("new_ds_rows", "Rows:", value = 10, min = 1, max = 500, step = 1, width = "110px"),
        numericInput("new_ds_cols", "Columns:", value = 5, min = 1, max = 30, step = 1, width = "110px"),
        div(style = "margin-top:24px;",
          actionButton("new_ds_resize", "Resize Grid", class = "btn-sm btn-outline-secondary"))),
      tags$p(class = "text-muted small mb-1",
             "Right-click any row to insert or delete rows. Edit column names above and click Apply."),
      rhandsontable::rHandsontableOutput("new_ds_hot", height = "280px"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("create_dataset", "Save Dataset", class = "btn-success")),
      size = "l", easyClose = FALSE
    ))
  })

  # Apply column names typed by the user
  observeEvent(input$new_ds_apply_names, {
    raw <- trimws(unlist(strsplit(input$new_ds_col_names %||% "", ",")))
    raw <- raw[nzchar(raw)]
    df  <- new_ds_df()
    if (length(raw) == 0) { showNotification("Enter at least one column name.", type = "warning"); return() }
    if (length(raw) != ncol(df)) {
      showNotification(paste0("Need exactly ", ncol(df), " names (got ", length(raw), ")."), type = "warning")
      return()
    }
    names(df) <- make.names(raw, unique = TRUE)
    new_ds_df(df)
  }, ignoreInit = TRUE)

  observeEvent(input$new_ds_resize, {
    r <- max(1L, as.integer(input$new_ds_rows %||% 10))
    c <- max(1L, as.integer(input$new_ds_cols %||% 5))
    old_df <- new_ds_df()
    new_df <- as.data.frame(matrix("", nrow = r, ncol = c), stringsAsFactors = FALSE)
    names(new_df) <- if (c <= ncol(old_df)) names(old_df)[seq_len(c)]
                     else c(names(old_df), paste0("Column", (ncol(old_df)+1):c))
    rs <- min(r, nrow(old_df)); cs <- min(c, ncol(old_df))
    if (rs > 0 && cs > 0)
      new_df[seq_len(rs), seq_len(cs)] <- old_df[seq_len(rs), seq_len(cs)]
    new_ds_df(new_df)
    # Keep the column-names field in sync
    updateTextInput(session, "new_ds_col_names", value = paste(names(new_df), collapse = ", "))
  }, ignoreInit = TRUE)

  output$new_ds_hot <- rhandsontable::renderRHandsontable({
    df <- new_ds_df()
    rhandsontable::rhandsontable(df,
      rowHeaders  = NULL, contextMenu = TRUE,
      stretchH    = "all", useTypes = FALSE
    ) %>%
      rhandsontable::hot_cols(colWidths = 120) %>%
      rhandsontable::hot_context_menu(allowRowEdit = TRUE, allowColEdit = FALSE)
  })

  observeEvent(input$create_dataset, {
    nm <- trimws(input$new_ds_name %||% "")
    if (!nzchar(nm)) { showNotification("Please enter a dataset name.", type = "warning"); return() }
    hot_data <- input$new_ds_hot
    if (is.null(hot_data)) { showNotification("Table is empty — add some data first.", type = "warning"); return() }
    tryCatch({
      df <- rhandsontable::hot_to_r(hot_data)
      blank_row <- apply(df, 1, function(r) all(is.na(r) | trimws(as.character(r)) == ""))
      df <- df[!blank_row, , drop = FALSE]
      if (nrow(df) == 0) stop("All rows are blank — enter some data.")
      # Auto-coerce numeric-looking columns
      df[] <- lapply(df, function(col) {
        num <- suppressWarnings(as.numeric(col))
        if (sum(!is.na(num), na.rm = TRUE) > 0.5 * sum(!is.na(col), na.rm = TRUE)) num else col
      })
      clean_df <- init_data(df)
      raw_pool[[nm]] <- clean_df; dataset_pool[[nm]] <- clean_df; active_ds(nm)
      blank <- as.data.frame(matrix("", 10, 5), stringsAsFactors = FALSE)
      names(blank) <- paste0("Column", 1:5); new_ds_df(blank)
      removeModal()
      showNotification(paste0("Created '", nm, "' (", nrow(clean_df), " rows, ", ncol(clean_df), " cols)."), type = "message")
    }, error = function(e) showNotification(paste("Error:", e$message), type = "error"))
  })

  # ---- Left rail: clickable datasets list (all file types) ----
  pool_nms <- function(pool, icon) {
    nms <- tryCatch(names(reactiveValuesToList(pool)), error = function(e) character(0))
    nms <- if (is.null(nms) || length(nms) == 0) character(0) else as.character(nms)
    if (length(nms) == 0) return(setNames(character(0), character(0)))
    setNames(nms, paste0(icon, " ", nms))
  }

  output$datasets_list <- renderUI({
    ds_refresh()  # re-render on delete (reactiveValuesToList misses key removals here)
    tryCatch({
      # Build a flat list with per-item metadata (label, onclick target view).
      .pool_icon <- function(fa, color)
        sprintf('<i class="fa fa-%s" style="font-size:11px;color:%s;flex-shrink:0;margin-right:4px;"></i>', fa, color)
      make_items <- function(pool, icon_html, view) {
        lst <- tryCatch(reactiveValuesToList(pool), error = function(e) list())
        nms <- names(lst); nms <- if (is.null(nms)) character(0) else as.character(nms)
        # Drop keys whose value is NULL: a deleted dataset can linger as a
        # NULL-valued key in this webR build (`pool[[k]] <- NULL` doesn't always
        # drop the name), which made deleted datasets reappear in the rail.
        if (length(nms)) nms <- nms[vapply(nms, function(n) !is.null(lst[[n]]), logical(1))]
        lapply(nms, function(nm) list(val = nm, lbl = paste0(icon_html, nm), view = view))
      }
      all_items <- c(
        make_items(dataset_pool, .pool_icon("table",        "#4caf50"), "data"),
        make_items(raster_pool,  .pool_icon("map",          "#1565c0"), "raster"),
        make_items(las_pool,     .pool_icon("tree",         "#2e7d32"), "pointcloud"),
        make_items(vector_pool,  .pool_icon("location-dot", "#e65100"), "raster")
      )
      if (length(all_items) == 0)
        return(div(class = "text-muted small fst-italic",
                   "No data yet. Use Add Data or New Dataset."))
      cur <- active_ds()
      lapply(all_items, function(it) {
        val  <- it$val
        lbl  <- it$lbl
        view <- it$view
        # Tabular items set active_dataset; spatial items navigate to their view.
        click_js <- if (view == "data")
          sprintf("Shiny.setInputValue('active_dataset','%s',{priority:'event'})", val)
        else
          sprintf(paste0(
            "Shiny.setInputValue('current_view','%s',{priority:'event'});",
            "Shiny.setInputValue('active_dataset','%s',{priority:'event'});"
          ), view, val)
        cls <- if (isTruthy(cur) && cur == val) "ds-item active" else "ds-item"
        tags$div(
          class = cls,
          style = "display:flex; justify-content:space-between; align-items:center; padding-right:4px;",
          tags$span(HTML(lbl),
            style = "flex:1; cursor:pointer; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; display:flex; align-items:center; gap:4px;",
            onclick = click_js),
          tags$span("×",
            title = "Remove",
            style = "cursor:pointer; color:#dc3545; font-weight:bold; padding:0 4px; flex-shrink:0;",
            onclick = sprintf(
              "event.stopPropagation(); Shiny.setInputValue('delete_dataset','%s',{priority:'event'})", val))
        )
      })
    }, error = function(e) {
      div(class = "text-danger small", paste("Error loading list:", e$message))
    })
  })

  # ---- Delete dataset from appropriate pool ----
  observeEvent(input$delete_dataset, {
    val <- input$delete_dataset
    req(isTruthy(val))
    if (val %in% names(reactiveValuesToList(dataset_pool))) {
      dataset_pool[[val]] <- NULL
      raw_pool[[val]]     <- NULL
      if (isTruthy(active_ds()) && active_ds() == val) active_ds(NULL)
    } else if (val %in% names(reactiveValuesToList(raster_pool))) {
      raster_pool[[val]] <- NULL
    } else if (val %in% names(reactiveValuesToList(las_pool))) {
      las_pool[[val]] <- NULL
    } else if (val %in% names(reactiveValuesToList(vector_pool))) {
      vector_pool[[val]] <- NULL
    }
    ds_refresh(ds_refresh() + 1)  # force datasets_list to drop the removed name
    # Clear the file-upload widget's leftover filename text (it keeps showing the
    # last uploaded name even after the dataset is removed).
    session$sendCustomMessage("ea-reset-upload", list())
    showNotification(paste0("'", val, "' removed."), type = "message", duration = 2)
  })

  # ---- Menubar -> switch canvas + tools in lockstep ----
  observeEvent(input$current_view, {
    nav_select("canvas_view", input$current_view)
    nav_select("tools_view", input$current_view)
  })

  # ---- Status bar ----
  output$status_active <- renderText({ ds <- active_dataset(); if (is.null(ds)) "—" else ds })
  output$status_dims <- renderText({
    ds <- active_dataset()
    if (is.null(ds)) return("no dataset loaded")
    df <- dataset_pool[[ds]]
    paste0(nrow(df), " rows × ", ncol(df), " cols")
  })

  # ---- View Data modal (left rail button) ----
  observeEvent(input$view_data, {
    req(active_dataset())
    showModal(modalDialog(
      title = paste("Dataset Viewer:", active_dataset()),
      DT::dataTableOutput("global_data_table"),
      size = "xl", easyClose = TRUE, footer = modalButton("Close")
    ))
  })
  output$global_data_table <- DT::renderDataTable({
    req(active_dataset())
    DT::datatable(dataset_pool[[active_dataset()]],
                  editable = "cell",
                  options  = list(pageLength = 15, scrollX = TRUE))
  })

  observeEvent(input$global_data_table_cell_edit, {
    info <- input$global_data_table_cell_edit
    ds   <- active_dataset()
    req(ds)
    df <- dataset_pool[[ds]]
    df[info$row, info$col] <- DT::coerceValue(info$value, df[info$row, info$col])
    dataset_pool[[ds]] <- df
  })

  # --- Components (canvas + tools wired by the shell; servers bound once) ---
  # Each model server returns a reactive of its live "context" text for the AI Co-Pilot.
  data_ctx  <- dataServer("data", raw_pool, dataset_pool, dataset_names, active_dataset)
  lm_ctx    <- lmServer("lm", dataset_pool, active_dataset)
  lme_ctx   <- lmeServer("lme", dataset_pool, active_dataset)
  anova_ctx <- anovaServer("anova", dataset_pool, active_dataset)
  log_ctx   <- logisticServer("logistic", dataset_pool, active_dataset)
  rf_ctx    <- rfServer("rf", dataset_pool, active_dataset)
  clust_ctx <- clusteringServer("clustering", dataset_pool, active_dataset)
  clf_ctx   <- classificationServer("classification", dataset_pool, active_dataset)
  da_ctx    <- daServer("da", dataset_pool, active_dataset)
  # New statistical modules
  desc_ctx  <- descriptiveServer("descriptive", dataset_pool, active_dataset)
  test_ctx  <- testsServer("tests", dataset_pool, active_dataset)
  pca_ctx   <- pcaServer("pca", dataset_pool, active_dataset)
  ts_ctx    <- timeseriesServer("timeseries", dataset_pool, active_dataset)
  surv_ctx  <- survivalServer("survival", dataset_pool, active_dataset)
  sem_ctx   <- semServer("sem", dataset_pool, active_dataset)
  bayes_ctx <- bayesianServer("bayesian", dataset_pool, active_dataset)
  # New ML modules
  xgb_ctx   <- xgboostServer("xgboost", dataset_pool, active_dataset)
  dtree_ctx <- dtreeServer("dtree", dataset_pool, active_dataset)
  nnet_ctx  <- nnetMlServer("nnet_ml", dataset_pool, active_dataset)
  svm_ctx   <- svmServer("svm", dataset_pool, active_dataset)
  # Spatial modules
  lidar_ctx      <- lidarServer("lidar", dataset_pool, las_pool, vector_pool)
  raster_ctx     <- rasterServer("raster", dataset_pool, active_dataset, raster_pool, vector_pool)
  surface_ctx    <- surfaceServer("surface", las_pool, raster_pool)
  terrain_ctx    <- terrainServer("terrain", raster_pool)
  hydro_ctx      <- hydroServer("hydro", raster_pool)
  suit_ctx       <- suitabilityServer("suitability", raster_pool)
  land_cls_ctx   <- landClassifyServer("land_classify", raster_pool)
  rs_ctx         <- rsSearchServer("rs_search", dataset_pool, active_dataset, raster_pool)
  rec_ctx        <- recommendServer("recommend", dataset_pool, active_dataset)
  # New spatial modeling & analysis modules
  ntl_ctx        <- ntlServer("ntl", dataset_pool, active_dataset, vector_pool)
  climate_ctx    <- climateTrendServer("climate_trend", raster_pool)
  wind_ctx       <- windServer("wind", dataset_pool, active_dataset)
  gam_ctx        <- gamServer("gam", dataset_pool, active_dataset)
  rconsole_ctx   <- rconsoleServer("rconsole", dataset_pool, active_dataset)

  module_ctx <- list(
    data = data_ctx,
    descriptive = desc_ctx, tests = test_ctx,
    lm = lm_ctx, lme = lme_ctx, anova = anova_ctx, logistic = log_ctx,
    survival = surv_ctx, sem = sem_ctx, bayesian = bayes_ctx,
    rf = rf_ctx, xgboost = xgb_ctx, dtree = dtree_ctx,
    nnet_ml = nnet_ctx, svm = svm_ctx,
    clustering = clust_ctx, classification = clf_ctx, da = da_ctx,
    pca = pca_ctx, timeseries = ts_ctx,
    pointcloud = lidar_ctx, chm_itd = lidar_ctx, metrics = lidar_ctx,
    raster = raster_ctx, surface = surface_ctx, rs_search = rs_ctx,
    terrain = terrain_ctx, hydro = hydro_ctx,
    suitability = suit_ctx, land_classify = land_cls_ctx,
    recommend = rec_ctx,
    ntl = ntl_ctx,
    climate_trend = climate_ctx, wind = wind_ctx, gam = gam_ctx,
    rconsole = rconsole_ctx
  )

  chatServer("chat", dataset_pool, active_dataset, reactive(input$current_view), module_ctx)
}
