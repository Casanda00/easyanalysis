# check_attrdock.R -- the attribute table's window state must survive a re-render
#
# WHY THIS EXISTS
# ---------------
# The dock is built inside .map_ui(), so it is destroyed and rebuilt every time
# the map re-renders: choosing a layer, toggling visibility, changing basemap.
# The original collapse button toggled a class ON THE DOCK and rewrote its own
# label, so both were lost at the first interaction and the panel sprang back
# open on its own. The fix keeps the state on <html>, which survives.
#
# That invariant is invisible in a screenshot and easy to undo by "tidying" the
# handler back onto the element, so it is asserted here: every state selector
# must be rooted at html.ea-attr-*, and the buttons must carry no state at all.
#
# Run:  Rscript check_attrdock.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages({source("global.R"); source("ui.R")})

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

u  <- if (is.function(ui)) ui(NULL) else ui
rt <- htmltools::renderTags(u)
html <- paste(paste(as.character(rt$head), collapse = "\n"),
              paste(as.character(rt$html), collapse = "\n"), sep = "\n")

# ---- 1. The stylesheet carries the state, rooted at <html> ------------------
say(grepl("html.ea-attr-max .ea-wsx-attrdock", html, fixed = TRUE), "maximise rule exists")
say(grepl("html.ea-attr-min .ea-wsx-attrbody", html, fixed = TRUE), "minimise rule exists")
say(grepl("html.ea-attr-closed .ea-wsx-attrdock", html, fixed = TRUE), "close rule exists")
say(grepl("--ea-attr-h", html, fixed = TRUE), "the drag-resize height is a custom property")

# ---- 2. The state machine, exercised as REAL code --------------------------
# The function is lifted out of the rendered page and run in node against a stub,
# so this tests what ships rather than a copy of it. The stub implements
# classList and the attribute pair properly -- an incomplete double is its own
# recurring source of false failures (gotcha 33).
js <- file.path(tempdir(), "ea_attr_state.js")
writeLines(c(
  "const src = require('fs').readFileSync(process.argv[2], 'utf8');",
  "const i = src.indexOf('var eaAttrSet = function');",
  "if (i < 0) { console.log('NOFUNC'); process.exit(0); }",
  "let d = 0, j = src.indexOf('{', i), k = j;",
  "for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } }",
  "const fn = src.slice(i, k + 1) + ';';",
  "const cls = new Set(); const attrs = {};",
  "const document = { documentElement: {",
  "  classList: { add:(c)=>cls.add(c), remove:(...c)=>c.forEach(x=>cls.delete(x)),",
  "               contains:(c)=>cls.has(c) },",
  "  setAttribute:(k2,v)=>attrs[k2]=v, getAttribute:(k2)=>attrs[k2] } };",
  "const window = {};",
  "eval(fn);",
  "const snap = () => [...cls].sort().join(',') + '|' + (attrs['data-attr-state']||'');",
  "const out = [];",
  "eaAttrSet('normal');  out.push(snap());",
  "eaAttrSet('min');     out.push(snap());",
  "eaAttrSet('max');     out.push(snap());",
  "eaAttrSet('closed');  out.push(snap());",
  "eaAttrSet('normal');  out.push(snap());",
  "console.log(out.join(' ~ '));"
), js)

page <- file.path(tempdir(), "ea_page.html")
writeLines(html, page)
res <- tryCatch(system2("node", c(shQuote(js), shQuote(page)), stdout = TRUE, stderr = TRUE),
                error = function(e) NA_character_)
res <- paste(res, collapse = " ")

if (is.na(res) || !nzchar(res)) {
  cat("SKIP  node unavailable; state machine not exercised\n")
} else if (grepl("NOFUNC", res)) {
  say(FALSE, "eaAttrSet was not found in the rendered page")
} else {
  parts <- strsplit(res, " ~ ", fixed = TRUE)[[1]]
  say(identical(parts[1], "|normal"),            "normal clears every state class")
  say(identical(parts[2], "ea-attr-min|min"),    "minimise sets exactly one class")
  say(identical(parts[3], "ea-attr-max|max"),    "maximise REPLACES minimise, never stacks")
  say(identical(parts[4], "ea-attr-closed|closed"), "close replaces maximise")
  say(identical(parts[5], "|normal"),            "returning to normal leaves nothing behind")
}

# ---- 3. The buttons hold no state --------------------------------------------
w <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = "\n")
say(grepl('data-attr-act` = "min"',   w, fixed = TRUE) &&
    grepl('data-attr-act` = "max"',   w, fixed = TRUE) &&
    grepl('data-attr-act` = "close"', w, fixed = TRUE),
    "the dock renders minimise, maximise and close")

# CONTROL: the exact shape that caused the bug. The old button toggled a class on
# the dock and rewrote its own textContent, both of which the next re-render threw
# away. If either returns, the panel silently starts springing back open again.
# Scoped to the DOCK. A bare search for classList.toggle('collapsed') also matches
# the split panes (.ea-wsx-sp), which legitimately keep their own collapse and are
# not rebuilt the same way -- the first version of this line failed on those and
# looked like a defect in working code.
say(!grepl("ea-wsx-attrdock')?.classList.toggle('collapsed')", w, fixed = TRUE) &&
    !grepl("ea-wsx-attrdock'); if(d)d.classList.toggle", w, fixed = TRUE),
    "CONTROL: nothing toggles state on the DOCK element any more")
say(!grepl("this.textContent=d.classList", w, fixed = TRUE),
    "CONTROL: no button stores its own label state")

cat(if (ok) "\nATTRIBUTE DOCK CHECK: PASS\n" else "\nATTRIBUTE DOCK CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
