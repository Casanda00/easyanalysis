# ==========================================================================
# helpers.R  --  shared, stateless helper + plotting functions
# Sourced by global.R so every module can use them. Ported verbatim from the
# legacy server. (AI/OpenAI helpers are intentionally NOT here yet.)
# ==========================================================================

# Null-coalescing: return a if non-null and non-empty, else b.
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# ==========================================================================
# Cross-validation and classification metric helpers
# ==========================================================================

# Exact LOO for any lm/lm-derived model via hat-matrix shortcut (O(n), no refits).
.loocv_lm <- function(model) {
  h     <- hatvalues(model)
  e     <- residuals(model)
  e_loo <- e / (1 - h)
  obs   <- model$model[[1]]
  ss_tot <- sum((obs - mean(obs))^2)
  list(
    LOOCV_RMSE = round(sqrt(mean(e_loo^2)), 4),
    LOOCV_MAE  = round(mean(abs(e_loo)), 4),
    LOOCV_R2   = round(1 - sum(e_loo^2) / ss_tot, 4)
  )
}

# Generic k-fold CV for lm / glm (returns regression or accuracy metrics).
.kfold_cv <- function(formula, data, k = 5, type = "regression", family = gaussian()) {
  set.seed(42)
  n     <- nrow(data)
  folds <- sample(rep_len(seq_len(k), n))
  preds <- actual <- c()
  for (fold in seq_len(k)) {
    tr <- data[folds != fold, , drop = FALSE]
    te <- data[folds == fold, , drop = FALSE]
    m <- tryCatch(
      if (type == "regression") lm(formula, data = tr)
      else glm(formula, data = tr, family = family),
      error = function(e) NULL)
    if (is.null(m)) next
    p <- tryCatch(predict(m, newdata = te), error = function(e) NULL)
    if (is.null(p)) next
    preds  <- c(preds,  as.numeric(p))
    actual <- c(actual, as.numeric(te[[all.vars(formula)[1]]]))
  }
  if (!length(preds)) return(NULL)
  if (type == "regression") {
    e <- actual - preds
    list(CV_RMSE = round(sqrt(mean(e^2)), 4),
         CV_MAE  = round(mean(abs(e)), 4),
         CV_R2   = round(1 - sum(e^2) / sum((actual - mean(actual))^2), 4))
  } else {
    list(CV_Accuracy = round(mean(round(preds) == actual, na.rm = TRUE), 4))
  }
}

# Per-class + macro-average Precision / Recall / F1 from two character vectors.
.clf_prf <- function(actual, predicted) {
  actual    <- as.character(actual)
  predicted <- as.character(predicted)
  classes   <- sort(unique(c(actual, predicted)))
  rows <- lapply(classes, function(cls) {
    tp  <- sum(actual == cls & predicted == cls)
    fp  <- sum(actual != cls & predicted == cls)
    fn  <- sum(actual == cls & predicted != cls)
    prec  <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    rec   <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
    f1    <- if (!is.na(prec) && !is.na(rec) && prec + rec > 0)
              2 * prec * rec / (prec + rec) else NA_real_
    data.frame(Class = cls, Precision = round(prec, 3),
               Recall = round(rec, 3), F1 = round(f1, 3),
               Support = as.integer(sum(actual == cls)),
               stringsAsFactors = FALSE)
  })
  df <- do.call(rbind, rows)
  macro <- data.frame(
    Class     = "— Macro avg",
    Precision = round(mean(df$Precision, na.rm = TRUE), 3),
    Recall    = round(mean(df$Recall,    na.rm = TRUE), 3),
    F1        = round(mean(df$F1,        na.rm = TRUE), 3),
    Support   = as.integer(length(actual)),
    stringsAsFactors = FALSE)
  rbind(df, macro)
}

# Render a .clf_prf() result as a compact DT datatable.
# prf_or_list: a single data.frame OR a named list of them (one per stage/source).
# acc_or_list: a single accuracy OR a matching named list of accuracies.
.prf_dt <- function(prf_or_list, acc_or_list = NULL) {
  fmt3 <- function(x) ifelse(is.na(x), "—", sprintf("%.3f", x))
  if (is.data.frame(prf_or_list)) {
    df  <- prf_or_list
    df$Precision <- fmt3(df$Precision)
    df$Recall    <- fmt3(df$Recall)
    df$F1        <- fmt3(df$F1)
    cap <- if (!is.null(acc_or_list) && length(acc_or_list) == 1 && !is.na(acc_or_list))
      sprintf("Accuracy: %.1f%%", acc_or_list * 100) else NULL
    tbl <- DT::datatable(df, rownames = FALSE, caption = cap,
      options = list(dom = "t", paging = FALSE, ordering = FALSE, scrollX = FALSE),
      class = "compact stripe")
  } else {
    parts <- lapply(names(prf_or_list), function(nm) {
      prf <- prf_or_list[[nm]]
      acc <- if (is.list(acc_or_list)) acc_or_list[[nm]] else NULL
      src <- if (!is.null(acc) && length(acc) == 1 && !is.na(acc))
        sprintf("%s  (Acc %.1f%%)", nm, acc * 100) else nm
      cbind(Source = src, prf)
    })
    df <- do.call(rbind, parts)
    df$Precision <- fmt3(df$Precision)
    df$Recall    <- fmt3(df$Recall)
    df$F1        <- fmt3(df$F1)
    tbl <- DT::datatable(df, rownames = FALSE,
      options = list(dom = "t", paging = FALSE, ordering = FALSE, scrollX = FALSE),
      class = "compact stripe")
  }
  tbl |>
    DT::formatStyle("Class", target = "row",
      fontWeight      = DT::styleEqual("— Macro avg", "bold"),
      backgroundColor = DT::styleEqual("— Macro avg", "color-mix(in srgb, var(--canopy) 16%, transparent)"))
}

# Render regression metrics as a compact DT: Metric | stage1 | stage2 …
# metrics_list: named list of stages; each stage is a named list of metric values.
# Keys may carry LOOCV_ or CV_ prefixes — they are stripped automatically.
.reg_metrics_dt <- function(metrics_list) {
  norm <- function(k) sub("^(LOOCV|CV)_", "", k)
  ml   <- lapply(metrics_list, function(m) setNames(m, norm(names(m))))
  key_ord <- c("RMSE", "MAE", "R2", "RRMSE", "Bias", "RelBias", "Accuracy")
  all_k   <- unique(unlist(lapply(ml, names)))
  all_k   <- c(intersect(key_ord, all_k), setdiff(all_k, key_ord))
  lbl_map <- c(RMSE = "RMSE", MAE = "MAE", R2 = "R²", RRMSE = "RRMSE",
               Bias = "Bias", RelBias = "Rel. Bias", Accuracy = "Accuracy")
  stages  <- names(metrics_list)
  rows <- lapply(all_k, function(k) {
    vals <- vapply(stages, function(nm) {
      v <- ml[[nm]][[k]]
      if (is.null(v) || (length(v) == 1 && is.na(v))) "—"
      else if (k == "Accuracy") sprintf("%.1f%%", as.numeric(v) * 100)
      else sprintf("%.4f", as.numeric(v))
    }, character(1))
    setNames(c(lbl_map[k] %||% k, vals), c("Metric", stages))
  })
  df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  DT::datatable(df, rownames = FALSE,
    options = list(dom = "t", paging = FALSE, ordering = FALSE, scrollX = FALSE),
    class = "compact stripe") |>
    DT::formatStyle("Metric", fontWeight = "bold")
}

# Page-size choices for any table showing a USER'S OWN DATA (attribute table,
# data view, View Data modal). DT's default lengthMenu is 10/25/50/100, so the
# largest page anyone could ask for was 100 rows -- which reads as "this table
# only holds 100", and did. -1 is DT's code for All; it comes last because with
# server-side tables it genuinely ships every row, so it should be a deliberate
# choice rather than something to stumble into.
#
# Only for data tables. Small fixed result tables (metrics, coefficients) use
# dom = "t" with no pager and must not get this.
ea_dt_len <- function()
  list(lengthMenu = list(c(10, 25, 50, 100, 500, 1000, -1),
                         c("10", "25", "50", "100", "500", "1000", "All")))

# ---- Linking an analysis back to the layer it came from (item 42) ----------
#
# The problem: a model is fitted on a COPY of a layer's attributes, and an
# analysis routinely drops incomplete rows. Writing results back by position
# would therefore attach predictions to the wrong features -- producing a map
# that looks entirely plausible and is wrong. That is the worst possible failure
# for this feature, so the link is made explicit and verified rather than
# assumed.
#
# Two pieces:
#   ea_layer_fingerprint() proves the layer has not changed since the export.
#   ea_fit_rows()          recovers WHICH original rows a fit actually used.

# A digest of a layer's attributes. Identical fingerprint => same rows, same
# order, so the positional link still holds. Geometry is deliberately excluded:
# moving a vertex does not invalidate a model fitted on attributes, and
# including it would refuse write-backs that are perfectly valid.
#
# `cols` scopes it to the columns the model actually saw. That matters: writing
# results back ADDS columns to the layer, so a whole-table fingerprint would
# then refuse a second, perfectly valid write-back — the tool refusing its own
# previous output. Scoping to the exported columns keeps every real protection
# (a deleted feature changes the row count, an edited value changes the digest,
# a renamed column goes missing) while being blind to columns added afterwards.
ea_layer_fingerprint <- function(v, cols = NULL) {
  df <- tryCatch(as.data.frame(sf::st_drop_geometry(v)), error = function(e) NULL)
  if (is.null(df)) return(NA_character_)
  if (!is.null(cols)) {
    if (!all(cols %in% names(df))) return(NA_character_)   # a modelled column is gone
    df <- df[, cols, drop = FALSE]
  }
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(list(nrow(df), names(df), df), algo = "xxhash64"))
  # digest ships with shiny, so this is belt-and-braces rather than expected.
  paste(nrow(df), ncol(df), paste(names(df), collapse = "|"), sep = "/")
}

# Which rows of the ORIGINAL data frame did this fit actually use?
#
# R already tracks this: model.frame() keeps the original row names, so a fit
# that dropped incomplete rows still says which ones it kept. Using R's own
# bookkeeping is safer than re-deriving complete.cases() here, because each
# method decides for itself what "usable" means (a factor level with one
# observation, a zero-variance column, its own na.action).
#
# Returns integer row indices, or NULL when the fit does not expose them -- and
# NULL must be treated as "cannot link", never as "assume 1:n".
ea_fit_rows <- function(fit, n_expected = NA_integer_) {
  rn <- tryCatch(rownames(stats::model.frame(fit)), error = function(e) NULL)
  if (is.null(rn)) rn <- tryCatch(names(stats::fitted(fit)), error = function(e) NULL)
  if (is.null(rn) || !length(rn)) return(NULL)
  i <- suppressWarnings(as.integer(rn))
  if (any(is.na(i))) return(NULL)                    # non-numeric row names
  if (!is.na(n_expected) && (any(i < 1L) || any(i > n_expected))) return(NULL)
  i
}

# Pretty-print .clf_prf() result to console.
.print_prf <- function(prf_df, acc = NULL) {
  if (!is.null(acc))
    cat(sprintf("Overall accuracy : %.1f%%\n\n", acc * 100))
  cat(sprintf("%-20s %9s %9s %9s %9s\n",
              "Class", "Precision", "Recall", "F1", "Support"))
  cat(strrep("-", 60), "\n")
  for (i in seq_len(nrow(prf_df))) {
    r <- prf_df[i, ]
    cat(sprintf("%-20s %9s %9s %9s %9d\n",
                r$Class,
                ifelse(is.na(r$Precision), "   —", sprintf("%.3f", r$Precision)),
                ifelse(is.na(r$Recall),    "   —", sprintf("%.3f", r$Recall)),
                ifelse(is.na(r$F1),        "   —", sprintf("%.3f", r$F1)),
                r$Support))
  }
}

# Shared UI widget for cross-validation method selection.
# Drop into any module's tools panel; read input$cv_method and input$cv_k in the server.
.cv_ui <- function(ns) {
  tagList(
    tags$h6(class = "text-uppercase text-muted small mt-2", "Cross-Validation"),
    radioButtons(ns("cv_method"), NULL,
                 choices  = c("LOOCV (Leave-One-Out)" = "loocv", "K-Fold" = "kfold"),
                 selected = "kfold", inline = TRUE),
    conditionalPanel(
      condition = sprintf("input['%s'] === 'kfold'", ns("cv_method")),
      numericInput(ns("cv_k"), "Number of Folds (k):",
                   value = 5, min = 2, max = 20, step = 1, width = "100%")
    )
  )
}

# Helper: resolve k from CV inputs (returns nrow(data) for LOOCV).
.cv_k <- function(input, data) {
  if (!is.null(input$cv_method) && input$cv_method == "loocv") nrow(data)
  else max(2L, as.integer(input$cv_k %||% 5L))
}

# Helper: short label for cv method used in output text.
.cv_label <- function(k, n) {
  if (k >= n) "LOOCV" else paste0(k, "-Fold CV")
}

# ggplot2 confusion matrix heatmap (tile + count text, recall-normalised colour).
# cm_table: a table() with dims [Predicted, Actual].
.plot_conf_matrix <- function(cm_table, title = "Confusion Matrix") {
  df_cm <- as.data.frame(cm_table)
  names(df_cm) <- c("Predicted", "Actual", "Count")
  totals <- tapply(df_cm$Count, df_cm$Actual, sum)
  df_cm$Recall <- df_cm$Count / totals[as.character(df_cm$Actual)]
  df_cm$Recall[is.nan(df_cm$Recall) | is.na(df_cm$Recall)] <- 0
  ggplot(df_cm, aes(x = Actual, y = Predicted, fill = Recall)) +
    geom_tile(color = "white", linewidth = 0.8) +
    geom_text(aes(label = Count), size = 4.5, fontface = "bold") +
    scale_fill_gradient2(low = "#f8d7da", mid = "#fff3cd", high = "#d1e7dd",
                         midpoint = 0.5, limits = c(0, 1), guide = "none") +
    labs(title = title, x = "Actual", y = "Predicted") +
    theme_minimal(base_size = 13) +
    theme(panel.grid = element_blank(),
          axis.text  = element_text(size = 11),
          plot.title = element_text(face = "bold", size = 14),
          axis.title = element_text(face = "bold"))
}

# Render a plotting function to an off-screen PNG and return base64 (for AI vision).
# Returns NULL if there is nothing to draw or the plot errors.
capture_plot_as_base64 <- function(plot_fn) {
  if (!is.function(plot_fn)) return(NULL)
  tmp <- tempfile(fileext = ".png")
  ok <- TRUE
  grDevices::png(tmp, width = 900, height = 650)
  tryCatch(plot_fn(), error = function(e) { ok <<- FALSE })
  grDevices::dev.off()
  if (!ok) { unlink(tmp); return(NULL) }
  b64 <- tryCatch(base64enc::base64encode(tmp), error = function(e) NULL)
  unlink(tmp)
  b64
}

show_placeholder <- function(msg) {
  par(mar = c(0,0,0,0))
  plot(c(0, 1), c(0, 1), ann = FALSE, bty = 'n', type = 'n', xaxt = 'n', yaxt = 'n')
  text(x = 0.5, y = 0.5, paste(msg), cex = 1.2, col = "#6c757d")
}

is_safe_cat <- function(vec) {
  if (!(is.factor(vec) || is.character(vec))) return(FALSE)
  lvls <- length(unique(vec[!is.na(vec)]))
  return(lvls > 1 && lvls <= 50)
}

init_data <- function(df) {
  if ("Organic_depth" %in% names(df)) {
    df$Organic_depth <- as.numeric(as.character(df$Organic_depth))
  }
  return(df)
}

plot_relationships <- function(df, num1, num2, cat_var, view_mode = "Grid View", target = NULL) {
  if (is.null(df) || !isTruthy(cat_var) || !isTruthy(num1) || !isTruthy(num2) || !(cat_var %in% names(df))) {
    show_placeholder("Awaiting valid numeric and categorical variables...")
    return()
  }

  plot_df <- df[complete.cases(df[, c(num1, num2, cat_var)]), ]
  if (nrow(plot_df) == 0) {
    show_placeholder("Data Error: No complete cases available.")
    return()
  }

  plot_df[[cat_var]] <- droplevels(as.factor(plot_df[[cat_var]]))
  fac <- plot_df[[cat_var]]
  num_levels <- length(levels(fac))
  pal <- if(num_levels > 8) rainbow(num_levels) else palette()[1:num_levels]

  wrap_text <- function(x) paste(strwrap(x, width = 15), collapse = "\n")
  wrapped_lvls <- sapply(levels(fac), wrap_text)
  counts <- as.numeric(table(fac))
  wrapped_lvls_with_n <- paste0(wrapped_lvls, "\n(n=", counts, ")")

  safe_num1 <- paste0("`", num1, "`")
  safe_num2 <- paste0("`", num2, "`")
  safe_cat <- paste0("`", cat_var, "`")

  if (view_mode == "Grid View") {
    rows <- 1 + ceiling(num_levels / 3)
    old_par <- ea_multi_par(mfrow = c(rows, 3), mar = c(6, 5, 4, 1) + 0.1, mgp = c(3, 1, 0))
    on.exit({ ea_fig_title(); par(old_par) })

    form1 <- as.formula(paste(safe_num1, "~", safe_cat))
    boxplot(form1, data = plot_df, main = paste(num1, "by", cat_var), ylab = num1, col = "lightblue",
            names = rep("", num_levels), xlab = "", las = 1, cex.lab = 1.3, cex.axis = 1.1, cex.main = 1.4, outline = FALSE)
    stripchart(form1, data = plot_df, vertical = TRUE, method = "jitter", add = TRUE, pch = 16, col = rgb(0, 0, 0, 0.25), cex = 0.8)
    text(x = 1:num_levels, y = par("usr")[3] - (par("usr")[4] - par("usr")[3]) * 0.03, labels = wrapped_lvls_with_n, xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.1)

    form2 <- as.formula(paste(safe_num2, "~", safe_cat))
    boxplot(form2, data = plot_df, main = paste(num2, "by", cat_var), ylab = num2, col = "lightgreen",
            names = rep("", num_levels), xlab = "", las = 1, cex.lab = 1.3, cex.axis = 1.1, cex.main = 1.4, outline = FALSE)
    stripchart(form2, data = plot_df, vertical = TRUE, method = "jitter", add = TRUE, pch = 16, col = rgb(0, 0, 0, 0.25), cex = 0.8)
    text(x = 1:num_levels, y = par("usr")[3] - (par("usr")[4] - par("usr")[3]) * 0.03, labels = wrapped_lvls_with_n, xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.1)

    plot(plot_df[[num1]], plot_df[[num2]], col = pal[as.numeric(fac)], pch = 16,
         main = paste(num1, "vs", num2, "\n(All Data)"), xlab = num1, ylab = num2, cex.lab = 1.3, cex.axis = 1.2, cex.main = 1.4)
    legend("bottomright", legend = levels(fac), col = pal, pch = 16, cex = 1.1, bty = "n")

    for (i in seq_along(levels(fac))) {
      lvl <- levels(fac)[i]
      sub_df <- plot_df[plot_df[[cat_var]] == lvl, ]
      if(nrow(sub_df) > 0) {
        plot(sub_df[[num1]], sub_df[[num2]], col = pal[i], pch = 16,
             main = paste0(wrap_text(lvl), "\n(n=", nrow(sub_df), ")"), xlab = num1, ylab = num2, cex.lab = 1.3, cex.axis = 1.2, cex.main = 1.4)
      } else { show_placeholder("No data") }
    }
  } else {
    old_par <- par(mar = c(11, 7, 7, 2) + 0.1, mgp = c(5, 1.5, 0))
    on.exit(par(old_par))
    if (is.null(target)) { show_placeholder("Select a plot to zoom."); return() }

    if (target == paste("Boxplot:", num1)) {
      form1 <- as.formula(paste(safe_num1, "~", safe_cat))
      boxplot(form1, data = plot_df, main = paste(num1, "by", cat_var), ylab = num1, col = "lightblue",
              names = rep("", num_levels), xlab = "", las = 1, cex.lab = 1.5, cex.axis = 1.2, cex.main = 1.8, outline = FALSE)
      stripchart(form1, data = plot_df, vertical = TRUE, method = "jitter", add = TRUE, pch = 16, col = rgb(0, 0, 0, 0.3), cex = 1.2)
      text(x = 1:num_levels, y = par("usr")[3] - (par("usr")[4] - par("usr")[3]) * 0.03, labels = wrapped_lvls_with_n, xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.2)

    } else if (target == paste("Boxplot:", num2)) {
      form2 <- as.formula(paste(safe_num2, "~", safe_cat))
      boxplot(form2, data = plot_df, main = paste(num2, "by", cat_var), ylab = num2, col = "lightgreen",
              names = rep("", num_levels), xlab = "", las = 1, cex.lab = 1.5, cex.axis = 1.2, cex.main = 1.8, outline = FALSE)
      stripchart(form2, data = plot_df, vertical = TRUE, method = "jitter", add = TRUE, pch = 16, col = rgb(0, 0, 0, 0.3), cex = 1.2)
      text(x = 1:num_levels, y = par("usr")[3] - (par("usr")[4] - par("usr")[3]) * 0.03, labels = wrapped_lvls_with_n, xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.2)

    } else if (target == "Scatter: All Data") {
      plot(plot_df[[num1]], plot_df[[num2]], col = pal[as.numeric(fac)], pch = 16, cex = 1.5,
           main = paste(num1, "vs", num2, "\n(All Data)"), xlab = num1, ylab = num2, cex.lab = 1.5, cex.axis = 1.3, cex.main = 1.8)
      legend("bottomright", legend = levels(fac), col = pal, pch = 16, cex = 1.2, bty = "n")
    } else {
      lvl <- target; idx <- match(lvl, levels(fac))
      sub_df <- plot_df[plot_df[[cat_var]] == lvl, ]
      if(nrow(sub_df) > 0) {
        plot(sub_df[[num1]], sub_df[[num2]], col = pal[idx], pch = 16, cex = 1.5,
             main = paste0(wrap_text(lvl), "\n(n=", nrow(sub_df), ")"), xlab = num1, ylab = num2, cex.lab = 1.5, cex.axis = 1.3, cex.main = 1.8)
      } else { show_placeholder("No data") }
    }
  }
}

plot_log_diagnostics <- function(model_obj, target_var) {
  if (is.character(model_obj)) {
    show_placeholder(model_obj)
    return()
  }
  preds <- predict(model_obj$model)
  actual <- model_obj$data[[target_var]]
  tbl <- table(Actual = actual, Predicted = preds)

  old_par <- par(mar = c(4, 4, 2, 2))
  on.exit(par(old_par))
  mosaicplot(tbl, main = "Classification: Actual vs Predicted",
             color = c("lightgray", "lightblue", "lightgreen", "lightcoral"),
             las = 1, cex.axis = 1.1)
}

plot_aov_diagnostics <- function(model, view_mode, target) {
  if (is.character(model)) {
    show_placeholder(model)
    return()
  }

  if (view_mode == "Grid View") {
    old_par <- ea_multi_par(mfrow = c(1, 2), mar = c(6, 6, 5, 2) + 0.1, mgp = c(4, 1.2, 0))
    on.exit({ ea_fig_title(); par(old_par) })
    plot(model, which = 1, cex.lab = 1.3, cex.main = 1.5)
    plot(model, which = 2, cex.lab = 1.3, cex.main = 1.5)
  } else {
    old_par <- par(mar = c(6, 6, 5, 2) + 0.1, mgp = c(4.5, 1.2, 0))
    on.exit(par(old_par))
    if (is.null(target)) return()
    if (target == "Residuals vs Fitted") plot(model, which = 1, cex.lab = 1.4, cex.axis = 1.2, cex.main = 1.6, cex = 1.5)
    else plot(model, which = 2, cex.lab = 1.4, cex.axis = 1.2, cex.main = 1.6, cex = 1.5)
  }
}

.quality_check <- function(df) {
  msgs <- character(0)
  # Some sources (e.g. rhandsontable hot_to_r on empty cells) yield list-columns,
  # which break duplicated()/sapply below. Flatten any list-column to a vector.
  for (j in seq_along(df)) if (is.list(df[[j]]))
    df[[j]] <- vapply(df[[j]], function(v)
      if (length(v)) as.character(v[[1]]) else NA_character_, character(1))
  col_miss <- 100 * sapply(df, function(x) mean(is.na(x)))
  high_miss <- names(col_miss[col_miss > 20])
  mod_miss  <- names(col_miss[col_miss >  5 & col_miss <= 20])
  if (length(high_miss) > 0)
    msgs <- c(msgs, sprintf("High missing (&gt;20%%): <b>%s</b> — consider imputation or removal.", paste(high_miss, collapse = ", ")))
  if (length(mod_miss) > 0)
    msgs <- c(msgs, sprintf("Moderate missing (5–20%%): <b>%s</b>", paste(mod_miss, collapse = ", ")))
  n_dup <- sum(duplicated(df))
  if (n_dup > 0)
    msgs <- c(msgs, sprintf("<b>%d duplicate row(s)</b> detected.", n_dup))
  near_const <- names(df)[sapply(df, function(x) {
    tbl <- table(x, useNA = "no")
    length(tbl) > 0 && max(tbl) / sum(tbl) > 0.95
  })]
  if (length(near_const) > 0)
    msgs <- c(msgs, sprintf("Near-constant column(s): <b>%s</b>", paste(near_const, collapse = ", ")))
  num_nms <- names(df)[sapply(df, is.numeric)]
  skewed_cols <- num_nms[sapply(num_nms, function(v) {
    x <- na.omit(df[[v]])
    if (length(x) < 5 || sd(x) == 0) return(FALSE)
    abs(mean((x - mean(x))^3) / sd(x)^3) > 2
  })]
  if (length(skewed_cols) > 0)
    msgs <- c(msgs, sprintf("Highly skewed — log transform may help: <b>%s</b>", paste(skewed_cols, collapse = ", ")))
  msgs
}

plot_lm_diagnostics <- function(model, dataset, y_var, view_mode, target) {
  if (is.character(model)) {
    show_placeholder(model)
    return()
  }

  if (view_mode == "Grid View") {
    old_par <- ea_multi_par(mfrow = c(1, 3), mar = c(6, 6, 5, 2) + 0.1, mgp = c(4, 1.2, 0))
    on.exit({ ea_fig_title(); par(old_par) })
    plot(model$fitted.values, model$model[[1]], main = "Actual vs. Fitted", xlab = "Fitted Values", ylab = "Actual Data", pch = 16, col = rgb(0.2, 0.5, 0.8, 0.5), cex.lab=1.3, cex.main=1.5)
    abline(0, 1, col = "red", lwd = 2, lty = 2)
    plot(model$fitted.values, resid(model), main = "Residuals vs Fitted", xlab = "Fitted Values", ylab = "Residuals", pch = 16, col = rgb(0.3, 0.3, 0.3, 0.5), cex.lab=1.3, cex.main=1.5)
    abline(h = 0, col = "red", lwd = 2)
    hist(dataset[[y_var]], main = paste("Distribution of", y_var), xlab = y_var, col = "lightblue", border = "white", cex.lab=1.3, cex.main=1.5)
  } else {
    old_par <- par(mar = c(6, 6, 5, 2) + 0.1, mgp = c(4.5, 1.2, 0))
    on.exit(par(old_par))
    if (is.null(target)) return()
    if (target == "Fitted vs Actual") {
      plot(model$fitted.values, model$model[[1]], main = "Actual vs. Fitted Values", xlab = "Model Predicted (Fitted)", ylab = "Actual Data", pch = 16, cex = 1.5, col = rgb(0.2, 0.5, 0.8, 0.5), cex.lab=1.4, cex.axis=1.2, cex.main=1.6)
      abline(0, 1, col = "red", lwd = 2, lty = 2)
    } else if (target == "Residual Plot") {
      plot(model$fitted.values, resid(model), main = "Residuals vs Fitted", xlab = "Fitted Values", ylab = "Residuals", pch = 16, cex = 1.5, col = rgb(0.3, 0.3, 0.3, 0.5), cex.lab=1.4, cex.axis=1.2, cex.main=1.6)
      abline(h = 0, col = "red", lwd = 2)
    } else {
      hist(dataset[[y_var]], main = paste("Distribution of", y_var), xlab = y_var, col = "lightblue", border = "white", cex.lab=1.4, cex.axis=1.2, cex.main=1.6)
    }
  }
}

# ==========================================================================
# Native OS file/folder dialogs (LOCAL desktop build).
# Confirmed on the target machine (2026-07-25): tcltk folder AND file dialogs
# (tk_choose.dir / tkgetOpenFile / tkgetSaveFile) all open. So tcltk is the
# PRIMARY for all three — it shares the Tk that global.R pre-warms at boot, so
# there is NO per-click process spawn and dialogs open fast. PowerShell is kept
# only as a fallback when tcltk itself is unavailable/errors (NOT on cancel).
# utils::choose.dir and PowerShell's FolderBrowserDialog were dropped (they did
# not reliably appear from an Rscript-launched app). All dialogs BLOCK the single
# R thread while open (fine for a one-user local app). Browser/wasm build has no
# OS dialogs -> everything returns NULL and callers fall back to a default.
#
# tcltk semantics that make the no-double-dialog logic work: the tk* functions
# return "" when the user CANCELS (a normal outcome) and only throw on a real
# failure. So: a character result (even "") = tcltk handled it, do NOT fall back;
# an error = try PowerShell.
# ==========================================================================

# NOTE: the native OS file/folder dialog helpers (.ps_* / .native_*) were
# removed 2026-07-27. They were abandoned in favour of the browser file
# picker + downloadHandler, were referenced nowhere, and shelling out to
# PowerShell was an unnecessary code-execution surface.

# ==========================================================================
# PLOT APPEARANCE — one mechanism for every screen
# --------------------------------------------------------------------------
# Users can name a plot's title, its axis labels and its colour, and that has
# to work on EVERY analysis and model screen — not be re-implemented ~35 times.
#
# The seam is `print.ggplot`. Shiny's renderPlot prints the ggplot object, and
# S3 dispatch finds a print.ggplot defined here (global env) before ggplot2's,
# so every ggplot in the app passes through ea_style_gg() without the modules
# knowing. The read happens inside renderPlot's reactive context, so changing
# an option re-renders the plot on its own.
#
# Base-R plots (plot/hist/barplot/...) cannot be restyled after the fact — they
# bake main/xlab/ylab in at draw time. Those modules call ea_opt() when building
# their arguments instead; see ea_opt() below.
# ==========================================================================

.EA_PLOTOPTS <- new.env(parent = emptyenv())
.EA_PLOTOPTS$rv  <- NULL      # reactiveValues, installed by server.R
.EA_PLOTOPTS$ctx <- NULL      # reactive returning the current screen's key

# Which screen's settings are in play. Falls back to a shared "global" bucket
# so a plot rendered outside the workspace still picks options up.
ea_plot_ctx <- function() {
  f <- .EA_PLOTOPTS$ctx
  k <- tryCatch(if (is.function(f)) f() else NULL, error = function(e) NULL)
  if (is.null(k) || !nzchar(k)) "global" else k
}

# One option for the current screen, or `default` when the user has not set it.
# Base-R plot modules use this directly, e.g.
#   plot(x, y, main = ea_opt("title", "Residuals"), xlab = ea_opt("xlab", "Fitted"))
ea_opt <- function(name, default = NULL) {
  rv <- .EA_PLOTOPTS$rv
  if (is.null(rv)) return(default)
  o <- tryCatch(rv[[ea_plot_ctx()]], error = function(e) NULL)
  v <- if (is.list(o)) o[[name]] else NULL
  if (is.null(v) || !nzchar(as.character(v))) default else v
}

# Apply the current screen's settings to a ggplot. Only overrides what the user
# actually set, so an untouched plot keeps exactly the labels its module chose.
ea_style_gg <- function(p) {
  ttl <- ea_opt("title"); xl <- ea_opt("xlab"); yl <- ea_opt("ylab")
  col <- ea_opt("colour")
  if (!is.null(ttl)) p <- p + ggplot2::labs(title = ttl)
  if (!is.null(xl))  p <- p + ggplot2::labs(x = xl)
  if (!is.null(yl))  p <- p + ggplot2::labs(y = yl)
  if (!is.null(col) && is.list(p$layers) && length(p$layers)) {
    # Recolour the layers that carry a FIXED colour/fill. Layers mapped to a
    # variable are left alone — overriding those would destroy the encoding.
    p$layers <- lapply(p$layers, function(L) {
      ap <- L$aes_params
      if (!is.null(ap$colour)) L$aes_params$colour <- col
      if (!is.null(ap$color))  L$aes_params$color  <- col
      if (!is.null(ap$fill))   L$aes_params$fill   <- col
      L
    })
  }
  if (!is.null(ttl))
    p <- p + ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
  p
}

# Registering the DEPENDENCY is a separate problem from applying the style.
# ea_style_gg() runs at print time, and Shiny prints the plot outside the
# reactive context that built it — so reading the options there restyles the
# plot but never invalidates the output, and nothing re-renders when a setting
# changes. Touching the store INSIDE the render expression is what creates the
# dependency, so renderPlot is wrapped below to do exactly that.
ea_plot_dep <- function() {
  rv <- .EA_PLOTOPTS$rv
  if (is.null(rv)) return(invisible(NULL))
  invisible(tryCatch(rv[[ea_plot_ctx()]], error = function(e) NULL))
}

# THE seam: shadow shiny::renderPlot for every module (they call it unqualified,
# and global.R sources this file first), so no module needs changing.
#
# Styling is applied HERE rather than through a print.ggplot override. Shiny's
# render path does not reliably reach an S3 method defined in the global env —
# ea_style_gg() worked when called directly while plots rendered unstyled — so
# the object is styled explicitly on the way out. ea_plot_dep() in the same
# expression is what makes the output re-render when a setting changes.
renderPlot <- function(expr, ..., env = parent.frame(), quoted = FALSE) {
  fn <- shiny::exprToFunction(expr, env, quoted)
  shiny::renderPlot({
    ea_plot_dep()
    v <- fn()
    # patchwork and friends inherit "ggplot" but are composites: styling them
    # as a single plot is wrong, so leave them to their module.
    if (inherits(v, "ggplot") && !inherits(v, "patchwork"))
      v <- tryCatch(ea_style_gg(v), error = function(e) v)
    v
  }, ...)
}

# --- Base-R plots -----------------------------------------------------------
# Base graphics bake main/xlab/ylab in at draw time, so there is no seam like
# print.ggplot. Call sites pass their defaults through these instead:
#   plot(x, y, main = ea_main("Residuals"), xlab = ea_xlab("Fitted"))
ea_main <- function(default = NULL) ea_opt("title",  default)
ea_xlab <- function(default = NULL) ea_opt("xlab",   default)
ea_ylab <- function(default = NULL) ea_opt("ylab",   default)
ea_col  <- function(default = NULL) ea_opt("colour", default)

# MULTI-PANEL figures (diagnostic grids) are different: one title and one axis
# pair repeated across panels that each mean something different would be
# actively wrong. So only an OVERALL title applies, drawn in the outer margin —
# and the margin is only reserved when the user actually set one.
ea_multi_par <- function(...) {
  a <- list(...)
  if (!is.null(ea_opt("title")) && is.null(a$oma)) a$oma <- c(0, 0, 2.2, 0)
  do.call(graphics::par, a)
}
ea_fig_title <- function(cex = 1.15) {
  t <- ea_opt("title")
  if (is.null(t)) return(invisible(FALSE))
  graphics::mtext(t, outer = TRUE, line = 0.4, cex = cex, font = 2)
  invisible(TRUE)
}

# ==========================================================================
# SELECT-AND-SPLIT output area (see UNIFIED_WORKSPACE.md, backlog item 12)
# --------------------------------------------------------------------------
# Model screens used to show every output at once across several tabs, all
# competing for the same space. These two helpers give a screen one area whose
# contents the USER picks: one selection fills it, more than one splits it with
# a draggable divider.
#
# The DEFAULT IS ONE, deliberately. Clutter chosen is fine; clutter by default
# was the problem. Panes stack rather than sitting side by side, because model
# output is mostly wide monospace text that wraps badly at half width.
#
#   VIEWS <- c(summary = "Model summary", plot = "Diagnostic plots")   # key = label
#   # UI:      card(card_header(ea_view_header(ns, VIEWS)),
#   #               div(class = "lm-viewport", uiOutput(ns("view_body"))))
#   # SERVER:  output$view_body <- renderUI(
#   #            ea_view_panes(input$view_pick, VIEWS, function(k, solo) switch(k, ...)))
# ==========================================================================

ea_view_header <- function(ns, views, selected = names(views)[1], tools = TRUE) {
  div(class = "d-flex justify-content-between align-items-center gap-2",
    div(class = "d-flex align-items-center gap-2",
      tags$span(class = "lm-view-label", "Show"),
      selectizeInput(ns("view_pick"), NULL, width = "330px", multiple = TRUE,
        choices  = stats::setNames(names(views), unname(views)),
        selected = selected,
        options  = list(plugins = list("remove_button"),
                        placeholder = "Pick one or more"))),
    if (isTRUE(tools)) uiOutput(ns("view_tools"), inline = TRUE))
}

# `build(key, solo)` returns the UI for one view. `solo` is TRUE when it has the
# whole area, so a plot can take a fixed height alone and fill its pane when shared.
ea_view_panes <- function(picked, views, build) {
  if (!length(picked)) picked <- names(views)[1]     # never render an empty canvas
  picked <- picked[picked %in% names(views)]
  if (!length(picked)) picked <- names(views)[1]
  if (length(picked) == 1) return(build(picked[[1]], TRUE))
  panes <- list()
  for (i in seq_along(picked)) {
    k <- picked[[i]]
    if (i > 1)
      panes[[length(panes) + 1]] <- div(class = "lm-split", title = "Drag to resize")
    panes[[length(panes) + 1]] <- div(class = "lm-pane",
      div(class = "lm-pane-h", unname(views[[k]])),
      div(class = "lm-pane-b", build(k, FALSE)))
  }
  div(class = "lm-panes", panes)
}

# ---- Plot appearance control, placed WITH the plot --------------------------
# It used to sit in the workspace's result header, which every screen shows, so
# it appeared on screens where there was no plot in view. It belongs in the plot
# section instead.
#
# The inputs are workspace-level (`workspace-po_*`) and this writes to them
# directly, so a module can drop the control next to its plot without any
# server wiring of its own — there is still exactly one store behind it.
#
# `fields` says which of the four this particular plot actually honours, so the
# control never offers something that would do nothing. A raster preview draws a
# map with a data-driven palette: its title is overridable, its axes are map
# coordinates and its colours come from the palette, so it passes fields="title".
ea_plot_appearance <- function(fields = c("title", "xlab", "ylab", "colour")) {
  fields <- match.arg(fields, several.ok = TRUE)
  fld <- function(key, ico, label) if (key %in% fields) div(class = "ea-pop-row",
    tags$label(icon(ico), tags$span(label)),
    tags$input(type = "text", class = "form-control", placeholder = "auto",
      oninput = sprintf(
        "Shiny.setInputValue('workspace-po_%s', this.value, {priority:'event'});", key)))
  labels <- c(title = "title", xlab = "axis labels", ylab = "axis labels",
              colour = "colour")
  div(class = "ea-pop",
    tags$button(type = "button", class = "ea-pop-btn",
      title = paste("Plot appearance -",
                    paste(unique(labels[fields]), collapse = ", ")),
      onclick = "eaPop(this)", icon("palette")),
    div(class = "ea-pop-body",
      div(class = "ea-pop-h", icon("palette"), tags$span("Plot appearance")),
      fld("title", "heading", "Title"),
      fld("xlab", "arrows-left-right", "X label"),
      fld("ylab", "arrows-up-down", "Y label"),
      if ("colour" %in% fields) div(class = "ea-pop-row",
        tags$label(icon("droplet"), tags$span("Colour")),
        tags$input(type = "color", class = "ea-wsx-colpick", value = "#2E7D32",
          onchange = "Shiny.setInputValue('workspace-po_colour', this.value, {priority:'event'});")),
      div(class = "ea-pop-note", "Leave a field empty to use the default.")))
}

# NOTE: there is deliberately no ea_is_plot_view() helper here any more.
# Guessing "is this view a plot?" from the view KEY was wrong on most screens --
# it missed posterior, performance, wind_rose, cox_ph_model and every timeseries
# plot, and "predictions" is a plot on the XGBoost screen but a table on the
# neural-net one, so no name rule could ever be right. Each screen now declares
# its own .<TAG>_VIEWS_PLOT vector, read off the bodies it actually renders.
