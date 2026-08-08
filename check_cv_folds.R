# check_cv_folds.R -- a cross-validated metric must never be quietly computed
# over less data than its label claims.
#
# WHY THIS EXISTS
# ---------------
# Two CV loops swallowed their own failures, and they failed in different ways:
#
#   mod_logistic.R       a fold whose fit failed was `next`-ed, so its rows left
#                        the pooled prediction entirely. The accuracy was then
#                        computed over a SUBSET while the caption still said
#                        "5-fold CV".
#
#   mod_classification.R a one-vs-all sub-model whose fit failed returned
#                        rep(0.5, n). That constant still entered which.max, so a
#                        class with NO MODEL AT ALL could win the vote -- and the
#                        fabricated label counted toward the reported accuracy as
#                        though it were a real prediction.
#
# Neither is a missing number; both are WRONG numbers, and wrong in a consistent
# direction. Folds do not fail at random: a fold fails when its training split is
# degenerate (a rare class absent, a separable subset), which is exactly the hard
# case. Dropping it inflates the score.
#
# Every assertion below that begins CONTROL: exercises the OLD rule and expects it
# to be wrong. That is the point -- a guard that has never been seen to fire is a
# guess (gotcha 33). If a CONTROL line starts failing, the bug has been reinstated
# somewhere or the check has stopped testing what it names.
#
# Run:  Rscript check_cv_folds.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
source("global.R")

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# ---- 1. The argmax rule -----------------------------------------------------
classes <- c("A", "B", "C")
# Class C failed to fit. A and B fitted, but both score below 0.5 on this row.
old_row <- c(A = 0.30, B = 0.20, C = 0.50)       # OLD: a failure became 0.5
new_row <- c(A = 0.30, B = 0.20, C = NA_real_)   # NEW: a failure is withdrawn

pick <- function(r) if (all(is.na(r))) NA_character_ else
  classes[which.max(replace(r, is.na(r), -Inf))]

say(classes[which.max(old_row)] == "C",
    "CONTROL: the old 0.5 fallback predicts the class that never fitted")
say(pick(new_row) == "A", "NA withdraws an unfitted class from the vote")
say(is.na(pick(c(A = NA_real_, B = NA_real_, C = NA_real_))),
    "a row with no usable model is NA, never a guess")
say(abs(mean(c("A", NA, "B") == c("A", "B", "B"), na.rm = TRUE) - 1) < 1e-9,
    "an unscored row is excluded from accuracy, not counted as an error")

# ---- 2. The single-row fold -------------------------------------------------
v <- vapply(classes, function(cl) rep(0.4, 1L), numeric(1L))
say(is.null(dim(v)), "CONTROL: vapply collapses to a vector when a fold holds one row")
say(identical(dim(matrix(v, nrow = 1L, dimnames = list(NULL, classes))), c(1L, 3L)),
    "matrix() restores the dimensions apply() needs")

# ---- 3. The caveat text -----------------------------------------------------
say(is.null(.cv_note(list(bad_folds = 0L, k = 5L, n_total = 100L))),
    "a clean run adds no caveat")
say(is.null(.cv_note(NULL)), "a NULL result yields no caveat")
n1 <- .cv_note(list(bad_folds = 2L, bad_rows = 40L, n_total = 100L, k = 5L))
say(grepl("2 of 5 folds", n1) && grepl("40 row", n1) && grepl("40%", n1),
    "a dropped fold reports the folds AND the share of data left out")
n2 <- .cv_note(list(bad_models = 3L, unpredicted = 7L))
say(grepl("3 per-class model", n2) && grepl("7 row", n2),
    "failed per-class models and unscored rows are both named")

# The caveat has to reach the SAME element as the number, or it will not be read.
prf <- data.frame(Class = "A", Precision = 1, Recall = 1, F1 = 1)
say(inherits(.prf_dt(prf, 0.9), "datatables"), "CONTROL: .prf_dt unchanged with no note")
cap <- .prf_dt(prf, 0.9, note = "Incomplete: something.")$x$caption
say(grepl("Incomplete", cap) && grepl("90.0%", cap),
    "the caveat sits in the caption beside the accuracy")

# ---- 4. The real modules ----------------------------------------------------
set.seed(1)
n  <- 90
df <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
df$tgt <- factor(ifelse(df$x1 > 0.5, "hi", ifelse(df$x1 < -0.5, "lo", "mid")))
df <- init_data(df)
pool <- reactiveValues(D = df)

cv <- NULL
suppressWarnings(testServer(classificationServer,
  args = list(dataset_pool = pool, active_dataset = reactive("D")),
  {
    session$setInputs(target = "tgt", formula_text = "x1 + x2",
                      exclude_classes = character(0), threshold = 0.5)
    session$setInputs(run = 1)
    cv <<- clf_cv_result_r()
  }))

say(!is.null(cv), "classification still produces a CV result")
say(identical(cv$bad_models, 0L),  "clean data reports zero failed per-class models")
say(identical(cv$unpredicted, 0L), "clean data leaves no row unscored")
say(length(cv$predicted) == nrow(df), "every row received a prediction")
say(is.null(.cv_note(cv)), "a clean run displays no caveat")
say(mean(cv$predicted == cv$actual, na.rm = TRUE) > 0.6, "accuracy is sane on separable data")

lcv <- NULL
suppressWarnings(testServer(logisticServer,
  args = list(dataset_pool = pool, active_dataset = reactive("D")),
  {
    # Names read from the module, not guessed: the trigger is run_model (not run)
    # and predictors arrive as formula_text (not x). A wrong name here would make
    # the CHECK look like a defect in the code -- the ninth harness fault.
    session$setInputs(y = "tgt", formula_text = "x1 + x2")
    session$setInputs(run_model = 1)
    lcv <<- cv_result_r()
  }))
say(!is.null(lcv), "logistic produces a CV result")
say(identical(lcv$bad_folds, 0L), "logistic reports zero dropped folds on clean data")
say(identical(lcv$bad_rows, 0L),  "logistic reports zero dropped rows on clean data")
say(!is.null(lcv$n_total) && !is.null(lcv$k), "logistic carries the fold accounting")
say(length(lcv$predicted) == nrow(df),
    sprintf("logistic pooled every row (%d of %d)", length(lcv$predicted), nrow(df)))
say(is.null(.cv_note(lcv)), "logistic shows no caveat on a clean run")

# ---- 5. A fold that REALLY fails -------------------------------------------
# The checks above prove a clean run is unchanged. This proves the caveat FIRES,
# which is the half that matters.
#
# Engineering a natural fold failure turned out not to work: a rare factor level
# does not produce "factor has new levels", because R RETAINS unused levels when
# subsetting, so the training fold still declares the level it never observed.
# So the failure is injected instead. assignInNamespace genuinely rebinds what
# `nnet::multinom` resolves to (unlike shadowing a name in the global env, which
# `::` ignores -- gotcha 27), making the failing fold deterministic rather than
# dependent on a lucky seed.
real_multinom <- nnet::multinom
calls <- 0L
# The stub must be STATELESS. Two earlier attempts failed for instructive reasons:
#
#   by call number   -- the module fits more often than the loop does, so "call 3"
#                       landed on the main fit and every fold still succeeded.
#   one-shot flag    -- the module evaluates the whole CV TWICE (observed call
#                       pattern: 90, 72x5, 90, 72x5). The single injected failure
#                       was spent on the first pass, and the value handed back
#                       came from the second, clean one. A fixture consumed by an
#                       earlier evaluation is a recurring harness fault here.
#
# Keying on a marker row is stateless, so it fires identically on every pass: the
# full fit (90 rows) always contains the marker, and exactly one fold per pass
# trains without it.
marker <- df$x1[1]
stub <- function(formula, data, ...) {
  calls <<- calls + 1L
  if (!any(data$x1 == marker)) stop("simulated fold failure")
  real_multinom(formula, data, ...)
}
suppressWarnings(assignInNamespace("multinom", stub, ns = "nnet"))

fcv <- NULL
suppressWarnings(testServer(logisticServer,
  args = list(dataset_pool = pool, active_dataset = reactive("D")),
  {
    session$setInputs(y = "tgt", formula_text = "x1 + x2")
    session$setInputs(run_model = 1)
    fcv <<- cv_result_r()
  }))
suppressWarnings(assignInNamespace("multinom", real_multinom, ns = "nnet"))
say(calls > 1L, sprintf("CONTROL: the stub was actually reached (%d calls)", calls))

if (is.null(fcv)) {
  say(FALSE, "a partly-failing CV still returns a result rather than vanishing")
} else {
  say(fcv$bad_folds > 0L,
      sprintf("a genuinely failing fold IS counted (bad_folds = %d)", fcv$bad_folds))
  say(fcv$bad_rows > 0L,
      sprintf("the rows it took with it are counted (bad_rows = %d)", fcv$bad_rows))
  say(length(fcv$predicted) == nrow(df) - fcv$bad_rows,
      "the pooled prediction is exactly the surviving rows")
  note <- .cv_note(fcv)
  say(!is.null(note), "the caveat FIRES -- this is the assertion the old code failed")
  say(grepl("NOT included", note %||% ""), sprintf("and it says so plainly: %s", note))
}

cat(if (ok) "\nCV FOLD CHECK: PASS\n" else "\nCV FOLD CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
