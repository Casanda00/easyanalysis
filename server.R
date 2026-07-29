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
  # Every view change must go through here so the client also learns about it —
  # the Projects screen hides the rails, and a programmatic switch (e.g. opening
  # a project) has to bring them back.
  # MUST pass session = session explicitly. This function is also called from
  # INSIDE module observers (e.g. projectsServer -> open_project), where
  # getDefaultReactiveDomain() is the MODULE session — nav_select would then look
  # for a namespaced "canvas_view", find nothing, and silently do nothing. The
  # pane stays hidden, its outputs stay suspended, and the screen renders
  # forever. Symptom: a renderUI stuck on "recalculating" with no error.
  # Only these views still exist as panes; every analysis screen was unified into
  # the workspace, so any other view id resolves to "workspace" (the workspace
  # then selects that tool via `tool_request`).
  .FRAME_VIEWS <- c("projects", "project", "workspace")
  .switch_view <- function(v) {
    if (!v %in% .FRAME_VIEWS) v <- "workspace"
    nav_select("canvas_view", v, session = session)
    nav_select("tools_view",  v, session = session)
    session$sendCustomMessage("ea-view", v)
    # Recompute the Projects empty/populated chrome on every entry (project
    # counts may have changed while we were away).
    if (identical(v, "projects")) {
      n <- tryCatch(length(ea_project_list()), error = function(e) 0L)
      session$sendCustomMessage("ea-projects-empty", n == 0L)
    }
  }

  active_dataset <- reactive({
    # ds_refresh is a deliberate invalidation handle. Module screens fill their
    # selectors with updateSelectInput() driven off this reactive, but the
    # workspace renders a module's panel LAZILY, when its tool is opened. The
    # update therefore fires while the element does not yet exist, Shiny drops
    # it, and nothing re-runs because the dataset itself never changed — which
    # is why Linear regression, ANOVA and Random forest opened with empty
    # Response dropdowns. Bumping ds_refresh when a tool opens re-runs those
    # observers against a panel that now exists.
    ds_refresh()
    ds <- active_ds()
    if (!isTruthy(ds) || !(ds %in% names(dataset_pool))) return(NULL)
    ds
  })

  observeEvent(active_ds(), {
    nm <- active_ds()
    req(isTruthy(nm), nm %in% names(dataset_pool))
    df <- dataset_pool[[nm]]
    # A quality warning must NEVER break dataset activation.
    msgs <- tryCatch(.quality_check(df), error = function(e) character(0))
    for (m in msgs)
      showNotification(HTML(paste0("<b>Data Quality:</b> ", m)),
                       type = "warning", duration = 8)
  }, ignoreInit = TRUE)

  # Read a LAS/LAZ with a memory-safety point cap: decimate AT READ above `cap`
  # so a large cloud never loads in full and OOMs. Used by BOTH the upload path
  # and project reopen. Header + point-count reads are guarded.
  .read_las_capped <- function(path, cap = 5000000L) {
    hdr <- tryCatch(lidR::readLASheader(path), error = function(e) NULL)
    tp  <- tryCatch({
      p <- if (!is.null(hdr)) hdr@PHB[["Number of point records"]] else NULL
      if (is.null(p) || length(p) != 1 || is.na(p) || p == 0)
        p <- tryCatch(hdr@PHB[["Number of points by return"]][1], error = function(e) NA)
      suppressWarnings(as.numeric(p))
    }, error = function(e) NA_real_)
    f <- if (!is.na(tp) && tp > cap) paste("-keep_random_fraction", round(cap / tp, 6)) else ""
    lidR::readLAS(path, filter = f)
  }

  # ---- Upload (shared) ------------------------------------------------------
  # Ingests one file by extension. Extracted from the left-rail observer so the
  # project screen's drop zone and the sample-data buttons route through exactly
  # the same path (including .keep_source, so everything persists identically).
  .ingest_files <- function(files) {

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

    n_files <- nrow(files)
    withProgress(message = "Adding data to the project…", value = 0, {
    for (i in seq_len(n_files)) {
      fname <- files$name[i]
      fpath <- files$datapath[i]
      ext   <- tolower(tools::file_ext(fname))

      # Skip companion shapefile parts (handled via the .shp entry below)
      if (ext %in% c("shx","dbf","prj","cpg")) next

      # Show which file is loading (large LiDAR/rasters can take a while).
      incProgress(0, detail = paste0("Reading ", fname, " …  (", i, " of ", n_files, ")"))

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
          .keep_source(nm, fpath, fname)
          showNotification(paste0("Raster '", nm, "' added to the project."), type = "message")

        } else if (ext %in% c("las","laz")) {
          # ---- LiDAR ----
          # Read the FULL cloud so the user can access all points; only decimate
          # at read for very large files, as a browser-memory safety net (each
          # point carries several attributes; ~5M pts is already several hundred
          # MB in the wasm heap). Display decimation (the snap_pts slider) is
          # separate and handles 3D-viewer performance.
          hdr <- tryCatch(lidR::readLASheader(fpath), error = function(e) NULL)
          # Point count slot name varies by LAS version — read it defensively so
          # a NULL/empty value can never crash the branch.
          total_pts <- tryCatch({
            p <- if (!is.null(hdr)) hdr@PHB[["Number of point records"]] else NULL
            if (is.null(p) || length(p) != 1 || is.na(p) || p == 0)
              p <- tryCatch(hdr@PHB[["Number of points by return"]][1], error = function(e) NA)
            suppressWarnings(as.numeric(p))
          }, error = function(e) NA_real_)
          cap  <- 5000000L   # memory-safety cap; decimate at read above this
          filt <- if (!is.na(total_pts) && total_pts > cap)
            paste("-keep_random_fraction", round(cap / total_pts, 6)) else ""
          incProgress(0, detail = paste0("Reading point cloud ", fname, " …"))
          las <- tryCatch(lidR::readLAS(fpath, filter = filt), error = function(e) e)
          if (inherits(las, "error") || is.null(las) || is.null(las@data) || nrow(las@data) == 0) {
            showNotification(
              HTML(paste0("<b>Could not read '", fname, "'</b> as a point cloud — the .laz may be ",
                          "corrupt, an unsupported version, or too large for available memory.",
                          if (inherits(las, "error"))
                            paste0("<br>", htmltools::htmlEscape(conditionMessage(las))) else "")),
              type = "error", duration = NULL)
          } else {
            loaded <- nrow(las@data)
            las_pool[[fname]] <- las
            .keep_source(fname, fpath, fname)
            msg <- if (!is.na(total_pts) && total_pts > cap)
              paste0("LAS '", fname, "': ", format(loaded, big.mark=","), " of ",
                     format(total_pts, big.mark=","), " pts loaded (sampled to a ",
                     format(cap, big.mark=","), "-pt memory cap).")
            else paste0("LAS '", fname, "' loaded — ", format(loaded, big.mark=","), " pts.")
            showNotification(msg, type = "message")
          }

        } else if (ext %in% c("gpkg","geojson","json")) {
          # ---- Vector (single-file) ----
          vec <- sf::st_read(fpath, quiet = TRUE)
          vector_pool[[fname]] <- vec
          .keep_source(fname, fpath, fname)
          showNotification(paste0("Vector '", fname, "' added to the project."), type = "message")

        } else if (ext == "shp" && !is.null(shp_tmpdir)) {
          # ---- Shapefile (multi-file; all parts already copied to tempdir) ----
          shp_path <- file.path(shp_tmpdir, fname)
          if (file.exists(shp_path)) {
            Sys.setenv(SHAPE_RESTORE_SHX = "YES")
            vec <- sf::st_read(shp_path, quiet = TRUE)
            Sys.unsetenv("SHAPE_RESTORE_SHX")
            vector_pool[[fname]] <- vec
            # A shapefile is several files; copy every sibling part too.
            .keep_source(fname, shp_path, fname,
                         extra = list.files(shp_tmpdir, full.names = TRUE))
            # A shapefile carries its ATTRIBUTES in the .dbf. Uploading only the
            # .shp still yields a perfectly good geometry layer, so the app used
            # to accept it silently and the attribute table then looked broken.
            # Say so at the point the information is lost.
            ncols <- tryCatch(ncol(sf::st_drop_geometry(vec)), error = function(e) NA_integer_)
            parts <- tolower(tools::file_ext(list.files(shp_tmpdir)))
            if (!is.na(ncols) && ncols == 0) {
              showNotification(HTML(paste0(
                "<b>", fname, "</b> loaded with geometry only — no attributes.<br>",
                "A shapefile keeps its attributes in the <b>.dbf</b> file, which was not ",
                "included. Select every part together (.shp, .dbf, .shx, .prj) and add it again.")),
                type = "warning", duration = 14)
            } else if (!("dbf" %in% parts)) {
              showNotification(paste0("Shapefile '", fname, "' added, but its .dbf was missing."),
                               type = "warning", duration = 10)
            } else {
              showNotification(paste0("Shapefile '", fname, "' added to the project."), type = "message")
            }
          }

        } else {
          # Extension not in the known lists: DETECT the type dynamically from
          # the file's content rather than giving up — try raster (terra), then
          # vector (sf). Both attempts are guarded, so a truly unreadable file
          # still falls through to the "unsupported" notice.
          rr <- tryCatch(suppressWarnings(terra::rast(fpath)), error = function(e) NULL)
          if (!is.null(rr)) {
            nm <- tools::file_path_sans_ext(fname)
            existing <- names(reactiveValuesToList(raster_pool))
            if (nm %in% existing) nm <- make.unique(c(existing, nm), sep = "_")[length(existing) + 1L]
            raster_pool[[nm]] <- rr
            .keep_source(nm, fpath, fname)
            showNotification(paste0("Detected raster '", nm, "' — added to the project."), type = "message")
          } else {
            vv <- tryCatch(sf::st_read(fpath, quiet = TRUE), error = function(e) NULL)
            if (!is.null(vv)) {
              vector_pool[[fname]] <- vv
              .keep_source(fname, fpath, fname)
              showNotification(paste0("Detected vector '", fname, "' — added to the project."), type = "message")
            } else {
              showNotification(paste("Skipped unsupported file:", fname), type = "warning")
            }
          }
        }
      }, error = function(e) {
        # Persistent (duration=NULL) so the real cause stays on screen for
        # spatial files — these are the hard ones to diagnose remotely.
        showNotification(
          HTML(paste0("<b>Error loading ", fname, "</b><br>", htmltools::htmlEscape(e$message))),
          type = "error", duration = NULL)
      })
      incProgress(1 / n_files)
    }
    })
  }

  # Left rail upload -> shared ingestion.
  observeEvent(input$upload_files, {
    req(input$upload_files)
    .ingest_files(input$upload_files)
  })

  # ---- Sample data ----------------------------------------------------------
  # Generated, then written to a real file and ingested through the SAME path as
  # an upload, so samples persist and reload exactly like a user's own data.
  .load_sample <- function(kind) {
    d <- file.path(tempdir(), paste0("ea-sample-", as.integer(runif(1, 1e5, 9e5))))
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
    f <- NULL
    tryCatch({
      if (identical(kind, "table")) {
        set.seed(42); n <- 180
        soil <- factor(sample(c("Moraine / Till", "Sorted mineral", "Organic peat"),
                              n, TRUE, c(.5, .3, .2)))
        df <- data.frame(
          plot_id   = sprintf("P%03d", seq_len(n)),
          soil_type = soil,
          drainage  = factor(sample(c("Dry", "Mesic", "Moist"), n, TRUE)),
          stand_age = round(rnorm(n, 55, 18)),
          basal_area = round(pmax(2, rnorm(n, 22, 6)), 1)
        )
        df$growth <- round(2.1 + .035 * df$stand_age + .09 * df$basal_area -
                             ifelse(soil == "Organic peat", 1.4, 0) + rnorm(n, 0, .7), 2)
        f <- file.path(d, "forest_plots.csv"); write.csv(df, f, row.names = FALSE)
      } else if (identical(kind, "raster")) {
        r <- terra::rast(nrows = 120, ncols = 120, xmin = 0, xmax = 1200,
                         ymin = 0, ymax = 1200, crs = "EPSG:3067")
        xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
        terra::values(r) <- pmax(0, 14 + 8 * sin(xy[,1]/180) * cos(xy[,2]/210) +
                                   rnorm(terra::ncell(r), 0, 1.2))
        names(r) <- "canopy_height"
        f <- file.path(d, "canopy_height.tif"); terra::writeRaster(r, f, overwrite = TRUE)
      } else if (identical(kind, "las")) {
        set.seed(7); n <- 40000
        x <- runif(n, 0, 100); y <- runif(n, 0, 100)
        ground <- 10 + .02 * x
        z <- ground + ifelse(runif(n) < .65, abs(rnorm(n, 12, 4)), runif(n, 0, .4))
        las <- lidR::LAS(data.frame(X = x, Y = y, Z = z,
                                    Intensity = as.integer(runif(n, 10, 200)),
                                    Classification = as.integer(ifelse(z - ground < .5, 2L, 5L)),
                                    ReturnNumber = 1L, NumberOfReturns = 1L))
        f <- file.path(d, "sample_tile.laz"); lidR::writeLAS(las, f)
      }
    }, error = function(e) {
      showNotification(paste("Could not build the sample:", e$message), type = "error")
      f <<- NULL
    })
    if (is.null(f) || !file.exists(f)) return(invisible(FALSE))
    .ingest_files(data.frame(name = basename(f), datapath = f,
                             stringsAsFactors = FALSE))
    invisible(TRUE)
  }

  # ---- New Dataset modal (left rail button) ----
  # ---- New Dataset modal: rhandsontable spreadsheet ----
  new_ds_df <- reactiveVal({
    df <- as.data.frame(matrix("", nrow = 6, ncol = 4), stringsAsFactors = FALSE)
    names(df) <- paste0("Column", 1:4); df
  })

  observeEvent(input$new_dataset, {
    showModal(modalDialog(
      title = "Create a dataset",
      div(class = "mb-3",
        textInput("new_ds_name", "Dataset name", placeholder = "e.g. my_data", width = "100%")),
      # Real-spreadsheet feel: rename a column by DOUBLE-CLICKING its header
      # (no comma field). Right-click for row/column insert/delete; rows auto-grow.
      tags$p(class = "text-muted small mb-2",
        "Double-click a column header to rename it. Use the buttons to add rows or ",
        "columns (or right-click a cell). Rows also grow as you type."),
      div(class = "d-flex gap-2 mb-2",
        actionButton("new_ds_add_row", "Row",
                     class = "btn-sm btn-outline-secondary", icon = icon("plus")),
        actionButton("new_ds_add_col", "Column",
                     class = "btn-sm btn-outline-secondary", icon = icon("plus"))),
      rhandsontable::rHandsontableOutput("new_ds_hot", height = "320px"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("create_dataset", "Save dataset", class = "btn-success")),
      size = "l", easyClose = FALSE
    ))
  })

  output$new_ds_hot <- rhandsontable::renderRHandsontable({
    rhandsontable::rhandsontable(new_ds_df(),
      rowHeaders = NULL, contextMenu = TRUE, stretchH = "all",
      useTypes = FALSE, minSpareRows = 1        # rows auto-grow (spreadsheet feel)
    ) %>%
      rhandsontable::hot_context_menu(allowRowEdit = TRUE, allowColEdit = TRUE) %>%
      htmlwidgets::onRender(
        "function(el, x){
           el.addEventListener('dblclick', function(e){
             var th = e.target.closest('thead th'); if(!th) return;
             var span = th.querySelector('.colHeader');
             var cur = (span || th).textContent.trim();
             var idx = Array.prototype.indexOf.call(th.parentNode.children, th);
             var name = window.prompt('Rename column', cur);
             if(name && name.trim() && name.trim() !== cur){
               Shiny.setInputValue('new_ds_hot_rename',
                 {col: idx, name: name.trim(), t: Date.now()}, {priority:'event'});
             }
           });
         }")
  })

  # Current grid data as character, with the trailing blank spare row trimmed
  # (minSpareRows adds one) — shared by rename / add-row / add-col.
  .new_ds_current <- function() {
    df <- tryCatch(
      if (!is.null(input$new_ds_hot)) rhandsontable::hot_to_r(input$new_ds_hot) else new_ds_df(),
      error = function(e) new_ds_df())
    df[] <- lapply(df, as.character)
    isblank <- function(r) all(is.na(r) | trimws(as.character(r)) == "")
    while (nrow(df) > 1 && isblank(df[nrow(df), , drop = FALSE])) df <- df[-nrow(df), , drop = FALSE]
    df
  }

  observeEvent(input$new_ds_add_row, {
    df <- .new_ds_current(); df[nrow(df) + 1L, ] <- ""; new_ds_df(df)
  })
  observeEvent(input$new_ds_add_col, {
    df <- .new_ds_current()
    nm <- make.unique(c(names(df), paste0("Column", ncol(df) + 1L)))[ncol(df) + 1L]
    df[[nm]] <- ""; new_ds_df(df)
  })

  # Inline header rename -> update the column name, preserving grid data.
  observeEvent(input$new_ds_hot_rename, {
    info <- input$new_ds_hot_rename
    col  <- suppressWarnings(as.integer(info$col)) + 1L
    df <- tryCatch(
      if (!is.null(input$new_ds_hot)) rhandsontable::hot_to_r(input$new_ds_hot) else new_ds_df(),
      error = function(e) new_ds_df())
    df[] <- lapply(df, as.character)   # hot_to_r can return list-cols for empty cells
    # drop the trailing all-blank spare row(s) so renaming never grows the grid
    isblank <- function(r) all(is.na(r) | trimws(as.character(r)) == "")
    while (nrow(df) > 1 && isblank(df[nrow(df), , drop = FALSE])) df <- df[-nrow(df), , drop = FALSE]
    if (is.na(col) || col < 1 || col > ncol(df)) return()
    nm <- make.names(info$name)
    others <- names(df)[-col]
    if (nm %in% others) nm <- make.unique(c(others, nm))[length(others) + 1L]
    names(df)[col] <- nm
    new_ds_df(df)
  }, ignoreInit = TRUE)

  observeEvent(input$create_dataset, {
    nm <- trimws(input$new_ds_name %||% "")
    if (!nzchar(nm)) { showNotification("Please enter a dataset name.", type = "warning"); return() }
    hot_data <- input$new_ds_hot
    if (is.null(hot_data)) { showNotification("Table is empty — add some data first.", type = "warning"); return() }
    tryCatch({
      df <- rhandsontable::hot_to_r(hot_data)
      df[] <- lapply(df, as.character)   # hot_to_r can return list-cols for empty cells
      # Column NAMES live in new_ds_df (rename/add update it); the grid input can
      # report STALE names after a server-side re-render, so a header renamed via
      # double-click would be lost on save. Realign names by position.
      tn <- names(new_ds_df())
      if (length(tn) == ncol(df)) names(df) <- tn
      blank_row <- vapply(seq_len(nrow(df)),
        function(i) all(is.na(unlist(df[i, ])) | trimws(as.character(unlist(df[i, ]))) == ""),
        logical(1))
      df <- df[!blank_row, , drop = FALSE]
      if (nrow(df) == 0) stop("All rows are blank — enter some data.")
      # Auto-coerce numeric-looking columns
      df[] <- lapply(df, function(col) {
        num <- suppressWarnings(as.numeric(col))
        if (sum(!is.na(num), na.rm = TRUE) > 0.5 * sum(!is.na(col), na.rm = TRUE)) num else col
      })
      clean_df <- init_data(df)
      raw_pool[[nm]] <- clean_df; dataset_pool[[nm]] <- clean_df; active_ds(nm)
      blank <- as.data.frame(matrix("", 6, 4), stringsAsFactors = FALSE)
      names(blank) <- paste0("Column", 1:4); new_ds_df(blank)
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
    # Delete the copy this project made of a spatial layer, so removing a layer
    # does not leave an orphaned file behind. ea_project_remove_file() only ever
    # deletes inside the project's own files/ folder — the user's original file
    # is never touched.
    local({
      pid <- current_project(); src <- .src_path(val)
      if (!is.null(pid) && nzchar(src))
        try(ea_project_remove_file(pid, src), silent = TRUE)
      src_paths[[val]] <- NULL
    })
    gc(FALSE)                     # reclaim the removed object's memory
    ds_refresh(ds_refresh() + 1)  # force datasets_list to drop the removed name
    # Clear the file-upload widget's leftover filename text (it keeps showing the
    # last uploaded name even after the dataset is removed).
    session$sendCustomMessage("ea-reset-upload", list())
    showNotification(paste0("'", val, "' removed."), type = "message", duration = 2)
  })

  # ---- Menubar -> switch canvas + tools in lockstep ----
  observeEvent(input$current_view, .switch_view(input$current_view))

  # ======================================================================
  # PROJECTS — a project is a folder on disk (project_store.R). Opening one
  # rehydrates the pools; edits are autosaved back. This is what makes
  # closing the browser (or the app) resumable.
  # ======================================================================
  current_project  <- reactiveVal(NULL)   # project id, or NULL on the Projects screen
  layer_style      <- reactiveVal(list())  # per-layer render settings, persisted

  # Plot appearance (title / axis labels / colour), per screen. Installed into
  # the helper env so print.ggplot and ea_opt() can reach it from any module
  # without every module having to accept it as an argument. Reads happen inside
  # renderPlot, so a change here re-renders the affected plot by itself.
  plot_opts <- reactiveValues()
  .EA_PLOTOPTS$rv  <- plot_opts
  .EA_PLOTOPTS$ctx <- reactive({
    v <- input$current_view %||% "global"
    t <- tryCatch(workspace_ctx$plot_ctx(), error = function(e) NULL)
    if (!is.null(t) && nzchar(t)) t else v
  })
  project_refresh  <- reactiveVal(0)      # bumped when the on-disk list changes
  restoring        <- reactiveVal(FALSE)  # guards autosave while we load

  # Shiny has no API to REMOVE a reactiveValues key: `rv[[k]] <- NULL` sets the
  # value to NULL but the name stays in names(). (Same trap as the ds_refresh
  # workaround above.) So every reader must skip NULL-valued keys.
  .pool_names <- function(p) {
    l <- reactiveValuesToList(p)
    if (!length(l)) return(character(0))
    names(l)[!vapply(l, is.null, logical(1))]
  }

  .clear_pools <- function() {
    for (p in list(raw_pool, dataset_pool, raster_pool, las_pool, vector_pool))
      for (k in .pool_names(p)) p[[k]] <- NULL
    gc(FALSE)   # release the freed objects (large LAS/raster) promptly
  }

  open_project <- function(pid) {
    restoring(TRUE)
    on.exit(restoring(FALSE), add = TRUE)
    st <- tryCatch(ea_project_load_data(pid), error = function(e) NULL)
    if (is.null(st)) { showNotification("Could not open that project.", type = "error"); return() }

    .clear_pools()
    for (k in .pool_names(src_paths)) src_paths[[k]] <- NULL
    for (nm in names(st$tables)) {
      raw_pool[[nm]]     <- st$tables[[nm]]
      dataset_pool[[nm]] <- st$tables[[nm]]
    }

    # Spatial layers: re-read each stored file back into its pool.
    failed <- character(0)
    for (s in st$spatial) {
      nm <- s$name %||% ""; kind <- s$kind %||% ""; path <- s$path %||% ""
      if (!nzchar(nm) || isTRUE(s$missing)) { failed <- c(failed, nm); next }
      okl <- tryCatch({
        if (identical(kind, "raster"))      raster_pool[[nm]] <- terra::rast(path)
        # LAS handling PAUSED: reopen loads a small, memory-safe PREVIEW (500k pts)
        # instead of the full cloud, which was OOM-crashing the app on project open
        # (raster + vector + a big LAS all loading at once). The reference is kept,
        # so full-resolution loading can be restored later. See MEMORY undone list.
        else if (identical(kind, "las"))    las_pool[[nm]]    <- .read_las_capped(path, cap = 500000L)
        else if (identical(kind, "vector")) vector_pool[[nm]] <- sf::st_read(path, quiet = TRUE)
        else return(NULL)
        src_paths[[nm]] <- path
        TRUE
      }, error = function(e) FALSE)
      if (!isTRUE(okl)) failed <- c(failed, nm)
    }
    if (length(failed))
      showNotification(
        sprintf("Could not reload %d spatial layer(s): %s",
                length(failed), paste(failed, collapse = ", ")),
        type = "warning", duration = 8)

    # Sweep orphans left in files/ by earlier versions (removing a layer used to
    # leave its copy behind). Keeps only what the project still references.
    try(ea_project_prune_files(
      pid, vapply(st$spatial, function(s) s$path %||% "", character(1))), silent = TRUE)

    current_project(pid)
    # Per-layer render settings (a raster's R/G/B band mapping) come back with
    # the project, so a mapping the user had to choose once is never asked for
    # again — and is never re-guessed.
    ls0 <- st$meta$layer_style
    layer_style(if (is.list(ls0)) ls0 else list())
    ad <- st$meta$active_dataset
    active_ds(if (isTruthy(ad) && ad %in% .pool_names(dataset_pool)) ad else NULL)
    ds_refresh(ds_refresh() + 1)

    # Always land on the project Overview — the menu-free "home" of a project.
    # From there "Open project" enters the workspace on the view that fits the
    # data (map for spatial, Data screen for a table). This mirrors the sandbox
    # flow: Projects -> Overview -> Workspace.
    .switch_view("project")
  }

  # Autosave. A plain observe (no debounce/timer) on purpose: it fires only when
  # a dependency actually changed, which for pools/active/view is a handful of
  # times per session, not per keystroke. Timer-based debouncing was tried and
  # is both unnecessary here and untestable under testServer.
  project_state <- reactive({
    tl <- reactiveValuesToList(dataset_pool)
    tl <- tl[!vapply(tl, is.null, logical(1))]
    list(tables  = tl,
         rasters = .pool_names(raster_pool),
         las     = .pool_names(las_pool),
         vectors = .pool_names(vector_pool),
         active  = active_ds(),
         view    = input$current_view,
         style   = layer_style())
  })
  observe({
    st  <- project_state()
    pid <- isolate(current_project())
    if (is.null(pid) || isTRUE(isolate(restoring()))) return()
    # Spatial pools hold live objects; persist a reference we can re-find.
    spatial <- c(
      lapply(st$rasters, function(n) list(name = n, kind = "raster", path = .src_path(n))),
      lapply(st$las,     function(n) list(name = n, kind = "las",    path = .src_path(n))),
      lapply(st$vectors, function(n) list(name = n, kind = "vector", path = .src_path(n)))
    )
    try(ea_project_save_data(pid, tables = st$tables, spatial = spatial,
                             last_view = st$view, active_dataset = st$active,
                             layer_style = st$style), silent = TRUE)
    project_refresh(isolate(project_refresh()) + 1)
  })

  # Where a loaded spatial layer's file lives, so a project can reload it.
  # NOTE: an upload's `datapath` is a Shiny TEMP file that gets cleaned up, so
  # referencing it would break on restart — we copy the file into the project
  # instead (which also makes a project folder self-contained).
  src_paths <- reactiveValues()
  .src_path <- function(nm) src_paths[[nm]] %||% ""
  .keep_source <- function(nm, path, name, extra = character(0)) {
    pid <- current_project()
    stored <- if (!is.null(pid))
      tryCatch(ea_project_import_file(pid, path, name, extra), error = function(e) "")
      else ""
    # No project open (or the copy failed): fall back to the temp path so the
    # layer at least works this session.
    src_paths[[nm]] <- if (nzchar(stored)) stored else path
  }

  projectsServer("projects", current_project, open_project, project_refresh, .switch_view)

  # Projects screen chrome: no panels when there are no projects, tools panel
  # (project info) once there are.
  observe({
    project_refresh()
    n <- tryCatch(length(ea_project_list()), error = function(e) 0L)
    session$sendCustomMessage("ea-projects-empty", n == 0L)
  })

  # Inside-a-project screen (data-first entry, then a summary).
  project_meta <- reactive({
    project_refresh()
    pid <- current_project()
    if (is.null(pid)) NULL else ea_project_meta(pid)
  })
  project_counts <- reactive({
    list(tables  = .pool_names(dataset_pool), rasters = .pool_names(raster_pool),
         las     = .pool_names(las_pool),     vectors = .pool_names(vector_pool))
  })
  project_ctx <- projectServer(
    "project", project_meta, project_counts,
    on_files  = function(df) .ingest_files(df),
    on_sample = function(kind) .load_sample(kind),
    on_rename = function(nm) {
      pid <- current_project(); req(pid)
      ea_project_rename(pid, nm)
      project_refresh(project_refresh() + 1)
    },
    on_delete = function() {
      pid <- current_project(); req(pid)
      ea_project_delete(pid)
      .clear_pools()
      current_project(NULL); active_ds(NULL)
      ds_refresh(ds_refresh() + 1)
      project_refresh(project_refresh() + 1)
      .switch_view("projects")
      showNotification("Project deleted.", type = "message", duration = 3)
    },
    switch_view = .switch_view
  )

  # ---- Status bar ----
  output$status_project <- renderText({
    pid <- current_project()
    if (is.null(pid)) return("no project open")
    m <- ea_project_meta(pid); m$name %||% pid
  })
  output$status_active <- renderText({ ds <- active_dataset(); if (is.null(ds)) "—" else ds })
  # Where the open project is saved on disk (visible in the status bar on every view).
  output$status_location <- renderText({
    pid <- current_project()
    if (is.null(pid)) return("—")
    tryCatch(ea_project_path(pid), error = function(e) "—")
  })
  # Live memory meter: total in-RAM footprint of all loaded data across the four
  # pools. Recomputes whenever a pool changes (the .pool_names reads make it
  # reactive). terra rasters are disk-backed, so their footprint is small here —
  # which is correct (they are not held in RAM).
  output$status_memory <- renderText({
    total <- 0
    for (p in list(dataset_pool, raster_pool, las_pool, vector_pool))
      for (k in .pool_names(p))
        total <- total + tryCatch(as.numeric(object.size(p[[k]])), error = function(e) 0)
    mb <- total / 1024^2
    if (mb >= 1024) sprintf("%.2f GB", mb / 1024) else sprintf("%.0f MB", mb)
  })
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
  # Each model server returns a reactive of its live "context" text for the Co-Analyst.
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
  rconsole_ctx   <- rconsoleServer("rconsole", dataset_pool, active_dataset,
                                   raster_pool, las_pool, vector_pool)
  # ---- Workspace File menu (ids are app-level, not module-namespaced) ----
  # "Save project as .eap": the .ea-eap-save JS turns this into a native
  # save-location dialog; otherwise it is a normal browser download.
  output$ws_export <- downloadHandler(
    filename = function() {
      pid <- current_project()
      paste0(if (!is.null(pid)) ea_slug(ea_project_meta(pid)$name %||% pid) else "project", ".eap")
    },
    content = function(file) {
      pid <- current_project(); req(pid)
      zip::zipr(zipfile = file, files = ea_project_path(pid), recurse = TRUE)
    }
  )
  # Project ▸ Open Recent ▸ <project>
  observeEvent(input$ws_open_recent, { open_project(input$ws_open_recent) })

  # Project ▸ Export report (HTML) — a self-contained snapshot of the project.
  output$ws_report <- downloadHandler(
    filename = function() {
      pid <- current_project()
      paste0(if (!is.null(pid)) ea_slug(ea_project_meta(pid)$name %||% pid) else "project",
             "-report.html")
    },
    content = function(file) {
      pid <- current_project()
      m   <- if (!is.null(pid)) ea_project_meta(pid) else list(name = "Untitled")
      row <- function(k, v) paste0("<tr><th>", htmltools::htmlEscape(k), "</th><td>",
                                   htmltools::htmlEscape(v), "</td></tr>")
      tabs <- .pool_names(dataset_pool)
      tab_rows <- vapply(tabs, function(n) {
        d <- dataset_pool[[n]]
        row(n, if (is.data.frame(d)) paste0(nrow(d), " rows x ", ncol(d), " cols") else "table")
      }, character(1))
      html <- paste0(
        "<!doctype html><meta charset='utf-8'><title>", htmltools::htmlEscape(m$name %||% "Project"),
        " - EasyAnalysis report</title>",
        "<style>body{font-family:system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;",
        "color:#10150f} h1{letter-spacing:-.02em} table{border-collapse:collapse;width:100%;margin:14px 0}",
        "th,td{border-bottom:1px solid #dce1d6;padding:8px 10px;text-align:left;font-size:14px}",
        "th{width:40%;color:#5c6657;font-weight:600} .sub{color:#5c6657}</style>",
        "<h1>", htmltools::htmlEscape(m$name %||% "Project"), "</h1>",
        "<p class='sub'>EasyAnalysis report - generated ", format(Sys.time(), "%Y-%m-%d %H:%M"), "</p>",
        "<h2>Project</h2><table>", row("Created", m$created %||% "-"), row("Last opened", m$modified %||% "-"), "</table>",
        "<h2>Data</h2><table>",
        if (length(tab_rows)) paste(tab_rows, collapse = "") else "<tr><td>No tables</td></tr>",
        row("Rasters", length(.pool_names(raster_pool))),
        row("Point clouds", length(.pool_names(las_pool))),
        row("Vectors", length(.pool_names(vector_pool))),
        "</table>",
        "<p class='sub'>Generated locally by EasyAnalysis v", APP_VERSION, ".</p>")
      writeLines(html, file)
    }
  )

  # "Save" — projects autosave continuously, so this confirms the save point.
  observeEvent(input$ws_save, {
    pid <- current_project()
    if (is.null(pid)) { showNotification("No project open.", type = "warning"); return() }
    showNotification("Project saved.", type = "message", duration = 2)
  })
  observeEvent(input$ws_import_file, {
    fi <- input$ws_import_file; req(fi)
    nid <- tryCatch(ea_project_import(fi$datapath[1]), error = function(e) NULL)
    if (is.null(nid)) {
      showNotification("That doesn't look like an EasyAnalysis project (.eap).", type = "error"); return()
    }
    project_refresh(project_refresh() + 1)
    open_project(nid)
    showNotification("Project imported.", type = "message", duration = 3)
  })

  # UNIFIED workspace: hosts every module's real UI (their servers are bound once
  # above, unchanged). `tool_request` lets a menubar click select a tool in it.
  # Opening a tool re-arms the module selector population (see active_dataset).
  observeEvent(workspace_ctx$tool_open(), {
    ds_refresh(isolate(ds_refresh()) + 1)
  }, ignoreInit = TRUE, ignoreNULL = TRUE)

  workspace_ctx  <- workspaceServer("workspace", dataset_pool, raster_pool,
                                    las_pool, vector_pool, active_dataset,
                                    tool_request = reactive(input$current_view),
                                    layer_style = layer_style, src_paths = src_paths,
                                    plot_opts = plot_opts)

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

  # ---- Free the session's in-RAM data on disconnect ----
  # The app runs locally and the R process keeps running between sessions, so a
  # closed tab's large LAS/rasters would otherwise linger until R's next GC.
  # Everything is on disk (the project), so reopening reloads it. See the
  # Memory management section in ARCHITECTURE.md.
  session$onSessionEnded(function() {
    tryCatch({
      for (p in list(raw_pool, dataset_pool, raster_pool, las_pool, vector_pool))
        for (k in .pool_names(p)) p[[k]] <- NULL
    }, error = function(e) NULL)
    gc(FALSE)
  })
}
