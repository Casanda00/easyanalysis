# ==========================================================================
# agent_tools.R -- tool registry + dispatcher for the Co-Analyst agent
# --------------------------------------------------------------------------
# Lets the co-pilot RUN analyses (not just describe them) via OpenAI tool
# calling. Each tool mirrors what the corresponding app module does, using the
# SAME fitting functions and defaults (lme convergence control, multinom,
# randomForest, ...), so agent results match what the user would get by hand.
# Sourced by global.R. Used by mod_chat.R's agent loop.
# ==========================================================================

# ---- Tool schema sent to OpenAI (chat/completions "tools" array) ----------
.agent_tools_spec <- function() {
  list(
    list(type = "function", `function` = list(
      name = "list_datasets",
      description = "List the datasets currently loaded in the app (name, rows, columns).",
      parameters = list(type = "object", properties = setNames(list(), character(0)))
    )),
    list(type = "function", `function` = list(
      name = "describe_dataset",
      description = "Column names, types, missing-value counts and summary statistics of one dataset. ALWAYS call this before run_analysis so you use real column names.",
      parameters = list(type = "object",
        properties = list(dataset = list(type = "string", description = "Dataset name from list_datasets")),
        required = list("dataset"))
    )),
    list(type = "function", `function` = list(
      name = "column_stats",
      description = paste(
        "Detailed statistics for ONE column: for numeric — n, mean, sd, min, quartiles, max,",
        "missing, skewness, outlier count; for categorical — level frequencies.",
        "Use this to answer questions about a single variable without fitting a model."),
      parameters = list(type = "object",
        properties = list(
          dataset = list(type = "string", description = "Dataset name"),
          column  = list(type = "string", description = "Column to summarise")),
        required = list("dataset", "column"))
    )),
    list(type = "function", `function` = list(
      name = "correlate",
      description = paste(
        "Correlation between numeric columns of a dataset (Pearson or Spearman).",
        "Give `columns` to restrict, otherwise all numeric columns are used.",
        "Reports the strongest pairs — useful for 'what relates to what' questions."),
      parameters = list(type = "object",
        properties = list(
          dataset = list(type = "string", description = "Dataset name"),
          columns = list(type = "array", items = list(type = "string"),
                         description = "Numeric columns (optional; default all numeric)"),
          method  = list(type = "string", enum = list("pearson", "spearman"),
                         description = "Correlation method (default pearson)")),
        required = list("dataset"))
    )),
    list(type = "function", `function` = list(
      name = "run_analysis",
      description = paste(
        "Fit a statistical model / run an analysis on a loaded dataset using the app's own methods.",
        "Methods: 'descriptive' (summary stats), 'lm' (linear regression),",
        "'anova' (ANOVA + Tukey HSD; response ~ categorical predictors),",
        "'ttest' (Welch two-sample t-test; response numeric, group = 2-level factor),",
        "'lme' (linear mixed effects, random intercept per group),",
        "'logistic' (multinomial logistic regression; categorical response),",
        "'rf' (random forest; classification if response is categorical, else regression),",
        "'clustering' (k-means on numeric predictors), 'pca' (principal components on numeric predictors)."),
      parameters = list(type = "object",
        properties = list(
          method     = list(type = "string", enum = list("descriptive","lm","anova","ttest","lme","logistic","rf","clustering","pca")),
          dataset    = list(type = "string", description = "Dataset name"),
          response   = list(type = "string", description = "Response/target column (not needed for descriptive/clustering/pca)"),
          predictors = list(type = "array", items = list(type = "string"),
                            description = "Predictor columns (clustering/pca: numeric columns to use; empty = all numeric)"),
          group      = list(type = "string", description = "Grouping column: random effect for lme, group for ttest"),
          k          = list(type = "integer", description = "Number of clusters for clustering (default 3)"),
          ntree      = list(type = "integer", description = "Trees for random forest (default 500)")),
        required = list("method", "dataset"))
    )),
    list(type = "function", `function` = list(
      name = "run_in_app",
      description = paste(
        "Open the app's own analysis SCREEN, fill in the settings and press Run, so the result appears",
        "on screen in the results dock exactly as if the user had done it by hand.",
        "Prefer this over run_analysis whenever the user asks you to RUN or DO an analysis, because the",
        "user can then see and change every setting. Currently supports method 'lm' (linear regression).",
        "Column names must be EXACT: call describe_dataset first and use the names it returns.",
        "If a name the user gave does not match a column exactly, do NOT substitute a similar one —",
        "this tool will refuse and list the real columns, and you must ask the user which they meant."),
      parameters = list(type = "object",
        properties = list(
          method     = list(type = "string", enum = list("lm")),
          dataset    = list(type = "string", description = "Exact dataset name"),
          response   = list(type = "string", description = "Exact response column name"),
          predictors = list(type = "array", items = list(type = "string"),
                            description = "Exact predictor column names")),
        required = list("method", "dataset", "response", "predictors"))
    ))
  )
}

# Side channel for UI actions. A tool that drives the SCREEN cannot return the
# instruction to the model as text — the model's reply goes to the chat, not to
# Shiny. So the tool records the action here and .ask_openai_agent() picks it up
# after the loop. Cleared at the start of every request.
.EA_AGENT_UI <- new.env(parent = emptyenv())
.EA_AGENT_UI$action <- NULL

# ---- helpers ---------------------------------------------------------------
.agent_fail <- function(msg) paste0("ERROR: ", msg,
  " (Check describe_dataset output and retry with valid arguments.)")

.agent_df <- function(pool, dataset) {
  nms <- tryCatch(names(pool), error = function(e) character(0))
  if (!dataset %in% nms) return(NULL)
  pool[[dataset]]
}

.agent_check_cols <- function(df, cols) {
  missing <- setdiff(cols, names(df))
  if (length(missing)) .agent_fail(paste("Columns not in dataset:", paste(missing, collapse = ", "))) else NULL
}

.agent_num_predictors <- function(df, predictors) {
  if (is.null(predictors) || !length(predictors)) {
    names(df)[vapply(df, is.numeric, logical(1))]
  } else predictors
}

.agent_capture <- function(x) paste(utils::capture.output(x), collapse = "\n")

# A metric or post-hoc test that may LEGITIMATELY fail -- a singular fit, an
# optional package absent, too few groups for Tukey. The model itself is fine,
# so the whole answer must not fail; but swallowing it to NULL was the wrong
# trade HERE in particular.
#
# This output is what the Co-Analyst answers FROM. A metric that vanishes with
# no explanation leaves the assistant two bad options: report a model with no R2
# and no reason, or guess at one. Saying plainly that it could not be computed,
# and why, is the only version that keeps the answer truthful.
#
# Returns list(v = value or NULL, why = NULL or a one-line explanation).
.agent_soft <- function(expr, what) {
  tryCatch(list(v = expr, why = NULL),
           error = function(e)
             list(v = NULL, why = paste0(what, " could not be computed (",
                                         conditionMessage(e), ")")))
}
# Renders the explanation for the answer, or nothing when it succeeded.
.agent_why <- function(x) if (is.null(x$why)) "" else paste0("\nNote: ", x$why, ".")

# ---- dispatcher ------------------------------------------------------------
# Returns a plain-text result block for the model. Never throws.
.agent_exec_tool <- function(name, args, dataset_pool) {
  tryCatch({
    if (name == "list_datasets") {
      nms <- tryCatch(names(dataset_pool), error = function(e) character(0))
      if (!length(nms)) return("No datasets loaded. Ask the user to upload one via the left rail.")
      return(paste(vapply(nms, function(n) {
        df <- dataset_pool[[n]]
        sprintf("- '%s': %d rows x %d cols", n, nrow(df), ncol(df))
      }, character(1)), collapse = "\n"))
    }

    if (name == "describe_dataset") {
      df <- .agent_df(dataset_pool, args$dataset)
      if (is.null(df)) return(.agent_fail(paste0("No dataset named '", args$dataset, "'. Use list_datasets.")))
      nas <- vapply(df, function(c) sum(is.na(c)), integer(1))
      return(paste0(
        "Dataset '", args$dataset, "': ", nrow(df), " rows x ", ncol(df), " cols\n\n",
        "Structure:\n", .agent_capture(utils::str(df)), "\n",
        "Missing values per column: ",
        paste(sprintf("%s=%d", names(nas)[nas > 0], nas[nas > 0]), collapse = ", "),
        if (!any(nas > 0)) "none" else "", "\n\n",
        "Summary:\n", .agent_capture(summary(df))))
    }

    if (name == "column_stats") {
      df <- .agent_df(dataset_pool, args$dataset)
      if (is.null(df)) return(.agent_fail(paste0("No dataset named '", args$dataset, "'.")))
      col <- args$column
      err <- .agent_check_cols(df, col); if (!is.null(err)) return(err)
      v <- df[[col]]
      n_na <- sum(is.na(v))
      if (is.numeric(v)) {
        x  <- v[!is.na(v)]
        q  <- stats::quantile(x, c(.25, .5, .75))
        iqr <- q[[3]] - q[[1]]
        out <- sum(x < q[[1]] - 1.5 * iqr | x > q[[3]] + 1.5 * iqr)
        sk  <- tryCatch({
          m <- mean(x); s <- stats::sd(x)
          if (s > 0) mean(((x - m) / s)^3) else 0
        }, error = function(e) NA_real_)
        return(paste0(
          "Column '", col, "' (numeric) in '", args$dataset, "':\n",
          sprintf("n=%d  missing=%d\nmean=%.4f  sd=%.4f\nmin=%.4f  Q1=%.4f  median=%.4f  Q3=%.4f  max=%.4f\n",
                  length(x), n_na, mean(x), stats::sd(x), min(x), q[[1]], q[[2]], q[[3]], max(x)),
          sprintf("skewness=%.3f  outliers(1.5*IQR)=%d\n", sk, out),
          if (!is.na(sk) && abs(sk) > 2) "NOTE: |skewness| > 2 — a log/sqrt transform may help before regression.\n" else ""))
      } else {
        tb <- sort(table(v), decreasing = TRUE)
        return(paste0("Column '", col, "' (categorical) in '", args$dataset, "':\n",
                      "levels=", length(tb), "  missing=", n_na, "\n\nFrequencies:\n",
                      .agent_capture(print(tb))))
      }
    }

    if (name == "correlate") {
      df <- .agent_df(dataset_pool, args$dataset)
      if (is.null(df)) return(.agent_fail(paste0("No dataset named '", args$dataset, "'.")))
      cols <- unlist(args$columns %||% NULL)
      if (!length(cols)) cols <- names(df)[vapply(df, is.numeric, logical(1))]
      err <- .agent_check_cols(df, cols); if (!is.null(err)) return(err)
      cols <- cols[vapply(df[cols], is.numeric, logical(1))]
      if (length(cols) < 2) return(.agent_fail("correlate needs at least 2 numeric columns."))
      meth <- args$method %||% "pearson"
      m <- stats::cor(df[, cols, drop = FALSE], use = "pairwise.complete.obs", method = meth)
      # strongest pairs first
      p <- which(upper.tri(m), arr.ind = TRUE)
      ord <- order(abs(m[upper.tri(m)]), decreasing = TRUE)
      top <- utils::head(ord, 15)
      lines <- vapply(top, function(i) sprintf("  %-22s %-22s r=% .3f",
                        cols[p[i, "row"]], cols[p[i, "col"]], m[p[i, "row"], p[i, "col"]]),
                      character(1))
      paste0(meth, " correlations in '", args$dataset, "' (strongest first):\n",
             paste(lines, collapse = "\n"),
             "\n\nFull matrix:\n", .agent_capture(print(round(m, 3))))
    } else if (name == "run_in_app") {
      return(.agent_run_in_app(args, dataset_pool))
    } else if (name == "run_analysis") {
      return(.agent_run_analysis(args, dataset_pool))
    } else {
      .agent_fail(paste("Unknown tool:", name))
    }
  }, error = function(e) .agent_fail(conditionMessage(e)))
}

.agent_run_analysis <- function(args, dataset_pool) {
  method <- args$method %||% ""
  df <- .agent_df(dataset_pool, args$dataset)
  if (is.null(df)) return(.agent_fail(paste0("No dataset named '", args$dataset, "'. Use list_datasets.")))

  response   <- args$response %||% NULL
  predictors <- unlist(args$predictors %||% NULL)
  group      <- args$group %||% NULL

  used <- c(response, predictors, group)
  err <- .agent_check_cols(df, used)
  if (!is.null(err)) return(err)

  # complete cases on the columns actually used
  if (length(used)) df <- df[stats::complete.cases(df[, used, drop = FALSE]), , drop = FALSE]
  if (!nrow(df)) return(.agent_fail("No complete rows for the selected columns."))

  if (method == "descriptive") {
    num <- names(df)[vapply(df, is.numeric, logical(1))]
    stats_tab <- do.call(rbind, lapply(num, function(v) data.frame(
      variable = v, n = sum(!is.na(df[[v]])), mean = mean(df[[v]], na.rm = TRUE),
      sd = stats::sd(df[[v]], na.rm = TRUE), min = min(df[[v]], na.rm = TRUE),
      median = stats::median(df[[v]], na.rm = TRUE), max = max(df[[v]], na.rm = TRUE))))
    return(paste0("Descriptive statistics (numeric columns):\n", .agent_capture(print(stats_tab, row.names = FALSE))))
  }

  if (method == "lm") {
    if (is.null(response) || !length(predictors)) return(.agent_fail("lm needs response and predictors."))
    m <- stats::lm(stats::reformulate(predictors, response), data = df)
    ev <- .agent_soft(uef_evaluation(stats::fitted(m), df[[response]]), "Model metrics")
    return(paste0("Linear regression ", response, " ~ ", paste(predictors, collapse = " + "), "\n\n",
      .agent_capture(summary(m)),
      if (!is.null(ev$v)) paste0("\nModel metrics: RMSE=", round(ev$v$RMSE, 4), " R2=", round(ev$v$R2, 4),
                               " Bias=", round(ev$v$Bias, 4), " RRMSE=", round(ev$v$RRMSE, 2), "%")
      else .agent_why(ev)))
  }

  if (method == "anova") {
    if (is.null(response) || !length(predictors)) return(.agent_fail("anova needs response and predictors."))
    for (p in predictors) df[[p]] <- as.factor(df[[p]])
    m <- stats::aov(stats::reformulate(predictors, response), data = df)
    out <- paste0("ANOVA ", response, " ~ ", paste(predictors, collapse = " + "), "\n\n", .agent_capture(summary(m)))
    tk <- .agent_soft(.agent_capture(stats::TukeyHSD(m)), "Tukey HSD post-hoc test")
    out <- if (!is.null(tk$v)) paste0(out, "\n\nTukey HSD:\n", tk$v)
           else paste0(out, .agent_why(tk))
    return(out)
  }

  if (method == "ttest") {
    if (is.null(response) || is.null(group)) return(.agent_fail("ttest needs response (numeric) and group (2-level)."))
    g <- as.factor(df[[group]])
    if (nlevels(g) != 2) return(.agent_fail(paste0("Group '", group, "' has ", nlevels(g), " levels; ttest needs exactly 2.")))
    t <- stats::t.test(df[[response]] ~ g)
    return(paste0("Welch two-sample t-test: ", response, " by ", group, "\n\n", .agent_capture(t)))
  }

  if (method == "lme") {
    if (is.null(response) || !length(predictors) || is.null(group))
      return(.agent_fail("lme needs response, predictors and group (random intercept)."))
    df[[group]] <- as.factor(df[[group]])
    m <- nlme::lme(stats::reformulate(predictors, response), random = stats::as.formula(paste0("~ 1 | ", group)),
                   data = df, control = nlme::lmeControl(opt = "optim", msMaxIter = 1000))
    r2 <- .agent_soft(suppressWarnings(MuMIn::r.squaredGLMM(m)), "Nakagawa R2")
    ev <- .agent_soft(uef_evaluation(as.numeric(stats::fitted(m)), df[[response]]), "Model metrics")
    return(paste0("Linear mixed effects: ", response, " ~ ", paste(predictors, collapse = " + "),
      ", random = ~1|", group, "\n\n", .agent_capture(summary(m)),
      if (!is.null(r2$v)) paste0("\nNakagawa R2: marginal=", round(r2$v[1, "R2m"], 4), " conditional=", round(r2$v[1, "R2c"], 4))
      else .agent_why(r2),
      if (!is.null(ev$v)) paste0("\nRMSE=", round(ev$v$RMSE, 4), " Bias=", round(ev$v$Bias, 4))
      else .agent_why(ev)))
  }

  if (method == "logistic") {
    if (is.null(response) || !length(predictors)) return(.agent_fail("logistic needs response (categorical) and predictors."))
    df[[response]] <- as.factor(df[[response]])
    m <- nnet::multinom(stats::reformulate(predictors, response), data = df, trace = FALSE)
    pred <- stats::predict(m, df)
    acc <- mean(pred == df[[response]])
    cm <- table(Predicted = pred, Actual = df[[response]])
    return(paste0("Multinomial logistic regression ", response, " ~ ", paste(predictors, collapse = " + "), "\n\n",
      .agent_capture(summary(m)), "\n\nTraining accuracy: ", round(100 * acc, 2), "%\nConfusion matrix:\n", .agent_capture(cm)))
  }

  if (method == "rf") {
    if (is.null(response) || !length(predictors)) return(.agent_fail("rf needs response and predictors."))
    ntree <- args$ntree %||% 500
    if (!is.numeric(df[[response]])) df[[response]] <- as.factor(df[[response]])
    m <- randomForest::randomForest(stats::reformulate(predictors, response), data = df,
                                    ntree = ntree, importance = TRUE)
    imp <- randomForest::importance(m)
    out <- paste0("Random forest (", if (is.factor(df[[response]])) "classification" else "regression",
                  ", ntree=", ntree, ") ", response, " ~ ", paste(predictors, collapse = " + "), "\n\n",
                  .agent_capture(print(m)), "\n\nVariable importance:\n", .agent_capture(round(imp, 3)))
    if (!is.factor(df[[response]])) {
      ev <- .agent_soft(uef_evaluation(m$predicted, df[[response]]), "OOB metrics")
      out <- if (!is.null(ev$v))
        paste0(out, "\n\nOOB metrics: RMSE=", round(ev$v$RMSE, 4), " R2=", round(ev$v$R2, 4))
        else paste0(out, .agent_why(ev))
    }
    return(out)
  }

  if (method == "clustering") {
    k <- args$k %||% 3
    num <- .agent_num_predictors(df, predictors)
    num <- num[vapply(df[num], is.numeric, logical(1))]
    if (length(num) < 2) return(.agent_fail("clustering needs at least 2 numeric columns."))
    x <- scale(df[, num, drop = FALSE])
    km <- stats::kmeans(x, centers = k, nstart = 25)
    return(paste0("K-means clustering (k=", k, ") on: ", paste(num, collapse = ", "),
      "\n\nCluster sizes: ", paste(km$size, collapse = ", "),
      "\nBetween-SS / Total-SS: ", round(100 * km$betweenss / km$totss, 1), "%",
      "\n\nCluster centers (scaled):\n", .agent_capture(round(km$centers, 3))))
  }

  if (method == "pca") {
    num <- .agent_num_predictors(df, predictors)
    num <- num[vapply(df[num], is.numeric, logical(1))]
    if (length(num) < 2) return(.agent_fail("pca needs at least 2 numeric columns."))
    p <- stats::prcomp(df[, num, drop = FALSE], scale. = TRUE)
    ve <- round(100 * p$sdev^2 / sum(p$sdev^2), 1)
    return(paste0("PCA on: ", paste(num, collapse = ", "),
      "\n\nVariance explained (%): ", paste(sprintf("PC%d=%.1f", seq_along(ve), ve), collapse = ", "),
      "\n\nLoadings:\n", .agent_capture(round(p$rotation, 3))))
  }

  .agent_fail(paste0("Unknown method '", method, "'."))
}

# ---- run_in_app: drive the real screen -------------------------------------
# EVERYTHING here is verified against the loaded data, nothing is inferred. No
# case-insensitive matching, no nearest-name guessing, no silent substitution:
# if a name does not match a column exactly, the tool refuses and lists the real
# columns so the model has to go back and ask the user which they meant. Running
# a regression on a quietly-substituted variable is a mistake nobody notices.
.agent_run_in_app <- function(args, dataset_pool) {
  method <- args$method %||% ""
  if (!identical(method, "lm"))
    return(.agent_fail(paste0("run_in_app does not support method '", method,
                              "' yet. Supported: lm.")))

  pools <- tryCatch(names(dataset_pool), error = function(e) character(0))
  pools <- pools[!vapply(pools, function(n) is.null(dataset_pool[[n]]), logical(1))]
  ds <- args$dataset %||% ""
  if (!nzchar(ds) || !(ds %in% pools))
    return(.agent_fail(paste0("No dataset named '", ds, "'. Loaded datasets: ",
                              if (length(pools)) paste(pools, collapse = ", ") else "(none)")))

  df <- dataset_pool[[ds]]
  if (!is.data.frame(df)) return(.agent_fail(paste0("'", ds, "' is not a table.")))
  cols <- names(df)

  resp <- args$response %||% ""
  if (!nzchar(resp) || !(resp %in% cols))
    return(.agent_fail(paste0("'", resp, "' is not a column of '", ds,
      "'. Do NOT pick a similar name — ask the user which of these they meant: ",
      paste(cols, collapse = ", "))))

  preds <- args$predictors
  if (is.null(preds) || !length(preds))
    return(.agent_fail("No predictors given. Ask the user which columns to use as predictors."))
  preds <- as.character(preds)
  missing <- setdiff(preds, cols)
  if (length(missing))
    return(.agent_fail(paste0("These are not columns of '", ds, "': ",
      paste(missing, collapse = ", "),
      ". Do NOT substitute similar names — ask the user which of these they meant: ",
      paste(cols, collapse = ", "))))
  if (resp %in% preds)
    return(.agent_fail(paste0("'", resp, "' is both the response and a predictor. Ask the user to clarify.")))

  # Linear regression needs a numeric response; refuse rather than coerce.
  if (!is.numeric(df[[resp]]))
    return(.agent_fail(paste0("Response '", resp, "' is ", class(df[[resp]])[1],
      ", not numeric, so linear regression does not apply. Numeric columns are: ",
      paste(cols[vapply(df, is.numeric, logical(1))], collapse = ", "))))

  .EA_AGENT_UI$action <- list(
    kind = "run_model", method = "lm", dataset = ds,
    response = resp, predictors = preds,
    formula = paste(preds, collapse = " + "))

  paste0("Opened the Linear Regression screen on '", ds, "', set the response to '", resp,
         "' and the predictors to ", paste(preds, collapse = " + "),
         ", and pressed Run. The fitted model and its diagnostics are now on the user's screen. ",
         "Tell the user briefly what was run; do NOT invent any coefficients or statistics, ",
         "because this tool does not return them.")
}
