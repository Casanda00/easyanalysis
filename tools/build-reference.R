# tools/build-reference.R -- generate landing/reference.html from the registries
#
# WHY THIS IS GENERATED
# ---------------------
# Hand-written method documentation drifts from the code, and this repo has
# already produced three proofs: llms.txt described a WebAssembly build that no
# longer existed, a favicon was recorded as "linked from the page <head>" while
# the site 404'd it, and CLAUDE.md called uef_evaluation() unused while four
# modules were calling it. Prose that repeats what code does will eventually
# lie about it.
#
# So this page is built FROM the registries. `statistics.R` and `algorithms.R`
# already hold id, label, group, summary, the variable roles and the parameters
# as structured data -- the page is a rendering of that, not a retelling.
#
# The part that matters most: THE ENGINE CALL IS EXTRACTED FROM THE CODE. Each
# spec's fit()/run() is deparsed and its `pkg::fn(` calls are read out, so the
# page states the function actually invoked. Swap MASS::polr for something else
# and the page follows on the next build; it cannot quietly become wrong.
#
# What is NOT generated: assumptions, interpretation and caveats. Those cannot
# be derived from a spec and are written by hand in REFERENCE_NOTES below, kept
# in this file so they are edited next to the thing they describe.
#
# Usage:  Rscript tools/build-reference.R      (from the repo root)

suppressMessages({
  ok <- tryCatch({ source("global.R"); TRUE }, error = function(e) {
    message("build-reference: could not load the app: ", conditionMessage(e)); FALSE })
})
if (!ok) quit(status = 1L)

esc <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

# --- Extract the real engine call(s) from a spec's code ---------------------
# Deparsing and reading `pkg::fn(` is deliberately literal: it reports what the
# code says, not what anyone believes it says. Base-R and app-internal helpers
# are filtered out so the list is the MODELLING call, not plumbing.
.SKIP_PKG <- c("stats", "base", "utils", "graphics", "grDevices", "methods",
               "tools", "DT", "shiny", "htmltools", "jsonlite", "ggplot2")
engine_of <- function(f) {
  if (!is.function(f)) return(character(0))
  src <- paste(deparse(f), collapse = "\n")
  m <- regmatches(src, gregexpr("\\b[A-Za-z][A-Za-z0-9.]*::[A-Za-z._][A-Za-z0-9._]*", src))[[1]]
  m <- unique(m)
  keep <- !vapply(strsplit(m, "::", fixed = TRUE), function(p) p[1] %in% .SKIP_PKG, logical(1))
  # stats:: is skipped as plumbing above, but stats::lm / glm / aov ARE the
  # engine for several methods -- keep those explicitly.
  stat_engines <- grep("^stats::(lm|glm|aov|nls|loess|prcomp|kmeans|t\\.test|wilcox\\.test|chisq\\.test|cor\\.test|anova)$", m)
  sort(unique(c(m[keep], m[stat_engines])))
}

# --- Hand-written notes the registry cannot express -------------------------
# Keyed by spec id. Everything else on the page is generated.
REFERENCE_NOTES <- list(
  ordinal = "Assumes proportional odds: one predictor effect across all level thresholds. If that is implausible, treat the outcome as nominal instead.",
  robust  = "Down-weights outliers rather than removing them. Standard errors are not directly comparable with ordinary least squares.",
  poisson = "Assumes the mean and variance of the count are equal. If the variance is much larger, use the negative binomial instead.",
  negbin  = "For counts whose variance exceeds their mean (overdispersion), which is the common case for ecological counts.",
  glmm    = "Random effects are estimated by maximum likelihood. Convergence warnings are reported rather than hidden -- a model that did not converge should not be interpreted."
)

fmt_role <- function(r)
  sprintf("<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td></tr>",
          esc(r$key), esc(r$label),
          esc(paste(r$types, collapse = ", ")),
          esc(r$hint %||% ""))

fmt_param <- function(p) {
  choices <- if (!is.null(p$choices))
    paste(names(p$choices) %||% unlist(p$choices), collapse = ", ") else ""
  sprintf("<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td></tr>",
          esc(p$key), esc(p$label), esc(p$kind %||% ""),
          esc(if (nzchar(choices)) choices else (p$value %||% "")))
}

sec_stat <- function(s) {
  eng <- engine_of(s$fit)
  paste0(
    sprintf('<section id="m-%s">', esc(s$id)),
    sprintf("<h3>%s</h3>", esc(s$label)),
    sprintf("<p>%s</p>", esc(s$summary)),
    if (length(eng))
      sprintf("<p><strong>Computed with:</strong> %s</p>",
              paste(sprintf("<code>%s()</code>", esc(eng)), collapse = ", "))
    else "",
    if (length(s$roles)) paste0(
      "<p><strong>Variables it needs</strong></p><table>",
      "<tr><th>Role</th><th>Shown as</th><th>Accepts</th><th>Note</th></tr>",
      paste(vapply(s$roles, fmt_role, character(1)), collapse = ""), "</table>") else "",
    if (length(s$params)) paste0(
      "<p><strong>Options</strong></p><table>",
      "<tr><th>Key</th><th>Shown as</th><th>Kind</th><th>Choices / default</th></tr>",
      paste(vapply(s$params, fmt_param, character(1)), collapse = ""), "</table>") else "",
    if (length(s$views))
      sprintf("<p><strong>Results shown:</strong> %s</p>",
              esc(paste(unname(s$views), collapse = " &middot; "))) else "",
    if (!is.null(REFERENCE_NOTES[[s$id]]))
      sprintf('<div class="callout">%s</div>', esc(REFERENCE_NOTES[[s$id]])) else "",
    "</section>")
}

sec_algo <- function(a) {
  eng <- engine_of(a$run)
  paste0(
    sprintf('<section id="a-%s">', esc(a$id)),
    sprintf("<h3>%s</h3>", esc(a$label)),
    sprintf("<p>%s</p>", esc(a$summary)),
    if (length(eng))
      sprintf("<p><strong>Computed with:</strong> %s</p>",
              paste(sprintf("<code>%s()</code>", esc(eng)), collapse = ", ")) else "",
    if (length(a$inputs))
      sprintf("<p><strong>Takes:</strong> %s</p>",
              esc(paste(vapply(a$inputs, function(i)
                sprintf("%s (%s)", i$label %||% i$key, i$pool %||% "?"), character(1)),
                collapse = ", "))) else "",
    if (length(a$params)) paste0(
      "<p><strong>Options</strong></p><table>",
      "<tr><th>Key</th><th>Shown as</th><th>Kind</th><th>Choices / default</th></tr>",
      paste(vapply(a$params, fmt_param, character(1)), collapse = ""), "</table>") else "",
    if (!is.null(a$output))
      sprintf("<p><strong>Produces:</strong> a %s layer</p>", esc(a$output$pool)) else "",
    "</section>")
}

stats_all <- tryCatch(ea_statistics(), error = function(e) list())
algos_all <- tryCatch(ea_algorithms(), error = function(e) list())

by_group <- function(x) split(x, vapply(x, function(e) e$group %||% "Other", character(1)))
sg <- by_group(stats_all); ag <- by_group(algos_all)

nav <- paste0(
  '<div class="t">Statistical methods</div>',
  paste(vapply(names(sg), function(g)
    sprintf('<a href="#g-%s">%s</a>', esc(gsub("[^A-Za-z0-9]", "-", g)), esc(g)),
    character(1)), collapse = ""),
  '<div class="t" style="margin-top:14px">Spatial operations</div>',
  paste(vapply(names(ag), function(g)
    sprintf('<a href="#ga-%s">%s</a>', esc(gsub("[^A-Za-z0-9]", "-", g)), esc(g)),
    character(1)), collapse = ""),
  '<div class="t" style="margin-top:14px">General</div>',
  '<a href="#metrics">Metrics</a><a href="#symbology">Symbology</a><a href="#about">About this page</a>')

body <- paste0(
  paste(vapply(names(sg), function(g) paste0(
    sprintf('<section id="g-%s"><h2>%s</h2></section>', esc(gsub("[^A-Za-z0-9]", "-", g)), esc(g)),
    paste(vapply(sg[[g]], sec_stat, character(1)), collapse = "")), character(1)), collapse = ""),
  paste(vapply(names(ag), function(g) paste0(
    sprintf('<section id="ga-%s"><h2>%s</h2></section>', esc(gsub("[^A-Za-z0-9]", "-", g)), esc(g)),
    paste(vapply(ag[[g]], sec_algo, character(1)), collapse = "")), character(1)), collapse = ""))

n_stat <- length(stats_all); n_algo <- length(algos_all)
built <- format(Sys.Date(), "%e %B %Y")

page <- sprintf('<!doctype html>
<html lang="en">

<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Reference — how EasyAnalysis computes things</title>
  <meta name="description"
    content="What EasyAnalysis actually runs: the function behind each analysis, the variables it needs, its options and what the results mean.">
  <link rel="canonical" href="https://easyanalysis.dev/reference">
  <meta name="robots" content="index, follow, max-snippet:-1">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="EasyAnalysis">
  <meta property="og:url" content="https://easyanalysis.dev/reference">
  <meta property="og:title" content="Reference — how EasyAnalysis computes things">
  <meta property="og:description"
    content="The function behind each analysis, the variables it needs, its options and what the results mean.">
  <meta name="twitter:card" content="summary">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="apple-touch-icon" href="/favicon.png">
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "TechArticle",
    "headline": "EasyAnalysis method reference",
    "url": "https://easyanalysis.dev/reference",
    "about": { "@type": "SoftwareApplication", "name": "EasyAnalysis", "url": "https://easyanalysis.dev/" },
    "author": { "@type": "Person", "name": "Tim Casanda Gibson" }
  }
  </script>
  <link rel="stylesheet" href="assets/site.css">
</head>

<body>
  <nav>
    <div class="wrap">
      <a class="brand" href="index.html">
        <span class="mk"><svg viewBox="0 0 24 24">
            <path d="M9 21h6v-1H9v1zm3-19a7 7 0 0 0-4 12.7V17a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1v-2.3A7 7 0 0 0 12 2z" />
          </svg></span>
        EasyAnalysis
      </a>
      <span class="links">
        <a href="index.html">Home</a>
        <a href="how-to-use.html">How to use</a>
        <a href="documentation.html">Getting started</a>
        <a class="on" href="reference.html">Reference</a>
        <a href="release-notes.html">Release notes</a>
        <a class="btn go sm" href="index.html#get">Download</a>
      </span>
    </div>
  </nav>

  <div class="wrap doc">
    <aside>%s</aside>

    <article>
      <div class="eyebrow">Reference</div>
      <h1>How EasyAnalysis computes things</h1>
      <p class="sub">The function behind each analysis, the variables it needs, the options it
        exposes and what it produces. If you are publishing a result, this is what to cite
        alongside the tool.</p>
      <div class="callout"><strong>This page is generated from the application itself</strong> —
        %d statistical methods and %d spatial operations, read from the registries that define
        them. The function names below are extracted from the code that runs, so they cannot
        drift from what the app actually does. Built %s.</div>

      %s

      <section id="metrics">
        <h2>Metrics</h2>
        <p>Model quality figures are computed by one shared function
          (<code>uef_evaluation()</code>) wherever they appear, so they are comparable across
          screens rather than each screen defining its own.</p>
        <table>
          <tr><th>Metric</th><th>Meaning</th></tr>
          <tr><td>RMSE</td><td>Root mean squared error — typical size of the prediction error, in
            the units of the response. Lower is better.</td></tr>
          <tr><td>R²</td><td>Proportion of variance explained. 1 is perfect; 0 is no better than
            predicting the mean.</td></tr>
          <tr><td>Bias</td><td>Mean signed error. Positive means the model over-predicts on
            average.</td></tr>
          <tr><td>RelBias / RRMSE</td><td>The same two quantities as a percentage of the mean
            observed value, so they can be compared between variables measured on different
            scales.</td></tr>
        </table>
        <p>Where a method reports cross-validated figures, the folds are produced by the shared
          helper and the metric is computed on held-out rows, not on the rows used to fit.</p>
      </section>

      <section id="symbology">
        <h2>Symbology</h2>
        <p>How map colours are decided. The full user-facing description is in
          <a href="documentation.html#symbology">Getting started</a>; this is what happens
          underneath.</p>
        <ul>
          <li><strong>Categorised</strong> — the distinct values of the chosen column are sorted,
            and one palette colour is assigned per value.</li>
          <li><strong>Graduated</strong> — class boundaries are <strong>quantiles</strong> of the
            chosen column, so each class holds a similar number of features. Equal-width bands are
            used only as a fallback, when the values are too tied for quantiles to produce distinct
            boundaries. Skewed data is the norm for measured attributes, and equal-width bands
            would put nearly every feature in one class.</li>
          <li><strong>Palettes</strong> are perceptually uniform ramps from
            <code>viridisLite</code>; viridis, magma, plasma and cividis remain distinguishable
            under the common forms of colour blindness.</li>
          <li>A numeric column is offered for <em>categorised</em> styling only when its values
            repeat — a column with one distinct value per feature would produce a legend as long
            as the layer.</li>
        </ul>
      </section>

      <section id="about">
        <h2>About this page</h2>
        <p>Method names, variable roles, options and the underlying function calls are read
          directly from the application when this page is built. Assumptions and caveats are
          written by hand, because they cannot be derived from code.</p>
        <p>If something here disagrees with what the app does, the page is wrong and should be
          rebuilt — that is the point of generating it.</p>
        <p>Published methods implemented in the app are listed with their citations on the
          <strong>References</strong> screen inside EasyAnalysis. Citing the tool does not replace
          citing the method — see <a href="documentation.html#cite">how to cite</a>.</p>
      </section>
    </article>
  </div>

  <footer>
    <div class="wrap">
      <span>EasyAnalysis</span>
      <span style="margin-left:auto"><a href="documentation.html">Getting started</a></span>
    </div>
  </footer>
</body>

</html>
', nav, n_stat, n_algo, built, body)

writeLines(page, "landing/reference.html", useBytes = TRUE)
cat(sprintf("reference.html written — %d statistical methods, %d spatial operations\n",
            n_stat, n_algo))
