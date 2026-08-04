# statistics.R -- the STATISTICAL METHOD registry
#
# One entry per analysis, the same move `algorithms.R` made for spatial
# operations (backlog D18): the method is DATA, and `mod_stat.R` renders and
# runs any of them. Adding an analysis means adding a list here and nothing
# else -- no new module, no new selectors, no new view plumbing.
#
# Why this exists (backlog item 33). All ~35 analyses were hand-written modules,
# so "more and more statistical analyses" meant "more and more modules", each
# repeating its own variable pickers, its own view switching and its own result
# panes -- and each a fresh chance to reintroduce gotchas 18/26, which have
# already produced empty dropdowns on four screens. It also settles E19/E20:
# every method here gets the SAME variable picker because the picker is
# generated from the spec's roles, not written per screen.
#
# Spec fields
#   id       unique key; the tool key becomes "stat_<id>"
#   label    what the menu and the search box show
#   group    menu group it appears under
#   summary  one line shown at the top of the panel
#   roles    list of ea_role(): which COLUMNS the method needs, by meaning
#   params   list of ea_num()/ea_txt()/ea_sel() from algorithms.R -- reused, not
#            redefined, so both registries take the same parameter shapes
#   fit      function(df, r, p) -> the fitted object. `r` holds the chosen
#            column names by role key, `p` the parameter values by key.
#            THROW to fail; mod_stat.R reports the message.
#   views    named character vector: key = label, for the select-and-split header
#   render   function(fit, key, solo) -> UI for one view
#
# NOT everything belongs here. A method whose inputs are variable-length or
# whose screen is genuinely two screens stays a module -- `mod_tests.R` (its
# role set is a function of the chosen test), `mod_da.R` (two-stage),
# `mod_descriptive.R` (no response, no run button) and `mod_clustering.R`. The
# same judgement kept `mod_suitability.R` out of `algorithms.R`.

# ---- Role constructor -------------------------------------------------------
# `types` filters what the picker offers, so a numeric-only response never lists
# a text column. This is the whole point of declaring roles rather than columns:
# the runner can build a correct picker without the spec writing any UI.
#   "numeric" | "categorical" | "ordered" | "count" | "any"
ea_role <- function(key, label, types = "any", multiple = FALSE,
                    required = TRUE, hint = NULL)
  list(key = key, label = label, types = types, multiple = multiple,
       required = required, hint = hint)

# Does a column satisfy a role's type filter?
ea_role_ok <- function(x, types) {
  switch(types,
    numeric     = is.numeric(x),
    integer     = is.integer(x) || (is.numeric(x) && all(x %% 1 == 0, na.rm = TRUE)),
    count       = is.numeric(x) && all(x >= 0 & x %% 1 == 0, na.rm = TRUE),
    categorical = is.factor(x) || is.character(x) || is.logical(x),
    ordered     = is.factor(x) || is.character(x) || is.numeric(x),
    TRUE)
}

# ---- Shared bits every spec uses -------------------------------------------
# Build `y ~ x1 + x2` from the chosen roles. Kept here so no spec hand-rolls a
# formula string and they cannot disagree about how predictors are joined.
.ea_formula <- function(resp, preds) {
  if (!length(preds)) stop("Choose at least one predictor.")
  stats::as.formula(paste(resp, "~", paste(preds, collapse = " + ")))
}

# A model summary rendered as text. Every method has one and they all look the
# same, so it lives here rather than in five specs.
.ea_v_summary <- function(fit)
  tags$pre(paste(utils::capture.output(summary(fit)), collapse = "\n"))

# Coefficients as a table. `broom` is not a dependency, so this reads the
# coefficient matrix directly -- which also works for polr/rlm/glm.nb, whose
# summary objects differ in what they carry.
.ea_v_coefs <- function(fit) {
  cf <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  if (is.null(cf) || !length(cf)) return(show_placeholder("No coefficients to show."))
  d <- as.data.frame(cf)
  d <- cbind(Term = rownames(d), d)
  # polr and rlm report no p-value; derive one from t/z where it is meaningful
  # rather than leaving a column the user cannot interpret.
  tcol <- grep("^(t|z) value$", names(d))
  if (length(tcol) == 1 && !any(grepl("^Pr", names(d))))
    d[["p value"]] <- 2 * stats::pnorm(abs(d[[tcol]]), lower.tail = FALSE)
  num <- vapply(d, is.numeric, logical(1))
  d[num] <- lapply(d[num], function(v) signif(v, 4))
  DT::datatable(d, rownames = FALSE,
                options = list(dom = "t", pageLength = 50, scrollX = TRUE))
}

# Fit-quality numbers, using the app's own evaluator so these screens report the
# same metrics as the hand-written ones.
.ea_v_metrics <- function(fit) {
  pred <- tryCatch(as.numeric(stats::fitted(fit)), error = function(e) NULL)
  obs  <- tryCatch(as.numeric(stats::model.response(stats::model.frame(fit))),
                   error = function(e) NULL)
  if (is.null(pred) || is.null(obs) || length(pred) != length(obs))
    return(show_placeholder("Fit-quality metrics are not available for this model."))
  m <- tryCatch(uef_evaluation(pred, obs), error = function(e) NULL)
  if (is.null(m)) return(show_placeholder("Could not compute metrics."))
  tags$pre(paste(sprintf("%-9s: %s", names(m), signif(unlist(m), 5)), collapse = "\n"))
}

# ==========================================================================
# THE REGISTRY
# ==========================================================================
ea_statistics <- function() {
  list(

    # ---- Ordinal regression ------------------------------------------------
    list(
      id = "ordinal", label = "Ordinal regression", group = "Regression",
      summary = paste("For an ordered outcome (low / medium / high, or a Likert",
                      "scale). Models the odds of being at or below each level."),
      roles = list(
        ea_role("y", "Ordered outcome", "ordered", hint =
                "Its levels are taken in the order they appear; reorder the column first if that is wrong."),
        ea_role("x", "Predictors", "any", multiple = TRUE)),
      params = list(
        ea_sel("method", "Link function",
               c("Logistic (proportional odds)" = "logistic",
                 "Probit" = "probit", "Complementary log-log" = "cloglog"),
               "logistic")),
      views = c(summary = "Model summary", coefs = "Coefficients",
                odds = "Odds ratios", interp = "Interpretation"),
      fit = function(df, r, p) {
        y <- df[[r$y]]
        # polr REQUIRES an ordered factor; say so plainly rather than letting
        # MASS fail with "response must be a factor".
        if (!is.ordered(y)) {
          lv <- if (is.factor(y)) levels(y) else sort(unique(stats::na.omit(y)))
          if (length(lv) < 3)
            stop("An ordered outcome needs at least 3 levels; use Logistic regression for 2.")
          df[[r$y]] <- factor(y, levels = lv, ordered = TRUE)
        }
        MASS::polr(.ea_formula(r$y, r$x), data = df, Hess = TRUE,
                   method = p$method %||% "logistic")
      },
      render = function(fit, key, solo) switch(key,
        summary = .ea_v_summary(fit),
        coefs   = .ea_v_coefs(fit),
        odds    = {
          or <- tryCatch(exp(stats::coef(fit)), error = function(e) NULL)
          if (is.null(or)) show_placeholder("No odds ratios available.")
          else DT::datatable(
            data.frame(Term = names(or), `Odds ratio` = signif(or, 4),
                       check.names = FALSE),
            rownames = FALSE, options = list(dom = "t", pageLength = 50))
        },
        interp  = {
          or <- tryCatch(exp(stats::coef(fit)), error = function(e) numeric(0))
          if (!length(or)) return(show_placeholder("Fit the model first."))
          top <- names(or)[which.max(abs(log(or)))]
          tags$div(class = "ea-subpanel", tags$p(
            sprintf(paste("Each one-unit rise in %s multiplies the odds of being in a",
                          "HIGHER category by %.3g, holding the others constant.",
                          "A value above 1 pushes the outcome up the scale; below 1, down."),
                    top, or[[top]])))
        })
    ),

    # ---- Robust regression -------------------------------------------------
    list(
      id = "robust", label = "Robust regression", group = "Regression",
      summary = paste("Linear regression that is not dragged around by outliers.",
                      "Use it when a few extreme points distort an ordinary fit."),
      roles = list(
        ea_role("y", "Response", "numeric"),
        ea_role("x", "Predictors", "any", multiple = TRUE)),
      params = list(
        ea_sel("psi", "Weighting function",
               c("Huber (default)" = "huber", "Tukey bisquare" = "bisquare",
                 "Hampel" = "hampel"), "huber")),
      views = c(summary = "Model summary", coefs = "Coefficients",
                metrics = "Fit quality", weights = "Down-weighted rows"),
      fit = function(df, r, p) {
        psi <- switch(p$psi %||% "huber", huber = MASS::psi.huber,
                      bisquare = MASS::psi.bisquare, hampel = MASS::psi.hampel)
        MASS::rlm(.ea_formula(r$y, r$x), data = df, psi = psi)
      },
      render = function(fit, key, solo) switch(key,
        summary = .ea_v_summary(fit),
        coefs   = .ea_v_coefs(fit),
        metrics = .ea_v_metrics(fit),
        weights = {
          # The point of a robust fit is WHICH rows it discounted -- that is the
          # thing an ordinary lm hides, so it gets its own view.
          w <- tryCatch(fit$w, error = function(e) NULL)
          if (is.null(w)) return(show_placeholder("No weights available."))
          i <- order(w)[seq_len(min(25, length(w)))]
          DT::datatable(
            data.frame(Row = i, Weight = signif(w[i], 3)),
            rownames = FALSE, options = list(dom = "tp", pageLength = 10),
            caption = "Lowest weights = rows the fit discounted most (1 = full weight).")
        })
    ),

    # ---- Poisson count model ----------------------------------------------
    list(
      id = "poisson", label = "Poisson regression (counts)", group = "Regression",
      summary = paste("For counts: number of stems, events, defects. Models the",
                      "log of the expected count."),
      roles = list(
        ea_role("y", "Count response", "count", hint =
                "Whole numbers, zero or greater."),
        ea_role("x", "Predictors", "any", multiple = TRUE),
        ea_role("offset", "Exposure / offset (optional)", "numeric",
                required = FALSE, hint =
                "Area, time or effort each count was observed over. Entered as log(offset).")),
      params = list(
        ea_sel("link", "Link function", c("log", "identity", "sqrt"), "log")),
      views = c(summary = "Model summary", coefs = "Coefficients",
                rates = "Rate ratios", disp = "Overdispersion check"),
      fit = function(df, r, p) {
        preds <- r$x
        if (isTruthy(r$offset)) {
          o <- df[[r$offset]]
          if (any(o <= 0, na.rm = TRUE))
            stop("The offset must be positive everywhere - it is used as log(offset).")
          # The offset goes into the FORMULA, not glm(offset = ...). glm()
          # deparses that argument and evaluates it in the model frame, so a
          # local variable is simply not visible there ("object 'off' not
          # found"). A column referenced by the formula always resolves.
          df$.ea_offset <- log(o)
          preds <- c(preds, "offset(.ea_offset)")
        }
        stats::glm(.ea_formula(r$y, preds), data = df,
                   family = stats::poisson(link = p$link %||% "log"))
      },
      render = function(fit, key, solo) switch(key,
        summary = .ea_v_summary(fit),
        coefs   = .ea_v_coefs(fit),
        rates   = {
          rr <- tryCatch(exp(stats::coef(fit)), error = function(e) NULL)
          if (is.null(rr)) show_placeholder("No rate ratios available.")
          else DT::datatable(
            data.frame(Term = names(rr), `Rate ratio` = signif(rr, 4),
                       check.names = FALSE),
            rownames = FALSE, options = list(dom = "t", pageLength = 50))
        },
        disp    = {
          # Poisson assumes variance = mean. When it does not hold the standard
          # errors are too small and every p-value is optimistic -- so this is
          # not optional information, it decides whether the model is usable.
          rp <- tryCatch(sum(stats::residuals(fit, type = "pearson")^2) /
                           stats::df.residual(fit), error = function(e) NA_real_)
          verdict <- if (is.na(rp)) "could not be computed"
            else if (rp > 2)  "SUBSTANTIAL overdispersion - prefer Negative binomial"
            else if (rp > 1.5) "some overdispersion - consider Negative binomial"
            else "no meaningful overdispersion"
          tags$div(class = if (!is.na(rp) && rp > 1.5) "ea-subpanel ea-subpanel-warn"
                           else "ea-subpanel",
            tags$p(tags$b(sprintf("Dispersion = %.3g", rp))),
            tags$p(sprintf("Poisson assumes this is about 1. Here: %s.", verdict)))
        })
    ),

    # ---- Negative binomial -------------------------------------------------
    list(
      id = "negbin", label = "Negative binomial (overdispersed counts)",
      group = "Regression",
      summary = paste("Counts whose spread is wider than Poisson allows.",
                      "Use when the Poisson overdispersion check says so."),
      roles = list(
        ea_role("y", "Count response", "count"),
        ea_role("x", "Predictors", "any", multiple = TRUE)),
      params = list(),
      views = c(summary = "Model summary", coefs = "Coefficients",
                rates = "Rate ratios", theta = "Dispersion (theta)"),
      fit = function(df, r, p) MASS::glm.nb(.ea_formula(r$y, r$x), data = df),
      render = function(fit, key, solo) switch(key,
        summary = .ea_v_summary(fit),
        coefs   = .ea_v_coefs(fit),
        rates   = {
          rr <- tryCatch(exp(stats::coef(fit)), error = function(e) NULL)
          if (is.null(rr)) show_placeholder("No rate ratios available.")
          else DT::datatable(
            data.frame(Term = names(rr), `Rate ratio` = signif(rr, 4),
                       check.names = FALSE),
            rownames = FALSE, options = list(dom = "t", pageLength = 50))
        },
        theta   = tags$div(class = "ea-subpanel",
          tags$p(tags$b(sprintf("theta = %.4g  (SE %.3g)",
                                fit$theta %||% NA, fit$SE.theta %||% NA))),
          tags$p(paste("Smaller theta means more extra-Poisson variation.",
                       "As theta grows large the fit approaches a plain Poisson,",
                       "which is the signal you did not need this model."))))
    ),

    # ---- GLMM (backlog item 34) --------------------------------------------
    # The existing Mixed effects screen is nlme::lme, which fits GAUSSIAN
    # responses only -- it has no `family` argument at all, so a binary or count
    # outcome with random effects could not be fitted anywhere in the app.
    #
    # The random-effects part DOES fit a static spec: a grouping role (several,
    # for crossed effects) plus an optional random-slope role is enough to build
    # `(1 | g)` / `(slope | g)` terms. This was the open question in item 34 and
    # the answer is yes -- so GLMM is an entry here rather than a new module.
    list(
      id = "glmm", label = "GLMM (generalised mixed effects)",
      group = "Regression",
      summary = paste("Mixed effects for a NON-normal response - binary, counts,",
                      "proportions - with random intercepts and slopes."),
      roles = list(
        ea_role("y", "Response", "any", hint =
                "Binary (2 levels) for binomial; whole numbers for Poisson."),
        ea_role("x", "Fixed effects", "any", multiple = TRUE),
        ea_role("g", "Grouping variable(s)", "categorical", multiple = TRUE,
                hint = "Plot, site, subject... Several gives crossed random effects."),
        ea_role("slope", "Random slope (optional)", "numeric", required = FALSE,
                hint = "Leave empty for random intercepts only.")),
      params = list(
        ea_sel("family", "Family",
               c("Binomial (yes/no)" = "binomial", "Poisson (counts)" = "poisson"),
               "binomial"),
        ea_sel("nested", "Several grouping variables are",
               c("Crossed  (1|a) + (1|b)" = "crossed",
                 "Nested   (1|a/b)" = "nested"), "crossed")),
      views = c(summary = "Model summary", coefs = "Fixed effects",
                ranef = "Random effects", conv = "Convergence & fit"),
      fit = function(df, r, p) {
        # Guarded here rather than at the binding: this `::` sits inside a
        # function body that only runs on Run, so it cannot break server
        # construction (gotcha 27). The message has to name the package,
        # because the workspace has a package installer that can fetch it.
        if (!requireNamespace("lme4", quietly = TRUE))
          stop("GLMM needs the 'lme4' package. Install it from the Packages screen.")
        re <- if (identical(p$nested, "nested") && length(r$g) > 1)
                sprintf("(%s | %s)", if (isTruthy(r$slope)) r$slope else "1",
                        paste(r$g, collapse = "/"))
              else
                paste(sprintf("(%s | %s)",
                              if (isTruthy(r$slope)) r$slope else "1", r$g),
                      collapse = " + ")
        y <- df[[r$y]]
        fam <- p$family %||% "binomial"
        if (identical(fam, "binomial")) {
          # Count levels for a FACTOR too. Checking only non-factors let a
          # 4-level factor through to glmer, which then fitted something
          # meaningless instead of refusing.
          u <- if (is.factor(y)) levels(droplevels(y))
               else unique(stats::na.omit(y))
          if (length(u) != 2)
            stop("A binomial response needs exactly 2 distinct values; this one has ",
                 length(u), ". Use Poisson, or pick another column.")
          if (!is.factor(y)) df[[r$y]] <- factor(y)
        }
        f <- stats::as.formula(paste(r$y, "~", paste(c(r$x, re), collapse = " + ")))
        lme4::glmer(f, data = df, family = fam)
      },
      render = function(fit, key, solo) switch(key,
        summary = .ea_v_summary(fit),
        coefs   = .ea_v_coefs(fit),
        ranef   = {
          vc <- tryCatch(as.data.frame(lme4::VarCorr(fit)), error = function(e) NULL)
          if (is.null(vc)) return(show_placeholder("No random effects to show."))
          keep <- intersect(c("grp", "var1", "var2", "vcov", "sdcor"), names(vc))
          d <- vc[keep]
          names(d)[names(d) == "grp"]   <- "Group"
          names(d)[names(d) == "var1"]  <- "Term"
          names(d)[names(d) == "vcov"]  <- "Variance"
          names(d)[names(d) == "sdcor"] <- "Std.Dev."
          num <- vapply(d, is.numeric, logical(1))
          d[num] <- lapply(d[num], function(v) signif(v, 4))
          DT::datatable(d, rownames = FALSE, options = list(dom = "t", pageLength = 25))
        },
        conv    = {
          # Convergence is NOT a footnote here. CLAUDE.md gotcha 7 already
          # records that nlme::lme "frequently fails to converge" when
          # predictors are on different scales, and glmer is worse. A raw
          # warning would make this the next screen that "cannot be run", so
          # it is surfaced in plain language with the standard remedies.
          msgs <- tryCatch(fit@optinfo$conv$lme4$messages, error = function(e) NULL)
          sing <- tryCatch(lme4::isSingular(fit), error = function(e) FALSE)
          r2   <- tryCatch(MuMIn::r.squaredGLMM(fit), error = function(e) NULL)
          ok   <- is.null(msgs) && !isTRUE(sing)
          tagList(
            tags$div(class = if (ok) "ea-subpanel" else "ea-subpanel ea-subpanel-warn",
              tags$p(tags$b(if (ok) "Converged cleanly."
                            else "This fit needs a second look.")),
              if (isTRUE(sing)) tags$p(paste(
                "SINGULAR fit: at least one random effect has near-zero variance.",
                "The grouping variable probably has too few levels, or the random",
                "slope is not supported by the data. Try random intercepts only.")),
              if (!is.null(msgs)) tags$ul(lapply(msgs, tags$li)),
              if (!ok) tags$p(paste(
                "Usual remedies: put predictors on a similar scale, drop the random",
                "slope, or reduce the number of fixed effects."))),
            if (!is.null(r2)) tags$div(class = "ea-subpanel mt-2",
              tags$p(tags$b("Nakagawa R-squared")),
              tags$pre(paste(utils::capture.output(signif(r2, 4)), collapse = "\n"))))
        })
    )
  )
}
