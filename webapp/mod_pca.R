# ==========================================================================
# MODULE: PCA, Factor Analysis & Multidimensional Scaling
# pcaCanvasUI / pcaToolsUI / pcaServer
# ==========================================================================

pcaToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Dimension Reduction", class = "text-uppercase text-muted small mb-2"),
    accordion(
      open = "pca_mode",
      accordion_panel("Method & Variables", value = "pca_mode", icon = icon("circle-nodes"),
        selectInput(ns("mode"), "Method", width = "100%",
          choices = c("Principal Component Analysis (PCA)" = "pca",
                      "Factor Analysis (FA)"              = "fa",
                      "Multidimensional Scaling (MDS)"    = "mds")),
        uiOutput(ns("var_ui")),
        checkboxInput(ns("scale_vars"), "Scale variables (recommended)", value = TRUE)
      ),
      accordion_panel("PCA / MDS Options", value = "pca_opts", icon = icon("sliders"),
        numericInput(ns("n_comp"), "Components / factors / dimensions",
                     value = 2, min = 2, max = 20, width = "100%"),
        conditionalPanel("input.mode == 'fa'", ns = ns,
          selectInput(ns("fa_rotation"), "Rotation", width = "100%",
            choices = c("varimax", "promax", "none")),
          selectInput(ns("fa_method"), "Factor method", width = "100%",
            choices = c("Maximum Likelihood" = "mle", "Principal Axis" = "pa"))
        ),
        conditionalPanel("input.mode == 'mds'", ns = ns,
          selectInput(ns("mds_dist"), "Distance metric", width = "100%",
            choices = c("euclidean", "manhattan", "maximum", "canberra"))
        ),
        conditionalPanel("input.mode == 'pca'", ns = ns,
          numericInput(ns("pc_x"), "X-axis PC", value = 1, min = 1, width = "100%"),
          numericInput(ns("pc_y"), "Y-axis PC", value = 2, min = 1, width = "100%"),
          uiOutput(ns("color_ui"))
        )
      ),
      accordion_panel("Export", value = "pca_exp", icon = icon("download"),
        downloadButton(ns("dl_scores"),   "Scores CSV",   class = "btn-sm btn-success w-100"),
        tags$br(), tags$br(),
        downloadButton(ns("dl_loadings"), "Loadings CSV", class = "btn-sm btn-outline-success w-100")
      )
    ),
    actionButton(ns("run_pca"), "Run Analysis",
      class = "btn-success w-100 mt-2", icon = icon("play"))
  )
}

pcaCanvasUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Main Plot",     plotOutput(ns("main_plot"),     height = "500px")),
    nav_panel("Scree / Var",   plotOutput(ns("scree_plot"),    height = "400px")),
    nav_panel("Loadings",      plotOutput(ns("loadings_plot"), height = "500px")),
    nav_panel("Summary Table", DTOutput(ns("summary_tbl"),     height = "500px"))
  )
}

pcaServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    fit_r <- reactiveVal(NULL)

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    num_cols <- reactive({
      df <- active_data(); req(!is.null(df))
      names(df)[sapply(df, is.numeric)]
    })

    output$var_ui <- renderUI({
      nms <- num_cols()
      if (length(nms) < 2)
        return(tags$p(class = "small text-warning", "Need ≥ 2 numeric columns."))
      selectInput(ns("vars"), "Variables", choices = nms, selected = nms,
                  multiple = TRUE, width = "100%")
    })

    output$color_ui <- renderUI({
      df <- active_data(); req(!is.null(df))
      cat_cols <- c("(none)", names(df)[sapply(df, function(x) is.factor(x) || is.character(x))])
      selectInput(ns("color_by"), "Color points by", choices = cat_cols, width = "100%")
    })

    observeEvent(input$run_pca, {
      df   <- active_data(); req(!is.null(df))
      vars <- input$vars;    req(isTruthy(vars), length(vars) >= 2)
      nd   <- df[, vars, drop = FALSE]
      nd   <- nd[, sapply(nd, is.numeric), drop = FALSE]
      req(ncol(nd) >= 2)
      nd_complete <- nd[complete.cases(nd), ]
      req(nrow(nd_complete) >= 3)

      sc   <- isTRUE(input$scale_vars)
      mode <- input$mode %||% "pca"
      k    <- max(2L, min(as.integer(input$n_comp %||% 2L), ncol(nd_complete) - 1L))

      result <- tryCatch({
        switch(mode,
          pca = {
            fit <- prcomp(nd_complete, scale. = sc, center = TRUE)
            list(mode = "pca", fit = fit, data = nd_complete, k = k,
                 var_pct = 100 * fit$sdev^2 / sum(fit$sdev^2))
          },
          fa = {
            rot <- input$fa_rotation %||% "varimax"
            meth <- input$fa_method %||% "mle"
            if (meth == "pa") {
              # Principal axis via prcomp + rotation proxy
              fit <- prcomp(nd_complete, scale. = sc, center = TRUE)
              list(mode = "fa_pca_proxy", fit = fit, data = nd_complete, k = k,
                   var_pct = 100 * fit$sdev^2 / sum(fit$sdev^2), rotation = rot)
            } else {
              fa_fit <- tryCatch(
                factanal(nd_complete, factors = k, rotation = rot, scores = "regression"),
                error = function(e) stop(paste("factanal:", e$message))
              )
              list(mode = "fa", fit = fa_fit, data = nd_complete, k = k)
            }
          },
          mds = {
            dm   <- dist(scale(nd_complete), method = input$mds_dist %||% "euclidean")
            fit  <- cmdscale(dm, k = k, eig = TRUE)
            list(mode = "mds", fit = fit, data = nd_complete, k = k,
                 labs = rownames(nd_complete))
          }
        )
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error", duration = 10)
        NULL
      })

      fit_r(result)
      if (!is.null(result)) showNotification("Analysis complete.", type = "message")
    })

    output$main_plot <- renderPlot({
      res <- fit_r(); req(!is.null(res))
      df  <- active_data()

      if (res$mode == "pca") {
        pcx <- max(1L, min(as.integer(input$pc_x %||% 1L), ncol(res$fit$x)))
        pcy <- max(1L, min(as.integer(input$pc_y %||% 2L), ncol(res$fit$x)))
        scores <- as.data.frame(res$fit$x)
        cx <- input$color_by %||% "(none)"
        col_vec <- if (cx != "(none)" && cx %in% names(df)) {
          g <- df[[cx]][complete.cases(res$data)]
          g <- as.factor(g)
          palette.colors(nlevels(g), palette = "Set2")[g]
        } else "#2e7d3288"
        plot(scores[, pcx], scores[, pcy],
             xlab = sprintf("PC%d (%.1f%%)", pcx, res$var_pct[pcx]),
             ylab = sprintf("PC%d (%.1f%%)", pcy, res$var_pct[pcy]),
             main = "PCA Score Plot", pch = 16, col = col_vec)
        abline(h = 0, v = 0, col = "grey70", lty = 2)
        # Add loading arrows (biplot overlay)
        ld <- res$fit$rotation[, c(pcx, pcy)]
        sc_range <- max(abs(scores[, c(pcx, pcy)]))
        ld_scale <- sc_range * 0.7 / max(abs(ld))
        arrows(0, 0, ld[, 1] * ld_scale, ld[, 2] * ld_scale,
               col = "#c62828", length = 0.08, lwd = 1.5)
        text(ld[, 1] * ld_scale * 1.12, ld[, 2] * ld_scale * 1.12,
             rownames(ld), col = "#c62828", cex = 0.75)
        if (cx != "(none)" && cx %in% names(df)) {
          g <- as.factor(df[[cx]][complete.cases(res$data)])
          legend("topright", legend = levels(g),
                 col = palette.colors(nlevels(g), "Set2"),
                 pch = 16, bty = "n", cex = 0.8)
        }

      } else if (res$mode %in% c("fa", "fa_pca_proxy")) {
        if (res$mode == "fa") {
          ld <- loadings(res$fit)[, seq_len(min(2, res$k)), drop = FALSE]
        } else {
          ld <- res$fit$rotation[, seq_len(min(2, res$k)), drop = FALSE]
        }
        barplot(t(ld), beside = TRUE, col = c("#2e7d32","#81c784","#4caf50"),
                las = 2, main = "Factor Loadings (first 2 factors)",
                legend.text = paste("F", seq_len(min(2, res$k))),
                args.legend = list(x = "topright", bty = "n", cex = 0.8))
        abline(h = c(-0.3, 0.3), col = "grey50", lty = 2)

      } else if (res$mode == "mds") {
        pts <- res$fit$points
        plot(pts[, 1], pts[, 2], pch = 16, col = "#2e7d3288",
             xlab = "Dim 1", ylab = "Dim 2", main = "MDS Configuration")
        if (!is.null(rownames(pts)))
          text(pts[, 1], pts[, 2], labels = rownames(pts), pos = 3, cex = 0.7)
        abline(h = 0, v = 0, col = "grey70", lty = 2)
      }
    })

    output$scree_plot <- renderPlot({
      res <- fit_r(); req(!is.null(res))
      if (res$mode %in% c("pca", "fa_pca_proxy")) {
        vp  <- res$var_pct
        cvp <- cumsum(vp)
        nshow <- min(length(vp), 15)
        barplot(vp[seq_len(nshow)], col = "#4caf5099", border = "#2e7d32",
                names.arg = paste0("PC", seq_len(nshow)),
                xlab = "Component", ylab = "Variance Explained (%)",
                main = "Scree Plot", ylim = c(0, max(vp) * 1.1))
        lines(seq_len(nshow), cvp[seq_len(nshow)], type = "b",
              col = "#c62828", pch = 16, lwd = 2)
        axis(4, at = seq(0, 100, 20), labels = paste0(seq(0, 100, 20), "%"), col.axis = "#c62828")
        legend("topright", c("Variance %", "Cumulative %"),
               col = c("#4caf50", "#c62828"), pch = c(15, 16), bty = "n", cex = 0.8)
      } else if (res$mode == "mds") {
        eig <- res$fit$eig
        if (!is.null(eig)) {
          nshow <- min(length(eig), 15)
          barplot(eig[seq_len(nshow)], col = "#4caf5099", border = "#2e7d32",
                  names.arg = paste0("Dim", seq_len(nshow)),
                  main = "MDS Eigenvalues", xlab = "Dimension", ylab = "Eigenvalue")
          abline(h = 0, col = "grey50", lty = 2)
        }
      } else {
        plot.new(); text(0.5, 0.5, "Scree not available for FA (mle).", cex = 1.2, col = "grey50")
      }
    })

    output$loadings_plot <- renderPlot({
      res <- fit_r(); req(!is.null(res))
      if (res$mode %in% c("pca", "fa_pca_proxy")) {
        ld <- res$fit$rotation[, seq_len(min(res$k, ncol(res$fit$rotation))), drop = FALSE]
      } else if (res$mode == "fa") {
        ld <- loadings(res$fit)[,, drop = FALSE]
      } else {
        plot.new(); text(0.5, 0.5, "Loadings not available for MDS.", cex = 1.2, col = "grey50"); return()
      }
      n <- ncol(ld); p <- nrow(ld)
      df_long <- data.frame(
        Var   = factor(rep(rownames(ld), n), levels = rownames(ld)),
        Comp  = factor(rep(colnames(ld), each = p), levels = colnames(ld)),
        value = as.vector(ld)
      )
      ggplot(df_long, aes(x = Var, y = Comp, fill = value)) +
        geom_tile(color = "white") +
        geom_text(aes(label = sprintf("%.2f", value)), size = 3) +
        scale_fill_gradient2(low = "#d73027", mid = "white", high = "#1a9850",
                             midpoint = 0, limits = c(-1, 1), name = "Loading") +
        labs(title = "Component Loadings Heatmap", x = NULL, y = NULL) +
        theme_minimal(base_size = 11) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1), panel.grid = element_blank())
    })

    output$summary_tbl <- renderDT({
      res <- fit_r(); req(!is.null(res))
      if (res$mode %in% c("pca", "fa_pca_proxy")) {
        vp  <- res$var_pct
        nshow <- min(length(vp), 20)
        df <- data.frame(
          Component = paste0("PC", seq_len(nshow)),
          `Std Dev` = round(res$fit$sdev[seq_len(nshow)], 4),
          `Variance %` = round(vp[seq_len(nshow)], 2),
          `Cumulative %` = round(cumsum(vp)[seq_len(nshow)], 2),
          check.names = FALSE
        )
      } else if (res$mode == "fa") {
        ld <- loadings(res$fit)[,, drop = FALSE]
        df <- as.data.frame(round(ld[,], 4))
        df <- cbind(Variable = rownames(df), df)
        rownames(df) <- NULL
      } else {
        pts <- res$fit$points
        df <- data.frame(Obs = seq_len(nrow(pts)), round(pts, 4))
        colnames(df)[-1] <- paste0("Dim", seq_len(ncol(pts)))
      }
      datatable(df, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 20))
    })

    output$dl_scores <- downloadHandler(
      filename = function() paste0(input$mode %||% "pca", "_scores.csv"),
      content  = function(f) {
        res <- fit_r(); req(!is.null(res))
        if (res$mode %in% c("pca","fa_pca_proxy"))      write.csv(as.data.frame(res$fit$x), f)
        else if (res$mode == "fa" && !is.null(res$fit$scores)) write.csv(as.data.frame(res$fit$scores), f)
        else write.csv(as.data.frame(res$fit$points), f)
      }
    )
    output$dl_loadings <- downloadHandler(
      filename = function() paste0(input$mode %||% "pca", "_loadings.csv"),
      content  = function(f) {
        res <- fit_r(); req(!is.null(res))
        if (res$mode %in% c("pca","fa_pca_proxy")) write.csv(as.data.frame(res$fit$rotation), f)
        else if (res$mode == "fa") write.csv(as.data.frame(loadings(res$fit)[,]), f)
        else write.csv(data.frame(), f)
      }
    )

    list(
      context = reactive({
        res <- fit_r()
        if (is.null(res)) return("PCA/FA/MDS: no analysis run yet.")
        paste0("Dimension Reduction | Method: ", res$mode, " | k=", res$k,
               if (res$mode %in% c("pca","fa_pca_proxy"))
                 sprintf(" | PC1=%.1f%%, PC2=%.1f%%", res$var_pct[1], res$var_pct[2])
               else "")
      }),
      plot = function() {
        res <- isolate(fit_r()); if (is.null(res)) return(invisible())
        if (res$mode %in% c("pca","fa_pca_proxy")) {
          biplot(res$fit, main = "PCA Biplot", cex = 0.7)
        }
      }
    )
  })
}
