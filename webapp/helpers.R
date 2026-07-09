# ==========================================================================
# helpers.R  --  shared, stateless helper + plotting functions
# Sourced by global.R so every module can use them. Ported verbatim from the
# legacy server. (AI/OpenAI helpers are intentionally NOT here yet.)
# ==========================================================================

# Null-coalescing: return a if non-null and non-empty, else b.
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# Optional-package access via strings so packages without WebAssembly builds
# (ggord, heplots) stay invisible to shinylive's dependency scanner — a
# literal requireNamespace()/pkg:: reference to them makes the export fail.
.opt_pkg <- function(p) requireNamespace(p, quietly = TRUE)
.opt_fun <- function(p, f) utils::getFromNamespace(f, p)

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
      backgroundColor = DT::styleEqual("— Macro avg", "#eef2f7"))
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
    old_par <- par(mfrow = c(rows, 3), mar = c(6, 5, 4, 1) + 0.1, mgp = c(3, 1, 0))
    on.exit(par(old_par))

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
    old_par <- par(mfrow = c(1, 2), mar = c(6, 6, 5, 2) + 0.1, mgp = c(4, 1.2, 0))
    on.exit(par(old_par))
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
    old_par <- par(mfrow = c(1, 3), mar = c(6, 6, 5, 2) + 0.1, mgp = c(4, 1.2, 0))
    on.exit(par(old_par))
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
