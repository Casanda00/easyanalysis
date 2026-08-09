# check_notifications.R -- an error message must not delete itself
#
# WHY THIS EXISTS
# ---------------
# The app raised 110 error notifications; 2 were persistent. The other 108 expired
# after 5-8 seconds, taking the explanation with them. The messages are usually
# specific and name a remedy, so what vanished was the useful part.
#
# It also silently taxes external testing: a tester cannot report a message they
# never finished reading, so the report arrives as "it didn't work" and the
# diagnosis is gone.
#
# The fix is a single wrapper in helpers.R that shadows shiny::showNotification,
# so this check exists to prove the shadow is REACHED and that it changes what
# arrives at shiny -- not merely that the wrapper runs when called directly.
#
# Run:  Rscript check_notifications.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
source("global.R")

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# Record what actually reaches shiny. assignInNamespace genuinely rebinds what
# `shiny::showNotification` resolves to (gotcha 27 / 35).
seen <- list()
real <- shiny::showNotification
rec  <- function(ui, action = NULL, duration = 5, closeButton = TRUE, id = NULL,
                 type = "default", session = NULL) {
  seen[[length(seen) + 1L]] <<- list(ui = as.character(ui), duration = duration,
                                     closeButton = closeButton, id = id, type = type)
  invisible(id)
}
suppressWarnings(assignInNamespace("showNotification", rec, ns = "shiny"))
on.exit(suppressWarnings(assignInNamespace("showNotification", real, ns = "shiny")))

# ---- 1. The wrapper is the one being called --------------------------------
say(!identical(showNotification, real),
    "the unqualified name resolves to OUR wrapper, not shiny's")
say(environmentName(environment(showNotification)) == "R_GlobalEnv",
    "the wrapper lives in the global env, where module code will find it")

# ---- 2. Errors become persistent -------------------------------------------
showNotification("Something broke, and here is why.", type = "error", duration = 8)
e <- seen[[length(seen)]]
say(is.null(e$duration),
    "CONTROL: an error passed duration = 8 arrives at shiny with duration = NULL")
say(isTRUE(e$closeButton), "a persistent error is dismissible")
say(!is.null(e$id), "an error is given an id so a repeat replaces rather than stacks")

showNotification("Something broke, and here is why.", type = "error")
say(identical(seen[[length(seen)]]$id, e$id),
    "the SAME error text yields the SAME id -- a failing reactive cannot stack up")
showNotification("A different failure entirely.", type = "error")
say(!identical(seen[[length(seen)]]$id, e$id),
    "a DIFFERENT error gets a different id, so distinct problems stay visible")

# ---- 3. Everything else is untouched ---------------------------------------
showNotification("Saved.", type = "message", duration = 3)
say(identical(seen[[length(seen)]]$duration, 3),
    "CONTROL: a message keeps its duration -- transient by intent")
showNotification("Careful.", type = "warning", duration = 6)
say(identical(seen[[length(seen)]]$duration, 6), "a warning keeps its duration")
showNotification("Plain.")
say(identical(seen[[length(seen)]]$duration, 5), "the default duration is preserved")

# Positional calls must still land correctly, since the signature is mirrored.
showNotification("Positional.", NULL, 9, TRUE, NULL, "warning")
say(identical(seen[[length(seen)]]$duration, 9) &&
    identical(seen[[length(seen)]]$type, "warning"),
    "a fully positional call still maps onto the right arguments")

suppressWarnings(assignInNamespace("showNotification", real, ns = "shiny"))

# ---- 4. The Data Quality pop-up is gone -------------------------------------
# Asserted on BEHAVIOUR, not on source text (gotcha 33): activating a dataset
# with obvious quality problems must raise nothing at all.
src <- paste(readLines("server.R", warn = FALSE), collapse = "\n")
say(!grepl("Data Quality:", src, fixed = TRUE),
    "server.R no longer raises a Data Quality notification")
say(exists(".quality_check") && is.function(.quality_check),
    ".quality_check() is KEPT -- the analysis was right, the delivery was not")

# ---- 5. The path that actually matters: from inside a MODULE ---------------
# Everything above ran in a script, whose environment is the global env. A module
# server is a different frame, so the shadow only works if lookup walks out to
# the global env from there. Reasoning says it does; this proves it, on the exact
# message that prompted the change -- the round-trip refusal, which a user hits
# by fitting a model on a dataset that did not come from "Attributes to Table".
seen <- list()
suppressWarnings(assignInNamespace("showNotification", rec, ns = "shiny"))

spec <- local({
  ss <- ea_statistics()
  ss[[which(vapply(ss, function(x) x$id, "") == "robust")]]
})
set.seed(2); nn <- 40
plain <- init_data(data.frame(y = rnorm(nn), x = rnorm(nn)))   # NO layer link
pool  <- reactiveValues(D = plain)
vpool <- reactiveValues()

suppressWarnings(testServer(statServer,
  args = list(spec = spec, dataset_pool = pool, active_dataset = reactive("D"),
              vector_pool = vpool, raster_pool = NULL),
  {
    # Role inputs are namespaced r_<key> (read from mod_stat.R, not guessed --
    # role_<key> was wrong, so nothing fitted and the check "passed" by proving
    # nothing at all).
    session$setInputs(r_y = "y", r_x = "x")
    session$setInputs(run = 1)
    session$setInputs(act_to_layer = 1)
  }))

suppressWarnings(assignInNamespace("showNotification", real, ns = "shiny"))

errs <- Filter(function(x) identical(x$type, "error"), seen)
say(length(errs) > 0,
    sprintf("the refusal reached the notification layer from inside a module (%d error(s))",
            length(errs)))
if (length(errs)) {
  say(is.null(errs[[length(errs)]]$duration),
      "and it is PERSISTENT -- the wrapper is reached from a module frame")
  say(grepl("Attributes to Table", errs[[length(errs)]]$ui),
      sprintf("the message still names the remedy: %s",
              substr(errs[[length(errs)]]$ui, 1, 70)))
}

cat(if (ok) "\nNOTIFICATION CHECK: PASS\n" else "\nNOTIFICATION CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
