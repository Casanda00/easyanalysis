# check_ui_js.R -- syntax-check every inline <script> the UI emits.
#
# WHY THIS EXISTS
# ---------------
# v0.10.7 shipped a Quit button whose confirm() text contained "\n\n". That
# string lives inside an R double-quoted HTML() block, so R consumed the escape
# and emitted REAL newlines inside a JavaScript string literal -- a syntax
# error. One bad character killed the entire <script> block, so openSettings(),
# the project-open handlers and every other inline function became undefined.
# The app looked completely normal and NOTHING was clickable.
#
# The build check did not catch it (the R parsed fine). The feature's own tests
# did not catch it either, because they asserted the confirm TEXT was PRESENT --
# presence, not validity. This script closes exactly that gap: it renders the
# real UI, pulls out every inline script, and asks node to parse it.
#
# This is CLAUDE.md gotcha 1's family: R escape sequences are interpreted before
# the browser ever sees the string. \n, \t and \" are all live hazards inside
# HTML(); write \\n, \\t, \\" when the JS is meant to receive them.
#
# Usage:  Rscript check_ui_js.R          (needs node on PATH)

suppressMessages({ library(shiny); library(bslib); library(shinyWidgets) })

ok_node <- nzchar(Sys.which("node"))
if (!ok_node) {
  cat("check_ui_js: node not found on PATH -- cannot validate JS. SKIPPED.\n")
  quit(status = 0L)
}

# Run from the app directory (same convention as check_plot_views.R).
if (!file.exists("ui.R")) stop("run this from the app directory (ui.R not found)")
suppressMessages({ source("global.R"); source("ui.R") })

u  <- if (is.function(ui)) ui(NULL) else ui
rt <- htmltools::renderTags(u)
html <- paste(paste(as.character(rt$head), collapse = "\n"),
              paste(as.character(rt$html), collapse = "\n"), sep = "\n")

# Inline scripts only: <script src=...> is a file, not our string-escaping risk.
m   <- gregexpr("<script(?![^>]*\\bsrc=)[^>]*>([\\s\\S]*?)</script>", html, perl = TRUE)
raw <- regmatches(html, m)[[1]]

# Keep only blocks that are actually JAVASCRIPT. A <script type="application/json">
# (Shiny emits these for selectize config) and type="application/ld+json" are
# DATA -- node rejects a bare object literal, which would be a false alarm.
open_tag <- sub(">[\\s\\S]*$", ">", raw, perl = TRUE)
type_of  <- sub('^.*\\btype\\s*=\\s*["\']([^"\']*)["\'].*$', "\\1", open_tag, perl = TRUE)
type_of[type_of == open_tag] <- ""            # no type attribute => JavaScript
is_js <- type_of %in% c("", "text/javascript", "application/javascript", "module")

blocks <- sub("^<script[^>]*>", "", raw[is_js])
blocks <- sub("</script>$", "", blocks)
blocks <- blocks[nzchar(trimws(blocks))]
cat(sprintf("check_ui_js: %d script tag(s), %d are JavaScript\n", length(raw), sum(is_js)))

cat(sprintf("check_ui_js: %d inline script block(s)\n", length(blocks)))
fail <- 0L
for (i in seq_along(blocks)) {
  f <- tempfile(fileext = ".js")
  writeLines(blocks[[i]], f)
  res <- suppressWarnings(system2("node", c("--check", shQuote(f)),
                                  stdout = TRUE, stderr = TRUE))
  st  <- attr(res, "status")
  if (!is.null(st) && st != 0L) {
    fail <- fail + 1L
    cat(sprintf("\n  BLOCK %d: SYNTAX ERROR\n", i))
    cat(paste0("    ", utils::head(res, 12), collapse = "\n"), "\n")
  } else {
    cat(sprintf("  block %d: OK (%d chars)\n", i, nchar(blocks[[i]])))
  }
  unlink(f)
}

if (fail > 0L) {
  cat(sprintf("\ncheck_ui_js: FAIL -- %d block(s) do not parse.\n", fail))
  cat("Hint: inside HTML(\"...\") write \\\\n, not \\n (CLAUDE.md gotcha 1).\n")
  quit(status = 1L)
}
cat("check_ui_js: PASS -- all inline scripts parse.\n")
