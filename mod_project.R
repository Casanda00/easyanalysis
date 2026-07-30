# ==========================================================================
# mod_project.R  --  inside a project (view "project")
# --------------------------------------------------------------------------
# The screen the user lands on straight after creating a project: the project
# NAME on top, then ONE door for any file type (landing concept D). Once data
# exists it becomes a short summary that points at the work screens.
# Uploads and sample data are handed back to server.R so they run through the
# same ingestion as the left rail.
# ==========================================================================

projectCanvasUI <- function(id) {
  ns <- NS(id)
  div(class = "ea-project", uiOutput(ns("body")))
}

# LEFT rail on the project Overview: a PURELY INFORMATIONAL list of what's in the
# project (no upload / switch controls — this is not the workspace Datasets rail).
projectLeftUI <- function(id) {
  ns <- NS(id)
  div(class = "ea-project-left",
    h6("Project data"),
    uiOutput(ns("data_list"))
  )
}

projectToolsUI <- function(id) {
  ns <- NS(id)
  # The per-type counts are NOT repeated here — they already show in the canvas
  # ("What's in here") and the left rail. This panel is just Help / about.
  fire <- function(inp) sprintf("Shiny.setInputValue('%s', Date.now(), {priority:'event'})", ns(inp))
  tagList(
    div(class = "ea-tools-block",
      h6("More info"),
      tags$button(type = "button", class = "ea-help-btn", onclick = fire("about"),
                  icon("circle-info", style = "color:var(--sky)"), " About EasyAnalysis"),
      tags$button(type = "button", class = "ea-help-btn", onclick = fire("docs"),
                  icon("book", style = "color:var(--canopy)"), " Documentation"),
      tags$button(type = "button", class = "ea-help-btn", onclick = fire("version"),
                  icon("code-branch", style = "color:var(--forest)"), " Version & release"),
      tags$button(type = "button", class = "ea-help-btn", onclick = fire("cite"),
                  icon("quote-right", style = "color:var(--sky)"), " How to cite")
    )
  )
}

# meta        : reactive -> project metadata list (or NULL)
# counts      : reactive -> list(tables=chr, rasters=chr, las=chr, vectors=chr)
# on_files    : function(files_df)  ingest an upload
# on_sample   : function(kind)      load bundled sample data
# on_rename   : function(new_name)
# switch_view : function(view)
projectServer <- function(id, meta, counts, on_files, on_sample, on_rename, on_delete,
                          switch_view) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    has_data <- reactive({
      cn <- counts()
      length(cn$tables) + length(cn$rasters) + length(cn$las) + length(cn$vectors) > 0
    })

    output$body <- renderUI({
      m <- meta()
      if (is.null(m)) {
        return(div(class = "ea-hint",
                   "No project is open. Go to ", strong("Projects"), " to open or create one."))
      }
      if (has_data()) .project_loaded(ns, m, counts()) else .project_empty(ns, m)
    })

    # Left rail: the CATEGORISED data — each type as a section with its items.
    output$data_list <- renderUI({
      cn <- counts(); if (is.null(cn)) return(NULL)
      row <- function(nm, colour) div(class = "ea-pd-item", style = "display:flex; align-items:center; justify-content:space-between;",
        div(style = "display:flex; align-items:center; gap:6px; overflow:hidden;",
          span(class = "ea-pd-dot", style = paste0("background:", colour, ";")),
          span(class = "ea-pd-nm", title = nm, nm)),
        tags$span("×",
          title = paste0("Remove '", nm, "' from this project"),
          style = "cursor:pointer; color:#dc3545; font-weight:bold; padding:0 4px; flex-shrink:0;",
          onclick = sprintf(
            "event.stopPropagation(); if(confirm('Remove \\'%s\\' from this project?\\n\\nYour original file on disk is not deleted.')) eaSetInput('delete_dataset', {val:%s, t:Date.now()});",
            gsub("'", "", nm), jsonlite::toJSON(nm, auto_unbox = TRUE))))
      sec <- function(label, names, colour) {
        if (!length(names)) return(NULL)
        div(class = "ea-pd-cat",
          div(class = "ea-pd-cat-h", label, span(class = "ea-pd-cat-n", length(names))),
          lapply(names, function(n) row(n, colour)))
      }
      secs <- Filter(Negate(is.null), list(
        sec("Tables",       cn$tables,  "var(--sky)"),
        sec("Rasters",      cn$rasters, "var(--forest)"),
        sec("Point clouds", cn$las,     "var(--earth)"),
        sec("Vectors",      cn$vectors, "#B07CC6")
      ))
      if (!length(secs)) return(div(class = "ea-hint", "No data yet."))
      div(class = "ea-pd-cats", secs)
    })

    # ---- More-info panel actions ----
    observeEvent(input$docs, switch_view("docs"))
    observeEvent(input$about, {
      showModal(modalDialog(title = NULL, easyClose = TRUE, footer = modalButton("Close"),
        div(class = "about-logo-mark", icon("lightbulb")),
        div(tags$span(class = "about-name", "EasyAnalysis"),
            tags$span(class = "about-version", paste0("v", APP_VERSION))),
        p(class = "about-tagline", "A universal, local-first scientific analysis platform."),
        p(style = "font-size:12.5px; color:var(--bark); line-height:1.5;",
          "Upload your data and run statistical, machine-learning and spatial / LiDAR ",
          "analyses point-and-click, with plain-English results — no code. Everything runs ",
          "on your own computer; your data never leaves your machine."),
        p(style = "font-size:12px; color:var(--bark); margin-top:8px;",
          strong("University of Eastern Finland"), " — code contributions and data for testing.")))
    })
    observeEvent(input$version, {
      showModal(modalDialog(title = "EasyAnalysis", easyClose = TRUE, footer = modalButton("Close"),
        div(class = "ea-hint", HTML(paste0("Version <b>", APP_VERSION, "</b> — local-first release."))),
        p(style = "margin-top:10px;",
          "A local-first platform for statistics, machine learning and spatial / LiDAR ",
          "analysis — point-and-click, with plain-English results. It runs entirely on ",
          "your computer; your data never leaves your machine.")))
    })
    observeEvent(input$cite, {
      showModal(modalDialog(title = "How to cite EasyAnalysis", easyClose = TRUE, footer = modalButton("Close"),
        p("If EasyAnalysis contributed to your work, please cite it ",
          "(a formal CITATION.cff is being prepared):"),
        tags$pre(paste0("EasyAnalysis (v", APP_VERSION, "). University of Eastern Finland."))))
    })

    observeEvent(input$files,     { req(input$files);     on_files(input$files) })
    observeEvent(input$add_files, { req(input$add_files); on_files(input$add_files) })
    observeEvent(input$s_table,  on_sample("table"))
    observeEvent(input$s_raster, on_sample("raster"))
    observeEvent(input$s_las,    on_sample("las"))

    # "Open project" enters the unified WORKSPACE (Map view + Data view). The old
    # per-screen views are still reachable from the top menubar during migration.
    observeEvent(input$go_data, { switch_view("workspace") })
    observeEvent(input$go_projects, switch_view("projects"))

    # rename in place
    observeEvent(input$rename, {
      m <- meta(); req(m)
      showModal(modalDialog(
        title = "Rename project",
        textInput(ns("rename_to"), "Project name", value = m$name %||% "", width = "100%"),
        footer = tagList(modalButton("Cancel"),
                         actionButton(ns("rename_go"), "Rename", class = "btn-success")),
        easyClose = TRUE
      ))
    })
    observeEvent(input$rename_go, {
      nm <- trimws(input$rename_to %||% "")
      if (nzchar(nm)) on_rename(nm)
      removeModal()
    })

    # delete this project (confirmed)
    observeEvent(input$delete, {
      m <- meta(); req(m)
      showModal(modalDialog(
        title = "Delete project",
        div(HTML(sprintf("Delete <b>%s</b> and everything in it?",
                         htmltools::htmlEscape(m$name %||% "this project")))),
        div(class = "ea-hint mt-2",
            "This removes the project folder from your computer. Files you loaded from ",
            "elsewhere are not touched."),
        footer = tagList(modalButton("Cancel"),
                         actionButton(ns("delete_go"), "Delete project", class = "btn-danger")),
        easyClose = TRUE
      ))
    })
    observeEvent(input$delete_go, { removeModal(); on_delete() })

    # Save this project as a shareable .eap (the .ea-eap-save JS turns this into
    # a native "choose where to save" dialog; plain download otherwise).
    output$export <- downloadHandler(
      filename = function() {
        m <- meta()
        paste0(if (!is.null(m)) ea_slug(m$name %||% m$id %||% "project") else "project",
               ".eap")
      },
      content = function(file) {
        m <- meta(); req(m)
        ea_project_export(m$id, file)
      }
    )

    list(context = reactive({
      m <- meta(); cn <- counts()
      if (is.null(m)) return("No project open.")
      paste0("Project '", m$name %||% "", "': ", length(cn$tables), " table(s), ",
             length(cn$rasters), " raster(s), ", length(cn$las), " point cloud(s), ",
             length(cn$vectors), " vector(s).")
    }))
  })
}

# ---- views ----------------------------------------------------------------

.ea_types <- c(".csv", ".xlsx", ".tif", ".las / .laz", ".gpkg", ".geojson", ".shp")

# Where you are + what you can do to the project itself.
# with_actions = TRUE adds the two PRIMARY actions (Open project / Add more data)
# as a centred cluster in the middle, BEFORE the management actions on the right.
.project_bar <- function(ns, with_actions = FALSE) {
  div(class = "ea-page-bar",
    actionLink(ns("go_projects"), "← Projects", class = "where back"),
    div(class = "acts",
      # Primary actions sit WITH the other buttons (before Rename), matching the
      # bar-button styling. They are NOT in the left rail (which is informational
      # only). "Add more data" triggers a hidden fileInput — same reliable pattern
      # as Import .eap — routed to on_files via input$add_files.
      if (with_actions) actionButton(ns("go_data"), "Open project", class = "ea-barbtn go",
                                     icon = icon("arrow-right-to-bracket")),
      if (with_actions) tags$span(class = "ea-addfile",
        tags$button(type = "button", class = "ea-barbtn",
          onclick = sprintf("document.getElementById('%s').click()", ns("add_files")),
          tags$i(class = "fa fa-plus"), " Add more data"),
        tags$span(class = "ea-hidden-file",
          fileInput(ns("add_files"), NULL, multiple = TRUE, width = "1px"))),
      # Rename is intentionally NOT here — it lives next to the project name.
      downloadButton(ns("export"), "Save as .eap",
                     class = "ea-barbtn ea-eap-save", icon = icon("floppy-disk")),
      actionButton(ns("delete"), "Delete project", class = "ea-barbtn danger")
    )
  )
}

.project_empty <- function(ns, m) {
  div(
    div(class = "ea-np-head",
      .project_bar(ns),
      div(class = "kicker", "New project"),
      h2(class = "ea-np-name",
         m$name %||% "Untitled project",
         actionButton(ns("rename"), "Rename", class = "btn btn-sm ea-rename")),
      p(class = "sub",
        "Start with whatever you have. EasyAnalysis works out what your file is ",
        "and what you can do with it — no exporting to another program.")
    ),

    div(class = "ea-drop",
      div(class = "big", "Drop your first file here, or browse"),
      div(class = "types", lapply(.ea_types, function(t) span(class = "ty", t))),
      div(class = "ea-drop-input",
          fileInput(ns("files"), NULL, multiple = TRUE, width = "100%",
                    buttonLabel = "Browse files", placeholder = "no file selected")),
      div(class = "samples",
        span("Nothing handy?"),
        actionButton(ns("s_table"),  "Forest plots (table)", class = "btn btn-sm ea-chipbtn"),
        actionButton(ns("s_raster"), "Canopy raster",        class = "btn btn-sm ea-chipbtn"),
        actionButton(ns("s_las"),    "LiDAR tile",           class = "btn btn-sm ea-chipbtn")
      )
    ),

    div(class = "ea-sect", span("What happens next")),
    div(class = "ea-typemap",
      .tm_card("A table", "#3E7CB1",
               c("Clean and explore it", "Test differences, fit models",
                 "Predict with machine learning")),
      .tm_card("A raster or image", "#2E7D32",
               c("Map it, crop, reproject", "Vegetation & water indices",
                 "Classify land cover")),
      .tm_card("A point cloud", "#8A6A3B",
               c("Terrain and canopy surfaces", "Individual tree detection",
                 "Plot metrics you can model"))
    )
  )
}

.tm_card <- function(title, colour, bullets) {
  div(class = "ea-tm",
    div(class = "hd",
        span(class = "sw", style = paste0("background:", colour, ";")),
        strong(title)),
    tags$ul(lapply(bullets, tags$li))
  )
}

.project_loaded <- function(ns, m, cn) {
  # One small card per file in the project (no category headers here — the
  # categorised view is the left rail).
  # Each file card carries its own remove button. `delete_dataset` is the
  # APP-level handler in server.R (it finds the right pool), and eaSetInput
  # queues the click if the socket is not up yet.
  fcard <- function(nm, type_label, colour) div(class = "ea-fcard",
    span(class = "ea-fcard-dot", style = paste0("background:", colour, ";")),
    div(class = "ea-fcard-body",
      div(class = "ea-fcard-nm", title = nm, nm),
      div(class = "ea-fcard-ty", type_label)),
    tags$button(class = "ea-fcard-x", type = "button",
      title = paste0("Remove '", nm, "' from this project"),
      onclick = sprintf(
        "event.stopPropagation(); if(confirm('Remove \\'%s\\' from this project?\\n\\nYour original file on disk is not deleted.')) eaSetInput('delete_dataset', {val:%s, t:Date.now()});",
        gsub("'", "", nm), jsonlite::toJSON(nm, auto_unbox = TRUE)),
      HTML("&times;")))
  cards <- c(
    lapply(cn$tables,  function(n) fcard(n, "Table",       "var(--sky)")),
    lapply(cn$rasters, function(n) fcard(n, "Raster",      "var(--forest)")),
    lapply(cn$las,     function(n) fcard(n, "Point cloud", "var(--earth)")),
    lapply(cn$vectors, function(n) fcard(n, "Vector",      "#B07CC6"))
  )
  div(
    div(class = "ea-np-head",
      .project_bar(ns, with_actions = TRUE),
      div(class = "kicker", "Project"),
      h2(class = "ea-np-name",
         m$name %||% "Untitled project",
         actionButton(ns("rename"), "Rename", class = "btn btn-sm ea-rename")),
      div(class = "ea-np-meta", paste0(
        if (isTruthy(m$created)) paste0("Created ", .ea_when(m$created), "   ·   ") else "",
        "Last opened ", .ea_when(m$modified)))
    ),
    div(class = "ea-sect", span("Project data")),
    if (length(cards)) div(class = "ea-filecards", cards)
    else div(class = "ea-hint", "No data yet — add data from the bar to get started.")
  )
}

.list_card <- function(title, items) {
  div(class = "ea-tm",
    div(class = "hd", strong(title), span(class = "n", length(items))),
    if (!length(items)) div(class = "none", "none yet")
    else tags$ul(lapply(utils::head(items, 6), tags$li)),
    if (length(items) > 6) div(class = "none", sprintf("+ %d more", length(items) - 6))
  )
}
