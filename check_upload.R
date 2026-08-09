# check_upload.R -- there is no upload cap, and a selection is never silent
#
# WHY THIS EXISTS
# ---------------
# A 4 GB raster was uploaded during testing and simply vanished: no layer, no
# error, nothing. Two causes, both verified in the code rather than guessed:
#
#   1. global.R set shiny.maxRequestSize = 3 * 1024^3 -- 3 GiB. A 4 GB file is
#      3.73 GiB, so it was over the cap.
#   2. Shiny rejects an oversized upload with stop("Maximum upload size exceeded")
#      INSIDE ShinySession$@uploadInit, an RPC handler. That surfaces in the
#      browser console, not in the app, so the user sees nothing at all. The
#      app's own handler then never runs -- req(input$upload_files) halts on an
#      input that never populated.
#
# Inf is used rather than a large number: any finite value is a cliff somebody
# eventually walks off, and this is what walking off it looks like.
#
# Run:  Rscript check_upload.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages({source("global.R"); source("ui.R")})   # ui.R defines `ui`

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# ---- 1. No cap --------------------------------------------------------------
v <- getOption("shiny.maxRequestSize")
say(is.infinite(v) && v > 0, sprintf("shiny.maxRequestSize is unbounded (%s)", format(v)))
say(!(4 * 1000^3 > v), "CONTROL: the 4 GB file that vanished would now pass")
say(!(1e13 > v), "and so would a 10 TB file -- there is no cliff left")

# ---- 2. Shiny's own comparison tolerates Inf --------------------------------
# Both sites read the option and compare with `>`; Inf must not be coerced or
# treated as "disabled". Exercised against the REAL expressions Shiny uses.
maxSize <- getOption("shiny.maxRequestSize", 5 * 1024 * 1024)
say(maxSize > 0, "uploadInit's `maxSize > 0` guard stays TRUE (0 would disable uploads)")
say(!any(c(4 * 1000^3, 1e13) > maxSize),
    "uploadInit's `any(sizes > maxSize)` is FALSE, so nothing is rejected")
say(!(maxSize <= 0), "createHttpuvApp's `maxSize <= 0` early-return does not trigger")

# ---- 3. A selection is reported before the wait -----------------------------
# The other half: an upload that takes minutes must not look like a hang.
u  <- if (is.function(ui)) ui(NULL) else ui
rt <- htmltools::renderTags(u)
html <- paste(paste(as.character(rt$head), collapse = "\n"),
              paste(as.character(rt$html), collapse = "\n"), sep = "\n")
say(grepl("upload_selected", html, fixed = TRUE),
    "the page reports a file selection the moment it is made")

# THE assertion this check was missing, and it shipped a dead feature because of
# it. The first version asserted only that "upload_selected" appeared in the HTML
# -- which it did, inside code that never ran. The script lives in <head>, so it
# executes BEFORE the body is parsed; getElementById('upload_files') returned
# null, `if(fi)` skipped, and no listener was ever attached. A 4 GB upload
# therefore produced no message at all, exactly as reported.
#
# Presence is not function. What must be true is that the handler does not depend
# on the element existing at script time.
say(grepl("document.addEventListener('change'", html, fixed = TRUE),
    "the selection handler is DELEGATED on document, so head/body order cannot break it")
say(!grepl("var fi=document.getElementById('upload_files')", html, fixed = TRUE),
    "CONTROL: it no longer grabs the element at script time (that was the dead version)")

s <- paste(readLines("server.R", warn = FALSE), collapse = "\n")
say(grepl("observeEvent(input$upload_selected", s, fixed = TRUE),
    "and the server answers it with a notification")

# ---- 4. CONTROL: the old cap is really gone ---------------------------------
g <- paste(readLines("global.R", warn = FALSE), collapse = "\n")
say(!grepl("maxRequestSize = 3 * 1024^3", g, fixed = TRUE),
    "CONTROL: the 3 GiB cap is no longer set")

cat(if (ok) "\nUPLOAD CHECK: PASS\n" else "\nUPLOAD CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
