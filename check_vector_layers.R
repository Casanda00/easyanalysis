# check_vector_layers.R -- a multi-layer file must not lose layers, silently
#
# WHY THIS EXISTS
# ---------------
# `sf::st_read(path)` on a source with more than one layer takes the FIRST one
# and warns:
#
#   "automatically selected the first layer in a data source containing more
#    than one"
#
# Every call site passed `quiet = TRUE`, so that warning went to the console --
# where nobody running the app sees it. It was only noticed because a terminal
# happened to be visible. Reproduced before fixing: a 2-layer GeoPackage loaded
# 3 of 5 features and reported success.
#
# That is the worst shape of failure in this app, and this is the third instance
# of it: not a wrong answer and not a visible error, just missing data that looks
# complete. The others were the self-deleting error messages and the silent
# upload rejection.
#
# Run:  Rscript check_vector_layers.R

suppressMessages({library(shiny); library(bslib); library(shinyWidgets)})
suppressMessages(source("global.R"))

ok  <- TRUE
say <- function(p, m) { cat(if (p) "PASS  " else "FAIL  ", m, "\n", sep = ""); if (!p) ok <<- FALSE }

# A GeoPackage with two layers, 3 + 2 features.
gp <- file.path(tempdir(), paste0("multi_", as.integer(runif(1, 1e5, 9e5)), ".gpkg"))
a  <- sf::st_as_sf(data.frame(id = 1:3, x = 1:3, y = 1:3), coords = c("x", "y"), crs = 4326)
b  <- sf::st_as_sf(data.frame(id = 1:2, x = 4:5, y = 4:5), coords = c("x", "y"), crs = 4326)
suppressMessages({
  sf::st_write(a, gp, layer = "roads",  quiet = TRUE, delete_dsn = TRUE)
  sf::st_write(b, gp, layer = "rivers", quiet = TRUE, append = TRUE)
})
say(nrow(sf::st_layers(gp)$name |> as.data.frame()) == 2 ||
    length(sf::st_layers(gp)$name) == 2, "fixture: the file really has two layers")

# ---- 1. CONTROL: the old call loses data ------------------------------------
old <- suppressWarnings(sf::st_read(gp, quiet = TRUE))
say(nrow(old) == 3,
    sprintf("CONTROL: plain st_read() returns only the first layer (%d of 5 features)",
            nrow(old)))

# ---- 2. The fix reads every layer -------------------------------------------
v <- ea_read_vector(gp, basename(gp))
say(length(v) == 2, sprintf("ea_read_vector() returns both layers (%d)", length(v)))
say(sum(vapply(v, nrow, integer(1))) == 5,
    sprintf("no features are lost (%d of 5)", sum(vapply(v, nrow, integer(1)))))
say(all(grepl(":", names(v), fixed = TRUE)),
    paste0("each layer is named <file>:<layer> - ", paste(names(v), collapse = ", ")))
say(any(grepl(":roads$", names(v))) && any(grepl(":rivers$", names(v))),
    "and named after the layers themselves, not layer1/layer2")

# ---- 3. A single-layer file still behaves normally --------------------------
one <- file.path(tempdir(), paste0("one_", as.integer(runif(1, 1e5, 9e5)), ".gpkg"))
suppressMessages(sf::st_write(a, one, layer = "only", quiet = TRUE, delete_dsn = TRUE))
v1 <- ea_read_vector(one, basename(one))
say(length(v1) == 1, "a single-layer file returns one entry")
say(identical(names(v1), basename(one)),
    "...named after the file, with no layer suffix to explain")
say(nrow(v1[[1]]) == 3, "and all of its features")

# ---- 4. The call sites use it -----------------------------------------------
s <- paste(readLines("server.R", warn = FALSE), collapse = "\n")
say(grepl("ea_read_vector(fpath, fname)", s, fixed = TRUE),
    "the upload path reads every layer")
say(!grepl("vec <- sf::st_read(fpath, quiet = TRUE)", s, fixed = TRUE),
    "CONTROL: the single-layer-only upload call is gone")
say(grepl('sub("^[^:]*:", "", name)', s, fixed = TRUE),
    "reopening a project restores the SAME layer, not the first")

cat(if (ok) "\nVECTOR LAYER CHECK: PASS\n" else "\nVECTOR LAYER CHECK: FAIL\n")
quit(status = if (ok) 0L else 1L)
