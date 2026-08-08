# tools/precommit.R -- refuse to commit a broken tree
#
# WHY THIS EXISTS
# ---------------
# v0.11.1 shipped an EMPTY global.R. The app could not start at all. The bug was
# a truncate-before-read in a release script, but the reason it reached a commit
# is the part worth fixing: every check that run passed BEFORE the release
# script, and the script itself reported success, because writing an empty file
# succeeds.
#
# Documenting that (gotcha 34) does not stop it. This does: the checks run at
# COMMIT time, after every script has finished, on exactly the content being
# committed.
#
# Deliberately FAST -- a slow hook gets bypassed, and a bypassed hook is worse
# than none. It parses staged R files and checks a few invariants; it does not
# start the app or run the test suite.
#
# INSTALL (once per clone):
#     git config core.hooksPath .githooks
#
# BYPASS, when you genuinely mean to:
#     git commit --no-verify

args   <- commandArgs(TRUE)
staged <- if (length(args)) args else character(0)
fail   <- character(0)
note   <- function(x) fail <<- c(fail, x)

if (!length(staged)) {
  cat("precommit: nothing staged.\n"); quit(status = 0L)
}

# ---- 1. Nothing being committed may be EMPTY -------------------------------
# This is the check that would have caught the global.R truncation outright.
for (f in staged) {
  if (!file.exists(f)) next                       # deletions are fine
  if (file.info(f)$size == 0) note(sprintf("%s is EMPTY (0 bytes)", f))
}

# ---- 2. Every staged R file must PARSE -------------------------------------
# Catches truncation, a stray quote inside HTML() (gotcha 1), and any half-
# applied edit. Parsing is the authority; grepping is not.
for (f in staged[grepl("\\.R$", staged, ignore.case = TRUE)]) {
  if (!file.exists(f)) next
  e <- tryCatch({ parse(f); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(e)) note(sprintf("%s does not parse: %s", f, e))
}

# ---- 3. Invariants that must never be false --------------------------------
# Named explicitly rather than inferred, so a failure says what is wrong.
inv <- list(
  list(file = "global.R",  must = "APP_VERSION <- \"",
       why  = "global.R has lost its version -- it is the app loader"),
  list(file = "helpers.R", must = "ea_layer_fingerprint",
       why  = "helpers.R has lost the layer-link helpers")
)
for (i in inv) {
  if (!(i$file %in% staged)) next
  if (!file.exists(i$file)) next
  txt <- paste(readLines(i$file, warn = FALSE), collapse = "\n")
  if (!grepl(i$must, txt, fixed = TRUE)) note(sprintf("%s: %s", i$file, i$why))
}

# ---- 4. Files that must shrink only on purpose -----------------------------
# A file losing more than 60% of its size is nearly always an accident. Compared
# against HEAD, so a deliberate deletion still passes with --no-verify.
big_drop <- function(f) {
  if (!file.exists(f)) return(FALSE)
  old <- suppressWarnings(system2("git", c("show", paste0("HEAD:", f)),
                                  stdout = TRUE, stderr = FALSE))
  if (!length(old)) return(FALSE)
  o <- sum(nchar(old)); n <- file.info(f)$size
  o > 2000 && n < o * 0.4
}
for (f in staged) if (isTRUE(try(big_drop(f), silent = TRUE)))
  note(sprintf("%s lost more than 60%% of its content -- deliberate?", f))

if (length(fail)) {
  cat("\nCOMMIT BLOCKED -- the staged tree has problems:\n")
  for (m in fail) cat("  * ", m, "\n", sep = "")
  cat("\nFix them, or use `git commit --no-verify` if this is deliberate.\n")
  quit(status = 1L)
}
cat(sprintf("precommit: %d staged file(s) OK\n", length(staged)))
quit(status = 0L)
