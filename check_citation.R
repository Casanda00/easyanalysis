# check_citation.R -- the citation must be present, correct, and never stale
#
# WHY THIS EXISTS
# ---------------
# Citation text is the one place where being quietly out of date causes real
# harm: it ends up in somebody's paper. The landing page carried APA and BibTeX
# with the version frozen at 0.10.16 while the app had moved on ELEVEN releases,
# and the app itself carried no citation at all -- which is the one place a
# person finishing an analysis actually is.
#
# So the version is read from APP_VERSION at call time and cannot drift, and the
# author is asserted rather than assumed.
#
# Run:  Rscript check_citation.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages({source("global.R"); source("ui.R")})

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

ct <- ea_citation()

# ---- 1. The author is credited, in both formats ----------------------------
say(grepl("Gibson, T. C.", ct$apa, fixed = TRUE), "APA credits Gibson, T. C.")
say(grepl("Gibson, Tim Casanda", ct$bibtex, fixed = TRUE),
    "BibTeX credits the full name, Gibson, Tim Casanda")

# CFF has no middle-name field, so all given names belong in `given-names`.
cff <- paste(readLines("CITATION.cff", warn = FALSE), collapse = "\n")
say(grepl('given-names: "Tim Casanda"', cff, fixed = TRUE) &&
    grepl("family-names: Gibson", cff, fixed = TRUE),
    "CITATION.cff agrees with both")

# ---- 2. It cannot go stale -------------------------------------------------
# THE assertion. A hardcoded version would pass every other check here and be
# wrong the moment APP_VERSION moved -- which is exactly what happened for eleven
# releases on the landing page.
say(grepl(APP_VERSION, ct$apa, fixed = TRUE),
    sprintf("APA carries the RUNNING version (%s), not a literal", APP_VERSION))
say(grepl(paste0("version = {", APP_VERSION, "}"), ct$bibtex, fixed = TRUE),
    "BibTeX likewise")
old <- ea_citation(version = "9.9.9")
say(grepl("9.9.9", old$apa, fixed = TRUE) && !grepl(APP_VERSION, old$apa, fixed = TRUE),
    "CONTROL: the version is genuinely a parameter, not a coincidence")

# The release year must NOT follow the clock -- a citation names when the
# software was published, so Sys.Date() would rewrite history every January.
say(grepl(EA_CITE_YEAR, ct$apa, fixed = TRUE), "the year is the release year constant")

# ---- 3. Reachable from Help, and in the in-app documentation ---------------
w <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = "\n")
say(grepl("Shiny.setInputValue('cite_open'", w, fixed = TRUE),
    "Help offers How to cite")
s <- paste(readLines("server.R", warn = FALSE), collapse = "\n")
say(grepl("observeEvent(input$cite_open", s, fixed = TRUE), "and it is handled")

doc <- paste(as.character(htmltools::renderTags(docsCanvasUI("d"))$html), collapse = " ")
say(grepl("How to cite", doc, fixed = TRUE),
    "the in-app documentation has a How to cite section")
say(grepl(APP_VERSION, doc, fixed = TRUE),
    "showing the running version, so it matches Help rather than drifting from it")
say(grepl("Tim Casanda Gibson", doc, fixed = TRUE),
    "and names the creator")

tools <- paste(as.character(htmltools::renderTags(docsToolsUI("d"))$html), collapse = " ")
say(grepl("doc-cite", tools, fixed = TRUE),
    "the docs sidebar links to it -- a section with no nav entry is hard to find")

# ---- 4. Acknowledgements credit the author ---------------------------------
u  <- if (is.function(ui)) ui(NULL) else ui
html <- paste(as.character(htmltools::renderTags(u)$html), collapse = " ")
say(grepl("Tim Casanda Gibson", html, fixed = TRUE),
    "Settings > Acknowledgements credits the creator")
say(grepl("University of Eastern Finland", html, fixed = TRUE),
    "CONTROL: the existing contributor credit is still there")

# ---- 5. The landing page agrees with the app -------------------------------
# Two copies of the same fact drift. This is the check that notices.
lp <- paste(readLines("landing/documentation.html", warn = FALSE), collapse = "\n")
say(grepl(APP_VERSION, lp, fixed = TRUE),
    sprintf("the landing page's citation shows %s too", APP_VERSION))
say(!grepl("0.10.16", lp, fixed = TRUE),
    "CONTROL: the frozen 0.10.16 is gone from the landing page")

cat(if (ok) "\nCITATION CHECK: PASS\n" else "\nCITATION CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
