# ==========================================================================
# serve_local.R — serve webapp_site/ WITH cross-origin isolation headers.
# --------------------------------------------------------------------------
# Run FROM THE Shiny_app FOLDER:
#   "C:\Program Files\R\R-4.5.3\bin\Rscript.exe" serve_local.R
#   -> http://localhost:8899
#
# WHY: plain httpuv::runStaticServer() does not send COOP/COEP, so the page is
# not cross-origin isolated -> no SharedArrayBuffer -> webR drops to its slower
# PostMessage channel ("nested R REPLs are not available"). Vercel sets the same
# two headers via vercel.json, so this makes local match production.
#
# IMPORTANT — use httpuv's staticPath, do NOT hand-roll the file serving.
# webR fetches its virtual filesystem LAZILY using HTTP Range/HEAD requests
# (fonts, cairo.so, libRlapack.so, package .so files). A naive handler that
# always returns 200 + the whole body breaks those lazy loads, which surfaces as
# "Failed to load .../NotoSans-Regular.ttf", "failed to load cairo DLL", or
# "LAPACK routines cannot be loaded". staticPath handles Range/HEAD/MIME
# correctly and still lets us attach the isolation headers.
# ==========================================================================

port <- 8899
root <- normalizePath("webapp_site", mustWork = TRUE)

iso_headers <- list(
  "Cross-Origin-Opener-Policy"   = "same-origin",
  "Cross-Origin-Embedder-Policy" = "require-corp",
  "Cache-Control"                = "no-cache"
)

cat(sprintf("Serving %s\n  -> http://localhost:%d  (cross-origin isolated)\n", root, port))
cat("Ctrl+C to stop.\n")

httpuv::runServer("127.0.0.1", port,
  list(
    staticPaths = list(
      "/" = httpuv::staticPath(root, indexhtml = TRUE, fallthrough = FALSE,
                               headers = iso_headers)
    ),
    call = function(req) {
      list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "Not found")
    }
  )
)
