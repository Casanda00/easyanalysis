# ==========================================================================
# mod_projects.R  --  Projects screen (the app's FIRST view)
# --------------------------------------------------------------------------
# projectsCanvasUI / projectsToolsUI / projectsServer, per the module contract.
# Two states, both designed in the approved mockups:
#   - no projects yet  -> a single invitation to create the first one
#   - projects exist   -> cards (newest first); clicking one opens it
# Persistence lives in project_store.R; this module is UI + wiring only.
# ==========================================================================

projectsCanvasUI <- function(id) {
  ns <- NS(id)
  # This is a plain uiOutput PLUS pre-rendered content. Shiny replaces the
  # children as soon as the session's renderUI arrives, but until then the user
  # already sees the real page — instead of an empty panel while the app wires
  # up ~35 module servers. Requires `ui` to be a function(request) (ui.R) so
  # this runs per page load rather than once at startup.
  initial <- tryCatch({
    ps <- ea_project_list()
    if (!length(ps)) .projects_empty(ns) else .projects_grid(ns, ps, NULL)
  }, error = function(e) NULL)
  div(class = "ea-projects",
      tags$div(id = ns("body"), class = "shiny-html-output", initial))
}

# LEFT rail on the Projects screen: project-level navigation + counts. (Shown
# in place of the normal Datasets rail; see ui.R view-projects CSS.)
projectsLeftUI <- function(id) {
  ns <- NS(id)
  # No "+ New project" here — it lives only in the centre (page bar + Welcome
  # header), per the design. This panel is pure navigation / counts.
  div(class = "ea-projleft",
    h6("Projects"),
    uiOutput(ns("nav"))
  )
}

# RIGHT tools panel: the selected project + help.
projectsToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "ea-tools-block",
      h6("Selected project"),
      uiOutput(ns("selected"))
    ),
    div(class = "ea-tools-block",
      h6("Help"),
      actionButton(ns("go_docs"), "Documentation", class = "btn-outline-secondary btn-sm w-100 mb-1",
                   icon = icon("book")),
      actionButton(ns("go_cite"), "How to cite", class = "btn-outline-secondary btn-sm w-100",
                   icon = icon("quote-right"))
    )
  )
}

# open_project  : function(id) called when the user opens a project
# refresh_token : reactive bumped by server.R when the project list changes
projectsServer <- function(id, current_project, open_project, refresh_token,
                           switch_view = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Local bump so this module re-renders after its own create/rename/delete.
    bump <- reactiveVal(0)
    projects <- reactive({
      bump(); refresh_token()
      ea_project_list()
    })

    sel <- reactiveVal(NULL)     # highlighted (not necessarily opened) project

    # ---- canvas -----------------------------------------------------------
    output$body <- renderUI({
      ps <- projects()
      if (!length(ps)) return(.projects_empty(ns))
      .projects_grid(ns, ps, sel())
    })

    output$nav <- renderUI({
      ps <- projects()
      n_tab <- sum(vapply(ps, function(p) as.integer(p$n_datasets %||% 0), integer(1)))
      n_sp  <- sum(vapply(ps, function(p) as.integer(p$n_spatial  %||% 0), integer(1)))
      loc <- ea_projects_dir()
      tagList(
        div(class = "ea-kv",
          div(span("All projects"),   span(class = "num", length(ps))),
          div(span("Datasets"),       span(class = "num", n_tab)),
          div(span("Spatial layers"), span(class = "num", n_sp))
        ),
        div(class = "ea-loc",
          div(class = "lab", "Projects folder"),
          div(class = "val", title = loc, loc)
        )
      )
    })

    output$selected <- renderUI({
      s <- sel(); ps <- projects()
      if (!isTruthy(s)) return(div(class = "ea-hint", "Click a project to see its details."))
      m <- Filter(function(p) identical(p$id, s), ps)
      if (!length(m)) return(div(class = "ea-hint", "Click a project to see its details."))
      m <- m[[1]]
      tagList(
        div(class = "ea-kv",
          div(span("Datasets"),       span(class = "num", m$n_datasets %||% 0)),
          div(span("Spatial layers"), span(class = "num", m$n_spatial %||% 0)),
          div(span("Last opened"),    span(class = "path", .ea_when(m$modified)))
        ),
        (function(){ p <- ea_project_path(m$id)
          div(class = "ea-loc",
            div(class = "lab", "Location"),
            div(class = "val", title = p, p)) })(),
        actionButton(ns("open_sel"), "Open project", class = "btn-success w-100 mt-2",
                     icon = icon("folder-open")),
        actionButton(ns("dup_sel"), "Duplicate", class = "btn-outline-secondary btn-sm w-100 mt-1",
                     icon = icon("copy")),
        downloadButton(ns("export"), "Save as .eap",
          class = "btn-outline-secondary btn-sm w-100 mt-1 ea-eap-save",
          icon = icon("floppy-disk"))
      )
    })

    # ---- select / open ----------------------------------------------------
    observeEvent(input$pick, { sel(input$pick) })
    observeEvent(input$open, { open_project(input$open) })
    observeEvent(input$open_sel, { req(sel()); open_project(sel()) })
    observeEvent(input$dup_sel, {
      req(sel())
      nid <- tryCatch(ea_project_duplicate(sel()), error = function(e) NULL)
      if (is.null(nid)) { showNotification("Could not duplicate the project.", type = "error"); return() }
      bump(bump() + 1); sel(nid)
      showNotification("Project duplicated.", type = "message", duration = 3)
    })

    # ---- export selected project -> .eap (browser download) --------------
    # A downloadHandler streams the zipped project; the browser saves it. No OS
    # dialog. filename() gives it the .eap name; content() zips the folder.
    output$export <- downloadHandler(
      filename = function() {
        m <- Filter(function(p) identical(p$id, sel()), projects())
        nm <- if (length(m)) ea_slug(m[[1]]$name %||% sel()) else "project"
        paste0(nm, ".eap")
      },
      content = function(file) {
        req(sel())
        ea_project_export(sel(), file)
      }
    )

    # ---- import an .eap -> new project (browser file picker) -------------
    observeEvent(input$import_file, {
      fi <- input$import_file; req(fi)
      src <- fi$datapath[1]                      # temp path of the uploaded .eap
      nid <- tryCatch(ea_project_import(src), error = function(e) NULL)
      if (is.null(nid)) {
        showNotification("That doesn't look like an EasyAnalysis project (.eap).",
                         type = "error"); return()
      }
      bump(bump() + 1); sel(nid)
      showNotification("Project imported.", type = "message", duration = 3)
    })

    # ---- create -----------------------------------------------------------
    show_new <- function() {
      showModal(modalDialog(
        title = NULL, size = "l", easyClose = TRUE, footer = NULL,
        div(class = "ea-newproj",
          div(class = "kicker", "New project"),
          h2("Name your project."),
          p(class = "sub",
            "Everything you load and every analysis you run is kept here — so you can ",
            "close the app, come back, and pick up exactly where you stopped."),

          div(class = "field",
            tags$label("Project name", `for` = ns("new_name")),
            textInput(ns("new_name"), NULL, value = "",
                      placeholder = "e.g. Trafficability 2026", width = "100%"),
            div(class = "ea-locpick-hint",
                "You can save the project as a shareable .eap file anywhere later, ",
                "from the project's ", tags$b("Save as .eap"), " button.")
          ),

          div(class = "ea-newproj-what",
            div(class = "w",
              div(class = "t", "Your data, together"),
              div(class = "d", "Tables, rasters, point clouds and vectors in one place.")),
            div(class = "w",
              div(class = "t", "Saved as you work"),
              div(class = "d", "Kept on your computer — nothing is uploaded anywhere.")),
            div(class = "w",
              div(class = "t", "Ready to cite"),
              div(class = "d", "Your analyses and results stay attached to the project."))
          ),

          div(class = "ea-newproj-foot",
            actionButton(ns("cancel_new"), "Cancel", class = "ea-barbtn"),
            actionButton(ns("create_go"), "Create project",
                         class = "btn-success btn-lg ea-cta", icon = icon("plus"))
          )
        )
      ))
    }
    observeEvent(input$cancel_new, removeModal())
    observeEvent(input$new_project, show_new())
    observeEvent(input$new_first,   show_new())

    observeEvent(input$create_go, {
      nm <- trimws(input$new_name %||% "")
      if (!nzchar(nm)) nm <- "Untitled project"
      # Projects live in the managed default location; the user chooses WHERE to
      # save only when they export the .eap (native save dialog).
      pid <- tryCatch(ea_project_create(nm), error = function(e) NULL)
      removeModal()
      if (is.null(pid)) {
        showNotification("Could not create the project folder. Check disk permissions.",
                         type = "error")
        return()
      }
      bump(bump() + 1)
      open_project(pid)
    })

    # ---- rename -----------------------------------------------------------
    .show_rename <- function() {
      req(sel())
      cur <- Filter(function(p) identical(p$id, sel()), projects())
      showModal(modalDialog(
        title = "Rename project",
        textInput(ns("rename_to"), "Project name",
                  value = if (length(cur)) cur[[1]]$name else "", width = "100%"),
        footer = tagList(modalButton("Cancel"),
                         actionButton(ns("rename_go"), "Rename", class = "btn-success")),
        easyClose = TRUE
      ))
    }
    observeEvent(input$rename_sel, .show_rename())
    observeEvent(input$ask_rename, { sel(input$ask_rename); .show_rename() })
    observeEvent(input$rename_go, {
      req(sel()); nm <- trimws(input$rename_to %||% "")
      if (nzchar(nm)) ea_project_rename(sel(), nm)
      removeModal(); bump(bump() + 1)
    })

    # ---- delete (confirmed) ----------------------------------------------
    .show_delete <- function() {
      req(sel())
      cur <- Filter(function(p) identical(p$id, sel()), projects())
      nm  <- if (length(cur)) cur[[1]]$name else sel()
      showModal(modalDialog(
        title = "Delete project",
        div(HTML(sprintf("Delete <b>%s</b> and everything in it?", htmltools::htmlEscape(nm)))),
        div(class = "ea-hint mt-2", "This removes the project folder from your computer. ",
            "Your original data files are not touched."),
        footer = tagList(modalButton("Cancel"),
                         actionButton(ns("delete_go"), "Delete project", class = "btn-danger")),
        easyClose = TRUE
      ))
    }
    observeEvent(input$delete_sel, .show_delete())
    observeEvent(input$ask_delete, { sel(input$ask_delete); .show_delete() })
    observeEvent(input$delete_go, {
      req(sel())
      gone <- sel()
      ea_project_delete(gone)
      if (identical(current_project(), gone)) current_project(NULL)
      sel(NULL); removeModal(); bump(bump() + 1)
      showNotification("Project deleted.", type = "message", duration = 3)
    })

    # ---- help shortcuts ---------------------------------------------------
    if (!is.null(switch_view)) {
      observeEvent(input$go_docs, switch_view("docs"))
      observeEvent(input$go_cite, switch_view("docs"))
    }

    list(context = reactive({
      ps <- projects()
      paste0("Projects screen. ", length(ps), " project(s) saved on this computer.")
    }))
  })
}

# ---- view helpers ---------------------------------------------------------

# onclick that sets a Shiny input without also triggering the card's own click.
.set_in <- function(input_id, value) {
  sprintf("event.stopPropagation();event.preventDefault();eaSetInput('%s', %s);return false;",
          input_id, jsonlite::toJSON(value, auto_unbox = TRUE))
}

.ea_when <- function(ts) {
  if (!isTruthy(ts)) return("—")
  t <- suppressWarnings(as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%S"))
  if (is.na(t)) return(as.character(ts))
  secs <- as.numeric(difftime(Sys.time(), t, units = "secs"))
  if (secs < 90)      return("just now")
  if (secs < 3600)    return(sprintf("%d min ago", round(secs / 60)))
  if (secs < 86400)   return(sprintf("%d h ago",   round(secs / 3600)))
  if (secs < 86400*7) return(sprintf("%d d ago",   round(secs / 86400)))
  format(t, "%d %b %Y")
}

.projects_empty <- function(ns) {
  tagList(
    .projects_bar(ns, show_new = FALSE),
    div(class = "ea-firstrun",
      h3("Welcome to EasyAnalysis."),
      p(class = "sub",
        "Analyse data, build models and map results — without moving between programs."),
      div(class = "ea-firstrun-card",
        div(class = "big", "You don't have any projects yet"),
        p("A project keeps your data, your analyses and your results together, so you",
          " can come back to them and cite them later."),
        actionButton(ns("new_first"), "Create your first project",
                     class = "btn-success btn-lg ea-cta", icon = icon("plus"))
      )
    )
  )
}

# The slim bar the mockup puts above the canvas: where you are, plus the two
# things this screen is for.
.projects_bar <- function(ns, show_new = TRUE) {
  div(class = "ea-page-bar",
    span(class = "where", "Projects"),
    div(class = "acts",
      # Import reuses the browser's own file picker (same mechanism as data
      # upload) — reliable, no OS dialog. A styled button triggers the hidden
      # fileInput; the chosen .eap uploads to a temp path we then import.
      tags$span(class = "ea-import",
        tags$button(type = "button", class = "ea-barbtn",
          onclick = sprintf("document.getElementById('%s').click()", ns("import_file")),
          tags$i(class = "fa fa-file-import"), " Import .eap"),
        tags$span(class = "ea-hidden-file",
          fileInput(ns("import_file"), NULL, accept = c(".eap", ".zip"),
                    width = "1px"))),
      if (show_new)
        actionButton(ns("new_project"), "+ New project", class = "ea-barbtn go")
    )
  )
}

.projects_grid <- function(ns, ps, selected) {
  cards <- lapply(ps, function(p) {
    pid  <- p$id
    kinds <- c(if ((p$n_datasets %||% 0) > 0) "TABLE",
               if ((p$n_spatial  %||% 0) > 0) "SPATIAL")
    # A SINGLE click opens the project (the screen's own hint says "click a card
    # to open it", and there is no longer a side panel that used the selection —
    # requiring a double-click just looked broken).
    # eaSetInput() queues the click if the websocket is not up yet — this screen
    # is pre-rendered, so a plain setInputValue on the FIRST click was lost.
    div(class = paste("ea-proj", if (identical(pid, selected)) "sel" else ""),
        onclick = sprintf("eaSetInput('%s', %s);",
                          ns("open"), jsonlite::toJSON(pid, auto_unbox = TRUE)),
      div(class = "ea-proj-body",
        div(class = "nm", p$name %||% pid),
        div(class = "when", .ea_when(p$modified)),
        div(class = "chips",
          lapply(kinds, function(k) span(class = "chip", k)),
          if (!length(kinds)) span(class = "chip empty", "EMPTY")
        )
      ),
      # Actions live on the card itself — the Projects screen has no side panel.
      div(class = "ea-proj-open",
        tags$a(href = "#", class = "go",
               onclick = .set_in(ns("open"), pid), "Open →"),
        tags$a(href = "#", class = "muted",
               onclick = .set_in(ns("ask_rename"), pid), "Rename"),
        tags$a(href = "#", class = "muted danger",
               onclick = .set_in(ns("ask_delete"), pid), "Delete")
      )
    )
  })
  tagList(
    .projects_bar(ns),
    div(class = "ea-ws-head",
      div(h3("Welcome back."), p("Pick up where you left off, or start something new.")),
    ),
    div(class = "ea-sect", span("Your projects"),
        span(class = "hint", "click a card to open it")),
    div(class = "ea-proj-grid", cards)
  )
}
