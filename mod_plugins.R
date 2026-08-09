# ==========================================================================
# mod_plugins.R -- the Plugin menu
# --------------------------------------------------------------------------
# External tool packs are OPT-IN. WhiteboxTools is somebody else's work -- Prof.
# John Lindsay's, wrapped for R by Qiusheng Wu and Andrew Brown -- and it makes
# this platform stronger without being part of it. So it is presented as a
# provider the user enables, with the authors named, rather than as a feature
# that silently appeared.
#
# Individual tools are activated one at a time, because binding an algorithm
# module costs 33 ms (measured) and 484 of them would add ~16 s to every session
# start. Search covers the whole catalogue whether or not a tool is active, so
# nothing is hidden -- a user searches for what they want and enables it from the
# result. That is the design that keeps the app fast without shrinking it.
# ==========================================================================

# ---- the dialog ----------------------------------------------------------
# A DIALOG, not a screen. Managing plugins is a settings action: it should not
# take the canvas or displace the tool panel, which is what the first version did.
# Built on ea_settings_modal() (helpers.R) so Packages, Plugins and Preferences
# share one shape.
#
# The search box is a REAL input placed in the shell, not inside the reactive
# body: rebuilding a text field on every keystroke wipes it mid-edit (gotcha 21).
# Only the card and the results list are uiOutput()s.
.plugins_dialog <- function(ns) {
  ea_settings_modal("Plugins",
    hint = paste("Tools from other open-source projects. Nothing is enabled until",
                 "you enable it, and nothing slows the app down until you do."),
    uiOutput(ns("provider_card")),
    div(class = "ea-plug-bar",
      textInput(ns("q"), NULL, placeholder = "Search tools…", width = "100%"),
      radioButtons(ns("filt"), NULL, inline = TRUE,
        c("Common" = "feat", "Enabled" = "on", "All" = "all"), selected = "feat"),
      uiOutput(ns("count"), inline = TRUE)),
    div(class = "ea-plug-scroll", uiOutput(ns("results"))),
    footer = tagList(
      actionButton(ns("enable_feat"), "Enable common tools", class = "btn-sm btn-outline-success"),
      actionButton(ns("disable_all"), "Disable all",         class = "btn-sm btn-outline-secondary"),
      modalButton("Close")))
}

pluginsServer <- function(id, open = reactive(NULL),
                          on_change = function() invisible(NULL)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    bump  <- reactiveVal(0)             # nudge after any state change
    build <- reactiveVal(NULL)          # the running background process
    blog  <- reactiveVal("")

    # Every state change refreshes this screen AND tells the app to bind whatever
    # became active. Activation is useless if the tool does not then appear.
    .refresh <- function() { bump(isolate(bump()) + 1); on_change() }

    # Opened from the top menu, beside Packages.
    observeEvent(open(), { showModal(.plugins_dialog(ns)) }, ignoreInit = TRUE)
    .state   <- reactive({ bump(); ea_plugin_state() })

    have_wbt <- reactive({
      bump()
      tryCatch({ .ea_require_whitebox(); TRUE }, error = function(e) conditionMessage(e))
    })

    # ---- Provider card ----------------------------------------------------
    output$provider_card <- renderUI({
      w <- have_wbt(); on <- isTRUE("whitebox" %in% .state()$providers)
      man <- if (isTRUE(w)) ea_wbt_manifest() else NULL
      nact <- length(.state()$tools[["whitebox"]] %||% character(0))
      div(class = paste("ea-plug-card", if (on) "on" else ""),
        div(class = "ea-plug-head",
          tags$span(class = "ea-plug-name", "WhiteboxTools"),
          tags$span(class = paste("ea-plug-pill", if (on) "on" else ""),
                    if (on) sprintf("Enabled · %d tool%s", nact, if (nact == 1) "" else "s")
                    else "Not enabled")),
        tags$p(class = "ea-plug-desc",
          "An open-source geospatial analysis engine with 484 algorithms for ",
          "hydrology, terrain, LiDAR and image processing."),
        tags$p(class = "ea-plug-cred",
          "Created by Prof. John Lindsay (University of Guelph). R package by ",
          "Qiusheng Wu and Andrew Brown, MIT licensed. ",
          tags$a(href = "https://www.whiteboxgeo.com/", target = "_blank",
                 rel = "noopener", "whiteboxgeo.com")),
        if (!isTRUE(w))
          div(class = "ea-plug-warn",
              tags$b("Not installed. "), as.character(w))
        else if (is.null(man))
          div(class = "ea-plug-warn",
              "Installed, but the tool catalogue has not been indexed yet. ",
              "Use ", tags$b("Index the common tools"), " to start.")
        else
          tags$p(class = "ea-plug-cred",
                 sprintf("Catalogue: %d tools indexed · version %s",
                         length(man$tools), man$version %||% "?")),
        # Controls live IN the card. They were in a tools panel, which the dialog
        # does not have -- and a settings action should not need one.
        div(class = "ea-plug-actions",
          actionButton(ns("toggle_prov"),
                       if (on) "Disable" else "Enable WhiteboxTools",
                       class = paste("btn-sm", if (on) "btn-outline-secondary" else "btn-success")),
          if (isTRUE(w)) actionButton(ns("build_feat"), "Index common tools",
                                      class = "btn-sm btn-outline-success"),
          if (isTRUE(w)) actionButton(ns("build_all"), "Index all 484",
                                      class = "btn-sm btn-outline-secondary"),
          uiOutput(ns("cat_status"), inline = TRUE)))
    })

    observeEvent(input$toggle_prov, {
      on <- isTRUE("whitebox" %in% ea_plugin_state()$providers)
      ea_plugin_set("whitebox", !on)
      .refresh()
      showNotification(if (on) "WhiteboxTools disabled."
                       else "WhiteboxTools enabled. Enable the tools you want below.",
                       type = "message")
    })

    # ---- Catalogue build (background) -------------------------------------
    output$cat_status <- renderUI({
      p <- build()
      if (is.null(p)) return(NULL)
      tags$span(class = "ea-plug-busy", "Indexing… ", tags$b(blog()))
    })

    .start_build <- function(only, what) {
      if (!is.null(build())) {
        showNotification("An indexing run is already in progress.", type = "warning")
        return()
      }
      w <- have_wbt()
      if (!isTRUE(w)) { showNotification(as.character(w), type = "error"); return() }
      p <- tryCatch(ea_wbt_build_async(getwd(), only), error = function(e) e)
      if (inherits(p, "error")) {
        showNotification(paste("Could not start indexing:", conditionMessage(p)),
                         type = "error"); return()
      }
      build(p); blog(paste("Starting", what, "…"))
    }
    observeEvent(input$build_feat, .start_build(EA_WBT_FEATURED, "the common tools"))
    observeEvent(input$build_all,  .start_build(NULL, "all 484 tools"))

    # Poll the background process. Its stdout is one line per tool, so the last
    # line IS the progress report -- no shared state between the processes.
    observe({
      p <- build()
      if (is.null(p)) return()
      invalidateLater(700, session)
      out <- tryCatch(p$read_output_lines(), error = function(e) character(0))
      if (length(out)) blog(utils::tail(out, 1))
      if (!p$is_alive()) {
        err <- tryCatch(paste(p$read_error_lines(), collapse = " "),
                        error = function(e) "")
        build(NULL); blog("")
        ea_wbt_manifest_clear()
        man <- ea_wbt_manifest()
        if (is.null(man))
          showNotification(paste0("Indexing did not produce a catalogue. ",
                                  substr(err, 1, 300)), type = "error")
        else
          showNotification(sprintf("Indexed %d tools.", length(man$tools)),
                           type = "message")
        .refresh()
      }
    })

    # ---- Search + per-tool activation --------------------------------------
    rows <- reactive({
      bump()
      if (!isTRUE(have_wbt())) return(data.frame())
      d <- ea_wbt_catalogue(input$q %||% "", limit = 300L)
      if (!nrow(d)) return(d)
      switch(input$filt %||% "feat",
             feat = d[d$featured, , drop = FALSE],
             on   = d[d$active,   , drop = FALSE],
             d)
    })

    output$count <- renderUI({
      d <- rows()
      tags$span(class = "ea-plug-count",
                if (!nrow(d)) "no tools" else sprintf("%d tool%s", nrow(d),
                                                      if (nrow(d) == 1) "" else "s"))
    })

    output$results <- renderUI({
      if (!isTRUE(have_wbt()))
        return(div(class = "ea-hint", "Install WhiteboxTools to browse its tools."))
      if (is.null(ea_wbt_manifest()))
        return(div(class = "ea-hint",
                   "No catalogue yet — index the tools from the panel on the right."))
      d <- rows()
      if (!nrow(d)) return(div(class = "ea-hint", "No tools match that search."))
      prov_on <- isTRUE("whitebox" %in% .state()$providers)
      div(class = "ea-plug-list", lapply(seq_len(nrow(d)), function(i) {
        r <- d[i, ]
        div(class = paste("ea-plug-row", if (r$active) "on" else ""),
          tags$button(class = paste("ea-plug-sw", if (r$active) "on" else ""),
            type = "button",
            onclick = sprintf(
              "Shiny.setInputValue('%s', {tool:'%s', on:%s, n:Date.now()}, {priority:'event'});",
              ns("tog"), r$tool, if (r$active) "false" else "true"),
            title = if (r$active) "Disable this tool" else "Enable this tool",
            tags$span(class = "knob")),
          div(class = "ea-plug-txt",
            tags$span(class = "ea-plug-tool", r$tool),
            tags$span(class = "ea-plug-box", r$toolbox),
            tags$p(class = "ea-plug-sum", r$description)))
      }),
      if (!prov_on)
        tags$p(class = "text-muted small mt-2",
               "WhiteboxTools is disabled, so none of these appear in the app yet."))
    })

    observeEvent(input$tog, {
      tg <- input$tog
      if (is.null(tg$tool)) return()
      ea_tool_set("whitebox", tg$tool, isTRUE(tg$on))
      .refresh()
      showNotification(
        sprintf("%s %s.", tg$tool, if (isTRUE(tg$on)) "enabled" else "disabled"),
        type = "message", duration = 4)
    })

    observeEvent(input$enable_feat, {
      ea_wbt_enable_featured(); .refresh()
      showNotification(sprintf("Enabled %d common tools.", length(EA_WBT_FEATURED)),
                       type = "message", duration = 5)
    })
    observeEvent(input$disable_all, {
      st <- ea_plugin_state(); st$tools[["whitebox"]] <- character(0)
      ea_plugin_state_set(st); .refresh()
      showNotification("All WhiteboxTools tools disabled.", type = "message")
    })

    list(context = reactive({
      st <- ea_plugin_state()
      sprintf("Plugins screen. WhiteboxTools %s; %d tool(s) enabled.",
              if ("whitebox" %in% st$providers) "enabled" else "disabled",
              length(st$tools[["whitebox"]] %||% character(0)))
    }), plot = function() NULL)
  })
}
