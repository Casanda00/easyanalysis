# check_plot_views.R -- run:  Rscript check_plot_views.R
#
# Every select-and-split screen declares .<TAG>_VIEWS_PLOT: the view keys whose
# body renders a plot. That vector decides whether the plot-appearance control
# appears in the header, so a wrong entry means a screen showing a plot with no
# way to title it (or a table offering axis labels).
#
# The vector must not be maintained by hand or guessed from the key NAME -- that
# was the original bug: name rules missed posterior, performance, wind_rose,
# cox_ph_model and every timeseries plot, and "predictions" is a plot on one
# screen and a table on another. This script re-derives the truth from each
# module's own switch() bodies and fails if the declaration disagrees.

files <- list.files(".", pattern = "^mod_")

# does this expression contain a call to plotOutput()/rglwidgetOutput()?
has_plot <- function(e) {
  if (is.call(e)) {
    fn <- e[[1]]
    if (is.name(fn) && as.character(fn) %in% c("plotOutput", "rglwidgetOutput"))
      return(TRUE)
    return(any(vapply(as.list(e), has_plot, logical(1))))
  }
  FALSE
}

# find the first call to `name` anywhere in the tree
find_call <- function(e, name) {
  if (!is.call(e)) return(NULL)
  if (is.name(e[[1]]) && identical(as.character(e[[1]]), name)) return(e)
  for (part in as.list(e)) {
    got <- find_call(part, name)
    if (!is.null(got)) return(got)
  }
  NULL
}

fail <- 0L
checked <- 0L

for (f in files) {
  exprs <- parse(f)
  decl <- NULL
  for (e in exprs) {
    if (is.call(e) && identical(as.character(e[[1]]), "<-") &&
        is.name(e[[2]]) && grepl("_VIEWS_PLOT$", as.character(e[[2]]))) {
      decl <- list(name = as.character(e[[2]]), keys = eval(e[[3]]))
    }
  }
  if (is.null(decl)) next
  checked <- checked + 1L

  panes <- NULL
  for (e in exprs) {
    panes <- find_call(e, "ea_view_panes")
    if (!is.null(panes)) break
  }
  sw <- if (is.null(panes)) NULL else find_call(panes, "switch")
  if (is.null(sw)) {
    cat(sprintf("FAIL %-22s %s declared but no ea_view_panes(switch(...)) found\n",
                f, decl$name))
    fail <- fail + 1L
    next
  }

  args <- as.list(sw)[-(1:2)]           # drop `switch` and the selector
  nm <- names(args)
  if (is.null(nm)) nm <- rep("", length(args))
  keep <- nzchar(nm)                    # named args are the branches
  derived <- nm[keep][vapply(args[keep], has_plot, logical(1))]

  missing <- setdiff(derived, decl$keys)
  extra   <- setdiff(decl$keys, derived)
  if (length(missing) || length(extra)) {
    fail <- fail + 1L
    cat(sprintf("FAIL %-22s %s\n", f, decl$name))
    if (length(missing))
      cat(sprintf("       renders a plot but is not declared: %s\n",
                  paste(missing, collapse = ", ")))
    if (length(extra))
      cat(sprintf("       declared but renders no plot: %s\n",
                  paste(extra, collapse = ", ")))
  } else {
    cat(sprintf("ok   %-22s %s\n", f, paste(decl$keys, collapse = ", ")))
  }
}

cat(sprintf("\n%d screens checked, %d wrong\n", checked, fail))
if (fail > 0L) quit(status = 1L)
