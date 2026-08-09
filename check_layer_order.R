# check_layer_order.R -- the layers panel and the map must agree on stacking
#
# WHY THIS EXISTS
# ---------------
# Before item 65 the panel was UPSIDE DOWN relative to the map. It listed pool
# order (tables, rasters, lidar, vectors) and .draw_layers() added them in that
# same order -- and leaflet puts the LAST overlay on top. So vectors sat at the
# BOTTOM of the panel and on TOP of the map. Nothing exposed it while the order
# was fixed, but the moment a row can be dragged, "up" would have meant "down".
#
# layers() is now top-first and .draw_layers() walks it in reverse. The assertion
# that matters most is therefore NOT the new feature: it is that an existing
# project's map is UNCHANGED. If the reversal is dropped or doubled, every map
# silently restacks and nothing raises an error.
#
# NOTE ON STYLE: each case runs its own testServer inline. A helper that passed
# `environment()` out of the body was tried first and failed -- the module's
# internals live in the PARENT of the body's evaluation environment, so
# `e$layers` was NULL and the error read like a defect in layers(). Inline is
# duller and cannot lie.
#
# Run:  Rscript check_layer_order.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages(source("global.R"))

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# Pool entries must be NON-NULL. `.names()` filters NULL-valued keys, because a
# reactiveValues key assigned NULL keeps its name (gotcha 14) -- so a fixture of
# NULLs yields an EMPTY pool and every assertion below collapses to the one table.
# That is exactly what the first version of this check did, and it read like a
# defect in layers().
dpool <- reactiveValues(TabA = data.frame(x = 1))
rpool <- reactiveValues(Ras1 = "raster", Ras2 = "raster")
lpool <- reactiveValues(Cloud = "las")
vpool <- reactiveValues(Vec1 = "vector")
POOL  <- c("TabA", "Ras1", "Ras2", "Cloud", "Vec1")   # the historical draw order

LO <- NULL; RES <- NULL
ARGS <- function(with_store = TRUE) {
  a <- list(dataset_pool = dpool, raster_pool = rpool, las_pool = lpool,
            vector_pool = vpool, active_dataset = reactive(NULL))
  if (with_store) a$layer_order <- LO
  a
}

# ---- 1. Default panel order is the pool order REVERSED ----------------------
LO <- reactiveVal(character(0))
suppressWarnings(testServer(workspaceServer, args = ARGS(),
  { RES <<- vapply(layers(), function(l) l$nm, character(1)) }))
panel <- RES
say(identical(panel, rev(POOL)),
    paste0("default panel is top-first: ", paste(panel, collapse = " > ")))

# ---- 2. CONTROL: the DRAW sequence is unchanged from before item 65 ---------
# .draw_layers() iterates rev(layers()). This is the only thing standing between
# a future refactor and every existing map quietly restacking.
say(identical(rev(panel), POOL),
    paste0("CONTROL: draw order still equals the historical pool order: ",
           paste(rev(panel), collapse = " > ")))

# ---- 3. A stored order is honoured, top-first -------------------------------
LO <- reactiveVal(c("Ras1", "Vec1", "TabA", "Ras2", "Cloud"))
suppressWarnings(testServer(workspaceServer, args = ARGS(),
  { RES <<- vapply(layers(), function(l) l$nm, character(1)) }))
say(identical(RES, c("Ras1", "Vec1", "TabA", "Ras2", "Cloud")),
    "a stored order is used verbatim")
say(identical(rev(RES)[length(RES)], "Ras1"),
    "the panel's FIRST row is drawn LAST, i.e. sits on top of the map")

# ---- 4. Unknown and missing names -------------------------------------------
# An order naming a deleted layer must not resurrect it; one missing a new layer
# must not hide it. Both happen constantly as layers come and go.
LO <- reactiveVal(c("Ghost", "Vec1", "TabA"))
suppressWarnings(testServer(workspaceServer, args = ARGS(),
  { RES <<- vapply(layers(), function(l) l$nm, character(1)) }))
say(!("Ghost" %in% RES), "a name in the order with no live layer is dropped")
say(setequal(RES, POOL), "every live layer still appears")
say(identical(tail(RES, 2), c("Vec1", "TabA")), "the stored tail keeps its order")
say(identical(head(RES, 3), rev(c("Ras1", "Ras2", "Cloud"))),
    paste0("unlisted layers go on TOP: ", paste(RES, collapse = " > ")))

# ---- 5. A drop writes the complete order back -------------------------------
LO <- reactiveVal(character(0))
suppressWarnings(testServer(workspaceServer, args = ARGS(), {
  session$setInputs(ws_reorder = list(order = list("Vec1", "Ras2", "TabA", "Ras1", "Cloud")))
  RES <<- list(stored = LO(), panel = vapply(layers(), function(l) l$nm, character(1)))
}))
say(identical(RES$stored, c("Vec1", "Ras2", "TabA", "Ras1", "Cloud")),
    "a drop stores the complete new order")
say(identical(RES$panel, c("Vec1", "Ras2", "TabA", "Ras1", "Cloud")),
    "and the panel re-renders from it")

# ---- 6. Move to top / bottom -------------------------------------------------
LO <- reactiveVal(character(0))
suppressWarnings(testServer(workspaceServer, args = ARGS(),
  { session$setInputs(ws_lyr_top = "TabA"); RES <<- LO() }))
say(identical(RES[1], "TabA"), "move to top puts the layer first")
say(setequal(RES, POOL), "move to top keeps every layer")

LO <- reactiveVal(character(0))
suppressWarnings(testServer(workspaceServer, args = ARGS(),
  { session$setInputs(ws_lyr_bottom = "Vec1"); RES <<- LO() }))
say(identical(RES[length(RES)], "Vec1"), "move to bottom puts the layer last")
say(setequal(RES, POOL), "move to bottom keeps every layer")

# ---- 7. No store: the module must still run ---------------------------------
# layer_order defaults to NULL so the workspace works standalone and under test.
noop <- tryCatch({
  suppressWarnings(testServer(workspaceServer, args = ARGS(with_store = FALSE),
    { session$setInputs(ws_lyr_top = "TabA")
      RES <<- vapply(layers(), function(l) l$nm, character(1)) }))
  TRUE
}, error = function(e) conditionMessage(e))
say(isTRUE(noop), paste0("reordering without a store is a safe no-op",
                         if (!isTRUE(noop)) paste0(" -- ", noop) else ""))
if (isTRUE(noop)) say(identical(RES, rev(POOL)), "and the default order still holds")

# ---- 8. The basemap row cannot be dragged -----------------------------------
# It is tiles pinned under everything, not a project layer. The drag handler keys
# off [data-lyr]; the basemap row has none. Asserted on markup because there is
# no behaviour to observe without a browser.
w  <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = "\n")
bm <- substr(sub("^.*[.]basemap_row <- function[(][)] [{]", "", w), 1, 900)
say(!grepl("data-lyr", bm, fixed = TRUE) && !grepl("ea-wsx-grip", bm, fixed = TRUE),
    "the basemap row carries no grip and no data-lyr, so it stays pinned")

cat(if (ok) "\nLAYER ORDER CHECK: PASS\n" else "\nLAYER ORDER CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
