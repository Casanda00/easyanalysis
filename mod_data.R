# ==========================================================================
# MODULE: Data & Exploration  (upload + ETL toolbox + EDA)
# --------------------------------------------------------------------------
# Owns the shared data pools (uploads write here; other modules read from them):
#   - raw_pool      : reactiveValues, untouched uploads
#   - dataset_pool  : reactiveValues, working/edited datasets
#   - dataset_names : reactive() of current dataset names (for picker sync)
# Module-internal state:
#   - rv$working_data : the dataset currently being edited on this screen
# All inputs/outputs are namespaced via ns(); dynamically-created inputs use
# ns() too so they resolve correctly inside the module.
# ==========================================================================

# Right-panel tools for the Data view (the processing toolbox accordion).
# Uploading lives in the global left rail now, so there is no "Import Data" panel.
# Every ETL command is its own pickable view (backlog B6: "each command should
# now be separate but of course be synced"). They were nine accordion panels in a
# narrow column, and several panels bundled more than one command -- Column
# Management held keep/drop/rename/mutate, Level Management held rename/merge/
# delete. Now one command per entry, in the same select-and-split idiom as the
# model screens: pick one and it fills the canvas, pick several and they split.
# Synced comes for free -- every branch writes the same rv$working_data.
# The CANVAS shows the dataset: overview and the two exploratory plot views,
# picked with the select-and-split header (one fills, several split).
.DATA_VIEWS <- c(
  overview      = "Dataset overview",
  distributions = "Column distributions",
  relationships = "Plot relationships"
)
.DATA_VIEWS_PLOT <- c("distributions", "relationships")

# The SIDEBAR shows ONE ETL command at a time -- the one you searched for or
# picked from "Prepare data" in the menu. That is the flow the app is built
# around: find the tool, click it, its controls appear in the tools sidebar.
#
# One command per entry (backlog B6). They used to be nine accordion panels and
# several bundled more than one command: Column Management held keep / drop /
# rename / mutate, Level Management held rename / merge / delete levels. Fourteen
# now, each separately searchable. "Synced" is free -- every builder below makes
# controls whose observers all read and write the same rv$working_data.
#
# Each entry is label + a builder taking ns. Keeping them as DATA means the
# menubar, the search index and the sidebar all read one list and cannot drift.
.cmd_box <- function(title, ..., help = NULL) tagList(
  tags$h6(class = "text-uppercase text-muted small mb-2", title),
  if (!is.null(help)) tags$p(class = "text-muted small", help),
  ...
)

.DATA_CMDS <- list(
  keep_cols = list(label = "Keep columns", ui = function(ns) .cmd_box("Keep columns",
    pickerInput(ns("eng_subset_cols"), "Columns to Keep:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    actionButton(ns("apply_subset"), "Apply Subset", class = "btn-primary btn-sm w-100"))),

  drop_cols = list(label = "Remove columns", ui = function(ns) .cmd_box("Remove columns",
    selectInput(ns("rem_cols_target_ds"), "Target Dataset:", choices = NULL),
    pickerInput(ns("eng_drop_cols"), "Columns to Remove:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    actionButton(ns("apply_drop"), "Remove Selected Columns", class = "btn-danger btn-sm w-100"))),

  rename_col = list(label = "Rename column", ui = function(ns) .cmd_box("Rename column",
    selectInput(ns("rename_col_target"), "Select Column:", choices = NULL),
    textInput(ns("rename_col_new_name"), "New Name:", placeholder = "Enter new name"),
    actionButton(ns("apply_col_rename"), "Rename Column", class = "btn-primary btn-sm w-100"))),

  add_col = list(label = "Add column", ui = function(ns) .cmd_box("Add column",
    selectInput(ns("add_col_target_ds"), "Target Dataset:", choices = NULL),
    textInput(ns("add_col_name"), "New Column Name:", placeholder = "e.g., total_val"),
    selectInput(ns("add_col_type"), "Column Source / Type:", choices = c(
      "Formula (Col1 [op] Col2)" = "formula",
      "Constant Value" = "constant",
      "Sequential Row Index (1..N)" = "index",
      "Log Transform log(x+1)" = "log",
      "Z-Score Standardize scale(x)" = "scale"
    )),
    uiOutput(ns("add_col_params_ui")),
    actionButton(ns("apply_add_col"), "Create Column", class = "btn-primary btn-sm w-100"))),

  filter = list(label = "Filter rows", ui = function(ns) .cmd_box("Filter rows",
    selectInput(ns("filter_col"), "Select Column to Filter:", choices = NULL),
    uiOutput(ns("filter_condition_ui")),
    actionButton(ns("apply_filter"), "Apply Filter", class = "btn-primary btn-sm w-100"))),

  remove_rows = list(label = "Remove rows", ui = function(ns) .cmd_box("Remove rows",
    selectInput(ns("rem_rows_target_ds"), "Target Dataset:", choices = NULL),
    selectInput(ns("rem_rows_mode"), "Remove Method:", choices = c(
      "Rows with Missing Values (NA)" = "na",
      "Condition (Column [op] Value)" = "condition",
      "Specific Row Index / Range" = "indices"
    )),
    uiOutput(ns("rem_rows_params_ui")),
    actionButton(ns("apply_remove_rows"), "Remove Rows", class = "btn-danger btn-sm w-100"))),

  transform_col = list(label = "Transform column", ui = function(ns) .cmd_box("Transform column",
    selectInput(ns("tf_col_target_ds"), "Target Dataset:", choices = NULL),
    selectInput(ns("tf_col_src"), "Select Column:", choices = NULL),
    selectInput(ns("tf_col_func"), "Transformation:", choices = c(
      "Logarithm: log(x + 1)" = "log",
      "Z-Score Standardize: (x - mean)/sd" = "zscore",
      "Min-Max Normalize (0 to 1)" = "minmax",
      "Square Root: sqrt(x)" = "sqrt",
      "Absolute Value: abs(x)" = "abs"
    )),
    textInput(ns("tf_col_new_name"), "New Column Name (leave blank to overwrite):", placeholder = "e.g., col_log"),
    actionButton(ns("apply_transform_col"), "Transform Column", class = "btn-primary btn-sm w-100"))),

  convert = list(label = "Convert types", ui = function(ns) .cmd_box("Convert column types",
    pickerInput(ns("convert_to_num"), "Convert to Numeric:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    pickerInput(ns("convert_to_cat"), "Convert to Categorical:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    actionButton(ns("apply_conversion"), "Apply Conversions", class = "btn-primary btn-sm w-100"))),

  rename_lvl = list(label = "Rename levels", ui = function(ns) .cmd_box("Rename levels",
    selectInput(ns("rename_col"), "Categorical Column:", choices = NULL),
    uiOutput(ns("dynamic_rename_ui")),
    actionButton(ns("apply_rename"), "Apply Renames", class = "btn-primary btn-sm w-100"))),

  merge_lvl = list(label = "Merge levels", ui = function(ns) .cmd_box("Merge levels",
    selectInput(ns("agg_col"), "Categorical Column:", choices = NULL),
    selectInput(ns("agg_levels"), "Levels to Merge:", choices = NULL, multiple = TRUE),
    textInput(ns("agg_new_name"), "New Combined Name:", placeholder = "e.g., Wetland"),
    actionButton(ns("apply_merge"), "Merge Levels", class = "btn-primary btn-sm w-100"))),

  delete_lvl = list(label = "Delete levels", ui = function(ns) .cmd_box("Delete levels",
    selectInput(ns("delete_lvl_col"), "Categorical Column:", choices = NULL),
    selectInput(ns("delete_levels"), "Levels to Delete:", choices = NULL, multiple = TRUE),
    actionButton(ns("apply_delete_lvl"), "Delete Levels", class = "btn-danger btn-sm w-100"))),

  aggregate = list(label = "Aggregate", ui = function(ns) .cmd_box("Aggregate",
    selectInput(ns("group_id"), "Aggregate by:", choices = NULL),
    selectInput(ns("agg_method"), "Aggregation Method:", choices = c("Average" = "mean", "Sum" = "sum", "Median" = "median", "Min" = "min", "Max" = "max")),
    pickerInput(ns("group_nums"), "Numeric Columns to Aggregate:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
    pickerInput(ns("group_cats"), "Categorical Columns to Keep:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE, `selected-text-format` = "count > 2", `count-selected-text` = "{0} columns selected")),
    actionButton(ns("apply_group"), "Aggregate Data", class = "btn-primary btn-sm w-100"))),

  bin = list(label = "Bin numeric", ui = function(ns) .cmd_box("Bin a numeric column",
    selectInput(ns("bin_col"), "Numeric Column to Bin:", choices = NULL),
    textInput(ns("bin_breaks"), "Breaks (e.g. -Inf,30,50,Inf):", placeholder = "-Inf, 30, 50, Inf"),
    textInput(ns("bin_labels"), "Labels (comma-separated):", placeholder = "Winter, Dry Summer, Summer"),
    textInput(ns("bin_new_name"), "New Column Name:", placeholder = "Trafficability_Class"),
    actionButton(ns("apply_bin"), "Create Bins", class = "btn-primary btn-sm w-100"))),

  impute = list(label = "Impute missing", ui = function(ns) .cmd_box("Impute missing values",
    help = "Fill missing values (NA) in the Primary column using values from the Secondary column.",
    selectInput(ns("coalesce_primary"), "Primary Column (Target):", choices = NULL),
    selectInput(ns("coalesce_secondary"), "Secondary Column (Source):", choices = NULL),
    actionButton(ns("apply_coalesce"), "Impute Missing Values", class = "btn-primary btn-sm w-100"))),

  join = list(label = "Join datasets", ui = function(ns) .cmd_box("Join with another dataset",
    selectInput(ns("join_target"), "Dataset to Join With:", choices = NULL),
    selectInput(ns("join_type"), "Join Type:", choices = c("Left Join" = "left", "Inner Join" = "inner", "Full Join" = "full", "Right Join" = "right")),
    selectInput(ns("join_by"), "Common ID Column:", choices = NULL),
    actionButton(ns("apply_join"), "Merge Datasets", class = "btn-primary btn-sm w-100"))),

  batch = list(label = "Batch apply", ui = function(ns) .cmd_box("Batch apply",
    help = "Instantly apply active settings to other datasets.",
    selectInput(ns("batch_targets"), "Select Datasets to Update:", choices = NULL, multiple = TRUE),
    actionButton(ns("apply_batch"), "Batch Apply Settings", class = "btn-danger btn-sm w-100")))
)

# Label lookup for the menubar / search index, so it reads the same list.
.DATA_CMD_LABELS <- vapply(.DATA_CMDS, function(x) x$label, character(1))

dataToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("cmd_panel")),
    hr(class = "my-2"),
    actionButton(ns("reset_data"), "Reset to Raw Data",
                 class = "btn-warning btn-sm w-100")
  )
}

dataCanvasUI <- function(id) {
  ns <- NS(id)
  card(
    card_header(ea_view_header(ns, .DATA_VIEWS)),
    div(class = "lm-viewport", uiOutput(ns("view_body")))
  )
}

dataServer <- function(id, raw_pool, dataset_pool, dataset_names, active_dataset,
                       active_ds = NULL, view_request = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {

    # ---- Select-and-split canvas (B6) --------------------------------------
    # Input ids are UNCHANGED from the old accordion, so every observer further
    # down still drives exactly the same controls.
    output$view_tools <- renderUI({
      picked <- input$view_pick
      if (!length(picked)) picked <- names(.DATA_VIEWS)[1]
      if (any(picked %in% .DATA_VIEWS_PLOT)) ea_plot_appearance()
    })

    output$view_body <- renderUI({
      ns <- session$ns
      ea_view_panes(input$view_pick, .DATA_VIEWS, function(k, solo) switch(k,

        overview = tagList(
          uiOutput(ns("overview_stats")),
          card(
            card_header(class = "bg-light", "Dataset Structure"),
            div(style = "padding: 8px 10px 0;",
              layout_columns(col_widths = c(3, 4, 5),
                selectInput(ns("dl_format"), "Export format",
                            choices = c("CSV (.csv)" = "csv", "Excel (.xlsx)" = "xlsx")),
                textInput(ns("dl_name"), "File name (optional)", placeholder = "dataset"),
                tags$div(style = "margin-top:32px;", class = "d-flex gap-2 align-items-center",
                  downloadButton(ns("do_download"), "Download",
                                icon = icon("download"), class = "btn-sm btn-outline-success"),
                  actionButton(ns("save_copy_proj"), "Save Copy to Project",
                               icon = icon("copy"), class = "btn-sm btn-outline-primary")))),
            div(style = "padding: 5px;", uiOutput(ns("eng_str")))
          )),

        distributions = div(style = "padding: 5px;",
          selectInput(ns("eng_view_col"), "View Frequency/Summary of:", choices = NULL),
          layout_columns(col_widths = c(6, 6),
            plotOutput(ns("eng_plot"), height = if (solo) "350px" else "100%"),
            div(style = "overflow-y: auto; height: 350px;",
                verbatimTextOutput(ns("eng_table"))))),

        relationships = tagList(
          tags$p(class = "text-muted small mb-2 px-2",
            "See how two variables relate: pick a ", tags$b("Y"), " and an ", tags$b("X"),
            " to plot them against each other, and optionally a ", tags$b("Group"),
            " to colour points by a category. Grid view shows every pairing at once."),
          div(class = "d-flex flex-wrap align-items-end gap-2 mb-2 px-2",
            div(style = "min-width: 150px;", selectInput(ns("eda_num1"), "Y (numeric)", choices = NULL, width = "100%")),
            div(style = "min-width: 150px;", selectInput(ns("eda_num2"), "X (numeric)", choices = NULL, width = "100%")),
            div(style = "min-width: 150px;", selectInput(ns("eda_category"), "Group (colour)", choices = NULL, width = "100%")),
            div(class = "ms-auto d-flex align-items-end gap-2",
              radioGroupButtons(ns("eda_view_mode"), label = NULL, choices = c("Grid View", "Single Plot"), selected = "Grid View", size = "sm", status = "primary"),
              uiOutput(ns("eda_single_selector")))),
          div(class = "ea-eda-frame", style = "overflow-x: hidden; overflow-y: auto;",
              uiOutput(ns("dynamic_eda_plot_ui")))),

        NULL))
    })

    # ---- The ETL command, in the SIDEBAR ------------------------------------
    # Search "rename", click the hit, and its controls appear here. One at a time:
    # two commands sharing the sidebar would mean two copies of the same input ids.
    cmd <- reactiveVal(NULL)
    observeEvent(view_request(), {
      k <- view_request()
      req(isTruthy(k), k %in% names(.DATA_CMDS))
      cmd(k)
    }, ignoreInit = TRUE)

    output$cmd_panel <- renderUI({
      k <- cmd()
      if (is.null(k)) return(div(class = "ea-hint",
        "Pick a command from ", tags$b("Data \u2192 Prepare data"),
        " in the menu bar, or search for it. Its controls open here and act on the ",
        "selected dataset."))
      # Arm the population AFTER this panel is out. Bumping only on view_request
      # was not enough on the FIRST open of the screen: this is a uiOutput nested
      # inside the sidebar the workspace had just rendered, so the controls
      # appeared a flush later than the update aimed at them and arrived empty.
      # Verified: searching a command and clicking it worked once the screen was
      # already open, and left the picker blank when it was not.
      # Safe from looping -- this output reads cmd(), never view_rendered().
      .arm_after_flush()
      .DATA_CMDS[[k]]$ui(session$ns)
    })

    ns <- session$ns
    rv <- reactiveValues(working_data = NULL, current_rename_levels = NULL)

    # ---- Undo: a bounded stack, PER DATASET (backlog item 32) ---------------
    # Bounded on purpose. Each entry is a full copy of the data frame, and an
    # unbounded store of large objects is exactly how this app OOM-ed before
    # (round-1 item 1 capped the project-load cache at 4 for the same reason).
    #
    # Keyed by dataset because the old single `prev_state` slot was shared across
    # datasets: switching from A to B and pressing Undo restored A's data INTO B,
    # silently corrupting it. A stack per dataset cannot do that.
    .UNDO_MAX <- 5L
    undo_stacks <- reactiveVal(list())   # name -> list of snapshots, newest LAST

    # Snapshot the current state before any mutation. `snap()` is the single
    # choke point every ~14 mutating handler already calls, so nothing else
    # needed changing to get 5 steps instead of 1.
    snap <- function() {
      ds <- active_dataset()
      if (!isTruthy(ds) || is.null(rv$working_data)) return(invisible(NULL))
      s  <- undo_stacks()
      st <- c(s[[ds]] %||% list(), list(rv$working_data))
      if (length(st) > .UNDO_MAX) st <- utils::tail(st, .UNDO_MAX)
      s[[ds]] <- st
      # Drop stacks for datasets that no longer exist, so a long session cannot
      # accumulate snapshots of deleted layers.
      live <- names(dataset_pool)
      s <- s[names(s) %in% live]
      undo_stacks(s)
      invisible(NULL)
    }

    # NOTE: Uploading is handled globally in server.R (left Datasets rail) and
    # writes to raw_pool/dataset_pool. This module only consumes those pools.

    # Load the globally-selected dataset into this screen's working copy.
    observeEvent(active_dataset(), {
      req(active_dataset())
      rv$working_data <- dataset_pool[[active_dataset()]]
    }, ignoreNULL = TRUE)

    observeEvent(input$reset_data, {
      req(active_dataset())
      snap()
      raw <- raw_pool[[active_dataset()]]
      rv$working_data <- raw
      dataset_pool[[active_dataset()]] <- raw
      showNotification("Dataset reset to original raw data across all tabs.", type = "message")
    })

    # ---- Undo last operation (up to .UNDO_MAX steps) ----
    observeEvent(input$undo_last, {
      ds <- active_dataset(); req(ds)
      s  <- undo_stacks()
      st <- s[[ds]] %||% list()
      if (!length(st)) {
        showNotification("Nothing left to undo.", type = "warning")
        return()
      }
      prev <- st[[length(st)]]
      st   <- st[-length(st)]          # pop
      s[[ds]] <- st
      undo_stacks(s)
      rv$working_data <- prev
      dataset_pool[[ds]] <- prev
      # Say how many are left. The Undo control is static markup fired from JS in
      # four places (ui.R, mod_workspace.R), so there is no server-rendered label
      # to update -- reporting it here is what stops the last press reading as a
      # broken button.
      showNotification(
        sprintf("Change undone. %s",
                if (!length(st)) "No further undo steps."
                else sprintf("%d undo step%s left.", length(st),
                             if (length(st) == 1L) "" else "s")),
        type = "message")
    })

    # ---- Reset to original upload (top-bar button) ----
    observeEvent(input$reset_raw, {
      req(active_dataset())
      orig <- raw_pool[[active_dataset()]]
      if (is.null(orig)) { showNotification("No original data found.", type = "warning"); return() }
      snap()
      rv$working_data <- orig
      dataset_pool[[active_dataset()]] <- orig
      showNotification("Dataset restored to original upload.", type = "message")
    })

    # ---- Toolbox picker population ----
    # Every observer that fills a selector must depend on THIS, not on
    # rv$working_data alone. The workspace renders this panel lazily, so the
    # first update*Input fires at an element that does not exist yet and Shiny
    # drops it. Re-opening a tool re-arms that on every other screen by bumping
    # active_dataset() (see server.R), but the re-arm never reached this module,
    # for two compounding reasons:
    #   * observeEvent ISOLATES its handler, so reading active_dataset() inside
    #     a handler body creates no dependency on it; and
    #   * the re-arm arrives here as `rv$working_data <- <the same data frame>`,
    #     and assigning an IDENTICAL value to a reactiveValues field does not
    #     invalidate (verified) -- so the chain died at that assignment.
    # The screen therefore opened with every picker empty, which is also why the
    # Column Distributions and Plot Relationships tabs showed nothing: they have
    # no columns to plot until these run.
    # Picking a view creates that command's controls for the FIRST time, so the
    # population observers have to run again afterwards or the pickers arrive
    # empty -- gotcha 18, now triggered by the view picker instead of the tool
    # menu. Bumping on input$view_pick directly is too early: the update message
    # would be sent in the same flush that inserts the UI, and Shiny drops an
    # update aimed at an element that does not exist yet. onFlushed fires once
    # that flush is out, so the update follows the insert.
    view_rendered <- reactiveVal(0)
    .arm_after_flush <- function()
      session$onFlushed(function() view_rendered(isolate(view_rendered()) + 1),
                        once = TRUE)
    observeEvent(input$view_pick, .arm_after_flush(), ignoreNULL = FALSE)
    # ...and when a COMMAND is opened in the sidebar, which is what creates its
    # controls in the first place.
    observeEvent(view_request(), .arm_after_flush(), ignoreNULL = FALSE)

    pop_arm <- reactive({ list(active_dataset(), rv$working_data, view_rendered()) })

    observeEvent(pop_arm(), {
      req(rv$working_data)
      act <- active_dataset()
      if (is.null(act) || !is.character(act) || length(act) != 1 || !nzchar(act)) return()
      df <- rv$working_data
      cols <- names(df)
      num_cols <- names(df)[sapply(df, is.numeric)]
      cat_cols <- names(df)[!sapply(df, is.numeric)]

      raw_df <- tryCatch(raw_pool[[act]], error = function(e) NULL)
      raw_cols <- if (!is.null(raw_df)) names(raw_df) else cols

      updatePickerInput(session, "eng_subset_cols", choices = raw_cols, selected = cols)
      updatePickerInput(session, "eng_drop_cols", choices = cols, selected = NULL)
      updateSelectInput(session, "rename_col_target", choices = cols)
      updateSelectInput(session, "mutate_col1", choices = num_cols)
      updateSelectInput(session, "mutate_col2", choices = num_cols)
      updateSelectInput(session, "filter_col", choices = cols)
      updateSelectInput(session, "bin_col", choices = num_cols)
      updateSelectInput(session, "coalesce_primary", choices = cols)
      updateSelectInput(session, "coalesce_secondary", choices = cols)
      updateSelectInput(session, "join_by", choices = cols)

      updatePickerInput(session, "convert_to_num", choices = cat_cols, selected = NULL)
      updatePickerInput(session, "convert_to_cat", choices = num_cols, selected = NULL)
      updateSelectInput(session, "group_id", choices = cols, selected = if ("final_id" %in% cols) "final_id" else cols[1])
      updatePickerInput(session, "group_nums", choices = num_cols, selected = num_cols)
      updatePickerInput(session, "group_cats", choices = cat_cols, selected = cat_cols)
      curr_rename <- if (isTruthy(isolate(input$rename_col)) && isolate(input$rename_col) %in% cat_cols) isolate(input$rename_col) else cat_cols[1]
      updateSelectInput(session, "rename_col", choices = cat_cols, selected = curr_rename)
      curr_agg <- if (isTruthy(isolate(input$agg_col)) && isolate(input$agg_col) %in% cat_cols) isolate(input$agg_col) else cat_cols[1]
      updateSelectInput(session, "agg_col", choices = cat_cols, selected = curr_agg)
      curr_del <- if (isTruthy(isolate(input$delete_lvl_col)) && isolate(input$delete_lvl_col) %in% cat_cols) isolate(input$delete_lvl_col) else cat_cols[1]
      updateSelectInput(session, "delete_lvl_col", choices = cat_cols, selected = curr_del)

      updatePickerInput(session, "rem_cols_list", choices = cols, selected = NULL)
      updateSelectInput(session, "tf_col_src", choices = cols)
    })

    # Datasets available to join / batch / target against.
    observeEvent(list(pop_arm(), dataset_names()), {
      dn <- dataset_names()
      act <- active_dataset()
      act_str <- if (is.character(act) && length(act) == 1 && nzchar(act)) act else NULL
      updateSelectInput(session, "batch_targets", choices = dn)
      updateSelectInput(session, "join_target", choices = dn)
      updateSelectInput(session, "add_col_target_ds", choices = dn, selected = act_str)
      updateSelectInput(session, "rem_rows_target_ds", choices = dn, selected = act_str)
      updateSelectInput(session, "rem_cols_target_ds", choices = dn, selected = act_str)
      updateSelectInput(session, "tf_col_target_ds", choices = dn, selected = act_str)
    })

    # Download handler for CSV and Excel (.xlsx) formats.
    output$do_download <- downloadHandler(
      filename = function() {
        base <- if (isTruthy(input$dl_name)) input$dl_name else {
          nm <- tryCatch(active_dataset(), error = function(e) NULL)
          if (isTruthy(nm)) paste0(nm, "_cleaned") else "dataset"
        }
        base <- gsub("[^A-Za-z0-9._-]+", "_", base)
        ext <- if (identical(input$dl_format, "xlsx")) ".xlsx" else ".csv"
        paste0(base, "_", Sys.Date(), ext)
      },
      content = function(file) {
        df <- rv$working_data
        req(!is.null(df), is.data.frame(df), nrow(df) > 0)
        fmt <- input$dl_format %||% "csv"
        if (identical(fmt, "xlsx")) {
          if (requireNamespace("writexl", quietly = TRUE)) {
            writexl::write_xlsx(df, path = file)
          } else if (requireNamespace("openxlsx", quietly = TRUE)) {
            openxlsx::write.xlsx(df, file = file)
          } else {
            write.csv(df, file, row.names = FALSE)
          }
        } else {
          write.csv(df, file, row.names = FALSE)
        }
      }
    )

    # Save Copy to Project handler
    observeEvent(input$save_copy_proj, {
      req(active_dataset(), rv$working_data)
      cur_name <- active_dataset()
      default_copy_name <- paste0(cur_name, "_copy")
      showModal(modalDialog(
        title = "Save Copy to Project",
        easyClose = TRUE,
        size = "m",
        div(style = "padding: 10px;",
          tags$p("Save the current working dataset (with all edits applied) as a new dataset copy in the project:"),
          textInput(ns("copy_ds_name"), "New Dataset Name", value = default_copy_name),
          tags$small(class = "text-muted",
                     sprintf("Current dimensions: %d rows \u00d7 %d columns",
                             nrow(rv$working_data), ncol(rv$working_data)))
        ),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_save_copy"), "Save Copy", class = "btn-primary")
        )
      ))
    })

    observeEvent(input$confirm_save_copy, {
      req(active_dataset(), rv$working_data)
      raw_name <- trimws(input$copy_ds_name %||% "")
      if (!nzchar(raw_name)) {
        showNotification("Please enter a valid dataset name.", type = "warning")
        return()
      }
      new_name <- make.names(raw_name)
      df <- rv$working_data
      
      snap()
      raw_pool[[new_name]] <- df
      dataset_pool[[new_name]] <- df
      removeModal()
      if (is.function(active_ds)) {
        active_ds(new_name)
      }
      showNotification(paste0("Dataset copy '", new_name, "' saved to project."), type = "message")
    })

    # ---- Column ops ----
    observeEvent(input$apply_subset, {
      req(active_dataset(), input$eng_subset_cols)
      snap()
      full_raw <- raw_pool[[active_dataset()]]
      safe_cols <- intersect(input$eng_subset_cols, names(full_raw))
      df <- full_raw[, safe_cols, drop = FALSE]
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      showNotification(paste("Subset applied globally. Columns reduced to:", length(safe_cols)), type = "message")
    })

    observeEvent(input$apply_drop, {
      req(active_dataset(), input$eng_drop_cols)
      snap()
      df <- rv$working_data
      df <- df[, !(names(df) %in% input$eng_drop_cols), drop = FALSE]
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      showNotification(paste("Dropped", length(input$eng_drop_cols), "columns globally."), type = "message")
    })

    observeEvent(input$apply_col_rename, {
      req(active_dataset(), input$rename_col_target, input$rename_col_new_name)
      snap()
      df <- rv$working_data
      if (input$rename_col_new_name != "") {
        names(df)[names(df) == input$rename_col_target] <- input$rename_col_new_name
        rv$working_data <- df
        dataset_pool[[active_dataset()]] <- df
        showNotification(paste("Column renamed to", input$rename_col_new_name), type = "message")
      }
    })

    observeEvent(input$apply_mutate, {
      req(active_dataset(), input$mutate_col1, input$mutate_col2, input$mutate_op, input$mutate_new_name)
      snap()
      df <- rv$working_data
      c1 <- df[[input$mutate_col1]]
      c2 <- df[[input$mutate_col2]]
      if (input$mutate_new_name != "") {
        new_col <- tryCatch({
          switch(input$mutate_op, "+" = c1 + c2, "-" = c1 - c2, "*" = c1 * c2, "/" = c1 / c2)
        }, error = function(e) NULL)
        if (!is.null(new_col)) {
          df[[input$mutate_new_name]] <- new_col
          rv$working_data <- df
          dataset_pool[[active_dataset()]] <- df
          showNotification(paste("Created new column:", input$mutate_new_name), type = "message")
        } else {
          showNotification("Error in mutation.", type = "error")
        }
      }
    })

    # ---- Filtering ----
    output$filter_condition_ui <- renderUI({
      req(rv$working_data, input$filter_col)
      col_data <- rv$working_data[[input$filter_col]]
      if (is.numeric(col_data)) {
        tagList(
          selectInput(ns("filter_op"), "Condition:", choices = c(">", "<", "==", ">=", "<=", "!=")),
          numericInput(ns("filter_val_num"), "Value:", value = 0)
        )
      } else {
        lvls <- unique(as.character(na.omit(col_data)))
        tagList(
          selectInput(ns("filter_op"), "Condition:", choices = c("==", "!=", "in", "not in")),
          pickerInput(ns("filter_val_cat"), "Value(s):", choices = lvls, multiple = TRUE, options = list(`live-search` = TRUE))
        )
      }
    })

    observeEvent(input$apply_filter, {
      req(active_dataset(), input$filter_col, input$filter_op)
      snap()
      df <- rv$working_data
      col_data <- df[[input$filter_col]]
      keep_idx <- tryCatch({
        if (is.numeric(col_data)) {
          val <- req(input$filter_val_num)
          switch(input$filter_op, ">" = col_data > val, "<" = col_data < val, "==" = col_data == val, ">=" = col_data >= val, "<=" = col_data <= val, "!=" = col_data != val)
        } else {
          val <- req(input$filter_val_cat)
          if (input$filter_op %in% c("in", "not in") && length(val) == 0) return(rep(TRUE, length(col_data)))
          switch(input$filter_op, "==" = col_data == val[1], "!=" = col_data != val[1], "in" = col_data %in% val, "not in" = !(col_data %in% val))
        }
      }, error = function(e) rep(TRUE, length(col_data)))
      keep_idx[is.na(keep_idx)] <- FALSE
      df <- df[keep_idx, , drop = FALSE]
      df <- droplevels(df)
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      showNotification(paste("Filter applied. Rows remaining:", nrow(df)), type = "message")
    })

    observeEvent(input$apply_bin, {
      req(active_dataset(), input$bin_col, input$bin_breaks, input$bin_labels, input$bin_new_name)
      snap()
      df <- rv$working_data
      tryCatch({
        breaks_vec <- as.numeric(trimws(unlist(strsplit(input$bin_breaks, ","))))
        labels_vec <- trimws(unlist(strsplit(input$bin_labels, ",")))
        if (length(breaks_vec) - 1 != length(labels_vec)) {
          showNotification("Number of labels must be exactly one less than the number of breaks.", type = "error")
          return()
        }
        new_col <- cut(df[[input$bin_col]], breaks = breaks_vec, labels = labels_vec, right = FALSE)
        df[[input$bin_new_name]] <- new_col
        rv$working_data <- df
        dataset_pool[[active_dataset()]] <- df
        showNotification(paste("Created binned column:", input$bin_new_name), type = "message")
      }, error = function(e) {
        showNotification(paste("Error in binning:", e$message), type = "error")
      })
    })

    observeEvent(input$apply_coalesce, {
      req(active_dataset(), input$coalesce_primary, input$coalesce_secondary)
      snap()
      df <- rv$working_data
      prim <- df[[input$coalesce_primary]]
      sec <- df[[input$coalesce_secondary]]
      nas <- is.na(prim) | prim == ""
      prim[nas] <- sec[nas]
      df[[input$coalesce_primary]] <- prim
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      showNotification("Conditional Imputation (Coalesce) applied.", type = "message")
    })

    observeEvent(input$apply_join, {
      req(active_dataset(), input$join_target, input$join_type, input$join_by)
      snap()
      df1 <- rv$working_data
      df2 <- dataset_pool[[input$join_target]]
      if (!(input$join_by %in% names(df2))) {
        showNotification(paste("Column", input$join_by, "not found in target dataset."), type = "error")
        return()
      }
      tryCatch({
        new_df <- switch(input$join_type,
          "left"  = merge(df1, df2, by = input$join_by, all.x = TRUE),
          "right" = merge(df1, df2, by = input$join_by, all.y = TRUE),
          "inner" = merge(df1, df2, by = input$join_by, all = FALSE),
          "full"  = merge(df1, df2, by = input$join_by, all = TRUE)
        )
        rv$working_data <- new_df
        dataset_pool[[active_dataset()]] <- new_df
        showNotification(paste(input$join_type, "join completed successfully."), type = "message")
      }, error = function(e) {
        showNotification(paste("Error joining datasets:", e$message), type = "error")
      })
    })

    # ---- Add Column dynamic UI & observer ----
    output$add_col_params_ui <- renderUI({
      req(input$add_col_type)
      df <- rv$working_data
      if (is.null(df)) return(NULL)
      cols <- names(df)
      num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
      switch(input$add_col_type,
        "constant" = textInput(ns("add_col_const_val"), "Constant Value:", value = "0"),
        "index"    = tags$p(class = "text-muted small my-2", "Adds a 1..N row index column."),
        "log"      = selectInput(ns("add_col_log_src"), "Source Numeric Column:", choices = num_cols),
        "scale"    = selectInput(ns("add_col_scale_src"), "Source Numeric Column:", choices = num_cols),
        "formula"  = tagList(
          selectInput(ns("add_col_f_c1"), "Column 1:", choices = num_cols),
          selectInput(ns("add_col_f_op"), "Operation:", choices = c("+", "-", "*", "/")),
          selectInput(ns("add_col_f_c2"), "Column 2:", choices = num_cols)
        )
      )
    })

    observeEvent(input$apply_add_col, {
      req(input$add_col_name, input$add_col_type)
      target_ds <- input$add_col_target_ds %||% active_dataset()
      req(target_ds, target_ds %in% names(dataset_pool))
      snap()
      df <- dataset_pool[[target_ds]]
      col_name <- trimws(input$add_col_name)
      if (!nzchar(col_name)) { showNotification("Please enter a column name.", type = "warning"); return() }

      new_vals <- tryCatch({
        switch(input$add_col_type,
          "constant" = rep(input$add_col_const_val %||% "0", nrow(df)),
          "index"    = seq_len(nrow(df)),
          "log"      = { c <- df[[req(input$add_col_log_src)]]; log(as.numeric(c) + 1) },
          "scale"    = { c <- df[[req(input$add_col_scale_src)]]; as.numeric(scale(as.numeric(c))) },
          "formula"  = {
            c1 <- as.numeric(df[[req(input$add_col_f_c1)]])
            c2 <- as.numeric(df[[req(input$add_col_f_c2)]])
            switch(input$add_col_f_op, "+" = c1 + c2, "-" = c1 - c2, "*" = c1 * c2, "/" = c1 / c2)
          }
        )
      }, error = function(e) NULL)

      if (is.null(new_vals) || length(new_vals) != nrow(df)) {
        showNotification("Error computing new column values.", type = "error")
        return()
      }

      df[[col_name]] <- new_vals
      dataset_pool[[target_ds]] <- df
      if (identical(target_ds, active_dataset())) rv$working_data <- df
      showNotification(paste("Added column", col_name, "to", target_ds), type = "message")
    })

    # ---- Remove Rows dynamic UI & observer ----
    output$rem_rows_params_ui <- renderUI({
      req(input$rem_rows_mode)
      df <- rv$working_data
      if (is.null(df)) return(NULL)
      cols <- names(df)
      switch(input$rem_rows_mode,
        "na" = selectInput(ns("rem_rows_na_col"), "Check NAs in Column:", choices = c("All Columns" = "_all_", cols)),
        "condition" = tagList(
          selectInput(ns("rem_rows_cond_col"), "Column:", choices = cols),
          selectInput(ns("rem_rows_cond_op"), "Operator:", choices = c(">", "<", "==", "!=", ">=", "<=")),
          textInput(ns("rem_rows_cond_val"), "Value:", value = "0")
        ),
        "indices" = textInput(ns("rem_rows_idx_text"), "Row Indices (e.g., 1, 5, 10:20):", placeholder = "1:5, 10")
      )
    })

    observeEvent(input$apply_remove_rows, {
      req(input$rem_rows_mode)
      target_ds <- input$rem_rows_target_ds %||% active_dataset()
      req(target_ds, target_ds %in% names(dataset_pool))
      snap()
      df <- dataset_pool[[target_ds]]
      n_start <- nrow(df)

      remove_idx <- tryCatch({
        switch(input$rem_rows_mode,
          "na" = {
            col <- input$rem_rows_na_col %||% "_all_"
            if (identical(col, "_all_")) !complete.cases(df) else is.na(df[[col]])
          },
          "condition" = {
            col_data <- df[[req(input$rem_rows_cond_col)]]
            op <- req(input$rem_rows_cond_op)
            val <- input$rem_rows_cond_val %||% "0"
            if (is.numeric(col_data)) {
              num_val <- as.numeric(val)
              switch(op, ">" = col_data > num_val, "<" = col_data < num_val, "==" = col_data == num_val, "!=" = col_data != num_val, ">=" = col_data >= num_val, "<=" = col_data <= num_val)
            } else {
              switch(op, "==" = col_data == val, "!=" = col_data != val, rep(FALSE, nrow(df)))
            }
          },
          "indices" = {
            txt <- trimws(input$rem_rows_idx_text %||% "")
            if (!nzchar(txt)) logical(nrow(df)) else {
              idxs <- suppressWarnings(as.integer(eval(parse(text = paste0("c(", txt, ")")))))
              seq_len(nrow(df)) %in% idxs[!is.na(idxs)]
            }
          }
        )
      }, error = function(e) logical(nrow(df)))

      remove_idx[is.na(remove_idx)] <- FALSE
      df <- df[!remove_idx, , drop = FALSE]
      df <- droplevels(df)
      dataset_pool[[target_ds]] <- df
      if (identical(target_ds, active_dataset())) rv$working_data <- df
      showNotification(paste("Removed", n_start - nrow(df), "rows from", target_ds), type = "message")
    })

    # ---- Remove Columns observer ----
    observeEvent(input$apply_remove_cols, {
      target_ds <- input$rem_cols_target_ds %||% active_dataset()
      cols_to_rem <- input$rem_cols_list
      req(target_ds, target_ds %in% names(dataset_pool), length(cols_to_rem) > 0)
      snap()
      df <- dataset_pool[[target_ds]]
      df <- df[, !(names(df) %in% cols_to_rem), drop = FALSE]
      dataset_pool[[target_ds]] <- df
      if (identical(target_ds, active_dataset())) rv$working_data <- df
      showNotification(paste("Removed", length(cols_to_rem), "columns from", target_ds), type = "message")
    })

    # ---- Transform Column observer ----
    observeEvent(input$apply_transform_col, {
      req(input$tf_col_src, input$tf_col_func)
      target_ds <- input$tf_col_target_ds %||% active_dataset()
      req(target_ds, target_ds %in% names(dataset_pool))
      snap()
      df <- dataset_pool[[target_ds]]
      src_col <- input$tf_col_src
      c_vals <- as.numeric(df[[src_col]])

      new_vals <- tryCatch({
        switch(input$tf_col_func,
          "log"    = log(c_vals + 1),
          "zscore" = as.numeric(scale(c_vals)),
          "minmax" = { rng <- range(c_vals, na.rm = TRUE); (c_vals - rng[1]) / (rng[2] - rng[1]) },
          "sqrt"   = sqrt(pmax(0, c_vals, na.rm = TRUE)),
          "abs"    = abs(c_vals)
        )
      }, error = function(e) NULL)

      if (is.null(new_vals)) {
        showNotification("Transformation failed.", type = "error")
        return()
      }

      dest_name <- if (nzchar(trimws(input$tf_col_new_name %||% ""))) trimws(input$tf_col_new_name) else src_col
      df[[dest_name]] <- new_vals
      dataset_pool[[target_ds]] <- df
      if (identical(target_ds, active_dataset())) rv$working_data <- df
      showNotification(paste("Transformed", src_col, "->", dest_name), type = "message")
    })

    # ---- Type conversion ----
    observeEvent(input$apply_conversion, {
      req(rv$working_data)
      snap()
      df <- rv$working_data
      raw <- raw_pool[[active_dataset()]]
      tryCatch({
        if (length(input$convert_to_num) > 0) {
          for (col in input$convert_to_num) {
            df[[col]] <- as.numeric(as.character(df[[col]]))
            if (col %in% names(raw)) raw[[col]] <- as.numeric(as.character(raw[[col]]))
          }
        }
        if (length(input$convert_to_cat) > 0) {
          for (col in input$convert_to_cat) {
            df[[col]] <- as.factor(df[[col]])
            if (col %in% names(raw)) raw[[col]] <- as.factor(raw[[col]])
          }
        }
        rv$working_data <- df
        dataset_pool[[active_dataset()]] <- df
        raw_pool[[active_dataset()]] <- raw
        showNotification("Column types successfully converted and state preserved!", type = "message")
        updateSelectInput(session, "convert_to_num", selected = "")
        updateSelectInput(session, "convert_to_cat", selected = "")
      }, error = function(e) {
        showNotification(paste("Warning: Failed to convert. Ensure text columns contain numbers."), type = "warning")
      })
    })

    # ---- Aggregation ----
    observeEvent(input$apply_group, {
      req(rv$working_data, input$group_id, input$group_nums, input$group_cats, input$agg_method)
      snap()
      df <- rv$working_data
      tryCatch({
        safe_nums <- paste0("`", input$group_nums, "`")
        safe_id <- paste0("`", input$group_id, "`")
        num_form <- as.formula(paste("cbind(", paste(safe_nums, collapse = ","), ") ~", safe_id))
        
        agg_fun <- switch(input$agg_method, 
                          "mean" = mean, 
                          "sum" = sum, 
                          "median" = median, 
                          "min" = min, 
                          "max" = max, 
                          mean)

        plot_nums <- aggregate(num_form, data = df, FUN = agg_fun, na.rm = TRUE)
        cat_cols <- c(input$group_id, input$group_cats)
        plot_cats <- unique(df[, cat_cols, drop = FALSE])
        plot_data <- merge(plot_nums, plot_cats, by = input$group_id)
        rv$working_data <- plot_data
        dataset_pool[[active_dataset()]] <- plot_data
        showNotification(paste("Data aggregated by", input$group_id, "globally! Rows reduced to:", nrow(plot_data)), type = "message")
      }, error = function(e) { showNotification(paste("Aggregation Error:", e$message), type = "error") })
    })

    # ---- Batch apply ----
    observeEvent(input$apply_batch, {
      req(input$batch_targets)
      subset_cols <- isolate(input$eng_subset_cols)
      conv_num <- isolate(input$convert_to_num)
      conv_cat <- isolate(input$convert_to_cat)
      grp_id <- isolate(input$group_id)
      grp_nums <- isolate(input$group_nums)
      grp_cats <- isolate(input$group_cats)
      success_log <- c()
      for (target in input$batch_targets) {
        if (target == active_dataset()) next
        df <- raw_pool[[target]]
        tryCatch({
          if (length(conv_num) > 0) {
            safe_num <- intersect(conv_num, names(df))
            for (col in safe_num) df[[col]] <- as.numeric(as.character(df[[col]]))
          }
          if (length(conv_cat) > 0) {
            safe_cat <- intersect(conv_cat, names(df))
            for (col in safe_cat) df[[col]] <- as.factor(df[[col]])
          }
          raw_pool[[target]] <- df
          if (length(subset_cols) > 0) {
            safe_cols <- intersect(subset_cols, names(df))
            if (length(safe_cols) > 0) df <- df[, safe_cols, drop = FALSE]
          }
          if (isTruthy(grp_id) && grp_id %in% names(df) && length(grp_nums) > 0) {
            safe_nums <- intersect(grp_nums, names(df))
            safe_cats <- intersect(grp_cats, names(df))
            if (length(safe_nums) > 0) {
              df[[grp_id]] <- as.character(df[[grp_id]])
              backtick_nums <- paste0("`", safe_nums, "`")
              backtick_id <- paste0("`", grp_id, "`")
              num_form <- as.formula(paste("cbind(", paste(backtick_nums, collapse = ","), ") ~", backtick_id))
              
              agg_method <- isolate(input$agg_method)
              agg_fun <- switch(agg_method, 
                          "mean" = mean, 
                          "sum" = sum, 
                          "median" = median, 
                          "min" = min, 
                          "max" = max, 
                          mean)

              plot_nums <- aggregate(num_form, data = df, FUN = agg_fun, na.rm = TRUE)
              cat_cols <- c(grp_id, safe_cats)
              plot_cats <- unique(df[, cat_cols, drop = FALSE])
              df <- merge(plot_nums, plot_cats, by = grp_id)
            }
          }
          if (nrow(df) > 0 && ncol(df) > 0) {
            dataset_pool[[target]] <- df
            success_log <- c(success_log, paste0(target, " (", nrow(df), " rows)"))
          } else {
            showNotification(paste("Batch failed for", target, "- resulted in empty dataset."), type = "error")
          }
        }, error = function(e) { showNotification(paste("Error batching", target, ":", e$message), type = "error") })
      }
      if (length(success_log) > 0) showNotification(paste("Batch successfully applied to:", paste(success_log, collapse = ", ")), type = "message", duration = 8)
    })

    # ---- Level management ----
    # Refreshes delete_levels picker from current working data after any mutation.
    refresh_delete_levels <- function() {
      col <- input$delete_lvl_col
      if (!isTruthy(col) || is.null(rv$working_data) || !col %in% names(rv$working_data)) return()
      lvls <- unique(as.character(rv$working_data[[col]]))
      lvls[is.na(lvls)] <- "NA"
      updateSelectInput(session, "delete_levels", choices = lvls)
    }

    output$dynamic_rename_ui <- renderUI({
      req(rv$working_data, input$rename_col)
      lvls <- as.character(unique(na.omit(rv$working_data[[input$rename_col]])))
      rv$current_rename_levels <- lvls
      if (length(lvls) == 0) return(markdown("*No levels found.*"))
      if (length(lvls) > 30) return(markdown("*Too many levels to rename manually (>30).*"))
      ui_list <- lapply(seq_along(lvls), function(i) {
        textInput(ns(paste0("rename_lvl_", i)), label = paste("Rename:", lvls[i]), value = lvls[i])
      })
      do.call(tagList, ui_list)
    })

    observeEvent(input$apply_rename, {
      req(rv$working_data, input$rename_col, rv$current_rename_levels)
      snap()
      df <- rv$working_data
      raw <- raw_pool[[active_dataset()]]
      col <- input$rename_col
      old_lvls <- rv$current_rename_levels
      tryCatch({
        new_lvls <- sapply(seq_along(old_lvls), function(i) { input[[paste0("rename_lvl_", i)]] })
        vec_work <- as.character(df[[col]])
        for (i in seq_along(old_lvls)) vec_work[vec_work == old_lvls[i]] <- new_lvls[i]
        df[[col]] <- as.factor(vec_work)
        rv$working_data <- df
        dataset_pool[[active_dataset()]] <- df
        if (col %in% names(raw)) {
          vec_raw <- as.character(raw[[col]])
          for (i in seq_along(old_lvls)) vec_raw[vec_raw == old_lvls[i]] <- new_lvls[i]
          raw[[col]] <- as.factor(vec_raw)
          raw_pool[[active_dataset()]] <- raw
        }
        showNotification(paste("Levels in", col, "successfully renamed globally and preserved."), type = "message")
        refresh_delete_levels()
      }, error = function(e) { showNotification(paste("Rename Error:", e$message), type = "error") })
    })

    observeEvent(input$agg_col, {
      req(rv$working_data, input$agg_col)
      levels_avail <- unique(as.character(na.omit(rv$working_data[[input$agg_col]])))
      updateSelectInput(session, "agg_levels", choices = levels_avail)
    })

    observeEvent(input$apply_merge, {
      req(rv$working_data, input$agg_col, input$agg_levels, input$agg_new_name)
      snap()
      df <- rv$working_data
      raw <- raw_pool[[active_dataset()]]
      df[[input$agg_col]] <- as.character(df[[input$agg_col]])
      df[[input$agg_col]][df[[input$agg_col]] %in% input$agg_levels] <- input$agg_new_name
      df[[input$agg_col]] <- droplevels(as.factor(df[[input$agg_col]]))
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      if (input$agg_col %in% names(raw)) {
        raw[[input$agg_col]] <- as.character(raw[[input$agg_col]])
        raw[[input$agg_col]][raw[[input$agg_col]] %in% input$agg_levels] <- input$agg_new_name
        raw[[input$agg_col]] <- droplevels(as.factor(raw[[input$agg_col]]))
        raw_pool[[active_dataset()]] <- raw
      }
      updateTextInput(session, "agg_new_name", value = "")
      updateSelectInput(session, "agg_levels", selected = "")
      showNotification("Levels dynamically merged and preserved.", type = "message")
      refresh_delete_levels()
    })

    observeEvent(input$delete_lvl_col, {
      req(rv$working_data, input$delete_lvl_col)
      levels_avail <- unique(as.character(rv$working_data[[input$delete_lvl_col]]))
      levels_avail[is.na(levels_avail)] <- "NA"
      updateSelectInput(session, "delete_levels", choices = levels_avail)
    })

    observeEvent(input$apply_delete_lvl, {
      req(rv$working_data, input$delete_lvl_col, input$delete_levels)
      snap()
      df <- rv$working_data
      raw <- raw_pool[[active_dataset()]]
      
      col <- input$delete_lvl_col
      col_data <- as.character(df[[col]])
      col_data[is.na(col_data)] <- "NA"
      keep_idx <- !(col_data %in% input$delete_levels)
      
      df <- df[keep_idx, , drop = FALSE]
      df <- droplevels(df)
      
      rv$working_data <- df
      dataset_pool[[active_dataset()]] <- df
      
      if (col %in% names(raw)) {
        raw_col_data <- as.character(raw[[col]])
        raw_col_data[is.na(raw_col_data)] <- "NA"
        raw_keep <- !(raw_col_data %in% input$delete_levels)
        raw <- raw[raw_keep, , drop = FALSE]
        raw <- droplevels(raw)
        raw_pool[[active_dataset()]] <- raw
      }
      
      updateSelectInput(session, "delete_levels", selected = "")
      showNotification(paste("Deleted selected levels. Rows remaining:", nrow(df)), type = "message")
      refresh_delete_levels()
    })

    # ---- Dataset Overview ----
    observe({
      pop_arm()                       # re-arm on tool open, see above
      req(rv$working_data)
      cols <- names(rv$working_data)
      curr_view <- if (isTruthy(isolate(input$eng_view_col)) && isolate(input$eng_view_col) %in% cols) isolate(input$eng_view_col) else cols[1]
      updateSelectInput(session, "eng_view_col", choices = cols, selected = curr_view)
    })

    output$overview_stats <- renderUI({
      df <- rv$working_data
      req(!is.null(df), nrow(df) > 0)
      n_complete  <- sum(complete.cases(df))
      pct_complete <- round(100 * n_complete / nrow(df))
      n_na_total  <- sum(is.na(df))
      # Each tile is clickable -> opens a detail modal (see tile_click observer).
      clk <- function(key, vb) tags$div(
        style = "cursor:pointer;", title = "Click to see details",
        onclick = sprintf("Shiny.setInputValue('%s','%s',{priority:'event'})",
                          session$ns("tile_click"), key), vb)
      layout_columns(col_widths = c(2, 2, 2, 2, 2, 2),
        clk("rows", value_box("Rows", format(nrow(df), big.mark=","),
                  showcase=icon("bars"), theme="success")),
        clk("cols", value_box("Columns", ncol(df),
                  showcase=icon("table-columns"), theme="secondary")),
        clk("num", value_box("Numeric", sum(sapply(df, is.numeric)),
                  showcase=icon("hashtag"), theme="secondary")),
        clk("cat", value_box("Categorical", sum(sapply(df, function(x) is.factor(x)||is.character(x))),
                  showcase=icon("tag"), theme="secondary")),
        clk("na", value_box("Total NA", format(n_na_total, big.mark=","),
                  showcase=icon("circle-question"),
                  theme=if(n_na_total > 0) "warning" else "secondary")),
        clk("complete", value_box("Complete rows", paste0(pct_complete, "%"),
                  showcase=icon("circle-check"),
                  theme=if(pct_complete == 100) "success" else "secondary"))
      )
    })

    # ---- Tile drill-down: click an overview tile to inspect the underlying data ----
    tile_dd <- reactiveValues(df = NULL, summary = NULL)
    observeEvent(input$tile_click, {
      df <- rv$working_data
      req(is.data.frame(df), nrow(df) > 0)
      key <- input$tile_click
      tile_dd$df <- NULL; tile_dd$summary <- NULL
      title <- "Detail"; note <- NULL
      if (key == "rows") {
        title <- paste0("All rows (", format(nrow(df), big.mark=","), ")"); tile_dd$df <- df
      } else if (key == "cols") {
        title <- paste0("Columns (", ncol(df), ")")
        tile_dd$df <- data.frame(Column = names(df),
          Type    = vapply(df, function(x) class(x)[1], character(1)),
          Missing = vapply(df, function(x) sum(is.na(x)), integer(1)),
          Unique  = vapply(df, function(x) length(unique(x)), integer(1)),
          row.names = NULL, check.names = FALSE)
      } else if (key == "num") {
        nm <- names(df)[vapply(df, is.numeric, logical(1))]
        title <- paste0("Numeric columns (", length(nm), ")")
        if (length(nm)) tile_dd$df <- df[, nm, drop = FALSE] else note <- "No numeric columns."
      } else if (key == "cat") {
        nm <- names(df)[vapply(df, function(x) is.factor(x)||is.character(x), logical(1))]
        title <- paste0("Categorical columns (", length(nm), ")")
        if (length(nm)) tile_dd$df <- df[, nm, drop = FALSE] else note <- "No categorical columns."
      } else if (key == "na") {
        title <- "Missing values"
        na_by <- vapply(df, function(x) sum(is.na(x)), integer(1))
        tile_dd$summary <- data.frame(Column = names(df), `NA count` = as.integer(na_by),
          `% NA` = round(100 * na_by / nrow(df), 1), row.names = NULL, check.names = FALSE)
        inc <- df[!complete.cases(df), , drop = FALSE]
        if (nrow(inc)) tile_dd$df <- inc else note <- "No missing values — every row is complete."
      } else if (key == "complete") {
        inc <- df[!complete.cases(df), , drop = FALSE]
        title <- paste0("Incomplete rows (", nrow(inc), ")")
        if (nrow(inc)) tile_dd$df <- inc else note <- "All rows are complete — no missing values."
      }
      body <- tagList(
        if (!is.null(note)) tags$p(class = "text-muted", note),
        if (!is.null(tile_dd$summary)) tagList(
          tags$b("Missing per column:"),
          DT::dataTableOutput(session$ns("tile_summary")), tags$hr()),
        if (!is.null(tile_dd$df)) tagList(
          if (!is.null(tile_dd$summary))
            tags$b(paste0("Rows containing missing values (", nrow(tile_dd$df), "):")),
          DT::dataTableOutput(session$ns("tile_detail")))
      )
      showModal(modalDialog(title = title, size = "xl", easyClose = TRUE,
                            footer = modalButton("Close"), body))
    })
    output$tile_detail <- DT::renderDataTable({
      req(tile_dd$df)
      DT::datatable(tile_dd$df, options = list(scrollX = TRUE, pageLength = 8), rownames = TRUE)
    })
    output$tile_summary <- DT::renderDataTable({
      req(tile_dd$summary)
      DT::datatable(tile_dd$summary, options = list(dom = "t", pageLength = 500), rownames = FALSE)
    })

    output$eng_str <- renderUI({
      df <- rv$working_data
      req(!is.null(df), nrow(df) > 0)
      n_rows <- nrow(df)

      # PLAIN WORDS, not tibble/pillar abbreviations. `dbl`/`fct`/`chr` are
      # conventional to R users and meaningless to everyone else -- and this app
      # exists so people do NOT have to write code, so the audience is exactly
      # the group that has never seen <dbl>. The R class goes in the cell's
      # tooltip instead, so nothing is lost for users who do know it.
      .tlbl <- function(x) {
        if (inherits(x, c("Date","POSIXct","POSIXlt"))) "date"
        else if (is.logical(x)) "true/false"
        else if (is.integer(x)) "whole number"
        else if (is.numeric(x)) "number"
        else if (is.factor(x)) "category"
        else if (is.character(x)) "text"
        else class(x)[1]
      }
      .tclass <- function(x) class(x)[1]   # tooltip: the real R class

      rows <- lapply(names(df), function(col) {
        x      <- df[[col]]
        n_na   <- sum(is.na(x))
        pct_na <- 100 * n_na / n_rows
        xc     <- na.omit(x)
        lbl    <- .tlbl(x)

        detail <- if (is.numeric(x) && length(xc) > 0)
          sprintf("min=%.3g  mean=%.3g  max=%.3g  sd=%.3g",
                  min(xc), mean(xc), max(xc), sd(xc))
        else if (is.factor(x) || is.character(x)) {
          lvls <- sort(unique(as.character(xc)))
          paste0(length(lvls), " levels: ",
                 paste(head(lvls, 4), collapse=", "),
                 if (length(lvls) > 4) "…" else "")
        } else "—"

        bg <- if (pct_na > 5) "#fff8e1"
              else if (length(unique(xc)) <= 1 && length(xc) > 0) "#fce4ec"
              else "transparent"

        na_td <- if (n_na == 0)
          tags$td(style="padding:4px 10px;color:#4caf50;font-size:12px;", "0")
        else
          tags$td(style="padding:4px 10px;color:#e65100;font-size:12px;",
                  sprintf("%d (%.1f%%)", n_na, pct_na))

        tags$tr(style=paste0("background:", bg, ";"),
          tags$td(style="padding:4px 10px;font-weight:600;font-size:12px;", col),
          # Plain text, matching the Recommend screen's Data Profile table. The
          # coloured badge this replaced carried six hardcoded hex values that
          # followed no theme, and the colour never meant anything the word did
          # not already say.
          tags$td(style="padding:4px 10px;font-size:11px;color:var(--bark);",
                  title = paste0("R type: ", .tclass(x)), lbl),
          na_td,
          tags$td(style="padding:4px 10px;font-size:11px;color:#555;", detail)
        )
      })

      tags$div(style="overflow-y:auto;max-height:420px;",
        tags$table(class="table table-sm table-hover mb-0",
          tags$thead(class="table-light",
            tags$tr(
              tags$th(style="font-size:11px;padding:4px 10px;", "Column"),
              tags$th(style="font-size:11px;padding:4px 10px;", "Type"),
              tags$th(style="font-size:11px;padding:4px 10px;", "N/A"),
              tags$th(style="font-size:11px;padding:4px 10px;", "Profile")
            )
          ),
          tags$tbody(rows)
        )
      )
    })

    output$eng_table <- renderPrint({
      req(rv$working_data, input$eng_view_col)
      vec <- rv$working_data[[input$eng_view_col]]
      if (is.numeric(vec)) summary(vec) else {
        if (is.factor(vec)) vec <- droplevels(vec)
        table(vec, useNA = "ifany")
      }
    })

    eng_plot_fn <- function() {
      req(rv$working_data, input$eng_view_col)
      vec <- rv$working_data[[input$eng_view_col]]
      if (is.numeric(vec)) {
        par(mar = c(4.5, 4.5, 2, 1))
        boxplot(vec, horizontal = TRUE, main = ea_main(paste("Distribution of", input$eng_view_col)), xlab = ea_xlab(input$eng_view_col), col = "lightgray", outline = TRUE)
        stripchart(vec, method = "jitter", add = TRUE, pch = 16, col = rgb(0,0,0,0.25), cex = 0.8)
      } else {
        if (is.factor(vec)) vec <- droplevels(vec)
        par(mar = c(4.5, 12, 2, 1))
        counts <- rev(sort(table(vec)))
        barplot(counts, horiz = TRUE, las = 1, main = ea_main(paste("Frequencies of", input$eng_view_col)), col = "lightgray", cex.names = 0.9, xlab = ea_xlab("Count"))
      }
    }

    output$eng_plot <- renderPlot({ eng_plot_fn() })

    

    # ---- Exploratory plots (EDA) ----
    observe({
      pop_arm()                       # re-arm on tool open, see above
      df <- rv$working_data
      req(df)
      num_cols <- names(df)[sapply(df, is.numeric)]
      cat_cols <- names(df)[sapply(df, is_safe_cat)]
      curr_num1 <- if (isTruthy(isolate(input$eda_num1)) && isolate(input$eda_num1) %in% num_cols) isolate(input$eda_num1) else if (length(num_cols) > 0) num_cols[1] else NULL
      curr_num2 <- if (isTruthy(isolate(input$eda_num2)) && isolate(input$eda_num2) %in% num_cols) isolate(input$eda_num2) else if (length(num_cols) > 1) num_cols[2] else curr_num1
      curr_cat <- if (isTruthy(isolate(input$eda_category)) && isolate(input$eda_category) %in% cat_cols) isolate(input$eda_category) else if (length(cat_cols) > 0) cat_cols[1] else NULL
      updateSelectInput(session, "eda_num1", choices = num_cols, selected = curr_num1)
      updateSelectInput(session, "eda_num2", choices = num_cols, selected = curr_num2)
      updateSelectInput(session, "eda_category", choices = cat_cols, selected = curr_cat)
    })

    output$eda_single_selector <- renderUI({
      req(input$eda_view_mode == "Single Plot", rv$working_data)
      df <- rv$working_data
      choices <- c(paste("Boxplot:", input$eda_num1), paste("Boxplot:", input$eda_num2), "Scatter: All Data")
      if (isTruthy(input$eda_category) && input$eda_category %in% names(df)) {
        fac <- na.omit(unique(as.character(df[[input$eda_category]])))
        choices <- c(choices, fac)
      }
      selectInput(ns("eda_zoom_target"), label = NULL, choices = choices, width = "200px")
    })

    output$dynamic_eda_plot_ui <- renderUI({
      req(rv$working_data, input$eda_view_mode)
      if (input$eda_view_mode == "Grid View") {
        df <- rv$working_data
        if (isTruthy(input$eda_category) && input$eda_category %in% names(df)) {
          fac <- as.factor(df[[input$eda_category]])
          num_lvls <- length(unique(na.omit(fac)))
          rows <- if (num_lvls > 0) 1 + ceiling(num_lvls / 3) else 1
        } else {
          rows <- 1
        }
        dynamic_height <- max(500, rows * 350)
        plotOutput(ns("relationship_plots"), height = paste0(dynamic_height, "px"))
      } else {
        plotOutput(ns("relationship_plots"), height = "700px")
      }
    })

    output$relationship_plots <- renderPlot({
      df <- rv$working_data
      if (is.null(df)) { show_placeholder("Awaiting valid dataset..."); return() }
      if (input$eda_view_mode == "Single Plot") req(input$eda_zoom_target)
      plot_relationships(df, input$eda_num1, input$eda_num2, input$eda_category,
                         view_mode = input$eda_view_mode, target = input$eda_zoom_target)
    })

    

    # Context (+ the current EDA plot) for the AI Co-Pilot.
    list(
      context = reactive({
        df <- rv$working_data
        if (is.null(df)) return("Data & Exploration — no dataset loaded.")
        paste0("Data & Exploration. Exploratory plot shows Y = ", input$eda_num1,
               ", X = ", input$eda_num2, ", grouped/coloured by = ", input$eda_category,
               " (", input$eda_view_mode, ").\nDataset structure:\n",
               paste(utils::capture.output(str(df)), collapse = "\n"))
      }),
      plot = function() {
        df <- rv$working_data
        if (is.null(df)) { show_placeholder("No dataset loaded."); return() }
        plot_relationships(df, input$eda_num1, input$eda_num2, input$eda_category,
                           view_mode = input$eda_view_mode, target = input$eda_zoom_target)
      }
    )
  })
}
