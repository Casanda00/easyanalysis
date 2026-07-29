# ==========================================================================
# mod_workspace.R  --  Unified workspace (BETA scaffold). See UNIFIED_WORKSPACE.md.
# --------------------------------------------------------------------------
# Two views sharing ONE GeoLibre-style frame:
#   - Map view  : (Step 1/6) leaflet canvas + layers + attribute-table dock
#   - Data view : active table + chart/plot builder (Step 5)
# Frame: left = layers/data spine, centre = canvas, right = tool panel host.
# STEP 1 delivers the frame + a real Data-view table. It is PARALLEL to the
# existing screens (reachable via the "Workspace" menu item) so nothing breaks
# while the rest of the staged plan lands.
# ==========================================================================

workspaceCanvasUI <- function(id) {
  ns <- NS(id)
  div(class = "ea-wsx",
    # NOTE: the GeoLibre menubar (Project | Edit | View | …) is rendered by this
    # module's `output$menubar` but PLACED IN THE APP TOP BAR (ui.R hosts it via
    # uiOutput("workspace-menubar")), so the workspace body starts at the tabs.
    tags$span(class = "ea-hidden-file",
      fileInput("ws_import_file", NULL, accept = c(".eap", ".zip"), width = "1px")),

    div(class = "ea-wsx-bar",
      # Rendered from wsview() rather than toggling its own classes in JS. With a
      # client-side highlight the server could switch the view -- opening a map
      # tool, or the canvas following the data -- while the tab stayed lit on the
      # old one. Two sources of truth for which tab is active is exactly how the
      # tab and the view came to disagree.
      uiOutput(ns("view_tabs"), inline = TRUE),
      # M7: the old tool dropdown is retired — tools are launched from the
      # Analysis menu in the top bar. This shows the ACTIVE tool instead.
      div(class = "ea-wsx-active-tool", uiOutput(ns("active_tool_label")))
    ),
    div(class = "ea-wsx-grid",
      tags$aside(class = "ea-wsx-left",
        tags$h6("Layers / Data"),
        uiOutput(ns("layers")),
        tags$div(class = "ea-wsx-resize l", title = "Drag to resize")
      ),
      tags$main(class = "ea-wsx-canvas",
        uiOutput(ns("canvas")),
        div(class = "ea-wsx-panels", uiOutput(ns("panels")))
      ),
      tags$aside(class = "ea-wsx-right",
        tags$div(class = "ea-wsx-resize r", title = "Drag to resize"),
        tags$h6("Tool"),
        uiOutput(ns("tool"))
      ),
      tags$aside(class = "ea-wsx-dock", uiOutput(ns("dock")))
    ),
    # M6: R Console. Docks to the BOTTOM by default and, like the tool panels,
    # can be floated over the canvas or minimized to a bar. Mode changes are
    # pure class swaps (eaConsole in ui.R) — no server round-trip, so the
    # console keeps its scroll position and its editor contents.
    div(id = ns("console"), class = "ea-wsx-console dock",
      div(class = "ea-wsx-conh",
        tags$span(icon("terminal"), " R Console"),
        tags$span(class = "ea-wsx-conx",
          tags$button(type = "button", class = "con-float", title = "Float over the canvas",
            onclick = sprintf("eaConsole('%s','float')", ns("console")), HTML("&#9744;")),
          tags$button(type = "button", class = "con-dock", title = "Dock back to the bottom",
            onclick = sprintf("eaConsole('%s','dock')", ns("console")), HTML("&#9707;")),
          tags$button(type = "button", class = "con-min", title = "Minimize",
            onclick = sprintf("eaConsole('%s','min')", ns("console")), "–"),
          tags$button(type = "button", title = "Close",
            onclick = sprintf("eaConsole('%s','close')", ns("console")), "×"))),
      div(class = "ea-wsx-conb", rconsoleCanvasUI("rconsole")))
  )
}

# The workspace carries its own right panel; the shell's tools slot just notes it.
workspaceToolsUI <- function(id) {
  div(class = "ea-hint",
      "The unified workspace has its own tool panel (right side of its canvas).")
}

workspaceServer <- function(id, dataset_pool, raster_pool, las_pool, vector_pool, active_dataset,
                            tool_request = reactive(NULL), layer_style = NULL,
                            src_paths = NULL, plot_opts = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    wsview <- reactiveVal("map")
    user_picked_view <- reactiveVal(FALSE)
    observeEvent(input$wsview, {
      wsview(input$wsview %||% "map"); user_picked_view(TRUE)
    })

    .names <- function(p) tryCatch({
      l <- reactiveValuesToList(p); names(l)[!vapply(l, is.null, logical(1))]
    }, error = function(e) character(0))

    # ---- Step 2: layers panel state (visibility + expand + active) ----
    lvis <- reactiveValues(); lexp <- reactiveValues(); activeLayer <- reactiveVal(NULL)
    .vis <- function(nm) { v <- lvis[[nm]]; if (is.null(v)) TRUE else isTRUE(v) }

    # unified layer list across the four pools
    layers <- reactive({
      mk <- function(nms, type, kind, col) lapply(nms, function(n)
        list(nm = n, type = type, kind = kind, col = col))
      c(mk(.names(dataset_pool), "table",  "table",  "var(--sky)"),
        mk(.names(raster_pool),  "raster", "raster", "var(--forest)"),
        mk(.names(las_pool),     "lidar",  "lidar",  "var(--earth)"),
        mk(.names(vector_pool),  "vector", "vector", "#B07CC6"))
    })
    observe({ ls <- layers(); if (is.null(activeLayer()) && length(ls)) activeLayer(ls[[1]]$nm) })

    # CANVAS FOLLOWS THE DATA: a project holding spatial layers opens on the Map
    # view; a tables-only project (e.g. just CSVs) opens on the Data view. Only
    # the DEFAULT — once the user picks a view themselves we stop overriding it.
    observe({
      if (isTRUE(user_picked_view())) return()
      ls <- layers(); if (!length(ls)) return()
      spatial <- any(vapply(ls, function(l) l$kind %in% c("raster", "vector", "lidar"), logical(1)))
      wsview(if (spatial) "map" else "data")
    })
    # Reopening a different project re-arms the automatic choice.
    observeEvent(active_dataset(), { user_picked_view(FALSE) }, ignoreInit = TRUE)

    observeEvent(input$ws_vis,    { nm <- input$ws_vis; lvis[[nm]] <- !.vis(nm) })
    observeEvent(input$ws_active, { activeLayer(input$ws_active) })
    observeEvent(input$ws_exp,    { nm <- input$ws_exp; lexp[[nm]] <- !isTRUE(lexp[[nm]]) })

    .fire <- function(inp, val) sprintf(
      "event.stopPropagation();Shiny.setInputValue('%s', %s, {priority:'event'});",
      ns(inp), jsonlite::toJSON(val, auto_unbox = TRUE))

    # One <select> per channel. Deliberately plain HTML rather than selectInput:
    # these are rebuilt for every layer on every render, and N Shiny inputs per
    # layer would need N observers and would fight the rebuild. One event
    # carrying {layer, channel, band} is enough.
    .band_sel <- function(l, ch, cur, nb) {
      tags$select(class = "ea-wsx-band", title = paste("Band feeding", toupper(ch)),
        onchange = sprintf(
          "event.stopPropagation();Shiny.setInputValue('%s',{nm:%s,ch:'%s',b:parseInt(this.value)},{priority:'event'});",
          ns("ws_rgb"), jsonlite::toJSON(l$nm, auto_unbox = TRUE), ch),
        lapply(seq_len(nb), function(i)
          tags$option(value = i, selected = if (i == cur) "selected", paste("Band", i))))
    }

    .legend <- function(l) {
      if (identical(l$kind, "raster")) {
        nb  <- tryCatch({ r <- raster_pool[[l$nm]]; if (is.null(r)) 0L else terra::nlyr(r) },
                        error = function(e) 0L)
        cfg <- .rgb_of(l$nm, nb)
        rgb_on <- identical(cfg$mode, "rgb") && nb >= 3
        return(tagList(
          if (nb >= 3) tagList(
            div(class = "ea-wsx-lgh", paste0("Render · ", nb, " bands")),
            div(class = "ea-wsx-rgbrow",
              tags$span(class = paste("ea-wsx-sw-toggle", if (rgb_on) "on" else ""),
                        onclick = .fire("ws_rgbmode", l$nm),
                        title = "Switch between a true-colour composite and a single-band ramp",
                        tags$span(class = "knob")),
              tags$span(class = "ea-wsx-rgblab",
                        if (rgb_on) "True colour (RGB)" else "Single band"))),
          if (rgb_on) tagList(
            div(class = "ea-wsx-lgh", "Band mapping"),
            div(class = "ea-wsx-rgbsel",
              div(tags$label("R"), .band_sel(l, "r", cfg$r, nb)),
              div(tags$label("G"), .band_sel(l, "g", cfg$g, nb)),
              div(tags$label("B"), .band_sel(l, "b", cfg$b, nb))),
            div(class = "ea-wsx-lgh2",
                if (!is.null(cfg$why)) paste0("From ", cfg$why, " · 2-98% stretch")
                else "2-98% stretch per band"))
          else tagList(
            # Undeclared band order is stated, not papered over with a guess.
            if (nb >= 3 && is.null(.detect_rgb(l$nm)))
              div(class = "ea-wsx-note",
                  "This file does not declare which band is red, green or blue. ",
                  "Switch on true colour and set them."),
            div(class = "ea-wsx-lgh", "Legend · continuous"), div(class = "ea-wsx-ramp"),
            div(class = "ea-wsx-ends", span("low"), span("high")),
            div(class = "ea-wsx-lgh", "Colour ramp"),
            div(class = "ea-wsx-style",
              span(class = "ea-wsx-sc", style = "background:linear-gradient(90deg,#2b4a2e,#d99b57)"),
              span(class = "ea-wsx-sc", style = "background:linear-gradient(90deg,#08306b,#6baed6)"),
              span(class = "ea-wsx-sc", style = "background:linear-gradient(90deg,#404040,#f0f0f0)")))))
      }
      if (identical(l$kind, "table")) {
        d <- tryCatch(dataset_pool[[l$nm]], error = function(e) NULL)
        dm <- if (is.data.frame(d)) paste0(nrow(d), " rows × ", ncol(d), " cols") else "table"
        return(div(class = "ea-wsx-lgh2", dm, " · not drawn on the map"))
      }
      if (identical(l$kind, "lidar")) {
        n <- tryCatch({ x <- las_pool[[l$nm]]
                        if (is.null(x) || inherits(x, "LASheader")) 0L else nrow(x@data) },
                      error = function(e) 0L)
        return(div(class = "ea-wsx-lgh2",
          if (n > .LAS_DRAW_CAP)
            paste0("point cloud · height-shaded · showing ",
                   format(.LAS_DRAW_CAP, big.mark = ","), " of ",
                   format(n, big.mark = ","), " points")
          else if (n > 0) paste0("point cloud · height-shaded · ", format(n, big.mark = ","), " points")
          else "point cloud · extent only (points not loaded)"))
      }
      tagList(  # vector
        div(class = "ea-wsx-lgh", "Symbol"),
        div(class = "ea-wsx-symrow", span(class = "ea-wsx-sym", style = paste0("background:", l$col, ";")), " single symbol"),
        div(class = "ea-wsx-lgh", "Colour by"),
        div(class = "ea-wsx-style", span(class = "ea-wsx-sc", style = paste0("background:", l$col, ";")),
          span(class = "ea-wsx-sc", style = "background:var(--sky)"),
          span(class = "ea-wsx-sc", style = "background:var(--earth)")))
    }

    output$layers <- renderUI({
      ls <- layers(); act <- activeLayer()
      if (!length(ls)) return(div(class = "ea-hint", "No data yet. Add data to the project."))
      div(lapply(ls, function(l) {
        vis <- .vis(l$nm); ex <- isTRUE(lexp[[l$nm]])
        div(class = paste("ea-wsx-lyr2", if (identical(l$nm, act)) "active" else "",
                          if (vis) "" else "off", if (ex) "exp" else ""),
          div(class = "ea-wsx-lyrtop",
            # visibility = a real toggle switch (was a ◉/○ glyph)
            tags$span(class = paste("ea-wsx-sw-toggle", if (vis) "on" else ""),
                      onclick = .fire("ws_vis", l$nm),
                      title = if (vis) "Hide layer" else "Show layer",
                      tags$span(class = "knob")),
            tags$span(class = "ea-wsx-sw", style = paste0("background:", l$col, ";")),
            # Clicking a TABLE also sets the app-level active dataset. Setting only
            # the workspace's own activeLayer left every model screen, the status
            # bar and the data view pointing at the previous dataset -- the click
            # looked like it worked while nothing downstream moved.
            tags$span(class = "ea-wsx-nm", title = l$nm,
              onclick = if (identical(l$kind, "table"))
                  paste0(.fire("ws_active", l$nm),
                         sprintf("Shiny.setInputValue('active_dataset', %s, {priority:'event'});",
                                 jsonlite::toJSON(l$nm, auto_unbox = TRUE)))
                else .fire("ws_active", l$nm),
              l$nm),
            tags$span(class = "ea-wsx-ty", l$type),
            # remove the layer from the project (app-level handler in server.R)
            tags$span(class = "ea-wsx-del", title = paste0("Remove '", l$nm, "'"),
              onclick = sprintf(
                "event.stopPropagation(); if(confirm('Remove \\'%s\\' from this project?\\n\\nYour original file on disk is not deleted.')) eaSetInput('delete_dataset', %s);",
                gsub("'", "", l$nm), jsonlite::toJSON(l$nm, auto_unbox = TRUE)),
              HTML("&times;")),
            tags$span(class = "ea-wsx-chev", onclick = .fire("ws_exp", l$nm), "▶")),
          div(class = "ea-wsx-leg", .legend(l)))
      }))
    })

    # the active layer (if a table) drives the Data view; else fall back
    dtName <- reactive({ a <- activeLayer(); if (!is.null(a) && a %in% .names(dataset_pool)) a else active_dataset() })

    # ---- GeoLibre-style menubar (M1-M5) -------------------------------------
    BASEMAPS <- c(
      "OpenStreetMap"     = "OpenStreetMap",     # default (bright standard OSM)
      "OSM Humanitarian"  = "OpenStreetMap.HOT",
      "Light"             = "CartoDB.Positron",
      "Voyager"           = "CartoDB.Voyager",
      "Dark"              = "CartoDB.DarkMatter",
      "Satellite"         = "Esri.WorldImagery",
      "Streets"           = "Esri.WorldStreetMap",
      "Topographic"       = "Esri.WorldTopoMap",
      "Terrain"           = "OpenTopoMap",
      "Shaded relief"     = "Esri.WorldShadedRelief",
      "Physical"          = "Esri.WorldPhysical",
      "National Geographic" = "Esri.NatGeoWorldMap",
      "Grey canvas"       = "Esri.WorldGrayCanvas",
      "None"              = "")
    basemap <- reactiveVal("OpenStreetMap")   # bright standard OSM by default
    observeEvent(input$ws_basemap, { basemap(input$ws_basemap) })

    .mi <- function(label, js = NULL, sub = FALSE, disabled = FALSE, icon_name = NULL) {
      if (disabled) return(tags$a(class = "gm-item disabled", label))
      tags$a(class = paste("gm-item", if (sub) "has-sub" else ""),
             onclick = js %||% "", label)
    }
    .msep <- function() tags$div(class = "gm-sep")
    .menu <- function(label, icon_name, items) {
      div(class = "gm",
        tags$button(class = "gm-btn", type = "button",
          onclick = "var p=this.parentNode, o=p.classList.contains('open'); document.querySelectorAll('.gm.open').forEach(function(x){x.classList.remove('open');}); if(!o)p.classList.add('open'); event.stopPropagation();",
          icon(icon_name), tags$span(label)),
        # no repeated title inside the menu — the button above already names it
        div(class = "gm-menu", items))
    }
    .setTool <- function(k) sprintf("Shiny.setInputValue('%s', '%s', {priority:'event'})", ns("tool_pick"), k)

    output$menubar <- renderUI({
      # Analysis = OUR tools, grouped exactly like GeoLibre's submenu list.
      # Each group is a ▸ FLY-OUT (GeoLibre style): hover the group, its tools
      # open in a nested panel to the side.
      grps <- unique(vapply(MODUI, function(t) t$grp, character(1)))
      proc_items <- lapply(grps, function(g) {
        ks <- names(MODUI)[vapply(MODUI, function(t) identical(t$grp, g), logical(1))]
        tags$div(class = "gm-item has-sub", g,
          tags$div(class = "gm-sub",
            lapply(ks, function(k) .mi(MODUI[[k]]$nm, .setTool(k))),
            # every Data & Exploration operation, listed individually
            if (identical(g, "Data")) tagList(
              .msep(),
              tags$div(class = "gm-grp", "Prepare data"),
              lapply(DATA_OPS, function(op) .mi(op, .setTool(paste0("dataop:", op)))))))
      })
      has_recent <- length(tryCatch(ea_project_list(), error = function(e) list())) > 0

      div(class = "gm-bar",
        .menu("Project", "folder", tagList(
          .mi("New…",        "Shiny.setInputValue('current_view','projects',{priority:'event'})"),
          .mi("Open From…",  "Shiny.setInputValue('current_view','projects',{priority:'event'})"),
          # Open Recent = a real fly-out of the most recent projects.
          if (has_recent) {
            recents <- utils::head(tryCatch(ea_project_list(), error = function(e) list()), 8)
            tags$div(class = "gm-item has-sub", "Open Recent",
              tags$div(class = "gm-sub", lapply(recents, function(p)
                .mi(p$name %||% p$id,
                    sprintf("Shiny.setInputValue('ws_open_recent', %s, {priority:'event'})",
                            jsonlite::toJSON(p$id, auto_unbox = TRUE))))))
          } else .mi("Open Recent", NULL, sub = TRUE, disabled = TRUE),
          .msep(),
          .mi("Save",        "Shiny.setInputValue('ws_save', Date.now(), {priority:'event'})"),
          tags$a(class = "gm-item ea-eap-save", href = "#", onclick =
                   "var l=document.getElementById('ws_export'); if(l) l.click(); return false;",
                 "Save As… (.eap)"),
          .mi("Import project (.eap)…", "document.getElementById('ws_import_file').click()"),
          .msep(),
          tags$a(class = "gm-item", href = "#", onclick =
                   "var l=document.getElementById('ws_report'); if(l) l.click(); return false;",
                 "Export report (HTML)…"),
          .mi("Share…",       sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("ws_share"))),
          .mi("Collaborate…", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("ws_collab"))),
          .msep(),
          .mi("Close project", "Shiny.setInputValue('current_view','projects',{priority:'event'})")
        )),
        .menu("Edit", "pen", tagList(
          .mi("Undo",  "Shiny.setInputValue('data-undo_last', Date.now(), {priority:'event'})"),
          .mi("Reset to upload", "Shiny.setInputValue('data-reset_raw', Date.now(), {priority:'event'})"),
          .msep(),
          .mi("Edit data table", .setTool("data"))
        )),
        .menu("View", "eye", tagList(
          # colour sets — instant, client-side, remembered across sessions
          tags$div(class = "gm-item has-sub", "Theme",
            tags$div(class = "gm-sub",
              lapply(names(ea_palettes), function(nm)
                tags$a(class = "gm-item",
                       onclick = sprintf("eaSetTheme('%s')", nm),
                       tags$span(class = "gm-swatch",
                         style = sprintf("background:%s; border-color:%s;",
                           ea_palettes[[nm]]$paper  %||% ea_palette$paper,
                           ea_palettes[[nm]]$forest %||% ea_palette$forest)),
                       ea_palettes[[nm]]$label %||% nm)))),
          .msep(),
          tags$div(class = "gm-grp", "Basemap"),
          tagList(lapply(names(BASEMAPS), function(nm) {
            tags$a(class = paste("gm-item", if (identical(unname(BASEMAPS[[nm]]), basemap())) "on" else ""),
                   onclick = sprintf("Shiny.setInputValue('%s', '%s', {priority:'event'})",
                                     ns("ws_basemap"), unname(BASEMAPS[[nm]])), nm)
          })),
          .msep(),
          tags$div(class = "gm-grp", "Layout"),
          .mi("Map view",  sprintf("Shiny.setInputValue('%s','map',{priority:'event'})",   ns("wsview"))),
          .mi("Data view", sprintf("Shiny.setInputValue('%s','data',{priority:'event'})",  ns("wsview"))),
          .mi("Split",     sprintf("Shiny.setInputValue('%s','split',{priority:'event'})", ns("wsview")))
        )),
        .menu("Add Data", "database", tagList(
          # no redundant "Add data" item — the menu is already Add Data
          .mi("From file…", "document.getElementById('upload_files').click()"),
          .mi("Create a table…", "Shiny.setInputValue('new_dataset', Date.now(), {priority:'event'})"),
          .msep(),
          .mi("Download spatial data", .setTool("rs_search"))
        )),
        .menu("Analysis", "gears", tagList(
          .mi("AI Assistant", "document.getElementById('chat-panel').classList.add('open')"),
          .msep(),
          proc_items,
          .msep(),
          # R Console opens the BOTTOM dock (not the right tool panel).
          .mi("R Console", sprintf(
            "var c=document.getElementById('%s'); eaConsole('%s', c.classList.contains('open') ? 'close' : 'dock');",
            ns("console"), ns("console")))
        )),
        .menu("Controls", "sliders", tagList(
          tags$div(class = "gm-grp", "Map"),
          .mi("Zoom to layers", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("ws_zoom"))),
          .mi("Zoom to active layer", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("ws_zoom_active"))),
          .msep(),
          tags$div(class = "gm-grp", "Panels"),
          .mi("Layers panel", "document.querySelector('.ea-wsx-grid').classList.toggle('no-left')"),
          .mi("Tool panel",   "document.querySelector('.ea-wsx-grid').classList.toggle('no-right')"),
          .mi("Results dock", "document.querySelector('.ea-wsx-grid').classList.toggle('no-dock')"),
          .mi("Attribute table", "var d=document.querySelector('.ea-wsx-attrdock'); if(d)d.classList.toggle('collapsed')"),
          .msep(),
          .mi("R Console", sprintf("document.getElementById('%s').classList.toggle('open')", ns("console")))
        )),
        .menu("Packages", "cube", tagList(
          .mi("Install a package…", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("pkg_install_ui"))),
          .mi("Optional packages…", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("pkg_optional_ui"))),
          .mi("Installed packages…", sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("pkg_list_ui"))),
          .msep(),
          tags$div(class = "gm-grp", "Optional engines"),
          .mi("Earth Engine (needs Python + GEE)", NULL, disabled = TRUE),
          .mi("Whitebox tools", NULL, disabled = TRUE)
        )),
        .menu("Settings", "gear", tagList(
          .mi("Preferences…", "openSettings('set-display')"),
          .msep(),
          .mi("Keyboard shortcuts", "openSettings('set-keys')")
        )),
        .menu("Help", "circle-question", tagList(
          .mi("Documentation", .setTool("docs")),
          .mi("References",    .setTool("references")),
          .msep(),
          .mi("Ask the Co-Analyst", "document.getElementById('chat-panel').classList.add('open')"),
          .mi("Take the tour", "Shiny.setInputValue('ws_tour', Date.now(), {priority:'event'})"),
          .msep(),
          .mi("About EasyAnalysis", "openSettings('set-about')")
        ))
      )
    })

    .zoom_to <- function(only = NULL, what = "layers") {
      bb <- tryCatch(.layer_bounds(only), error = function(e) NULL)
      if (is.null(bb)) {
        showNotification(
          if (is.null(only)) "Nothing to zoom to: no spatial layer has a known location."
          else sprintf("Cannot zoom to '%s': it has no location on the map.", only),
          type = "warning", duration = 5)
        return(invisible(FALSE))
      }
      fit_req(bb); map_rebuild(map_rebuild() + 1); invisible(TRUE)
    }
    observeEvent(input$ws_zoom,        { .zoom_to(NULL) })
    observeEvent(input$ws_zoom_active, { .zoom_to(activeLayer()) })
    observeEvent(input$ws_tour, { session$sendCustomMessage("ea-tour", "start") })

    observeEvent(input$ws_share, {
      showModal(modalDialog(title = "Share this project", easyClose = TRUE,
        p("EasyAnalysis runs entirely on your computer, so sharing is by file:"),
        tags$ol(
          tags$li(tags$b("Project ▸ Save As… (.eap)"), " — one file with your data and analyses."),
          tags$li("Send that .eap however you like."),
          tags$li("They open it with ", tags$b("Project ▸ Import project (.eap)…"), ".")),
        div(class = "ea-hint", "Live multi-user collaboration needs cloud storage and is not built yet."),
        footer = modalButton("Close")))
    })
    observeEvent(input$ws_collab, {
      showModal(modalDialog(title = "Collaborate", easyClose = TRUE,
        p("Real-time collaboration (two people in one project, presence avatars) is planned but ",
          "not built — it needs cloud storage."),
        div(class = "ea-hint", "For now, share a .eap file (Project ▸ Save As…)."),
        footer = modalButton("Close")))
    })

    # ---- Packages menu: install / inspect R packages (local-first app) -------
    # Optional packages the app can use but does not hard-require.
    OPT_PKGS <- c(
      xgboost = "XGBoost models", glmnet = "Ridge / Lasso regression",
      kernlab = "SVM & kernel methods", mgcv = "Generalized additive models",
      rpart = "Decision trees", survival = "Survival analysis",
      lavaan = "SEM & path models", BayesFactor = "Bayesian tests",
      klaR = "Discriminant analysis extras", exactextractr = "Fast zonal statistics",
      rstac = "Satellite (STAC) search", esquisse = "Interactive plot builder"
    )
    .installed <- function(p) isTRUE(requireNamespace(p, quietly = TRUE))
    pkg_refresh <- reactiveVal(0)

    # A CRAN mirror must be set explicitly: in a non-interactive R session
    # install.packages() fails with "trying to use CRAN without setting a mirror".
    .CRAN <- "https://cloud.r-project.org"
    .lib  <- function() .libPaths()[1]

    # CRAN's package index, fetched once per session (used for search).
    cran_index <- reactiveVal(NULL)   # 2-column data.frame, for search
    cran_full  <- reactiveVal(NULL)   # full matrix, for dependency resolution
    .cran <- function() {
      if (!is.null(cran_index())) return(cran_index())
      m <- tryCatch(utils::available.packages(repos = .CRAN), error = function(e) NULL)
      if (is.null(m)) return(NULL)
      cran_full(m)
      ap <- as.data.frame(m[, c("Package", "Version")], stringsAsFactors = FALSE)
      rownames(ap) <- NULL; cran_index(ap); ap
    }
    # Search CRAN: exact/substring first, then FUZZY (agrep) so a misspelling
    # still finds the package.
    .pkg_search <- function(q, n = 25) {
      ap <- .cran(); if (is.null(ap) || !nzchar(q)) return(NULL)
      p  <- ap$Package
      hit <- grepl(q, p, ignore.case = TRUE, fixed = FALSE)
      out <- ap[hit, , drop = FALSE]
      # rank: exact, then starts-with, then the rest
      if (nrow(out)) {
        lp <- tolower(out$Package); lq <- tolower(q)
        out <- out[order(!(lp == lq), !startsWith(lp, lq), nchar(out$Package)), , drop = FALSE]
      }
      # Too few hits -> the user probably mistyped. Rank ALL package names by
      # edit distance to the query and append the closest ones (agrep alone
      # returns unranked noise: "esquise" never surfaced "esquisse").
      if (nrow(out) < 5) {
        d <- tryCatch(as.integer(utils::adist(tolower(q), tolower(p), partial = FALSE)),
                      error = function(e) NULL)
        if (!is.null(d)) {
          keep <- order(d)[seq_len(min(10L, length(d)))]
          keep <- keep[d[keep] <= max(2L, ceiling(nchar(q) * 0.4))]
          if (length(keep)) out <- unique(rbind(out, ap[keep, , drop = FALSE]))
        }
      }
      utils::head(out, n)
    }
    # Installs with a real mirror, REAL progress (one step per package actually
    # installed, dependencies included), and loads it so it is usable at once.
    .do_install <- function(p) {
      .cran()                                   # ensure the index is available
      db <- cran_full()
      # what actually has to be installed = missing recursive dependencies + p
      todo <- tryCatch({
        deps <- if (!is.null(db))
          tools::package_dependencies(p, db = db, recursive = TRUE)[[1]] else character(0)
        c(setdiff(deps %||% character(0), rownames(utils::installed.packages())), p)
      }, error = function(e) p)
      todo <- unique(todo[nzchar(todo)])
      n <- length(todo)

      ok <- FALSE
      withProgress(message = paste0("Installing ", p), value = 0, {
        for (i in seq_along(todo)) {
          pkg <- todo[i]
          # progress reflects REAL work: package i of n actually being installed
          setProgress(value = (i - 1) / n,
                      detail = sprintf("%s  (%d of %d)", pkg, i, n))
          tryCatch(utils::install.packages(pkg, lib = .lib(), repos = .CRAN, quiet = TRUE),
                   error = function(e) NULL, warning = function(w) NULL)
        }
        setProgress(value = 1, detail = "loading…")
        # Load it NOW so the user can use it without restarting the app.
        ok <- isTRUE(tryCatch({
          if (.installed(p)) { suppressPackageStartupMessages(
            library(p, character.only = TRUE, quietly = TRUE)); TRUE } else FALSE
        }, error = function(e) .installed(p)))
      })

      pkg_refresh(pkg_refresh() + 1)
      # the full CRAN matrix (~24k packages) was only needed for dependency
      # resolution — drop it so it does not sit in memory for the session
      cran_full(NULL); gc(FALSE)
      showNotification(
        if (isTRUE(ok)) paste0("Installed and loaded '", p, "' — ready to use now.")
        else paste0("Could not install '", p, "'. Check the name, or your internet/library permissions."),
        type = if (isTRUE(ok)) "message" else "error", duration = 8)
      ok
    }

    # SEARCH-FIRST install: type a name (typos tolerated), pick from the results,
    # install from the row. No blind typing of an exact package name.
    observeEvent(input$pkg_install_ui, {
      showModal(modalDialog(title = "Find & install a package", easyClose = TRUE, size = "l",
        textInput(ns("pkg_q"), NULL, placeholder = "Search CRAN — e.g. esquisse, forest, xgboost",
                  width = "100%"),
        div(class = "ea-hint",
            "Searching CRAN's index (fetched once per session). Misspellings still match. ",
            "Installing a large package can take a few minutes and pauses the app."),
        uiOutput(ns("pkg_results")),
        footer = modalButton("Close")))
    })
    output$pkg_results <- renderUI({
      pkg_refresh()
      q <- trimws(input$pkg_q %||% "")
      if (nchar(q) < 2) return(div(class = "ea-hint", "Type at least 2 characters."))
      res <- .pkg_search(q)
      if (is.null(res)) return(div(class = "ea-hint",
        "Could not reach CRAN. Check your internet connection."))
      if (!nrow(res)) return(div(class = "ea-hint", "No package matches that name."))
      div(class = "ea-wsx-pkglist",
        lapply(seq_len(nrow(res)), function(i) {
          p <- res$Package[i]; has <- .installed(p)
          div(class = "ea-wsx-pkgrow",
            span(class = paste("ea-wsx-pkgdot", if (has) "ok" else "no")),
            span(class = "ea-wsx-pkgnm", p),
            span(class = "ea-wsx-pkgd", paste("v", res$Version[i])),
            if (has) span(class = "ea-wsx-pkgok", "installed")
            else tags$button(class = "btn btn-sm btn-success", type = "button",
                   onclick = sprintf("Shiny.setInputValue('%s', '%s', {priority:'event'})", ns("pkg_pick"), p),
                   "Install"))
        }))
    })
    observeEvent(input$pkg_pick, {
      p <- input$pkg_pick; req(nzchar(p))
      .do_install(p)      # .do_install owns the (real) progress reporting
    })

    observeEvent(input$pkg_optional_ui, {
      pkg_refresh()
      rows <- lapply(names(OPT_PKGS), function(p) {
        has <- .installed(p)
        div(class = "ea-wsx-pkgrow",
          span(class = paste("ea-wsx-pkgdot", if (has) "ok" else "no")),
          span(class = "ea-wsx-pkgnm", p),
          span(class = "ea-wsx-pkgd", OPT_PKGS[[p]]),
          if (has) span(class = "ea-wsx-pkgok", "installed")
          else actionButton(ns(paste0("pkgi_", p)), "Install", class = "btn-sm btn-success"))
      })
      showModal(modalDialog(title = "Optional packages", easyClose = TRUE, size = "l",
        div(class = "ea-hint", "These unlock extra methods. Install the ones you need."),
        div(class = "ea-wsx-pkglist", rows),
        footer = modalButton("Close")))
    })
    # one install handler per optional package
    lapply(names(OPT_PKGS), function(p) {
      observeEvent(input[[paste0("pkgi_", p)]], {
        removeModal(); .do_install(p)
      }, ignoreInit = TRUE)
    })

    observeEvent(input$pkg_list_ui, {
      showModal(modalDialog(title = "Installed packages", easyClose = TRUE, size = "l",
        DT::dataTableOutput(ns("pkg_table")), footer = modalButton("Close")))
    })
    output$pkg_table <- DT::renderDataTable({
      pkg_refresh()
      ip <- as.data.frame(utils::installed.packages()[, c("Package", "Version"), drop = FALSE],
                          stringsAsFactors = FALSE)
      DT::datatable(ip, options = list(pageLength = 12, scrollX = TRUE), rownames = FALSE)
    }, server = TRUE)

    # Title / axis labels / colour. These write to the SHARED store in server.R
    # (plot_opts), so they drive every screen's plot through print.ggplot and
    # ea_opt() rather than being wired per module.
    # Bumped once a module's tools panel has actually been delivered; server.R
    # watches it to re-arm the selector population.
    tool_rendered <- reactiveVal(0)

    .pkey <- function() { t <- current_tool(); if (is.null(t)) "workspace" else t }
    # ISOLATED on purpose. These controls live inside .data_ui() / the tool
    # panel, which are renderUI-built; a reactive read here would make the panel
    # depend on the very store the controls write to, so every keystroke would
    # rebuild the panel and wipe the box being typed in. The plot still updates,
    # because ea_plot_dep() takes the dependency inside renderPlot instead.
    .popt <- function(nm, dflt = "") {
      if (is.null(plot_opts)) return(dflt)
      o <- isolate(plot_opts[[.pkey()]])
      v <- if (is.list(o)) o[[nm]] else NULL
      if (is.null(v)) dflt else v
    }
    .set_popt <- function(nm, val) {
      if (is.null(plot_opts)) return(invisible(NULL))
      k <- .pkey(); o <- plot_opts[[k]]; if (!is.list(o)) o <- list()
      o[[nm]] <- val; plot_opts[[k]] <- o
    }
    observeEvent(input$po_title,  .set_popt("title",  input$po_title),  ignoreInit = TRUE)
    observeEvent(input$po_xlab,   .set_popt("xlab",   input$po_xlab),   ignoreInit = TRUE)
    observeEvent(input$po_ylab,   .set_popt("ylab",   input$po_ylab),   ignoreInit = TRUE)
    observeEvent(input$po_colour, .set_popt("colour", input$po_colour), ignoreInit = TRUE)
    # PLOT APPEARANCE — one icon that opens a small panel on hover.
    # Three permanent text boxes ate most of the chart bar for something used
    # occasionally; three Rename buttons were better but still three controls.
    # This is one icon, and the panel it opens houses the whole group. The
    # generic .ea-pop wrapper (ui.R) is reusable anywhere the app wants a
    # hover panel: hover opens it, click pins it, Escape or a click outside
    # closes it, so it never vanishes while you are typing in it.
    .pop_row <- function(ico, label, control) div(class = "ea-pop-row",
      tags$label(icon(ico), tags$span(label)), control)

    .plot_opts_ui <- function(inline = FALSE) {
      set <- any(nzchar(c(.popt("title"), .popt("xlab"), .popt("ylab"))))
      div(class = paste("ea-pop", if (inline) "" else "block"),
        tags$button(type = "button",
          class = paste("ea-pop-btn", if (set) "set" else ""),
          title = "Plot appearance - title, axis labels, colour",
          onclick = "eaPop(this)",
          icon("palette"), if (!inline) tags$span(" Plot appearance")),
        div(class = "ea-pop-body",
          div(class = "ea-pop-h", icon("palette"), tags$span("Plot appearance")),
          .pop_row("heading", "Title",
            textInput(ns("po_title"), NULL, value = .popt("title"),
                      placeholder = "auto", width = "100%")),
          .pop_row("arrows-left-right", "X label",
            textInput(ns("po_xlab"), NULL, value = .popt("xlab"),
                      placeholder = "auto", width = "100%")),
          .pop_row("arrows-up-down", "Y label",
            textInput(ns("po_ylab"), NULL, value = .popt("ylab"),
                      placeholder = "auto", width = "100%")),
          .pop_row("droplet", "Colour",
            tags$input(type = "color", id = ns("po_colour"), class = "ea-wsx-colpick",
                       value = .popt("colour", "#2E7D32"),
                       onchange = sprintf(
                         "Shiny.setInputValue('%s', this.value, {priority:'event'})",
                         ns("po_colour")))),
          div(class = "ea-pop-note", "Leave a field empty to use the default.")))
    }

    # Panels here are renderUI-built, so ANY dependency change (render mode, a
    # new layer, a different table) rebuilds them from scratch and the user's
    # picks would silently snap back to the defaults. Carry them over instead:
    # keep the current value when it still exists among the new choices, and
    # fall back to the default only when it genuinely went away.
    .keep_sel <- function(id, choices, default, multi = FALSE) {
      cur <- isolate(input[[id]])
      if (is.null(cur)) return(default)
      hit <- cur[nzchar(cur) & cur %in% choices]
      if (!length(hit)) return(default)
      if (multi) hit else hit[1]
    }

    # Pane bodies, shared by the single views AND the split view.
    .data_ui <- function() {
      # (A tool taking the centre is handled by the canvas router above; this is
      # the plain data canvas: chart builder + table.)
      cols <- .cols()
      if (!length(cols)) return(div(class = "ea-hint",
        "No table active. Select a table layer in the Layers panel."))
      geoms <- c("scatter","histogram","boxplot","line","bars")
      .keep_txt <- function(id) { v <- isolate(input[[id]]); if (is.null(v)) "" else v }
      tagList(
        div(class = "ea-wsx-chartbar",
          tags$label("Plot"),
          selectInput(ns("cgeom"), NULL, geoms,
                      selected = .keep_sel("cgeom", geoms, "scatter"), width = "112px"),
          tags$label("X"), selectInput(ns("cx"), NULL, cols,
                      selected = .keep_sel("cx", cols, cols[1]), width = "118px"),
          tags$label("Y"), selectInput(ns("cy"), NULL, cols,
                      selected = .keep_sel("cy", cols,
                                           if (length(cols) > 1) cols[2] else cols[1]),
                      width = "118px"),
          .plot_opts_ui(inline = TRUE),
          # static (ggplot) <-> interactive (plotly: hover, zoom, pan, select)
          div(class = "ea-wsx-cmode",
            tags$button(class = paste("ea-wsx-cmb", if (!identical(input$cmode %||% "static", "interactive")) "on" else ""),
              type = "button", onclick = sprintf("Shiny.setInputValue('%s','static',{priority:'event'})", ns("cmode")),
              "Static"),
            tags$button(class = paste("ea-wsx-cmb", if (identical(input$cmode %||% "static", "interactive")) "on" else ""),
              type = "button", onclick = sprintf("Shiny.setInputValue('%s','interactive',{priority:'event'})", ns("cmode")),
              "Interactive"))),
        # plot / table split — drag the bar between them to resize
        div(class = "ea-wsx-dsplit",
          div(class = "ea-wsx-dplot",
            if (identical(input$cmode %||% "static", "interactive") &&
                requireNamespace("plotly", quietly = TRUE))
              plotly::plotlyOutput(ns("chart_i"), height = "100%")
            else plotOutput(ns("chart"), height = "100%")),
          div(class = "ea-wsx-dbar", title = "Drag to resize"),
          div(class = "ea-wsx-dtable",
            div(class = "ea-wsx-tdh", "Data table · ", tags$b(dtName() %||% "—")),
            DT::dataTableOutput(ns("dt")))))
    }
    .three_ui <- function() {
      if (!length(Filter(function(x) identical(x$kind, "lidar"), layers())))
        return(div(class = "ea-hint",
          "No point cloud in this project. Add a .las/.laz file to use the 3D view."))
      tagList(
        div(class = "ea-wsx-maptop", tags$span("3D view"),
            tags$span(class = "ea-wsx-mapsub", "Drag to rotate · scroll to zoom"),
            uiOutput(ns("tab_three_ui"), inline = TRUE)),
        # 3D only — no map pane. The basemap belongs to the LiDAR screen.
        div(class = "ea-wsx-threewrap", lidar3DOnlyUI("lidar")))
    }
    .map_ui <- function() {
      act <- activeLayer(); vis <- Filter(function(l) .vis(l$nm) && l$kind != "table", layers())
      tagList(
        div(class = "ea-wsx-maptop", tags$span("Map view"),
          tags$span(class = "ea-wsx-mapsub", "Visible: ",
            if (length(vis)) paste(vapply(vis, function(l) l$nm, character(1)), collapse = ", ") else "none"),
          # 3D viewer: sits at the right-hand end of this strip, and only while
          # a point cloud is the selected layer.
          uiOutput(ns("tab_three_ui"), inline = TRUE)),
        leaflet::leafletOutput(ns("map"), height = "100%"),
        # Point-density control. Rendered as its own small output rather than
        # inside .map_ui() so that selecting a layer does NOT re-create the
        # leaflet element (which would rebuild the whole map).
        uiOutput(ns("las_ctl")),
        div(class = "ea-wsx-attrdock",
          div(class = "ea-wsx-attrhead",
            tags$span("Attributes · ", tags$b(act %||% "—")),
            tags$button(class = "ea-wsx-attrmin", type = "button",
              onclick = paste0("var d=this.closest('.ea-wsx-attrdock');d.classList.toggle('collapsed');",
                               "this.textContent=d.classList.contains('collapsed')?'▴':'▾';"), "▾")),
          div(class = "ea-wsx-attrbody", uiOutput(ns("attr")))))
    }

    output$canvas <- renderUI({
      # NEW DESIGN: the canvas ALWAYS stays the map (Map view) or the chart
      # builder (Data view). A tool's own output never takes over the centre —
      # it renders in a pop-out result panel (see output$panels).
      if (identical(wsview(), "split")) {
        # Both views side by side with a draggable divider (each pane collapsible).
        return(div(class = "ea-wsx-split",
          div(class = "ea-wsx-sp ea-wsx-sp-map",
            div(class = "ea-wsx-sph", "Map",
              tags$button(class = "ea-wsx-spmin", type = "button",
                onclick = "this.closest('.ea-wsx-sp').classList.toggle('collapsed')", "–")),
            div(class = "ea-wsx-spb", .map_ui())),
          div(class = "ea-wsx-splitter"),
          div(class = "ea-wsx-sp ea-wsx-sp-data",
            div(class = "ea-wsx-sph", "Data",
              tags$button(class = "ea-wsx-spmin", type = "button",
                onclick = "this.closest('.ea-wsx-sp').classList.toggle('collapsed')", "–")),
            div(class = "ea-wsx-spb", .data_ui()))))
      }
      # A non-map tool (docs, references, a model…) takes the CENTRE by default,
      # in either view — the sidebar holds its controls. Map tools never do:
      # they draw on the map, which keeps the centre.
      t <- current_tool()
      mi <- if (!is.null(t) && !startsWith(t, "dataop:")) MODUI[[t]] else NULL
      if (!is.null(mi) && !isTRUE(mi$map_based) && identical(tool_mode(), "dock"))
        return(tagList(
          div(class = "ea-wsx-resulthead",
            span(class = "ea-wsx-toolnm", mi$nm),
            # Plot appearance belongs WITH THE PLOT, not across the screen in the
            # tool panel: it changes what you are looking at, so it sits above it.
            .plot_opts_ui(inline = TRUE),
            tags$button(class = "ea-wsx-backbtn", type = "button",
              onclick = sprintf("Shiny.setInputValue('%s','',{priority:'event'})", ns("tool_pick")),
              "← back")),
          div(class = "ea-wsx-modcanvas", mi$canvas(mi$id))))
      if (identical(wsview(), "three")) .three_ui()
      else if (identical(wsview(), "data")) .data_ui() else .map_ui()
    })

    # Step 6: attribute-table dock (Map view) — active layer's features / raster info
    fit_sig     <- reactiveVal("")   # which layer set we last auto-zoomed to
    fit_req     <- reactiveVal(NULL)  # explicit "Zoom to ..." bounds, applied once
    map_rebuild <- reactiveVal(0)    # bump to rebuild the map (and re-fit)
    # The map DEPENDS on basemap() so choosing one rebuilds the map with those
    # tiles. (A leafletProxy tile-swap was unreliable here: the canvas uiOutput
    # can re-create the map element, which discards pending proxy calls — the
    # basemap then appeared not to change at all.)
    # Display-ready copy of a raster: one band, downsampled, in WGS84.
    #
    # Two things this fixes. (1) ORDER: projecting first and downsampling after
    # meant a 33 M-cell orthomosaic was reprojected at FULL resolution just to
    # throw 99% of it away — 18.1 s, against 3.2 s downsampling first, for an
    # extent that differs by ~0.7 m. (2) REUSE: the bounds and the image each
    # built their own copy, so every map build paid that cost TWICE.
    .disp_cache <- new.env(parent = emptyenv())
    .disp_raster <- function(nm, idx = 1L) {
      r <- raster_pool[[nm]]
      if (is.null(r)) return(NULL)
      idx <- idx[idx >= 1 & idx <= terra::nlyr(r)]
      if (!length(idx)) return(NULL)
      key <- paste0(nm, "|", terra::ncell(r), "|", paste(idx, collapse = "-"), "|",
                    paste(as.vector(terra::ext(r)), collapse = ","))
      if (!is.null(.disp_cache[[key]])) return(.disp_cache[[key]])
      shrink <- function(x) if (terra::ncell(x) > 4e5)
        terra::aggregate(x, fact = ceiling(sqrt(terra::ncell(x) / 4e5)),
                         fun = "mean", na.rm = TRUE) else x
      out <- shrink(.to_wgs84(shrink(r[[idx]])))  # reprojection can re-inflate a little
      # Bounded, like the results store: rasters are big and this must not grow.
      if (length(ls(.disp_cache)) > 6L) rm(list = ls(.disp_cache), envir = .disp_cache)
      assign(key, out, envir = .disp_cache)
      out
    }

    # Per-band percentile stretch to 0-255. Orthomosaics carry FLOAT reflectance
    # (this one is 0.0004-0.63), and terra::colorize — the path leaflet uses for
    # RGB — expects byte values, so without this the composite is near-black.
    # Clipping at 2/98% is the usual remote-sensing default: it discards the
    # few extreme pixels that would otherwise flatten the whole image.
    .stretch_byte <- function(x, p = c(.02, .98)) {
      for (i in seq_len(terra::nlyr(x))) {
        v <- terra::values(x[[i]], mat = FALSE); v <- v[is.finite(v)]
        if (!length(v)) next
        q <- stats::quantile(v, p, names = FALSE)
        if (!all(is.finite(q)) || q[2] <= q[1]) q <- range(v)
        if (!all(is.finite(q)) || q[2] <= q[1]) next
        x[[i]] <- round((terra::clamp(x[[i]], q[1], q[2], values = TRUE) - q[1]) /
                        (q[2] - q[1]) * 255)
      }
      x
    }

    # The FINISHED composite (downsampled, projected, stretched, RGB-tagged).
    # Cached because every map rebuild re-runs .draw_layers — and a rebuild is
    # triggered by things that do not change the pixels at all, such as zooming
    # or switching basemap. Recomputing the stretch each time allocated a fresh
    # set of rasters per zoom, which on a 33 M-cell orthomosaic walked the
    # session into "cannot allocate vector" / GDAL block-cache failures.
    .rgb_cache <- new.env(parent = emptyenv())
    .rgb_raster <- function(nm, cfg) {
      key <- paste0(nm, "|", cfg$r, "-", cfg$g, "-", cfg$b)
      if (!is.null(.rgb_cache[[key]])) return(.rgb_cache[[key]])
      x <- .disp_raster(nm, c(cfg$r, cfg$g, cfg$b))
      if (is.null(x) || terra::nlyr(x) < 3) return(NULL)
      x <- .stretch_byte(x)
      terra::RGB(x) <- 1:3
      if (length(ls(.rgb_cache)) > 4L) rm(list = ls(.rgb_cache), envir = .rgb_cache)
      assign(key, x, envir = .rgb_cache)
      x
    }

    # Which bands feed R, G and B — DETECTED from what the file declares, never
    # inferred from band count. Band order genuinely varies: a plain ortho is
    # R,G,B, while a multispectral cube is often B,G,R,(RedEdge,NIR), so a guess
    # silently produces a wrong-coloured image that still looks plausible. If
    # the file does not say, we do not decide: the layer stays single-band and
    # the panel asks. Returns NULL when nothing authoritative is available.
    .detect_cache <- new.env(parent = emptyenv())
    .detect_rgb <- function(nm) {
      r <- raster_pool[[nm]]
      if (is.null(r) || terra::nlyr(r) < 3) return(NULL)
      if (!is.null(.detect_cache[[nm]])) return(.detect_cache[[nm]]$v)
      out <- NULL
      # (a) the raster carries RGB channel tags (terra/GDAL colour interpretation)
      if (isTRUE(tryCatch(terra::has.RGB(r), error = function(e) FALSE))) {
        i <- tryCatch(terra::RGB(r), error = function(e) NULL)
        if (length(i) >= 3 && all(is.finite(i[1:3])))
          out <- list(r = i[1], g = i[2], b = i[3], why = "the file's RGB channel tags")
      }
      # (b) gdalinfo's per-band ColorInterp (Red/Green/Blue), when tags are absent
      if (is.null(out)) {
        src <- tryCatch(terra::sources(r), error = function(e) character(0))
        if (length(src) && nzchar(src[1]) && file.exists(src[1])) {
          info <- tryCatch(terra::describe(src[1]), error = function(e) character(0))
          ci   <- grep("^Band [0-9]+ .*ColorInterp=", info, value = TRUE)
          pick <- function(w) {
            h <- grep(paste0("ColorInterp=", w, "$"), ci, value = TRUE)
            if (!length(h)) return(NA_integer_)
            as.integer(sub("^Band ([0-9]+) .*$", "\\1", h[1]))
          }
          idx <- c(r = pick("Red"), g = pick("Green"), b = pick("Blue"))
          if (all(!is.na(idx)))
            out <- list(r = idx[["r"]], g = idx[["g"]], b = idx[["b"]],
                        why = "the file's colour interpretation")
        }
      }
      # (c) band names that state the colour outright (e.g. "red", "B03_green")
      if (is.null(out)) {
        nms  <- tolower(c(names(r)))
        pick <- function(w) { h <- grep(paste0("(^|[^a-z])", w, "([^a-z]|$)"), nms)
                              if (length(h) == 1L) h else NA_integer_ }
        idx <- c(r = pick("red"), g = pick("green"), b = pick("blue"))
        if (all(!is.na(idx)))
          out <- list(r = idx[["r"]], g = idx[["g"]], b = idx[["b"]],
                      why = "the band names")
      }
      assign(nm, list(v = out), envir = .detect_cache)
      out
    }

    # Stored settings live in the PROJECT (layer_style), so a mapping chosen
    # once survives closing the app. NULL layer_style = tests/standalone use.
    .style_get <- function() if (is.null(layer_style)) list() else (layer_style() %||% list())
    .style_set <- function(nm, cfg) {
      if (is.null(layer_style)) return(invisible(NULL))
      st <- .style_get(); st[[nm]] <- cfg; layer_style(st)
    }
    .rgb_of <- function(nm, nb) {
      cur <- .style_get()[[nm]]
      if (is.list(cur) && !is.null(cur$mode)) return(cur)   # the user decided
      det <- .detect_rgb(nm)
      if (!is.null(det))
        list(mode = "rgb", r = det$r, g = det$g, b = det$b, why = det$why)
      else list(mode = "single", r = 1, g = 2, b = 3, why = NULL)  # undeclared: ask
    }
    observeEvent(input$ws_rgb, {
      s <- input$ws_rgb; nm <- s$nm
      r <- raster_pool[[nm]]; if (is.null(r)) return()
      cfg <- .rgb_of(nm, terra::nlyr(r))
      cfg[[s$ch]] <- as.integer(s$b); cfg$why <- "your choice"
      .style_set(nm, cfg)
    })
    observeEvent(input$ws_rgbmode, {
      nm <- input$ws_rgbmode
      r <- raster_pool[[nm]]; if (is.null(r)) return()
      cfg <- .rgb_of(nm, terra::nlyr(r))
      cfg$mode <- if (identical(cfg$mode, "rgb")) "single" else "rgb"
      if (identical(cfg$mode, "rgb") && is.null(cfg$why)) cfg$why <- "your choice"
      .style_set(nm, cfg)
    })

    # A raster's footprint in WGS84, computed from its EXTENT ALONE — the pixels
    # are never touched. Bounds used to come from the projected display copy,
    # which tied the zoom to a full raster reprojection: if that copy was built
    # for different bands (or failed on memory) the map silently skipped its fit
    # and sat at the default view with the layer drawn as a dot. Segmentised so
    # a curved projection does not clip the edges.
    .rast_bbox <- function(r) {
      if (is.null(r)) return(NULL)
      tryCatch({
        e  <- as.numeric(as.vector(terra::ext(r)))          # xmin,xmax,ymin,ymax
        cr <- sf::st_crs(terra::crs(r))
        if (is.na(cr)) return(NULL)
        bx <- sf::st_as_sfc(sf::st_bbox(
                c(xmin = e[1], ymin = e[3], xmax = e[2], ymax = e[4]), crs = cr))
        bx <- sf::st_segmentize(bx, max(diff(e[1:2]), diff(e[3:4])) / 25)
        v  <- as.numeric(sf::st_bbox(sf::st_transform(bx, 4326)))
        if (length(v) == 4 && all(is.finite(v))) v else NULL
      }, error = function(e) NULL)
    }

    # A drawable sample of a point cloud, in WGS84, carrying Z for shading.
    # Decimated hard on purpose: the pool holds up to 500k points and leaflet
    # renders one DOM element per marker, so the full cloud would lock the
    # browser. Cached per layer — this runs on every map rebuild otherwise.
    .LAS_DRAW_CAP   <- 4000L      # points drawn by default
    .LAS_MARKER_MAX <- 25000L     # above this, markers stop being viable (see below)
    lden <- reactiveValues()                       # per-layer point budget
    .las_cap <- function(nm) {
      v <- if (is.null(nm)) NULL else lden[[nm]]
      if (is.null(v)) .LAS_DRAW_CAP else as.integer(v)
    }
    .las_read_cache <- new.env(parent = emptyenv())
    .las_src <- function(nm) {
      if (is.null(src_paths) || is.null(nm)) return("")
      p <- tryCatch(src_paths[[nm]], error = function(e) NULL)
      if (is.null(p) || !nzchar(p) || !file.exists(p)) "" else p
    }
    # Points in the ORIGINAL FILE. Loading is capped for RAM, so the pool holds
    # a sample; the slider is bounded by the file so the whole cloud is
    # reachable, and the extra points are read only WHEN THE SLIDER ASKS.
    .las_total <- function(nm) {
      p <- .las_src(nm); if (!nzchar(p)) return(NA_real_)
      tryCatch({
        h <- lidR::readLASheader(p)
        n <- h@PHB[["Number of point records"]]
        if (is.null(n) || is.na(n) || n == 0) n <- h@PHB[["Number of points by return"]][1]
        as.numeric(n)
      }, error = function(e) NA_real_)
    }
    # A cloud holding at least `cap` points, re-reading from disk only when the
    # pool's sample is thinner than asked. Read cost is proportional to the ask,
    # not the whole file, via a random-fraction filter.
    .las_at <- function(nm, cap) {
      las  <- las_pool[[nm]]
      have <- tryCatch(if (is.null(las) || inherits(las, "LASheader")) 0L else nrow(las@data),
                       error = function(e) 0L)
      if (have >= cap) return(las)
      p <- .las_src(nm); if (!nzchar(p)) return(las)
      tot <- .las_total(nm); if (is.na(tot) || tot <= have) return(las)
      key <- paste0(nm, "|", cap)
      if (!is.null(.las_read_cache[[key]])) return(.las_read_cache[[key]])
      out <- tryCatch({
        f <- if (tot > cap) paste("-keep_random_fraction", round(min(1, cap / tot), 6)) else ""
        lidR::readLAS(p, filter = f)
      }, error = function(e) NULL)
      if (is.null(out)) return(las)
      if (length(ls(.las_read_cache)) > 1L)   # a full cloud is large; keep one
        rm(list = ls(.las_read_cache), envir = .las_read_cache)
      assign(key, out, envir = .las_read_cache)
      out
    }
    .las_pts_cache <- new.env(parent = emptyenv())
    .las_points <- function(x, cap = .LAS_DRAW_CAP) {
      if (is.null(x) || inherits(x, "LASheader")) return(NULL)   # header-only: no points
      d <- tryCatch(x@data, error = function(e) NULL)
      if (is.null(d) || !nrow(d) || is.null(d$Z)) return(NULL)
      cap <- max(100L, as.integer(cap))
      key <- paste0(nrow(d), "|", d$X[1], "|", d$Y[1], "|", d$Z[1], "|", cap)
      if (!is.null(.las_pts_cache[[key]])) return(.las_pts_cache[[key]])
      out <- tryCatch({
        cr <- sf::st_crs(x); if (is.na(cr)) return(NULL)
        i  <- if (nrow(d) > cap) sort(sample.int(nrow(d), cap)) else seq_len(nrow(d))
        p  <- sf::st_transform(sf::st_as_sf(
                data.frame(X = d$X[i], Y = d$Y[i], Z = d$Z[i]),
                coords = c("X", "Y"), crs = cr), 4326)
        if (!nrow(p) || !any(is.finite(p$Z))) NULL else p
      }, error = function(e) NULL)
      if (length(ls(.las_pts_cache)) > 4L)
        rm(list = ls(.las_pts_cache), envir = .las_pts_cache)
      assign(key, out, envir = .las_pts_cache)
      out
    }

    # LAS/LAZ footprint in WGS84. The pool may hold a full LAS *or* just its
    # header (big clouds are capped at read time), so read whichever it is.
    # lidR::extent() is avoided on purpose: it returns a terra::SpatExtent on
    # some versions and @xmin then fails (CLAUDE.md — LAS CRS/extent gotcha).
    .las_bbox <- function(x) {
      if (is.null(x)) return(NULL)
      e <- tryCatch({
        if (inherits(x, "LASheader")) {
          p <- x@PHB
          c(p[["Min X"]], p[["Min Y"]], p[["Max X"]], p[["Max Y"]])
        } else {
          c(min(x@data$X, na.rm = TRUE), min(x@data$Y, na.rm = TRUE),
            max(x@data$X, na.rm = TRUE), max(x@data$Y, na.rm = TRUE))
        }
      }, error = function(e) NULL)
      if (length(e) != 4 || !all(is.finite(e))) return(NULL)
      cr <- tryCatch(sf::st_crs(x), error = function(e) NA)
      if (is.na(cr)) return(NULL)          # unknown CRS — cannot place it on a map
      tryCatch(as.numeric(sf::st_bbox(sf::st_transform(
        sf::st_as_sfc(sf::st_bbox(c(xmin = e[1], ymin = e[2], xmax = e[3], ymax = e[4]),
                                  crs = cr)), 4326))),
        error = function(e) NULL)
    }

    # Bounds in WGS84 (lng1, lat1, lng2, lat2). With `only`, just that layer —
    # and its visibility is ignored, because "zoom to this layer" is an explicit
    # instruction about a layer the user just named.
    .layer_bounds <- function(only = NULL) {
      bb <- NULL
      keep <- if (is.null(only))
        function(x) x$kind %in% c("raster", "vector", "lidar") && .vis(x$nm)
      else
        function(x) x$kind %in% c("raster", "vector", "lidar") && identical(x$nm, only)
      for (l in Filter(keep, layers())) {
        e <- tryCatch({
          if (identical(l$kind, "raster")) {
            # NOTE: yield NULL, never return() — return() inside this loop exits
            # .layer_bounds() entirely, so one empty pool entry used to throw
            # away the bounds of every other layer and the map never zoomed.
            .rast_bbox(raster_pool[[l$nm]])
          } else if (identical(l$kind, "lidar")) {
            .las_bbox(las_pool[[l$nm]])
          } else {
            vv <- vector_pool[[l$nm]]
            if (is.null(vv)) NULL
            else as.numeric(sf::st_bbox(sf::st_transform(sf::st_zm(vv), 4326)))
          }
        }, error = function(e) NULL)
        if (length(e) == 4 && all(is.finite(e)))
          bb <- if (is.null(bb)) e else c(min(bb[1], e[1]), min(bb[2], e[2]),
                                          max(bb[3], e[3]), max(bb[4], e[4]))
      }
      bb
    }

    # Draw the VISIBLE spatial layers straight ONTO THE MAP OBJECT.
    # Deliberately NOT a leafletProxy: the map element is re-created whenever the
    # canvas re-renders or the basemap changes, and a proxy message that arrives
    # around that moment is silently dropped. That is why the raster stayed
    # invisible while the zoom — already applied at build time — worked fine.
    # Tiles, view and data are now built in one pass, in that order, so the map
    # can never end up half-drawn or with data underneath the basemap.
    .draw_layers <- function(m) {
      for (l in Filter(function(x) x$kind %in% c("raster", "vector", "lidar") && .vis(x$nm),
                       layers())) {
        m <- tryCatch({
          if (identical(l$kind, "raster")) {
            src <- raster_pool[[l$nm]]
            nb  <- if (is.null(src)) 0L else terra::nlyr(src)
            cfg <- .rgb_of(l$nm, nb)
            if (identical(cfg$mode, "rgb") && nb >= 3) {
              # TRUE-COLOUR COMPOSITE. leaflet only takes its RGB path when
              # terra::has.RGB() is set, so declare the channels; otherwise it
              # silently keeps band 1 and warns "using the first layer in 'x'".
              x <- .rgb_raster(l$nm, cfg)     # cached: stretched + RGB-tagged
              if (is.null(x)) m else
                leaflet::addRasterImage(m, x, opacity = 0.9, group = "ws_layers")
            } else {
              r1 <- .disp_raster(l$nm, 1L)   # cached, downsampled + in WGS84
              if (is.null(r1)) m else {
                vals <- suppressWarnings(terra::values(r1, mat = FALSE))
                vals <- vals[is.finite(vals)]
                if (!length(vals)) m else {
                  pal <- leaflet::colorNumeric(.pal_colors("viridis"), range(vals),
                                               na.color = "transparent")
                  leaflet::addRasterImage(m, r1, colors = pal, opacity = 0.85,
                                          group = "ws_layers")
                }
              }
            }
          } else if (identical(l$kind, "lidar")) {
            # The cloud itself, height-shaded — the footprint alone told you
            # where the data was but not what it looked like. Drawn as a
            # DECIMATED sample: the pool holds up to 500k points and the browser
            # cannot take that many markers, so a few thousand carry the shape.
            cap <- .las_cap(l$nm)
            las <- .las_at(l$nm, cap) %||% las_pool[[l$nm]]   # reads more only if asked
            e   <- .las_bbox(las)
            pts <- .las_points(las, cap)
            mm  <- m
            if (!is.null(e))                       # outline of the full tile
              mm <- leaflet::addRectangles(mm, e[1], e[2], e[3], e[4],
                      color = "#D99B57", weight = 1.2, fill = FALSE,
                      label = l$nm, group = "ws_layers")
            if (is.null(pts)) mm else {
              # ALWAYS real points — a LAZ layer is a point cloud, not a surface.
              # The map is built with preferCanvas so these are painted onto a
              # canvas rather than becoming one DOM node each, which is what
              # keeps large clouds drawable.
              pal <- leaflet::colorNumeric(.pal_colors("viridis"), range(pts$Z),
                                           na.color = "transparent")
              big <- nrow(pts) > .LAS_MARKER_MAX
              leaflet::addCircleMarkers(mm, data = pts,
                radius = if (big) 1.4 else 2, stroke = FALSE,
                fillOpacity = if (big) .6 else .75,
                fillColor = pal(pts$Z), group = "ws_layers",
                label = if (big) NULL else paste0(l$nm, " · Z ", round(pts$Z, 1)))
            }
          } else {
            v <- vector_pool[[l$nm]]
            if (is.null(v)) m else {
              v1 <- sf::st_transform(sf::st_zm(v), 4326)
              gt <- as.character(sf::st_geometry_type(v1, by_geometry = FALSE))
              if (grepl("POINT", gt))
                leaflet::addCircleMarkers(m, data = v1, radius = 5, color = "#7ED481",
                  fillOpacity = .85, stroke = TRUE, weight = 1, group = "ws_layers")
              else if (grepl("LINE", gt))
                leaflet::addPolylines(m, data = v1, color = "#7ED481", weight = 2,
                  group = "ws_layers")
              else
                leaflet::addPolygons(m, data = v1, color = "#5FBF62", weight = 1.5,
                  fillOpacity = .25, group = "ws_layers")
            }
          }
        }, error = function(e) m)   # one bad layer must not blank the whole map
      }
      m
    }

    output$map <- leaflet::renderLeaflet({
      bm <- basemap(); map_rebuild()   # rebuild when new layers arrive
      wsview()                         # re-entering Map view re-creates the element
      # PRESERVE THE VIEW across a rebuild: reuse wherever the user currently is
      # (leaflet reports it as input$map_center / input$map_zoom) instead of
      # snapping back to the default. Changing the basemap must not move the map.
      ctr <- isolate(input$map_center); zm <- isolate(input$map_zoom)
      # Zoom to the data AT BUILD TIME. Doing it here (rather than through a
      # leafletProxy after the fact) is what finally makes it reliable: the map
      # element is re-created whenever the canvas re-renders, which silently
      # discarded pending proxy fitBounds calls — so the raster never zoomed.
      bb  <- isolate(tryCatch(.layer_bounds(), error = function(e) NULL))
      # lidar belongs in the signature too — a LAZ-only project otherwise had an
      # empty signature and so never triggered its first automatic fit.
      sig <- isolate(tryCatch(paste(vapply(
               Filter(function(x) x$kind %in% c("raster","vector","lidar") && .vis(x$nm), layers()),
               function(l) l$nm, character(1)), collapse = "|"), error = function(e) ""))
      fr  <- isolate(fit_req())
      # preferCanvas: point clouds are drawn as circle markers, and the default
      # SVG renderer makes one DOM node per point. Canvas keeps tens of
      # thousands of points viable without turning them into a raster.
      m <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE))
      # An explicit "Zoom to ..." outranks everything; then the automatic
      # first-fit for a new layer set; then wherever the user had panned to.
      if (!is.null(fr)) {
        m <- leaflet::fitBounds(m, fr[1], fr[2], fr[3], fr[4])
        fit_req(NULL); fit_sig(sig)
      } else if (!is.null(bb) && !nzchar(isolate(fit_sig())) && nzchar(sig)) {
        # ONE MAP, everything overlays on it. The automatic fit therefore fires
        # only for the FIRST spatial layer, to get off the default world view.
        # Adding a second file must not yank the view away from what the user is
        # looking at — re-framing is on request ("Zoom to layers").
        m <- leaflet::fitBounds(m, bb[1], bb[2], bb[3], bb[4])
        fit_sig(sig)
      } else if (!is.null(ctr) && !is.null(zm)) {
        m <- leaflet::setView(m, lng = ctr$lng, lat = ctr$lat, zoom = zm)
      } else if (!is.null(bb)) {
        m <- leaflet::fitBounds(m, bb[1], bb[2], bb[3], bb[4])
      } else {
        m <- leaflet::setView(m, lng = 27, lat = 63, zoom = 5)
      }
      # Tiles FIRST, then the data on top of them — one atomic build.
      # zIndex = 0 pins the basemap BELOW everything else: addRasterImage builds
      # a canvas tile layer that also lives in the tilePane, and at equal z-index
      # the two are separated only by DOM order. Making the basemap explicitly
      # the bottom layer is what guarantees a raster can never hide under it.
      if (nzchar(bm)) m <- leaflet::addProviderTiles(m, bm, layerId = "ws_base",
                             options = leaflet::providerTileOptions(zIndex = 0))
      .draw_layers(m)
    })
    # Opening another project clears the pools first; re-arm the first-fit so
    # the incoming project frames itself instead of inheriting the old view.
    observe({
      if (!length(Filter(function(x) x$kind %in% c("raster","vector","lidar"), layers())))
        fit_sig("")
    })
    # New layers must rebuild the map so the fit applies.
    observeEvent(layers(), {
      sig <- tryCatch(paste(vapply(
               Filter(function(x) x$kind %in% c("raster","vector","lidar") && .vis(x$nm), layers()),
               function(l) l$nm, character(1)), collapse = "|"), error = function(e) "")
      if (!identical(sig, fit_sig())) map_rebuild(map_rebuild() + 1)
    }, ignoreInit = FALSE)


    output$view_tabs <- renderUI({
      v <- wsview()
      mk <- function(key, label) tags$button(
        id = ns(paste0("tab_", key)),
        class = paste("ea-wsx-tab", if (identical(v, key)) "on" else ""),
        type = "button",
        onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'});",
                          ns("wsview"), key),
        label)
      div(class = "ea-wsx-tabs",
        mk("map", "Map view"), mk("data", "Data view"), mk("split", "Split"))
    })

    .active_is_lidar <- reactive({
      a <- activeLayer()
      if (is.null(a)) return(FALSE)
      l <- Filter(function(x) identical(x$nm, a), layers())
      length(l) > 0 && identical(l[[1]]$kind, "lidar")
    })
    output$tab_three_ui <- renderUI({
      if (!.active_is_lidar()) return(NULL)
      on3d <- identical(wsview(), "three")
      # The button IS the way back, so it has to say so. Relying on the user
      # guessing that a button labelled "3D view" also leaves 3D is not a toggle,
      # it is a puzzle. Label, icon and active styling all change with the state.
      tags$button(id = ns("tab_three"),
        class = paste("ea-wsx-3dbtn", if (on3d) "on" else ""), type = "button",
        title = if (on3d) "Return to the map view" else "Open the 3D point cloud",
        onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'});",
                          ns("wsview"), if (on3d) "map" else "three"),
        icon(if (on3d) "map-location-dot" else "cube"),
        if (on3d) " Back to map" else " 3D view")
    })
    # Selecting a non-cloud layer takes the 3D tab away, so do not strand the
    # user on a view that no longer has a tab.
    observe({
      if (identical(wsview(), "three") && !.active_is_lidar()) wsview("map")
    })

    # Visible ONLY while a point cloud is the selected layer — it is that
    # layer's control, and an always-on slider would be noise for everything else.
    output$las_ctl <- renderUI({
      a <- activeLayer(); if (is.null(a)) return(NULL)
      l <- Filter(function(x) identical(x$nm, a), layers())
      if (!length(l) || !identical(l[[1]]$kind, "lidar")) return(NULL)
      x <- las_pool[[a]]
      n <- tryCatch(if (is.null(x) || inherits(x, "LASheader")) 0L else nrow(x@data),
                    error = function(e) 0L)
      tot <- .las_total(a)
      hi  <- if (!is.na(tot) && tot > 0) tot else n     # the FILE's point count
      if (!hi) return(NULL)
      cur <- min(.las_cap(a), hi)
      div(class = "ea-wsx-lasctl",
        div(class = "ea-wsx-lasctl-h", "Points shown"),
        sliderInput(ns("las_density"), NULL, min = 500, max = hi, value = cur,
                    step = max(500, round(hi / 200)), width = "170px", ticks = FALSE),
        div(class = "ea-wsx-lasctl-n",
            paste0("of ", format(hi, big.mark = ","), " in file",
                   if (cur > .LAS_MARKER_MAX) " · heavy" else "")))
    })
    observeEvent(input$las_density, {
      a <- activeLayer(); req(a)
      if (identical(.las_cap(a), as.integer(input$las_density))) return()
      lden[[a]] <- as.integer(input$las_density)
      map_rebuild(map_rebuild() + 1)
    }, ignoreInit = TRUE)

    output$attr <- renderUI({
      act <- activeLayer(); req(act)
      lay <- Filter(function(l) identical(l$nm, act), layers()); lay <- if (length(lay)) lay[[1]] else NULL
      req(lay)
      # THE ATTRIBUTE TABLE BELONGS TO THE SPATIAL LAYER — it is the vector's own
      # attributes (st_drop_geometry), NOT an unrelated CSV that happens to be in
      # the project. A table layer is not drawn on the map, so it has no
      # attribute table here; it belongs in the Data view.
      if (identical(lay$kind, "vector")) {
        # A vector with geometry but NO attribute columns rendered as a blank
        # table, which reads as "the attribute table is broken". It is not —
        # there is genuinely nothing to show, and the usual cause is a shapefile
        # uploaded without its .dbf. Say that instead of showing an empty grid.
        nc <- tryCatch(ncol(sf::st_drop_geometry(vector_pool[[act]])),
                       error = function(e) NA_integer_)
        n  <- tryCatch(nrow(vector_pool[[act]]), error = function(e) NA_integer_)
        if (!is.na(nc) && nc == 0)
          return(div(class = "ea-wsx-attrinfo",
            tags$b(act), " has ", format(n), " features but no attribute columns.",
            tags$br(),
            "A shapefile stores its attributes in the ", tags$b(".dbf"), " file. If you added ",
            "only the .shp, add it again with every part selected (.shp, .dbf, .shx, .prj)."))
        return(DT::dataTableOutput(ns("attr_dt")))
      }
      if (identical(lay$kind, "table"))
        return(div(class = "ea-wsx-attrinfo",
          "'", act, "' is a table, not a map layer — open it in ", tags$b("Data view"),
          ". The attribute table here shows a vector layer's own attributes."))
      if (identical(lay$kind, "raster")) {
        r <- tryCatch(raster_pool[[act]], error = function(e) NULL)
        info <- tryCatch(paste0("Raster · dims ", paste(dim(r), collapse = " × "),
                                " · res ", paste(round(terra::res(r), 2), collapse = ", ")),
                         error = function(e) "raster layer (band stats)")
        return(div(class = "ea-wsx-attrinfo", info))
      }
      div(class = "ea-wsx-attrinfo", "Point cloud — no feature table.")
    })
    output$attr_dt <- DT::renderDataTable({
      # ONLY the active VECTOR layer's own attributes (never a separate CSV).
      act <- activeLayer(); req(act, act %in% .names(vector_pool))
      df <- tryCatch(as.data.frame(sf::st_drop_geometry(vector_pool[[act]])),
                     error = function(e) NULL)
      req(is.data.frame(df))
      DT::datatable(utils::head(df, 200), options = list(pageLength = 6, scrollX = TRUE), rownames = FALSE)
    }, server = TRUE)

    output$dt <- DT::renderDataTable({
      ds <- dtName(); req(ds)
      df <- dataset_pool[[ds]]; req(is.data.frame(df))
      DT::datatable(utils::head(df, 200),
                    options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
    }, server = TRUE)

    # ONE ggplot spec, rendered either STATIC (ggplot) or INTERACTIVE (plotly:
    # hover tooltips, zoom, pan, box-select). Same data, same mapping.
    .gg <- reactive({
      ds <- dtName(); df <- tryCatch(dataset_pool[[ds]], error = function(e) NULL)
      req(is.data.frame(df))
      geom <- input$cgeom %||% "scatter"; x <- input$cx; y <- input$cy
      req(isTruthy(x))
      num <- function(c) suppressWarnings(as.numeric(df[[c]]))
      g <- ggplot2::ggplot(df)
      # No label/colour wiring here on purpose: ea_style_gg() applies the
      # shared plot options to every ggplot in the app at print time.
      fg <- "#2E7D32"; sky <- "#3E7CB1"
      p <- switch(geom,
        histogram = g + ggplot2::aes(x = num(x)) +
                    ggplot2::geom_histogram(fill = sky, colour = "white", bins = 20) +
                    ggplot2::labs(x = x, y = "count"),
        boxplot   = { req(isTruthy(y)); g + ggplot2::aes(y = num(y)) +
                    ggplot2::geom_boxplot(fill = fg, alpha = .7) +
                    ggplot2::labs(y = y) },
        bars      = g + ggplot2::aes(x = factor(df[[x]])) +
                    ggplot2::geom_bar(fill = fg) +
                    ggplot2::labs(x = x, y = "count") +
                    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)),
        line      = { req(isTruthy(y)); g + ggplot2::aes(x = num(x), y = num(y)) +
                    ggplot2::geom_line(colour = fg, linewidth = .9) +
                    ggplot2::labs(x = x, y = y) },
        { req(isTruthy(y)); g + ggplot2::aes(x = num(x), y = num(y)) +
                    ggplot2::geom_point(colour = fg, size = 2.2, alpha = .85) +
                    ggplot2::labs(x = x, y = y) })
      p + ggplot2::theme_minimal(base_size = 12)
    })

    output$chart_i <- plotly::renderPlotly({
      plotly::ggplotly(.gg()) %>%
        plotly::config(displaylogo = FALSE,
                       modeBarButtonsToRemove = c("lasso2d", "autoScale2d"))
    })

    # Static renderer uses the SAME ggplot spec as the interactive one, so
    # toggling Static/Interactive shows the same plot, not two different ones.
    output$chart <- renderPlot({ .gg() }, bg = "white")


    # ---- Data & Exploration: each ETL operation is its OWN menu entry --------
    # The Data module's tools panel is a 9-panel accordion. Instead of dumping
    # all of it into the sidebar, every operation is listed individually in the
    # menu and only the chosen one's controls render in the panel.
    DATA_OPS <- c("Column Management", "Row Filtering", "Type Conversion",
                  "Level Management", "Aggregation", "Bin/Cut Numeric",
                  "Conditional Imputation", "Merge/Join Datasets", "Batch Apply Pipeline")
    # Pull ONE accordion panel out of the built UI and render it already open.
    .data_op_ui <- function(title) {
      ui <- tryCatch(dataToolsUI("data"), error = function(e) NULL)
      if (is.null(ui)) return(NULL)
      items <- tryCatch(htmltools::tagQuery(ui)$find(".accordion-item")$selectedTags(),
                        error = function(e) NULL)
      if (!length(items)) return(NULL)
      for (it in items) {
        hdr <- tryCatch(paste(as.character(
                 htmltools::tagQuery(it)$find(".accordion-header")$selectedTags()), collapse = ""),
                 error = function(e) "")
        if (grepl(title, hdr, fixed = TRUE)) {
          opened <- tryCatch(
            htmltools::tagQuery(it)$find(".accordion-collapse")$addClass("show")$allTags(),
            error = function(e) it)
          return(div(class = "accordion", opened))
        }
      }
      NULL
    }

    # ---- Step 3: tool-panel host — pick a tool -> its settings load here ----
    current_tool <- reactiveVal(NULL)
    # Step 7 (complete): EVERY analysis module is hosted here, using its ORIGINAL
    # namespace id — the module servers stay bound once in server.R and their old
    # standalone panes are retired, so there is exactly one instance of each.
    MODUI <- list(
      # --- Data ---
      data           = list(nm = "Data & Exploration",  grp = "Data", tools = dataToolsUI,          canvas = dataCanvasUI),
      descriptive    = list(nm = "Descriptive & Correlation", grp = "Data", tools = descriptiveToolsUI, canvas = descriptiveCanvasUI),
      # NOTE: `recommend` is NOT here — it is merged into the Co-Analyst dock
      # (mod_chat.R "Recommend" tab), so its UI exists in exactly one place.
      # --- Statistics ---
      tests          = list(nm = "Statistical tests",   grp = "Statistics", tools = testsToolsUI,   canvas = testsCanvasUI),
      anova          = list(nm = "ANOVA",               grp = "Statistics", tools = anovaToolsUI,   canvas = anovaCanvasUI),
      lm             = list(nm = "Linear regression",   grp = "Statistics", tools = lmToolsUI,      canvas = lmCanvasUI),
      logistic       = list(nm = "Logistic regression", grp = "Statistics", tools = logisticToolsUI,canvas = logisticCanvasUI),
      lme            = list(nm = "Linear mixed effects",grp = "Statistics", tools = lmeToolsUI,     canvas = lmeCanvasUI),
      gam            = list(nm = "GAM",                 grp = "Statistics", tools = gamToolsUI,     canvas = gamCanvasUI),
      survival       = list(nm = "Survival analysis",   grp = "Statistics", tools = survivalToolsUI,canvas = survivalCanvasUI),
      sem            = list(nm = "SEM & mediation",     grp = "Statistics", tools = semToolsUI,     canvas = semCanvasUI),
      bayesian       = list(nm = "Bayesian analysis",   grp = "Statistics", tools = bayesianToolsUI,canvas = bayesianCanvasUI),
      timeseries     = list(nm = "Time series",         grp = "Statistics", tools = timeseriesToolsUI, canvas = timeseriesCanvasUI),
      # --- Machine learning ---
      rf             = list(nm = "Random Forest",       grp = "Machine Learning", tools = rfToolsUI,     canvas = rfCanvasUI),
      xgboost        = list(nm = "XGBoost",             grp = "Machine Learning", tools = xgboostToolsUI,canvas = xgboostCanvasUI),
      dtree          = list(nm = "Decision tree",       grp = "Machine Learning", tools = dtreeToolsUI,  canvas = dtreeCanvasUI),
      svm            = list(nm = "Support vector machine", grp = "Machine Learning", tools = svmToolsUI, canvas = svmCanvasUI),
      nnet_ml        = list(nm = "Neural network",      grp = "Machine Learning", tools = nnetMlToolsUI, canvas = nnetMlCanvasUI),
      da             = list(nm = "Discriminant analysis", grp = "Machine Learning", tools = daToolsUI,   canvas = daCanvasUI),
      clustering     = list(nm = "Clustering",          grp = "Machine Learning", tools = clusteringToolsUI, canvas = clusteringCanvasUI),
      classification = list(nm = "Classification",      grp = "Machine Learning", tools = classificationToolsUI, canvas = classificationCanvasUI),
      pca            = list(nm = "Dimension reduction (PCA)", grp = "Machine Learning", tools = pcaToolsUI, canvas = pcaCanvasUI),
      # --- Spatial & LiDAR ---
      raster         = list(nm = "Raster & vector analysis", grp = "Spatial & LiDAR", tools = rasterToolsUI,  canvas = rasterCanvasUI, map_based = TRUE),
      surface        = list(nm = "Surface models",      grp = "Spatial & LiDAR", tools = surfaceToolsUI,      canvas = surfaceCanvasUI, map_based = TRUE),
      terrain        = list(nm = "Terrain analysis",    grp = "Spatial & LiDAR", tools = terrainToolsUI,      canvas = terrainCanvasUI, map_based = TRUE),
      hydro          = list(nm = "Hydrology",           grp = "Spatial & LiDAR", tools = hydroToolsUI,        canvas = hydroCanvasUI, map_based = TRUE),
      suitability    = list(nm = "Suitability modeling",grp = "Spatial & LiDAR", tools = suitabilityToolsUI,  canvas = suitabilityCanvasUI, map_based = TRUE),
      land_classify  = list(nm = "Land classification", grp = "Spatial & LiDAR", tools = landClassifyToolsUI, canvas = landClassifyCanvasUI, map_based = TRUE),
      rs_search      = list(nm = "Download spatial data", grp = "Spatial & LiDAR", tools = rsSearchToolsUI,   canvas = rsSearchCanvasUI, map_based = TRUE),
      ntl            = list(nm = "Night-time lights",   grp = "Spatial & LiDAR", tools = ntlToolsUI,          canvas = ntlCanvasUI, map_based = TRUE),
      climate_trend  = list(nm = "Climate trend",       grp = "Spatial & LiDAR", tools = climateTrendToolsUI, canvas = climateTrendCanvasUI, map_based = TRUE),
      wind           = list(nm = "Wind & environment",  grp = "Spatial & LiDAR", tools = windToolsUI,         canvas = windCanvasUI),
      pointcloud     = list(nm = "Point cloud / 3D",    grp = "Spatial & LiDAR", tools = lidarPointcloudToolsUI, canvas = lidarPointcloudCanvasUI),
      chm_itd        = list(nm = "CHM & tree detection",grp = "Spatial & LiDAR", tools = lidarChmToolsUI,     canvas = lidarChmCanvasUI),
      metrics        = list(nm = "LiDAR metrics",       grp = "Spatial & LiDAR", tools = lidarMetricsToolsUI, canvas = lidarMetricsCanvasUI),
      # --- Docs (R console is NOT here: it lives in the bottom dock) ---
      docs           = list(nm = "Documentation",       grp = "More", tools = docsToolsUI,       canvas = docsCanvasUI),
      references     = list(nm = "References",          grp = "More", tools = referencesToolsUI, canvas = referencesCanvasUI)
    )
    for (k in names(MODUI)) MODUI[[k]]$id <- k   # original namespace = the tool key
    # Built-in scaffold tools (no dedicated module) keep working alongside.
    TOOLS <- list(
      clip    = list(nm = "Clip raster (scaffold)",  grp = "Spatial", kind = "spatial"),
      extract = list(nm = "Extract values (scaffold)", grp = "Spatial", kind = "spatial")
    )
    # A menubar click elsewhere in the app can request a tool here.
    observeEvent(tool_request(), {
      tr <- tool_request()
      if (isTruthy(tr) && (tr %in% names(MODUI) || tr %in% names(TOOLS))) current_tool(tr)
    }, ignoreInit = TRUE)
    observeEvent(input$tool_pick, {
      current_tool(if (nzchar(input$tool_pick %||% "")) input$tool_pick else NULL)
    })
    .cols <- function() {
      ds <- dtName(); df <- tryCatch(dataset_pool[[ds]], error = function(e) NULL)
      if (is.data.frame(df)) names(df) else character(0)
    }

    # A tool opens in the SIDEBAR by default; the user can float it (draggable,
    # resizable) or minimize it to the results dock.
    tool_mode <- reactiveVal("dock")           # "dock" | "float" | "min"
    observeEvent(input$tool_pick, {
      if (!nzchar(input$tool_pick %||% "")) return()
      tool_mode("dock")
      # A map-based tool needs the map on screen — switch to it (unless split).
      mi <- MODUI[[input$tool_pick]]
      if (!is.null(mi) && isTRUE(mi$map_based) && !identical(wsview(), "split")) wsview("map")
    })
    observeEvent(input$tool_float, { tool_mode("float") })
    observeEvent(input$tool_dock,  { tool_mode("dock") })
    observeEvent(input$tool_min,   { tool_mode("min") })
    out_min <- reactiveVal(FALSE)                       # tool OUTPUT panel minimized?
    observeEvent(input$ws_out_min,     { out_min(TRUE) })
    observeEvent(input$ws_out_restore, { out_min(FALSE) })
    observeEvent(input$tool_pick,       { out_min(FALSE) })

    .tool_title <- function() {
      t <- current_tool(); if (is.null(t)) return(NULL)
      if (startsWith(t, "dataop:")) return(sub("^dataop:", "", t))
      (MODUI[[t]] %||% TOOLS[[t]])$nm %||% t
    }
    # header buttons shared by the sidebar and the floating panel
    .tool_ctrls <- function(mode) tags$span(class = "ea-wsx-toolctl",
      if (identical(mode, "float"))
        tags$button(type = "button", title = "Dock to sidebar",
          onclick = sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("tool_dock")),
          HTML("&#9707;"))
      else
        tags$button(type = "button", title = "Float this tool",
          onclick = sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("tool_float")),
          HTML("&#9744;")),
      tags$button(type = "button", title = "Minimize to the dock",
        onclick = sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("tool_min")), "–"),
      tags$button(type = "button", title = "Close tool",
        onclick = sprintf("Shiny.setInputValue('%s','',{priority:'event'})", ns("tool_pick")), "×"))

    output$tool <- renderUI({
      t <- current_tool()
      if (is.null(t)) return(uiOutput(ns("tool_body")))
      m <- tool_mode()
      if (identical(m, "dock"))
        return(tagList(
          div(class = "ea-wsx-toolbar", span(class = "ea-wsx-toolnm", .tool_title()), .tool_ctrls("dock")),
          uiOutput(ns("tool_body"))))
      div(class = "ea-hint",
          if (identical(m, "float")) "This tool is floating over the canvas."
          else "This tool is minimized — reopen it from the dock on the right.",
          tags$button(class = "btn btn-sm btn-outline-success w-100 mt-2", type = "button",
            onclick = sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns("tool_dock")),
            "Dock it back"))
    })
    # Shows which tool is open (launched from Analysis) + a way to close it.
    output$active_tool_label <- renderUI({
      t <- current_tool()
      if (is.null(t)) return(span(class = "ea-wsx-atl-none", "No tool open — use ",
                                  tags$b("Analysis"), " in the menu bar"))
      nm <- .tool_title() %||% t     # strips the internal "dataop:" prefix
      tagList(
        span(class = "ea-wsx-atl", icon("gears"), nm),
        tags$button(class = "ea-wsx-atl-x", type = "button", title = "Close tool",
          onclick = sprintf("Shiny.setInputValue('%s','',{priority:'event'})", ns("tool_pick")), "×"))
    })
    output$tool_body <- renderUI({
      t <- current_tool()
      if (is.null(t)) return(div(class = "ea-hint",
        "Pick a tool above. Its settings load here; spatial ops add a layer, models drop a result (Step 4)."))
      # a single Data & Exploration operation, opened from the menu
      if (startsWith(t, "dataop:")) {
        op <- sub("^dataop:", "", t)
        body <- .data_op_ui(op)
        return(if (is.null(body))
                 div(class = "ea-hint", paste0("Could not load '", op, "'.")) else body)
      }
      mi <- MODUI[[t]]
      if (!is.null(mi)) {
        # Signal AFTER this panel has been sent to the browser. Bumping on
        # tool_pick alone was timing-fragile: the module's repopulate ran while
        # the panel still did not exist, the update was dropped, and nothing
        # bumped again. onFlushed fires once the flush carrying this UI is out,
        # so the update message that follows is processed AFTER the insert —
        # message order is what guarantees the element is there.
        session$onFlushed(function() tool_rendered(isolate(tool_rendered()) + 1),
                          once = TRUE)
      }
      if (!is.null(mi)) return(tagList(
        if (isTRUE(mi$map_based))
          div(class = "ea-wsx-mapnote2", icon("map-location-dot"),
              " Results are drawn on the workspace map and added to the Layers panel."),
        mi$tools(mi$id)))            # real migrated module's own settings panel
      spec <- TOOLS[[t]]; cols <- .cols()
      head <- div(class = "ea-wsx-toolhead",
        span(class = "ea-wsx-sw", style = "background:var(--forest);"),
        div(strong(spec$nm), div(class = "ea-wsx-toolg", spec$grp)))
      if (identical(spec$kind, "model")) {
        body <- tagList(
          selectInput(ns("resp"), "Response", choices = cols,
                      selected = .keep_sel("resp", cols, cols[1])),
          selectizeInput(ns("preds"), "Predictors", choices = cols, multiple = TRUE,
                         selected = .keep_sel("preds", cols, character(0), multi = TRUE),
                         options = list(plugins = list("remove_button"))))
      } else {
        rl <- .names(raster_pool); vl <- .names(vector_pool)
        body <- tagList(
          selectInput(ns("in_layer"), "Input raster",
                      choices  = if (length(rl)) rl else "(no raster loaded)",
                      selected = .keep_sel("in_layer", rl, NULL)),
          selectInput(ns("clip_to"), if (identical(t, "clip")) "Clip to" else "Sample at",
                      choices  = if (length(vl)) vl else "(no vector loaded)",
                      selected = .keep_sel("clip_to", vl, NULL)))
      }
      tagList(head, body,
        actionButton(ns("ws_run"), "Run", class = "btn-success w-100", icon = icon("play")))
    })
    # ---- Step 4: results store + dock + resizable pop-out mini-screens ----
    results <- reactiveVal(list())   # named list: {id,title,metrics(named chr),img,kind,open}
    runN    <- reactiveVal(0)

    # Results hold a base64 PNG each, so the store MUST be bounded — an unbounded
    # list is a genuine leak over a long session. Keep the most recent N.
    .WS_MAX_RESULTS <- 20L
    .push_result <- function(res, id) {
      r <- c(results(), setNames(list(res), id))
      if (length(r) > .WS_MAX_RESULTS) r <- utils::tail(r, .WS_MAX_RESULTS)
      results(r)
    }

    .plot_b64 <- function(draw, w = 460, h = 300) {
      f <- tempfile(fileext = ".png"); on.exit(unlink(f), add = TRUE)
      grDevices::png(f, width = w, height = h, bg = "white")
      tryCatch(draw(), error = function(e) { plot.new(); text(0.5, 0.5, "(no plot)") })
      grDevices::dev.off()
      paste0("data:image/png;base64,", base64enc::base64encode(f))
    }

    observeEvent(input$ws_run, {
      t <- current_tool(); req(t); spec <- TOOLS[[t]]
      runN(runN() + 1); id <- paste0("res", runN())
      if (identical(spec$kind, "model")) {
        ds <- dtName(); df <- tryCatch(dataset_pool[[ds]], error = function(e) NULL)
        resp <- input$resp; preds <- input$preds
        if (!is.data.frame(df) || !isTruthy(resp) || !length(preds)) {
          showNotification("Pick a response and at least one predictor.", type = "warning"); return()
        }
        ok <- tryCatch({
          d2 <- df[, c(resp, preds), drop = FALSE]
          d2[[resp]] <- suppressWarnings(as.numeric(d2[[resp]]))
          for (p in preds) if (!is.numeric(d2[[p]])) d2[[p]] <- suppressWarnings(as.numeric(as.factor(d2[[p]])))
          d2 <- d2[stats::complete.cases(d2), , drop = FALSE]
          if (identical(t, "rf")) {
            m <- randomForest::randomForest(reformulate(preds, resp), data = d2, ntree = 300)
            pred <- as.numeric(m$predicted)
          } else {
            m <- stats::lm(reformulate(preds, resp), data = d2); pred <- as.numeric(stats::fitted(m))
          }
          y <- d2[[resp]]
          ev <- tryCatch(uef_evaluation(pred, y), error = function(e) NULL)
          mets <- if (!is.null(ev)) c(`R2` = sprintf("%.3f", ev$R2), RMSE = sprintf("%.3f", ev$RMSE),
                                      Bias = sprintf("%.3f", ev$Bias), RRMSE = sprintf("%.1f%%", ev$RRMSE)) else character(0)
          img <- .plot_b64(function() {
            op <- par(mar = c(4,4,2.4,1)); on.exit(par(op))
            plot(y, pred, xlab = ea_xlab(paste("observed", resp)), ylab = ea_ylab("predicted"),
                 main = spec$nm, pch = 19, col = "#2E7D32")
            abline(0, 1, col = "#B08F5C", lwd = 2, lty = 2)
          })
          res <- list(id = id, title = spec$nm, metrics = mets, img = img, kind = "model", open = TRUE)
          .push_result(res, id); TRUE
        }, error = function(e) { showNotification(paste("Model failed:", conditionMessage(e)), type = "error"); FALSE })
        req(isTRUE(ok))
      } else {
        res <- list(id = id, title = spec$nm, kind = "spatial", open = TRUE,
                    metrics = c(status = "would add a layer"), img = NULL)
        .push_result(res, id)
      }
    })

    output$dock <- renderUI({
      rs <- results()
      # minimized TOOL chips (settings and/or output) park here too
      tchips <- tagList(
        if (!is.null(current_tool()) && identical(tool_mode(), "min"))
          tags$button(class = "ea-wsx-dchip", title = paste(.tool_title(), "settings"),
            onclick = .fire("tool_dock", "x"),
            span(class = "ea-wsx-dcw", style = "background:var(--canopy);"),
            span(class = "ea-wsx-dcl", "Settings")),
        if (!is.null(current_tool()) && isTRUE(out_min()))
          tags$button(class = "ea-wsx-dchip", title = paste(.tool_title(), "output"),
            onclick = .fire("ws_out_restore", "x"),
            span(class = "ea-wsx-dcw", style = "background:var(--forest);"),
            span(class = "ea-wsx-dcl", "Output")))
      if (!length(rs)) return(tagList(tchips,
        if (is.null(current_tool()) || (!identical(tool_mode(), "min") && !isTRUE(out_min())))
          div(class = "ea-wsx-dockhint", "results park here")))
      tagList(tchips, lapply(rs, function(r)
        tags$button(class = paste("ea-wsx-dchip", if (isTRUE(r$open)) "open" else ""),
          onclick = .fire("ws_chip", r$id), title = r$title,
          span(class = "ea-wsx-dcw", style = "background:var(--forest);"),
          span(class = "ea-wsx-dcl", substr(r$title, 1, 10)))))
    })
    observeEvent(input$ws_chip,  { rs <- results(); id <- input$ws_chip
      if (!is.null(rs[[id]])) { rs[[id]]$open <- !isTRUE(rs[[id]]$open); results(rs) } })
    observeEvent(input$ws_min,   { rs <- results(); if (!is.null(rs[[input$ws_min]])) { rs[[input$ws_min]]$open <- FALSE; results(rs) } })
    observeEvent(input$ws_close, { rs <- results(); rs[[input$ws_close]] <- NULL; results(rs) })
    observeEvent(input$ws_tool_close, { current_tool(NULL) })

    output$panels <- renderUI({
      # The ACTIVE TOOL's own output renders as a pop-out panel over the canvas —
      # the canvas itself stays the map / chart (new design).
      t0 <- current_tool()
      if (!is.null(t0) && startsWith(t0, "dataop:")) t0 <- NULL   # ETL ops have no own canvas
      mi0 <- if (!is.null(t0)) MODUI[[t0]] else NULL
      # DEFAULT = sidebar controls + results in the CENTRE. A tool only becomes a
      # floating pop-out when the user asks for it (the float button), or when a
      # map tool needs the map to stay in the centre.
      if (!is.null(mi0) && !identical(tool_mode(), "float")) mi0 <- NULL
      # The tool's OUTPUT panel floats only when the centre is taken by the MAP.
      # In Data view the results render in the middle instead (see .data_ui()).
      # MAP-BASED tools never render their own canvas: THE WORKSPACE MAP IS THE
      # MAP. Their outputs land in raster_pool/vector_pool and are drawn on it.
      in_data_view <- identical(wsview(), "data")
      if (!is.null(mi0) && isTRUE(mi0$map_based)) mi0 <- NULL
      tool_panel <- if (!is.null(mi0) && !isTRUE(out_min()) && !in_data_view)
        div(class = "ea-wsx-panel ea-wsx-panel-tool",
        style = "left:16px; top:12px;",
        div(class = "ea-wsx-ph", span(class = "ea-wsx-sw", style = "background:var(--forest);"),
            paste0(mi0$nm, " — output"),
            span(class = "ea-wsx-px",
              tags$button(onclick = .fire("ws_out_min", "x"), title = "minimize", "–"),
              tags$button(onclick = .fire("ws_tool_close", "x"), title = "close tool", "×"))),
        div(class = "ea-wsx-pb", mi0$canvas(mi0$id))) else NULL

      # The tool's SETTINGS, floated out of the sidebar on request.
      settings_floater <- if (!is.null(t0) && identical(tool_mode(), "float"))
        div(class = "ea-wsx-panel", style = "right:24px; left:auto; top:16px; width:330px; height:440px;",
          div(class = "ea-wsx-ph", span(class = "ea-wsx-sw", style = "background:var(--canopy);"),
              paste0(.tool_title(), " — settings"), .tool_ctrls("float")),
          div(class = "ea-wsx-pb", uiOutput(ns("tool_body")))) else NULL

      open <- Filter(function(r) isTRUE(r$open), results())
      if (is.null(tool_panel) && is.null(settings_floater) && !length(open)) return(NULL)
      i <- 0
      tagList(tool_panel, settings_floater, lapply(open, function(r) { i <<- i + 1
        div(class = "ea-wsx-panel", style = sprintf("left:%dpx; top:%dpx;", 18 + (i-1)*26, 14 + (i-1)*26),
          div(class = "ea-wsx-ph", span(class = "ea-wsx-sw", style = "background:var(--forest);"), r$title,
            span(class = "ea-wsx-px",
              tags$button(onclick = .fire("ws_min", r$id), title = "minimize", "–"),
              tags$button(onclick = .fire("ws_close", r$id), title = "close", "×"))),
          div(class = "ea-wsx-pb",
            if (!is.null(r$img)) tags$img(src = r$img)
            else div(class = "ea-hint", "Spatial op — would add a layer to the Map view."),
            if (length(r$metrics)) div(class = "ea-wsx-pmet",
              lapply(seq_along(r$metrics), function(k)
                tags$span(tags$u(names(r$metrics)[k]), tags$b(unname(r$metrics)[k]))))))
      }))
    })

    # Free this module's own retained state on disconnect (results hold base64
    # PNGs; cran_index/cran_full can be tens of MB).
    session$onSessionEnded(function() {
      tryCatch({ results(list()); cran_index(NULL); cran_full(NULL) }, error = function(e) NULL)
      gc(FALSE)
    })

    list(context  = reactive("Unified workspace (beta scaffold)."),
         plot_ctx  = reactive({ t <- current_tool(); if (is.null(t)) "workspace" else t }),
         # server.R watches this to re-arm module selector population. It counts
         # PANEL RENDERS, not tool picks: the panel has to exist before the
         # repopulate is worth sending.
         tool_open = reactive(tool_rendered()))
  })
}
