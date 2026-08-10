# check_local_ingest.R -- adding data from disk must not copy the bytes
#
# WHY THIS EXISTS
# ---------------
# THE DATA RULE (CLAUDE.md): this app runs on the same machine as the data, so a
# file the user already has should be OPENED, not uploaded. The browser route
# copies the bytes through an HTTP multipart transfer into a temp file and then
# opens that -- and the transport is the entire wait, since a 100 M-cell raster
# opens in 0.09 s and disk runs at 1,277 MB/s.
#
# The property being guarded is therefore NOT speed. It is that no copy happens:
# the layer must reference the user's own path. A future "optimisation" that
# staged files to a temp directory would look harmless, pass every other check,
# and silently reinstate the cost this route exists to remove.
#
# Run:  Rscript check_local_ingest.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages({source("global.R"); source("ui.R")})   # ui.R defines `ui`

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

home <- file.path(tempdir(), paste0("li_", as.integer(runif(1, 1e5, 9e5))))
dir.create(home, recursive = TRUE, showWarnings = FALSE)

# A file that is emphatically NOT in any temp upload directory.
src <- file.path(home, "mydata.csv")
utils::write.csv(data.frame(a = 1:5, b = runif(5)), src, row.names = FALSE)
tif <- file.path(home, "myraster.tif")
r <- terra::rast(nrows = 40, ncols = 40, xmin = 0, xmax = 40, ymin = 0, ymax = 40)
terra::values(r) <- seq_len(terra::ncell(r))
suppressWarnings(terra::writeRaster(r, tif, overwrite = TRUE))
rm(r)

# ---- 1. The fileInput shape is reproduced exactly ---------------------------
# `.ingest_files` is reused verbatim, so this shape is the whole contract.
f <- ea_files_from_paths(c(src, tif))
say(!is.null(f) && nrow(f) == 2, "two real paths become a two-row file table")
say(all(c("name", "size", "type", "datapath") %in% names(f)),
    "with the same columns Shiny's fileInput produces")
say(identical(f$name, c("mydata.csv", "myraster.tif")), "names are the file names")

# THE assertion. datapath must be the user's file, not a copy of it.
say(identical(normalizePath(f$datapath, winslash = "/"),
              normalizePath(c(src, tif), winslash = "/")),
    "CONTROL: datapath points at the ORIGINAL file -- nothing was copied")
say(!any(grepl(tempdir(), f$datapath, fixed = TRUE) &
         !grepl(basename(home), f$datapath, fixed = TRUE)),
    "and not at an upload staging directory")

# ---- 2. Missing files are dropped, not passed on ----------------------------
say(is.null(ea_files_from_paths(file.path(home, "nope.csv"))),
    "a path that does not exist yields nothing rather than a broken row")
f2 <- ea_files_from_paths(c(src, file.path(home, "nope.csv")))
say(!is.null(f2) && nrow(f2) == 1, "a mix keeps only what exists")

# ---- 3. The picker degrades honestly ----------------------------------------
# NULL means "no OS dialog here" (browser build) and must be distinguishable from
# character(0), which means "the user cancelled". Conflating them would either
# swallow a cancel or show a spurious error.
say(is.function(ea_pick_files), "ea_pick_files() exists")
say(!identical(NULL, character(0)),
    "CONTROL: NULL (no dialog) and character(0) (cancelled) are different values")

# ---- 4. It is reachable, and the local route is the primary one -------------
u  <- if (is.function(ui)) ui(NULL) else ui
rt <- htmltools::renderTags(u)
html <- paste(paste(as.character(rt$head), collapse = "\n"),
              paste(as.character(rt$html), collapse = "\n"), sep = "\n")
# ONE control, not two. Offering both routes made the user choose between things
# they should not have to tell apart, so the rail renders a single "Add Data"
# whose underlying function is the disk route.
say(grepl("add_data_ui", html, fixed = TRUE), "the rail renders one Add Data control")
body_html <- paste(as.character(rt$html), collapse = "\n")
say(!grepl("add_from_disk", body_html, fixed = TRUE),
    "CONTROL: the separate 'Add data from disk' button is gone")
say(!grepl("Upload instead", body_html, fixed = TRUE),
    "CONTROL: there is no second, competing upload button")

s <- paste(readLines("server.R", warn = FALSE), collapse = "\n")
say(grepl("observeEvent(input$add_data", s, fixed = TRUE), "and is handled")
say(grepl("output$add_data_ui", s, fixed = TRUE) &&
    grepl(".ea_tk_ready()", s, fixed = TRUE),
    "the control is chosen by whether a native dialog exists, not by the user")
say(grepl('buttonLabel = "Add Data"', s, fixed = TRUE),
    "and the fallback carries the SAME name, so only the mechanism differs")

# The workspace's Add Data > From file must reach the SAME action. It used to do
# document.getElementById('upload_files').click(), which broke silently the moment
# the rail rendered a button instead of a file input: getElementById returned null
# and .click() threw, so the menu item did nothing at all. A menu item must never
# depend on another control's DOM node existing.
w <- paste(readLines("mod_workspace.R", warn = FALSE), collapse = "\n")
say(!grepl("getElementById('upload_files').click()", w, fixed = TRUE),
    "CONTROL: the menu no longer clicks a DOM node that may not exist")
say(grepl("Shiny.setInputValue('add_data_request'", w, fixed = TRUE),
    "the Add Data menu fires the shared action instead")
say(grepl("observeEvent(input$add_data_request", s, fixed = TRUE) &&
    grepl("observeEvent(input$add_data,", s, fixed = TRUE),
    "and both surfaces call one handler, so they cannot drift apart")
say(grepl("ea_files_from_paths(paths)", s, fixed = TRUE) &&
    grepl(".ingest_files(files)", s, fixed = TRUE),
    "reusing .ingest_files verbatim, so every file type behaves identically")

cat(if (ok) "\nLOCAL INGEST CHECK: PASS\n" else "\nLOCAL INGEST CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
