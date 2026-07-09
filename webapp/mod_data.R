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
dataToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
  accordion(
          id = ns("etl_accordion"),
          open = FALSE,

          accordion_panel("Column Management",
            markdown("**Keep/Drop Columns**"),
            pickerInput(ns("eng_subset_cols"), "Columns to Keep:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
            actionButton(ns("apply_subset"), "Apply Subset", class = "btn-primary btn-sm", width = "100%"),
            hr(),
            pickerInput(ns("eng_drop_cols"), "Columns to Drop:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
            actionButton(ns("apply_drop"), "Drop Selected", class = "btn-danger btn-sm", width = "100%"),
            hr(),
            markdown("**Rename Column**"),
            selectInput(ns("rename_col_target"), "Select Column:", choices = NULL),
            textInput(ns("rename_col_new_name"), "New Name:", placeholder = "Enter new name"),
            actionButton(ns("apply_col_rename"), "Rename Column", class = "btn-primary btn-sm", width = "100%"),
            hr(),
            markdown("**Mutate (Add Numeric Col)**"),
            selectInput(ns("mutate_col1"), "Numeric Col 1:", choices = NULL),
            selectInput(ns("mutate_op"), "Operation:", choices = c("+", "-", "*", "/")),
            selectInput(ns("mutate_col2"), "Numeric Col 2:", choices = NULL),
            textInput(ns("mutate_new_name"), "New Column Name:", placeholder = "e.g., area_calc"),
            actionButton(ns("apply_mutate"), "Create Column", class = "btn-primary btn-sm", width = "100%"),
            hr(),
            actionButton(ns("reset_data"), "Reset to Raw Data", class = "btn-warning btn-sm", width = "100%")
          ),

          accordion_panel("Row Filtering",
            selectInput(ns("filter_col"), "Select Column to Filter:", choices = NULL),
            uiOutput(ns("filter_condition_ui")),
            actionButton(ns("apply_filter"), "Apply Filter", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Type Conversion",
            pickerInput(ns("convert_to_num"), "Convert to Numeric:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
            pickerInput(ns("convert_to_cat"), "Convert to Categorical:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
            actionButton(ns("apply_conversion"), "Apply Conversions", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Level Management",
            markdown("**Rename Levels**"),
            selectInput(ns("rename_col"), "Categorical Column:", choices = NULL),
            uiOutput(ns("dynamic_rename_ui")),
            actionButton(ns("apply_rename"), "Apply Renames", class = "btn-primary btn-sm", width = "100%"),
            hr(),
            markdown("**Merge Levels**"),
            selectInput(ns("agg_col"), "Categorical Column:", choices = NULL),
            selectInput(ns("agg_levels"), "Levels to Merge:", choices = NULL, multiple = TRUE),
            textInput(ns("agg_new_name"), "New Combined Name:", placeholder = "e.g., Wetland"),
            actionButton(ns("apply_merge"), "Merge Levels", class = "btn-primary btn-sm", width = "100%"),
            hr(),
            markdown("**Delete Levels**"),
            selectInput(ns("delete_lvl_col"), "Categorical Column:", choices = NULL),
            selectInput(ns("delete_levels"), "Levels to Delete:", choices = NULL, multiple = TRUE),
            actionButton(ns("apply_delete_lvl"), "Delete Levels", class = "btn-danger btn-sm", width = "100%")
          ),

          accordion_panel("Aggregation",
            selectInput(ns("group_id"), "Aggregate by:", choices = NULL),
            selectInput(ns("agg_method"), "Aggregation Method:", choices = c("Average" = "mean", "Sum" = "sum", "Median" = "median", "Min" = "min", "Max" = "max")),
            pickerInput(ns("group_nums"), "Numeric Columns to Aggregate:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE)),
            pickerInput(ns("group_cats"), "Categorical Columns to Keep:", choices = NULL, multiple = TRUE, options = list(`actions-box` = TRUE, `live-search` = TRUE, `selected-text-format` = "count > 2", `count-selected-text` = "{0} columns selected")),
            actionButton(ns("apply_group"), "Aggregate Data", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Bin/Cut Numeric",
            selectInput(ns("bin_col"), "Numeric Column to Bin:", choices = NULL),
            textInput(ns("bin_breaks"), "Breaks (e.g. -Inf,30,50,Inf):", placeholder = "-Inf, 30, 50, Inf"),
            textInput(ns("bin_labels"), "Labels (comma-separated):", placeholder = "Winter, Dry Summer, Summer"),
            textInput(ns("bin_new_name"), "New Column Name:", placeholder = "Trafficability_Class"),
            actionButton(ns("apply_bin"), "Create Bins", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Conditional Imputation",
            markdown("*Fill missing values (NA) in the Primary column using values from the Secondary column.*"),
            selectInput(ns("coalesce_primary"), "Primary Column (Target):", choices = NULL),
            selectInput(ns("coalesce_secondary"), "Secondary Column (Source):", choices = NULL),
            actionButton(ns("apply_coalesce"), "Impute Missing Values", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Merge/Join Datasets",
            selectInput(ns("join_target"), "Dataset to Join With:", choices = NULL),
            selectInput(ns("join_type"), "Join Type:", choices = c("Left Join" = "left", "Inner Join" = "inner", "Full Join" = "full", "Right Join" = "right")),
            selectInput(ns("join_by"), "Common ID Column:", choices = NULL),
            actionButton(ns("apply_join"), "Merge Datasets", class = "btn-primary btn-sm", width = "100%")
          ),

          accordion_panel("Batch Apply Pipeline",
            markdown("*Instantly apply active settings to other datasets.*"),
            selectInput(ns("batch_targets"), "Select Datasets to Update:", choices = NULL, multiple = TRUE),
            actionButton(ns("apply_batch"), "Batch Apply Settings", class = "btn-danger btn-sm", width = "100%")
          )
  )  # end accordion
  )  # end tagList
}

# Center-canvas content for the Data view (Dataset Overview / Exploratory Plots).
dataCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
        nav_panel("Dataset Overview",
          uiOutput(ns("overview_stats")),
          card(
            card_header(class = "d-flex justify-content-between align-items-center bg-light",
              "Dataset Structure",
              downloadButton(ns("download_data"), "Download CSV", class = "btn-sm btn-outline-success")),
            div(style = "padding: 5px;", uiOutput(ns("eng_str")))
          )
        ),
        nav_panel("Column Distributions",
          card(
            card_header(class = "d-flex justify-content-between align-items-center bg-light",
              "Active Column Distributions",
              downloadButton(ns("download_dist_plot"), "Download Plot", class = "btn-sm btn-outline-success")),
            div(style = "padding: 5px;",
              selectInput(ns("eng_view_col"), "View Frequency/Summary of:", choices = NULL),
              layout_columns(col_widths = c(6, 6),
                plotOutput(ns("eng_plot"), height = "350px"),
                div(style = "overflow-y: auto; height: 350px;", verbatimTextOutput(ns("eng_table")))
              )
            )
          )
        ),
        nav_panel("Exploratory Plots",
          # Column pickers live WITH the plot so you can change variables right here.
          div(class = "d-flex flex-wrap align-items-end gap-2 mb-2",
            div(style = "min-width: 150px;", selectInput(ns("eda_num1"), "Y-Axis (numeric)", choices = NULL, width = "100%")),
            div(style = "min-width: 150px;", selectInput(ns("eda_num2"), "X-Axis (numeric)", choices = NULL, width = "100%")),
            div(style = "min-width: 150px;", selectInput(ns("eda_category"), "Group (colour)", choices = NULL, width = "100%")),
            div(class = "ms-auto d-flex align-items-end gap-2",
              radioGroupButtons(ns("eda_view_mode"), label = NULL, choices = c("Grid View", "Single Plot"), selected = "Grid View", size = "sm", status = "primary"),
              uiOutput(ns("eda_single_selector")),
              downloadButton(ns("download_eda_plot"), "Download Plot", class = "btn-sm btn-outline-success")
            )
          ),
          div(style = "padding: 5px; overflow-x: hidden; overflow-y: auto; height: 600px;", uiOutput(ns("dynamic_eda_plot_ui")))
        )
      )
}

dataServer <- function(id, raw_pool, dataset_pool, dataset_names, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    rv <- reactiveValues(working_data = NULL, current_rename_levels = NULL)
    prev_state <- reactiveVal(NULL)  # one-step undo snapshot

    # Helper: snapshot current state before any mutation
    snap <- function() prev_state(rv$working_data)

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

    # ---- Undo last operation ----
    observeEvent(input$undo_last, {
      req(active_dataset())
      prev <- prev_state()
      if (is.null(prev)) { showNotification("Nothing to undo.", type = "warning"); return() }
      rv$working_data <- prev
      dataset_pool[[active_dataset()]] <- prev
      prev_state(NULL)
      showNotification("Last change undone.", type = "message")
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
    observeEvent(rv$working_data, {
      req(rv$working_data)
      df <- rv$working_data
      cols <- names(df)
      num_cols <- names(df)[sapply(df, is.numeric)]
      cat_cols <- names(df)[!sapply(df, is.numeric)]

      updatePickerInput(session, "eng_subset_cols", choices = names(raw_pool[[active_dataset()]]), selected = cols)
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
    })

    # Datasets available to join / batch against.
    observeEvent(dataset_names(), {
      updateSelectInput(session, "batch_targets", choices = dataset_names())
      updateSelectInput(session, "join_target", choices = dataset_names())
    })

    output$download_data <- downloadHandler(
      filename = function() { paste0("cleaned_", active_dataset(), "_", Sys.Date(), ".csv") },
      content = function(file) { write.csv(rv$working_data, file, row.names = FALSE) }
    )

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
      layout_columns(col_widths = c(2, 2, 2, 2, 2, 2),
        value_box("Rows",        format(nrow(df), big.mark=","),
                  showcase=icon("rows"),          theme="success"),
        value_box("Columns",     ncol(df),
                  showcase=icon("table-columns"), theme="secondary"),
        value_box("Numeric",     sum(sapply(df, is.numeric)),
                  showcase=icon("hashtag"),       theme="secondary"),
        value_box("Categorical", sum(sapply(df, function(x) is.factor(x)||is.character(x))),
                  showcase=icon("tag"),           theme="secondary"),
        value_box("Total NA",    format(n_na_total, big.mark=","),
                  showcase=icon("circle-question"),
                  theme=if(n_na_total > 0) "warning" else "secondary"),
        value_box("Complete rows", paste0(pct_complete, "%"),
                  showcase=icon("circle-check"),
                  theme=if(pct_complete == 100) "success" else "secondary")
      )
    })

    output$eng_str <- renderUI({
      df <- rv$working_data
      req(!is.null(df), nrow(df) > 0)
      n_rows <- nrow(df)

      .tlbl <- function(x) {
        if (inherits(x, c("Date","POSIXct","POSIXlt"))) "date"
        else if (is.logical(x)) "lgl"
        else if (is.integer(x)) "int"
        else if (is.numeric(x)) "dbl"
        else if (is.factor(x)) "fct"
        else if (is.character(x)) "chr"
        else class(x)[1]
      }
      .tcol <- function(lbl) switch(lbl,
        dbl="#1565c0", int="#1565c0", fct="#2e7d32", chr="#33691e",
        date="#6a1b9a", lgl="#e65100", "#555")

      rows <- lapply(names(df), function(col) {
        x      <- df[[col]]
        n_na   <- sum(is.na(x))
        pct_na <- 100 * n_na / n_rows
        xc     <- na.omit(x)
        lbl    <- .tlbl(x)
        clr    <- .tcol(lbl)

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
          tags$td(style="padding:4px 10px;",
            tags$span(class="badge",
                      style=paste0("background:", clr, "22;color:", clr,
                                   ";font-size:10px;font-weight:600;border:1px solid ", clr, "44;"),
                      lbl)),
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
        boxplot(vec, horizontal = TRUE, main = paste("Distribution of", input$eng_view_col), xlab = input$eng_view_col, col = "lightgray", outline = TRUE)
        stripchart(vec, method = "jitter", add = TRUE, pch = 16, col = rgb(0,0,0,0.25), cex = 0.8)
      } else {
        if (is.factor(vec)) vec <- droplevels(vec)
        par(mar = c(4.5, 12, 2, 1))
        counts <- rev(sort(table(vec)))
        barplot(counts, horiz = TRUE, las = 1, main = paste("Frequencies of", input$eng_view_col), col = "lightgray", cex.names = 0.9, xlab = "Count")
      }
    }

    output$eng_plot <- renderPlot({ eng_plot_fn() })

    output$download_dist_plot <- downloadHandler(
      filename = function() { paste0("distribution_", input$eng_view_col, "_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 800, height = 600); eng_plot_fn(); dev.off() }
    )

    # ---- Exploratory plots (EDA) ----
    observe({
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

    output$download_eda_plot <- downloadHandler(
      filename = function() { paste0("eda_relationships_", Sys.Date(), ".png") },
      content = function(file) {
        df <- rv$working_data
        if (isTruthy(input$eda_category) && input$eda_category %in% names(df)) {
          fac <- as.factor(df[[input$eda_category]])
          num_lvls <- length(unique(na.omit(fac)))
          rows <- if (num_lvls > 0) 1 + ceiling(num_lvls / 3) else 1
        } else {
          rows <- 1
        }
        png_height <- if (input$eda_view_mode == "Grid View") max(600, rows * 400) else 600
        png(file, width = 1000, height = png_height)
        plot_relationships(df, input$eda_num1, input$eda_num2, input$eda_category,
                           view_mode = input$eda_view_mode, target = input$eda_zoom_target)
        dev.off()
      }
    )

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
