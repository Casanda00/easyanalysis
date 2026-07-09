# ==========================================================================
# MODULE: Clustering Analysis  (canvas + tools contract)
# clusteringToolsUI / clusteringCanvasUI / clusteringServer(id, dataset_pool, active_dataset)
# K-Means / Hierarchical (+ Gower/PAM for mixed data); multiple diagnostic views.
# ==========================================================================

clusteringToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6(class = "text-uppercase text-muted small", "Clustering Controls"),
    markdown("**1. Data Preparation**"),
    checkboxInput(ns("scale_data"), "Standardize Numeric Data (Z-Score)", value = TRUE),
    selectInput(ns("vars"), "Variables to Cluster (Numeric & Categorical):", choices = NULL, multiple = TRUE),
    markdown("*Mixed numeric + categorical variables will use Gower distance with PAM clustering.*"),
    hr(),
    markdown("**2. Algorithm Selection**"),
    selectInput(ns("method"), "Clustering Method:", choices = c("K-Means", "Hierarchical"), selected = "K-Means"),
    conditionalPanel(
      condition = "input.method == 'Hierarchical'", ns = ns,
      selectInput(ns("hclust_dist"), "Distance Metric:", choices = c("euclidean", "manhattan", "pearson"), selected = "euclidean"),
      selectInput(ns("hclust_link"), "Linkage Method:", choices = c("complete", "average", "single", "ward.D2"), selected = "ward.D2")
    ),
    hr(),
    markdown("**3. Diagnostic View**"),
    selectInput(ns("view"), "Select Display:",
      choices = c("1. Optimal k (Elbow Method)", "2. Optimal k (Silhouette Method)",
                  "3. Cluster Map (PCA/Dendrogram)", "4. Custom Scatter Plot",
                  "5. Silhouette Profile", "6. Phylogenetic Tree (ape)"),
      selected = "3. Cluster Map (PCA/Dendrogram)"),
    conditionalPanel(
      condition = "['3. Cluster Map (PCA/Dendrogram)','4. Custom Scatter Plot','5. Silhouette Profile','6. Phylogenetic Tree (ape)'].indexOf(input.view) > -1", ns = ns,
      sliderInput(ns("k"), "Number of Clusters (k):", min = 2, max = 10, value = 3, step = 1)
    ),
    conditionalPanel(
      condition = "input.view == '4. Custom Scatter Plot'", ns = ns,
      selectInput(ns("scatter_x"), "X-Axis Variable:", choices = NULL),
      selectInput(ns("scatter_y"), "Y-Axis Variable:", choices = NULL)
    )
  )
}

clusteringCanvasUI <- function(id) {
  ns <- NS(id)
  div(
    card(
      card_header(class = "d-flex justify-content-between align-items-center bg-light", "Visual Diagnostics",
                  downloadButton(ns("download_plot"), "Download Plot", class = "btn-sm btn-outline-success")),
      div(style = "padding: 10px;", uiOutput(ns("explanation"))),
      div(style = "height: 500px; padding: 10px;", plotOutput(ns("main_plot"), height = "480px"))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header(class = "d-flex justify-content-between align-items-center bg-light",
          "Cluster Profiles (Raw Means)",
          downloadButton(ns("dl_profiles"), "CSV", class = "btn-sm btn-outline-secondary")),
        div(style = "overflow-y: auto; height: 300px; padding: 5px;", verbatimTextOutput(ns("summary")))
      ),
      card(
        card_header(class = "bg-light", "Cluster Assignments"),
        div(style = "overflow-y: auto; height: 300px; padding: 5px;", verbatimTextOutput(ns("assignments")))
      )
    )
  )
}

clusteringServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset()
      if (is.null(ds)) return(NULL)
      dataset_pool[[ds]]
    })

    observe({
      df <- active_data()
      req(df)
      all_cols <- names(df)
      num_cols <- names(df)[sapply(df, is.numeric)]
      updateSelectInput(session, "vars", choices = all_cols, selected = if (isTruthy(isolate(input$vars))) isolate(input$vars) else num_cols)
      curr_x <- if (isTruthy(isolate(input$scatter_x)) && isolate(input$scatter_x) %in% num_cols) isolate(input$scatter_x) else if (length(num_cols) > 0) num_cols[1] else NULL
      curr_y <- if (isTruthy(isolate(input$scatter_y)) && isolate(input$scatter_y) %in% num_cols) isolate(input$scatter_y) else if (length(num_cols) > 1) num_cols[2] else curr_x
      updateSelectInput(session, "scatter_x", choices = num_cols, selected = curr_x)
      updateSelectInput(session, "scatter_y", choices = num_cols, selected = curr_y)
    })

    is_mixed <- reactive({
      if (is.null(active_data()) || length(input$vars) < 2) return(FALSE)
      df <- active_data()[, input$vars, drop = FALSE]
      any(!sapply(df, is.numeric))
    })

    prepared_data <- reactive({
      if (is.null(active_data()) || length(input$vars) < 2) return(NULL)
      df <- active_data()[, input$vars, drop = FALSE]
      df <- df[complete.cases(df), , drop = FALSE]
      if (nrow(df) < 3) return(NULL)
      has_cat <- any(!sapply(df, is.numeric))
      if (has_cat) {
        for (col in names(df)) if (is.character(df[[col]])) df[[col]] <- as.factor(df[[col]])
        if (input$scale_data) for (col in names(df)) if (is.numeric(df[[col]])) df[[col]] <- as.numeric(scale(df[[col]]))
        return(df)
      } else {
        if (input$scale_data) df <- scale(df)
        return(as.data.frame(df))
      }
    })

    get_clusters <- reactive({
      req(input$k)
      df <- prepared_data()
      req(df)
      if (is_mixed()) {
        d <- cluster::daisy(df, metric = "gower")
        if (input$method == "K-Means") {
          pam_result <- cluster::pam(d, k = input$k)
          return(list(obj = pam_result, vector = pam_result$clustering, dist = d, is_pam = TRUE))
        } else {
          hc <- hclust(d, method = input$hclust_link)
          return(list(obj = hc, vector = cutree(hc, k = input$k), dist = d, is_pam = FALSE))
        }
      } else {
        if (input$method == "K-Means") {
          set.seed(123)
          km <- kmeans(df, centers = input$k, nstart = 25)
          return(list(obj = km, vector = km$cluster, is_pam = FALSE))
        } else {
          d <- get_dist(df, method = input$hclust_dist)
          hc <- hclust(d, method = input$hclust_link)
          return(list(obj = hc, vector = cutree(hc, k = input$k), is_pam = FALSE))
        }
      }
    })

    output$explanation <- renderUI({
      req(input$view)
      switch(input$view,
        "1. Optimal k (Elbow Method)" = markdown("*The **Elbow Method** plots within-cluster sum of squares (WSS). Look for the 'bend'.*"),
        "2. Optimal k (Silhouette Method)" = markdown("*The **Silhouette Method** measures cluster quality. Highest peak = optimal k.*"),
        "3. Cluster Map (PCA/Dendrogram)" = markdown("*K-Means projects groups via PCA; Hierarchical maps the merge lineage.*"),
        "4. Custom Scatter Plot" = markdown("*Maps cluster assignments onto raw, unscaled data.*"),
        "5. Silhouette Profile" = markdown("*How well each point fits its cluster. Near 1 is excellent; negative suggests a better neighbor.*"),
        "6. Phylogenetic Tree (ape)" = markdown("*Hierarchical clustering as an unrooted circular tree (requires `ape`).*"))
    })

    main_plot_fn <- function() {
      req(input$view)
      if (is.null(active_data())) return(show_placeholder("Awaiting dataset..."))
      if (length(input$vars) < 2) return(show_placeholder("Please select at least 2 variables to cluster."))
      df <- prepared_data()
      if (is.null(df)) return(show_placeholder("Awaiting valid data..."))
      mixed <- is_mixed()
      tryCatch({
        if (input$view == "1. Optimal k (Elbow Method)") {
          if (mixed) { d <- cluster::daisy(df, metric = "gower"); p <- fviz_nbclust(d, FUNcluster = cluster::pam, method = "wss") }
          else if (input$method == "K-Means") p <- fviz_nbclust(df, FUNcluster = kmeans, method = "wss")
          else p <- fviz_nbclust(df, FUNcluster = factoextra::hcut, method = "wss", hc_method = input$hclust_link, hc_metric = input$hclust_dist)
          print(p + theme_minimal(base_size = 14) + labs(title = "Elbow Method"))
        } else if (input$view == "2. Optimal k (Silhouette Method)") {
          if (mixed) { d <- cluster::daisy(df, metric = "gower"); p <- fviz_nbclust(d, FUNcluster = cluster::pam, method = "silhouette") }
          else if (input$method == "K-Means") p <- fviz_nbclust(df, FUNcluster = kmeans, method = "silhouette")
          else p <- fviz_nbclust(df, FUNcluster = factoextra::hcut, method = "silhouette", hc_method = input$hclust_link, hc_metric = input$hclust_dist)
          print(p + theme_minimal(base_size = 14) + labs(title = "Silhouette Method"))
        } else if (input$view == "3. Cluster Map (PCA/Dendrogram)") {
          c_data <- get_clusters()
          if (isTRUE(c_data$is_pam)) {
            print(fviz_cluster(c_data$obj, ellipse.type = "convex", geom = "point", ggtheme = theme_minimal(base_size = 14), main = paste("PAM Cluster Map (k =", input$k, ") — Gower")))
          } else if (input$method == "K-Means") {
            print(fviz_cluster(c_data$obj, data = df, ellipse.type = "convex", geom = "point", repel = TRUE, ggtheme = theme_minimal(base_size = 14), main = paste("K-Means Map (k =", input$k, ")")))
          } else {
            print(fviz_dend(c_data$obj, k = input$k, cex = 0.9, lwd = 0.4, rect = TRUE, rect_fill = TRUE, rect_border = "jco", color_labels_by_k = TRUE, ggtheme = theme_classic(base_size = 14), main = "Hierarchical Dendrogram"))
          }
        } else if (input$view == "4. Custom Scatter Plot") {
          req(input$scatter_x, input$scatter_y)
          raw_full <- active_data()
          raw_df <- raw_full[complete.cases(raw_full[, input$vars]), input$vars, drop = FALSE]
          c_data <- get_clusters()
          raw_df$Cluster <- as.factor(c_data$vector)
          print(ggplot(raw_df, aes_string(x = input$scatter_x, y = input$scatter_y, col = "Cluster")) +
                  geom_point(size = 3, alpha = 0.8) + theme_minimal(base_size = 14) +
                  labs(title = paste("Clusters:", input$scatter_x, "vs", input$scatter_y)))
        } else if (input$view == "5. Silhouette Profile") {
          c_data <- get_clusters()
          dist_matrix <- if (mixed) cluster::daisy(df, metric = "gower") else if (input$method == "Hierarchical") get_dist(df, method = input$hclust_dist) else get_dist(df, method = "euclidean")
          sil <- silhouette(c_data$vector, dist_matrix)
          print(fviz_silhouette(sil, print.summary = FALSE, ggtheme = theme_minimal(base_size = 14)) + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank()))
        } else if (input$view == "6. Phylogenetic Tree (ape)") {
          if (input$method == "K-Means") { show_placeholder("Phylogenetic trees are only available for Hierarchical Clustering.") }
          else {
            c_data <- get_clusters()
            phy <- ape::as.phylo(c_data$obj)
            colors <- if (input$k <= 8) palette()[1:input$k] else rainbow(input$k)
            old_par <- par(mar = c(1, 1, 3, 1)); on.exit(par(old_par))
            plot(phy, type = "fan", tip.color = colors[c_data$vector], cex = 0.8, font = 2, no.margin = TRUE, main = paste("Circular Phylogenetic Tree (k =", input$k, ")"))
          }
        }
      }, error = function(e) show_placeholder(paste("Plot Error:", e$message)))
    }

    output$main_plot <- renderPlot({ main_plot_fn() })

    output$download_plot <- downloadHandler(
      filename = function() { paste0("clustering_", Sys.Date(), ".png") },
      content = function(file) { png(file, width = 800, height = 600); main_plot_fn(); dev.off() }
    )

    output$summary <- renderPrint({
      if (is.null(active_data())) return(cat("Awaiting dataset..."))
      if (length(input$vars) < 2) return(cat("Please select at least 2 variables."))
      df_raw <- active_data()
      df_raw <- df_raw[complete.cases(df_raw[, input$vars]), input$vars, drop = FALSE]
      c_data <- get_clusters(); req(c_data)
      cat("Cluster Profiles (Raw Data):\n\n")
      num_cols <- names(df_raw)[sapply(df_raw, is.numeric)]
      cat_cols <- names(df_raw)[!sapply(df_raw, is.numeric)]
      if (length(num_cols) > 0) {
        cat("--- Numeric Variables (Mean by Cluster) ---\n")
        print(aggregate(df_raw[, num_cols, drop = FALSE], by = list(Cluster = c_data$vector), FUN = mean))
      }
      if (length(cat_cols) > 0) {
        cat("\n--- Categorical Variables (Mode by Cluster) ---\n")
        get_mode <- function(x) { ux <- unique(x); ux[which.max(tabulate(match(x, ux)))] }
        for (col in cat_cols) { cat("\n", col, ":\n"); print(tapply(df_raw[[col]], c_data$vector, get_mode)) }
      }
    })

    output$assignments <- renderPrint({
      if (is.null(active_data())) return(cat("Awaiting dataset..."))
      if (length(input$vars) < 2) return(cat("Please select at least 2 variables."))
      c_data <- get_clusters(); req(c_data)
      print(data.frame(Cluster = c_data$vector))
    })

    output$dl_profiles <- downloadHandler(
      filename = function() paste0("cluster_profiles_", Sys.Date(), ".csv"),
      content  = function(file) {
        req(length(input$vars) >= 2, !is.null(active_data()))
        df_raw  <- active_data()
        df_raw  <- df_raw[complete.cases(df_raw[, input$vars]), input$vars, drop = FALSE]
        c_data  <- get_clusters(); req(c_data)
        num_cols <- names(df_raw)[sapply(df_raw, is.numeric)]
        if (length(num_cols) > 0) {
          out <- aggregate(df_raw[, num_cols, drop = FALSE],
                           by = list(Cluster = c_data$vector), FUN = mean)
        } else {
          out <- data.frame(Cluster = sort(unique(c_data$vector)))
        }
        write.csv(out, file, row.names = FALSE)
      }
    )

    # Context (+ plot) for the AI Co-Pilot.
    list(
      context = reactive({
        if (is.null(active_data())) return("Clustering — no dataset loaded.")
        if (length(input$vars) < 2) return("Clustering — fewer than 2 variables selected.")
        sizes <- tryCatch({
          if (grepl("Optimal k", input$view)) "(choosing k via diagnostic plot)"
          else paste("cluster sizes:", paste(table(get_clusters()$vector), collapse = ", "))
        }, error = function(e) "(not computed)")
        paste0("Clustering. Method: ", input$method, " ; k = ", input$k, " ; view: ", input$view,
               " ; variables: ", paste(input$vars, collapse = ", "), " ; ", sizes)
      }),
      plot = function() main_plot_fn()
    )
  })
}
