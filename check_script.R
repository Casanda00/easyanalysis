# check_script.R -- "See script" must REPRODUCE the result, not describe it
#
# WHY THIS EXISTS
# ---------------
# A point-and-click result cannot be reproduced by anyone who was not at the
# machine. Item 57 shows the code that produced it -- and the only thing that
# makes that worth having is that the code actually runs and gives the SAME
# answer. A script that parses but quietly disagrees with what ran is worse than
# no script at all, because it looks authoritative.
#
# So this does not check that a script was produced. It runs it, in a fresh
# environment, and compares coefficients with what the app computed.
#
# Run:  Rscript check_script.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages(source("global.R"))

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

set.seed(7)
n  <- 120
dat <- data.frame(age = runif(n, 5, 80), dbh = runif(n, 5, 60))
dat$height <- 1.5 + 0.22 * dat$age + 0.31 * dat$dbh + rnorm(n, 0, 1.2)

st  <- ea_statistics()
get <- function(id) st[[which(vapply(st, function(x) identical(x$id, id), logical(1)))]]

# ---- every spec can produce a script ---------------------------------------
made <- vapply(st, function(s)
  !is.null(ea_analysis_script(s, roles = list(y = "height", x = c("age", "dbh")),
                              params = list(), data_name = "d")), logical(1))
say(all(made), sprintf("every statistics entry produces a script (%d/%d)",
                       sum(made), length(st)))
al <- ea_algorithms()
made_a <- vapply(al, function(a)
  !is.null(ea_analysis_script(a, data_name = "d")), logical(1))
say(all(made_a), sprintf("every algorithm entry produces a script (%d/%d)",
                         sum(made_a), length(al)))

# ---- every script PARSES ----------------------------------------------------
bad <- character(0)
for (s in st) {
  sc <- ea_analysis_script(s, roles = list(y = "height", x = c("age", "dbh")),
                           params = list(), data_name = "d")
  if (inherits(tryCatch(parse(text = sc), error = function(e) e), "error"))
    bad <- c(bad, s$id)
}
say(!length(bad), if (length(bad)) paste("scripts that do not parse:", paste(bad, collapse = ", "))
                  else "every statistics script parses as R")

# ---- THE ONE THAT MATTERS: it reproduces the app's own answer ----------------
spec  <- get("robust")
roles <- list(y = "height", x = c("age", "dbh"))
params <- list(psi = "bisquare")

app_fit <- spec$fit(dat, roles, params)
sc <- ea_analysis_script(spec, roles, params, data_name = "d")
# Executed with the loader swapped for a fixture via `data_expr`, NOT by
# regex-patching the generated text: a test that rewrites the artefact it is
# testing ends up testing its own regex. Everything else is byte-identical to
# what a user would get.
sc_run <- ea_analysis_script(spec, roles, params, data_expr = "df <- .fixture")
env <- new.env(parent = globalenv())
assign(".fixture", dat, envir = env)
res <- tryCatch(eval(parse(text = sc_run), envir = env), error = function(e) e)

if (inherits(res, "error")) {
  say(FALSE, paste("the generated script failed to run:", conditionMessage(res)))
} else {
  scr_fit <- get0("result", envir = env)
  say(!is.null(scr_fit), "the script runs and produces a fitted model")
  a <- tryCatch(coef(app_fit), error = function(e) NULL)
  b <- tryCatch(coef(scr_fit), error = function(e) NULL)
  say(!is.null(a) && !is.null(b) && identical(names(a), names(b)),
      "same coefficient names")
  say(!is.null(a) && !is.null(b) && max(abs(a - b)) < 1e-8,
      sprintf("IDENTICAL coefficients - the script reproduces the result (max diff %.2e)",
              if (is.null(a) || is.null(b)) NA_real_ else max(abs(a - b))))
}

# ---- the parts that make it runnable ---------------------------------------
say(grepl("library(MASS)", sc, fixed = TRUE),
    "library() lines are derived from the code, not a hand-kept list")
say(grepl("read.csv", sc, fixed = TRUE), "a data-loading line is included")
say(grepl("%||%", sc, fixed = TRUE) && grepl(".ea_formula", sc, fixed = TRUE),
    "the internal helpers the body relies on are emitted, so it stands alone")
say(grepl("bisquare", sc, fixed = TRUE),
    "the user's actual parameter value appears, not a placeholder")

# CONTROL: the body must be the REAL one, not a rebuilt description. If someone
# replaces it with a prettified reconstruction, this fails -- which is the point.
say(grepl("MASS::rlm(.ea_formula(r$y, r$x), data = df, psi = psi)", sc, fixed = TRUE),
    "CONTROL: the analysis body is verbatim from the spec")

# ---- it is reachable from the analysis screen -------------------------------
# A script nobody can open is item 67 again. Asserted by driving the module: the
# button must not exist before a fit, and must exist after one.
dpool <- reactiveValues(D = init_data(dat))
S <- NULL
suppressWarnings(testServer(statServer,
  args = list(spec = spec, dataset_pool = dpool, active_dataset = reactive("D")),
  {
    S <<- list(before = is.null(output$script_ui))
    session$setInputs(r_y = "height", r_x = c("age", "dbh"), p_psi = "bisquare")
    session$setInputs(run = 1)
    S$after  <<- !is.null(output$script_ui)
    S$script <<- .script_text()
  }))
say(isTRUE(S$before), "CONTROL: no See-script button before anything has been run")
say(isTRUE(S$after),  "the See-script button appears once a result exists")
say(!is.null(S$script) && grepl("height", S$script, fixed = TRUE),
    "and the script it offers carries the columns actually chosen")

cat(if (ok) "\nSCRIPT CHECK: PASS\n" else "\nSCRIPT CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
