# tools/testkit.R -- make the right thing the easy thing when writing checks
#
# WHY THIS EXISTS
# ---------------
# Nine checks in one session reported failures that did not exist, and the app
# was correct every time. Two of those were the same mistake: calling a function
# with arguments invented from memory instead of read from its signature.
#
#   testServer(dataServer, args = list(...))            # dataset_names omitted
#   .agent_run_analysis(pool, "d", "lm", response = ..) # real signature is
#                                                       # (args, dataset_pool)
#
# Both surfaced as "the feature is broken" rather than "your call is wrong",
# because the error happened INSIDE the framework. Writing "read the signature"
# in a rules file did not stop it happening a second time, so this makes it
# mechanical: derive the call from formals(), or have the mismatch reported
# immediately and in plain terms.
#
# Usage:  source("tools/testkit.R") at the top of a check script.

# Print a function's real signature. Use this instead of remembering one.
ea_sig <- function(f, name = deparse(substitute(f))) {
  fm  <- formals(f)
  # A formal with no default IS the empty symbol, and binding that to a local
  # variable makes the variable itself "missing" -- so `d <- fm[[n]]` then blew up
  # on the next line that touched `d`. Never bind it: test the flag, and read
  # fm[[i]] only on the branch where a real default exists.
  is_req <- vapply(fm, function(x) identical(x, quote(expr = )), logical(1))
  req <- names(fm)[is_req]
  cat(sprintf("%s(%s)\n", name,
              paste(vapply(seq_along(fm), function(i) {
                if (is_req[i]) names(fm)[i]
                else paste0(names(fm)[i], " = ",
                            paste(deparse(fm[[i]]), collapse = ""))
              }, character(1)), collapse = ", ")))
  cat("  required:", if (length(req)) paste(req, collapse = ", ") else "(none)", "\n")
  invisible(list(all = names(fm), required = req))
}

# Validate a named argument list against a function BEFORE calling it.
# Stops with the real signature rather than letting the framework fail in a way
# that looks like a defect in the code under test.
ea_check_args <- function(f, args, name = deparse(substitute(f))) {
  stopifnot(is.function(f), is.list(args))
  fm  <- formals(f)
  has_dots <- "..." %in% names(fm)
  req <- setdiff(names(fm)[vapply(fm, function(x) identical(x, quote(expr = )), logical(1))],
                 "...")

  unknown <- if (has_dots) character(0) else setdiff(names(args), names(fm))
  missing <- setdiff(req, names(args))

  if (length(unknown) || length(missing)) {
    msg <- sprintf("Call to %s() does not match its signature.\n", name)
    if (length(missing))
      msg <- paste0(msg, "  MISSING required: ", paste(missing, collapse = ", "), "\n")
    if (length(unknown))
      msg <- paste0(msg, "  NOT AN ARGUMENT : ", paste(unknown, collapse = ", "), "\n")
    msg <- paste0(msg, "  real signature  : ", name, "(",
                  paste(names(fm), collapse = ", "), ")\n",
                  "  This is a fault in the CHECK, not in the code under test.")
    stop(msg, call. = FALSE)
  }
  invisible(TRUE)
}

# testServer() with the argument list validated first. A module server that
# throws because an argument was omitted aborts the observer chain, and the
# symptom is every feature looking broken -- which is exactly how "multi-step
# undo is completely broken" was reported when the real fault was a missing
# `dataset_names`.
ea_test_server <- function(server_fn, args, expr,
                           name = deparse(substitute(server_fn))) {
  ea_check_args(server_fn, args, name)
  shiny::testServer(server_fn, args = args, expr = substitute(expr))
}
