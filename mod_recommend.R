# ==========================================================================
# MODULE: Analysis Recommender
# Rule-based engine + AI co-pilot elaboration (hybrid)
# recommendCanvasUI / recommendToolsUI / recommendServer
# ==========================================================================

# ---------- Dataset profiler ---------------------------------------------- #
.profile_ds <- function(df) {
  nms      <- names(df)
  num_nms  <- nms[sapply(df, is.numeric)]
  fct_nms  <- nms[sapply(df, function(x) is.factor(x) || is.character(x))]
  date_nms <- nms[sapply(df, function(x) inherits(x, c("Date","POSIXct","POSIXlt")))]

  n  <- nrow(df)
  p  <- ncol(df)
  missing_pct <- 100 * mean(is.na(df))

  # Normality p-values (Shapiro-Wilk, max 15 cols, max n=5000)
  norm_p <- setNames(rep(NA_real_, length(num_nms)), num_nms)
  for (v in head(num_nms, 15)) {
    x <- df[[v]][!is.na(df[[v]])]
    if (length(x) >= 3 && length(x) <= 5000)
      norm_p[[v]] <- tryCatch(shapiro.test(x)$p.value, error = function(e) NA)
  }

  bin_nms <- num_nms[sapply(num_nms, function(v) {
    x <- na.omit(df[[v]])
    length(unique(x)) == 2 && all(x %in% c(0, 1))
  })]

  count_nms <- setdiff(num_nms, bin_nms)
  count_nms <- count_nms[sapply(count_nms, function(v) {
    x <- na.omit(df[[v]])
    length(x) > 0 && all(x >= 0) && all(x == round(x)) && length(unique(x)) > 2
  })]

  fct_levels <- if (length(fct_nms) > 0)
    sapply(fct_nms, function(v) nlevels(as.factor(na.omit(df[[v]])))) else integer(0)

  two_lev_fct   <- fct_nms[fct_levels == 2]
  multi_lev_fct <- fct_nms[fct_levels >= 3]

  max_r <- NA_real_
  if (length(num_nms) >= 2) {
    cm <- tryCatch(cor(df[, num_nms, drop=FALSE], use = "pairwise.complete.obs"), error = function(e) NULL)
    if (!is.null(cm)) { diag(cm) <- NA; max_r <- max(abs(cm), na.rm = TRUE) }
  }

  pct_normal <- if (length(norm_p) > 0) mean(norm_p > 0.05, na.rm = TRUE) else NA

  group_like <- unique(c(fct_nms,
    num_nms[grepl("(?i)\\bid\\b|subject|plot|site|animal|patient|tree|block",
                   num_nms, perl = TRUE)]))

  time_like <- num_nms[grepl("(?i)time|duration|surv|days|months|years|follow",
                               num_nms, perl = TRUE)]

  list(n=n, p=p, missing_pct=missing_pct,
       num_nms=num_nms, fct_nms=fct_nms, date_nms=date_nms,
       bin_nms=bin_nms, count_nms=count_nms,
       n_num=length(num_nms), n_fct=length(fct_nms),
       fct_levels=fct_levels,
       two_lev_fct=two_lev_fct, multi_lev_fct=multi_lev_fct,
       has_date=length(date_nms) > 0, has_binary=length(bin_nms) > 0,
       has_counts=length(count_nms) > 0,
       norm_p=norm_p, pct_normal=pct_normal, max_r=max_r,
       group_like=group_like, time_like=time_like)
}

# ---------- Rule engine --------------------------------------------------- #
.gen_recs <- function(prof, purpose, y_var) {
  n  <- prof$n
  nn <- prof$n_num
  recs <- list()

  .add <- function(id, name, ico, priority, why, assump = list(),
                   nav = id, suggest_y = NULL, suggest_x = NULL) {
    recs[[length(recs) + 1]] <<- list(
      id=id, name=name, icon=ico, priority=priority,
      why=why, assump=assump, nav=nav,
      suggest_y=suggest_y, suggest_x=suggest_x
    )
  }
  .badge <- function(lbl, status) list(label=lbl, status=status)
  is_normal <- !is.na(prof$pct_normal) && prof$pct_normal > 0.5

  # 1. Descriptive Statistics — always
  .add("descriptive","Descriptive Statistics & Correlation","chart-bar","high",
    paste0("First step for any analysis. Dataset: <b>",n," rows × ",prof$p," columns</b> (",
           nn," numeric, ",prof$n_fct," categorical",
           if(prof$missing_pct>0) sprintf(", <b>%.1f%%</b> missing",prof$missing_pct) else "",
           ")."),
    list(.badge("Always applicable","pass"),
         if(prof$missing_pct>5) .badge(sprintf("%.1f%% missing — investigate",prof$missing_pct),"warn")
         else .badge("Missing data OK","pass")),
    suggest_x = head(prof$num_nms,5)
  )

  # 2. t-test / Mann-Whitney
  if (nn >= 1 && length(prof$two_lev_fct) >= 1) {
    .add("tests",
      if(is_normal)"Independent t-test" else "Mann-Whitney U Test",
      "not-equal", if(n>=20)"high" else "medium",
      paste0("2-level grouping variable <b>",prof$two_lev_fct[1],"</b> + numeric outcome detected. ",
             if(is_normal)"Distributions appear normal → parametric t-test."
             else "Non-normal distributions → Mann-Whitney U (non-parametric)."),
      list(.badge(sprintf("n=%d",n), if(n>=20)"pass" else "warn"),
           .badge(if(is_normal)"Normal ✓ → t-test" else "Non-normal → non-param",
                  if(is_normal)"pass" else "warn")),
      suggest_y = if(isTruthy(y_var)) y_var else head(setdiff(prof$num_nms,prof$bin_nms),1),
      suggest_x = prof$two_lev_fct[1]
    )
  }

  # 3. ANOVA / Kruskal-Wallis
  if (nn >= 1 && length(prof$multi_lev_fct) >= 1) {
    nlev <- prof$fct_levels[prof$multi_lev_fct[1]]
    .add("anova",
      if(is_normal)"One-Way ANOVA (+ Tukey)" else "Kruskal-Wallis Test",
      "layer-group", if(n>=30)"high" else "medium",
      paste0("<b>",prof$multi_lev_fct[1],"</b> has <b>",nlev," groups</b>. ",
             if(is_normal)"ANOVA tests whether group means differ; Tukey post-hoc available."
             else "Non-normal data → Kruskal-Wallis non-parametric alternative."),
      list(.badge(sprintf("n=%d",n),if(n>=30)"pass" else "warn"),
           .badge(paste0(nlev," groups"),if(nlev<=10)"pass" else "warn")),
      suggest_y = if(isTruthy(y_var)) y_var else head(setdiff(prof$num_nms,prof$bin_nms),1),
      suggest_x = prof$multi_lev_fct[1]
    )
  }

  # 4. Linear Regression
  if (nn >= 2) {
    y_sug <- if(isTruthy(y_var) && y_var %in% prof$num_nms && !y_var %in% prof$bin_nms) y_var
             else head(setdiff(prof$num_nms, c(prof$bin_nms, prof$count_nms)), 1)
    x_sug <- head(setdiff(prof$num_nms, c(y_sug, prof$bin_nms)), 5)
    has_mc <- !is.na(prof$max_r) && prof$max_r > 0.85
    .add("lm","Linear Regression","chart-line",
      if(n>=50 && nn>=2)"high" else "medium",
      paste0("<b>",nn," numeric predictors</b>, <b>n=",n,"</b>. ",
             "Standard approach for a continuous outcome. ",
             if(has_mc) "<b>High collinearity detected</b> — consider Ridge/Lasso option." else ""),
      list(.badge(sprintf("n=%d",n),if(n>=30)"pass" else "warn"),
           .badge(if(has_mc)"High collinearity → Ridge/Lasso" else "Collinearity OK",
                  if(has_mc)"warn" else "pass"),
           .badge("Check residual normality","info")),
      suggest_y = y_sug, suggest_x = x_sug
    )
  }

  # 5. Logistic Regression
  if (prof$has_binary) {
    bin_y <- prof$bin_nms[1]
    .add("logistic","Logistic Regression","toggle-on",
      if(n>=100)"high" else "medium",
      paste0("Binary (0/1) variable <b>",bin_y,"</b> detected. ",
             "Logistic regression models event probability. Rule of thumb: ≥10 events per predictor."),
      list(.badge(sprintf("n=%d",n),if(n>=50)"pass" else "warn"),
           .badge(paste0("Binary outcome: ",bin_y),"pass"),
           .badge("Verify 1=event, 0=non-event","info")),
      suggest_y=bin_y, suggest_x=head(setdiff(prof$num_nms,bin_y),5)
    )
  }

  # 6. Poisson
  if (prof$has_counts && nn >= 2) {
    cnt_y <- prof$count_nms[1]
    .add("lm","Poisson Regression (GLM)","hashtag","medium",
      paste0("Count variable <b>",cnt_y,"</b> (non-negative integers) detected. ",
             "In the Regression screen select <b>Poisson</b> type."),
      list(.badge("Count outcome detected","pass"),
           .badge("Check overdispersion after fit","info")),
      nav="lm", suggest_y=cnt_y, suggest_x=head(setdiff(prof$num_nms,cnt_y),4)
    )
  }

  # 7. PCA
  if (nn >= 4) {
    mc_txt <- if(!is.na(prof$max_r) && prof$max_r > 0.6)
      sprintf(" Max |r|=<b>%.2f</b> — variables are correlated, PCA will reduce redundancy.",prof$max_r)
    else ""
    .add("pca","PCA & Dimension Reduction","circle-nodes",
      if(nn>=6 && n>=30)"high" else "medium",
      paste0("<b>",nn," numeric variables</b> available.",mc_txt,
             " PCA reveals latent structure and removes redundant dimensions."),
      list(.badge(sprintf("%d numeric variables",nn),"pass"),
           .badge(if(n>=nn*3)"n adequate" else "Small n — interpret PC loadings carefully",
                  if(n>=nn*3)"pass" else "warn"),
           .badge("Standardise before running","info")),
      suggest_x=prof$num_nms
    )
  }

  # 8. Clustering
  if (nn >= 2 && n >= 20) {
    .add("clustering","Cluster Analysis","object-group",
      if(nn>=3 && n>=50)"high" else "medium",
      paste0("<b>n=",n,"</b> observations, <b>",nn," numeric features</b>. ",
             "K-Means and Hierarchical clustering can identify natural groupings."),
      list(.badge(sprintf("n=%d",n),"pass"),
           .badge(sprintf("%d features",nn),"pass"),
           .badge("Scale variables before clustering","info")),
      suggest_x=head(prof$num_nms,8)
    )
  }

  # 9. Random Forest
  if (nn >= 2 && n >= 30) {
    y_sug <- if(isTruthy(y_var)) y_var else head(prof$num_nms,1)
    .add("rf","Random Forest","tree",
      if(n>=100 && nn>=3)"high" else "medium",
      paste0("Handles regression & classification. <b>n=",n,"</b>, <b>",nn," predictors</b>. ",
             "Robust to outliers, non-linearity, and correlated predictors."),
      list(.badge(sprintf("n=%d",n),if(n>=100)"pass" else "warn"),
           .badge("No distributional assumptions","pass"),
           .badge("Feature importance built-in","pass")),
      suggest_y=y_sug, suggest_x=head(setdiff(prof$num_nms,y_sug),8)
    )
  }

  # 10. XGBoost
  if (nn >= 3 && n >= 50) {
    y_sug <- if(isTruthy(y_var)) y_var else head(prof$num_nms,1)
    .add("xgboost","XGBoost","bolt",
      if(n>=200 && nn>=4)"high" else "medium",
      paste0("Gradient boosting with <b>n=",n,"</b> and <b>",nn," features</b>. ",
             "Often outperforms Random Forest on structured/tabular data with complex interactions."),
      list(.badge(sprintf("n=%d",n),if(n>=200)"pass" else "warn"),
           .badge("Handles missing values","pass"),
           .badge("Tune nrounds + eta","info")),
      suggest_y=y_sug, suggest_x=head(setdiff(prof$num_nms,y_sug),8)
    )
  }

  # 11. Time Series
  if (prof$has_date || length(prof$time_like) > 0) {
    ts_col <- if(prof$has_date) prof$date_nms[1] else prof$time_like[1]
    .add("timeseries","Time Series & Forecasting","wave-square",
      if(prof$has_date)"high" else "medium",
      paste0(if(prof$has_date) paste0("Date column <b>",ts_col,"</b> detected. ")
             else paste0("Time-like column <b>",ts_col,"</b> found. "),
             "ARIMA/SARIMA, Holt-Winters, and decomposition available."),
      list(.badge(if(prof$has_date)"Date column found ✓" else "Possible time column","pass"),
           .badge("Observations must be equally spaced","info")),
      suggest_x=ts_col
    )
  }

  # 12. Survival Analysis
  if (prof$has_binary && length(prof$time_like) >= 1) {
    .add("survival","Survival Analysis","hourglass-half","high",
      paste0("Event indicator <b>",prof$bin_nms[1],"</b> + time variable <b>",
             prof$time_like[1],"</b> detected. ",
             "Kaplan-Meier, Cox PH, and log-rank test are available."),
      list(.badge("Binary event indicator ✓","pass"),
           .badge("Time-to-event variable ✓","pass"),
           .badge("Verify: 1=event, 0=censored","info")),
      suggest_y=prof$bin_nms[1], suggest_x=prof$time_like[1]
    )
  }

  # 13. LME
  if (length(prof$group_like) >= 1 && nn >= 2 && n >= 20) {
    .add("lme","Linear Mixed Effects","layer-group",
      if(n>=50)"medium" else "consider",
      paste0("Grouping variable <b>",prof$group_like[1],"</b> detected. ",
             "If observations are nested or repeated, LME accounts for within-group correlation."),
      list(.badge("Potential grouping variable found","info"),
           .badge("Use for repeated/hierarchical data","info"),
           .badge(sprintf("n=%d",n),if(n>=50)"pass" else "warn")),
      suggest_x=prof$group_like[1]
    )
  }

  # 14. SEM / Mediation
  if (nn >= 3 && n >= 50) {
    y_sug <- if(isTruthy(y_var)) y_var else head(prof$num_nms,1)
    .add("sem","SEM & Mediation Analysis","diagram-project",
      if(nn>=5 && n>=100)"medium" else "consider",
      paste0("<b>",nn," numeric variables</b> and <b>n=",n,"</b>. ",
             "Test whether a mediator M explains the X→Y relationship. ",
             "Full SEM with latent variables also available (requires lavaan)."),
      list(.badge(sprintf("n=%d",n),if(n>=100)"pass" else "warn"),
           .badge("Requires theoretical model","info")),
      suggest_y=y_sug
    )
  }

  # 15. Discriminant Analysis (LDA / QDA / LLDA)
  all_fcts <- c(prof$two_lev_fct, prof$multi_lev_fct)
  if (nn >= 2 && length(all_fcts) >= 1) {
    class_fct <- all_fcts[1]
    n_cls     <- prof$fct_levels[class_fct]
    .add("da","Discriminant Analysis (LDA / QDA / LLDA)","brain",
      if(nn>=4 && n>=50)"high" else "medium",
      paste0("Factor <b>",class_fct,"</b> (",n_cls," classes) can serve as the class outcome. ",
             "LDA finds linear boundaries between groups; LLDA (Linear Local DA) often ",
             "outperforms standard LDA on complex boundaries. QDA/RLDA available for non-equal covariances."),
      list(.badge(paste0(n_cls," classes: ",class_fct),"pass"),
           .badge(sprintf("%d numeric predictors",nn),"pass"),
           .badge("LLDA recommended for overlapping groups","info")),
      suggest_y=class_fct, suggest_x=head(prof$num_nms,6)
    )
  }

  # ---- Purpose-based suppression (hide clearly irrelevant analyses) ------- #
  suppress_ids <- switch(purpose %||% "explore",
    describe  = c("timeseries","survival","xgboost","dtree","svm","nnet_ml","sem","lme"),
    test      = c("timeseries","survival","xgboost","dtree","svm","nnet_ml","pca",
                  "clustering","sem","rf"),
    predict   = c("timeseries","survival","clustering","sem","tests","anova","descriptive"),
    classify  = c("timeseries","survival","sem","tests","anova","lm","pca"),
    explore   = c("timeseries","survival","xgboost","dtree","svm","nnet_ml","sem","lme"),
    relate    = c("timeseries","survival","xgboost","dtree","svm","nnet_ml","clustering"),
    forecast  = c("pca","clustering","rf","xgboost","dtree","svm","nnet_ml","sem",
                  "tests","anova","survival","da","logistic"),
    character(0)
  )
  if (length(suppress_ids) > 0)
    recs <- Filter(function(r) !r$id %in% suppress_ids, recs)

  # ---- Boost & sort ------------------------------------------------------- #
  boost_ids <- switch(purpose %||% "explore",
    describe  = c("descriptive"),
    test      = c("tests","anova","survival"),
    predict   = c("rf","xgboost","lm"),
    classify  = c("da","rf","xgboost","logistic","dtree"),
    explore   = c("descriptive","pca","clustering"),
    relate    = c("lm","pca","sem"),
    forecast  = c("timeseries"),
    character(0)
  )

  pri_ord <- c(high=1L, medium=2L, consider=3L)
  recs[order(sapply(recs, function(r) {
    (if (r$id %in% boost_ids) 0L else 10L) + pri_ord[[r$priority]]
  }))]
}

# ---------- Card renderer ------------------------------------------------- #
.rec_card_html <- function(rec, ns, idx) {
  col <- switch(rec$priority, high="#2e7d32", medium="#e65100", consider="#1565c0")
  badge_cls <- switch(rec$priority,
    high="bg-success", medium="bg-warning text-dark", consider="bg-info")
  badge_lbl <- switch(rec$priority,
    high="High Priority", medium="Recommended", consider="Consider")

  tags$div(
    class = "rec-card mb-3",
    style = paste0("border-left:4px solid ",col,
                   ";background:#fff;border-radius:6px;",
                   "box-shadow:0 1px 4px rgba(0,0,0,.08);padding:14px 16px;"),
    tags$div(class="d-flex align-items-center gap-2 mb-2",
      icon(rec$icon, style=paste0("color:",col,";font-size:1em;")),
      tags$strong(rec$name, style="font-size:14px;"),
      tags$span(class=paste("badge ms-auto", badge_cls), badge_lbl)
    ),
    tags$p(HTML(rec$why), class="small text-muted mb-2", style="line-height:1.5;"),
    if (length(rec$assump) > 0)
      tags$div(class="mb-2 d-flex flex-wrap gap-1",
        lapply(rec$assump, function(a) {
          cls <- switch(a$status,
            pass="bg-success", warn="bg-warning text-dark",
            fail="bg-danger",  info="bg-secondary")
          tags$span(class=paste("badge",cls), style="font-size:10px;", a$label)
        })
      ),
    tags$div(class="d-flex gap-2 mt-1",
      tags$button(
        class="btn btn-sm btn-success",
        style="font-size:12px;",
        onclick=sprintf(paste0(
          "Shiny.setInputValue('current_view','%s',{priority:'event'});",
          "Shiny.setInputValue('%s','%d',{priority:'event'});",
          "return false;"
        ), rec$nav, ns("goto_rec"), idx),
        HTML(paste0("Go to ", rec$name, " &#8594;"))
      ),
      tags$button(
        class="btn btn-sm btn-outline-secondary",
        style="font-size:12px;",
        onclick=sprintf("Shiny.setInputValue('%s','%s:%d',{priority:'event'});",
                        ns("ask_ai_btn"), rec$id, idx),
        HTML("&#129302; Ask AI")
      )
    )
  )
}

# ---------- UI ------------------------------------------------------------ #
# ---------- Business-question keyword parser -------------------------------- #
.parse_biz_question <- function(q) {
  q <- tolower(q)
  if (grepl("forecast|future|next|trend|season|arima|month|year|week", q))
    return("forecast")
  if (grepl("classif|categorize|group|segment|discriminate|label|type|which.*class|which.*category", q))
    return("classify")
  if (grepl("predict|model|estimate|explain|driver|factor|affect|influenc|cause", q))
    return("predict")
  if (grepl("correlat|relat|associat|link|connect|depend", q))
    return("relate")
  if (grepl("differ|better|best|worse|signif|test|hypothes|compare|vs\\.|versus", q))
    return("test")
  if (grepl("describ|summarize|overview|distribution|spread|range|mean|average", q))
    return("describe")
  "explore"
}

recommendToolsUI <- function(id) {
  ns <- NS(id)
  tagList(
    tags$h6("Analysis Recommender", class="text-uppercase text-muted small mb-2"),
    radioButtons(ns("is_cleaned"), "Is your data already cleaned?",
      choices = c("Yes, it's ready" = "yes", "Not yet" = "no"),
      selected = "yes", inline = TRUE),
    selectInput(ns("domain"), "Domain", width="100%",
      choices = c(
        "General"                   = "general",
        "Ecology / Forest science"  = "ecology",
        "Medicine / Clinical"       = "medicine",
        "Business / Operations"     = "business"
      )),
    accordion(
      open = "rec_question",
      accordion_panel("Ask a Question", value="rec_question",
        icon=icon("wand-magic-sparkles"),
        tags$p(class="small text-muted mb-2",
          "Describe your research question in plain language and the engine will recommend the right analysis."),
        textAreaInput(ns("biz_question"), NULL, width="100%", rows=3,
          placeholder=paste0(
            "e.g.\n",
            "Which factors predict tree height?\n",
            "Do sites differ in trafficability?\n",
            "Which features classify timber type best?"
          )),
        actionButton(ns("parse_question"), "Recommend for this question",
          class="btn-sm btn-success w-100 mt-1",
          icon=icon("wand-magic-sparkles")),
        uiOutput(ns("y_picker_ui"))
      ),
      accordion_panel("Manual Filters", value="rec_goal", icon=icon("sliders"),
        selectInput(ns("purpose"), "Research goal", width="100%",
          choices = c(
            "Explore structure & patterns"  = "explore",
            "Describe my data"              = "describe",
            "Test a hypothesis"             = "test",
            "Predict an outcome"            = "predict",
            "Classify / predict a category" = "classify",
            "Understand relationships"      = "relate",
            "Forecast future values"        = "forecast"
          )),
        selectInput(ns("priority_filter"), "Show", width="100%", selected="high_med",
          choices=c("High + Recommended"="high_med",
                    "High priority only"="high",
                    "All recommendations"="all"))
      )
    ),
    tags$div(class="mt-2 p-2 small text-muted ea-subpanel",
      style="font-size:11px;",
      icon("circle-info"),
      " Type a question, then select which column you want to analyse."
    )
  )
}

recommendCanvasUI <- function(id) {
  ns <- NS(id)
  tagList(
    # JS handler for the AI pre-fill (correct IDs: chat-panel / chat-input)
    tags$script(HTML("
      Shiny.addCustomMessageHandler('rec_pre_fill_chat', function(msg) {
        var panel = document.getElementById('chat-panel');
        if (panel) panel.classList.add('open');
        setTimeout(function() {
          var inp = document.getElementById('chat-input');
          if (inp) {
            inp.value = msg.text;
            inp.dispatchEvent(new Event('input', {bubbles:true}));
            inp.focus();
          }
        }, 250);
      });
    ")),

    # Data profile (column-by-column summary)
    uiOutput(ns("data_summary_ui")),

    # Data cleaning recommendations (shown when issues exist)
    uiOutput(ns("data_clean_ui")),

    # Profile summary stats
    uiOutput(ns("profile_row")),

    # Recommendation cards
    tags$div(
      style = "margin-top:12px; overflow-y:auto; max-height:calc(100vh - 220px);",
      uiOutput(ns("rec_cards"))
    )
  )
}

# ---------- Server -------------------------------------------------------- #
recommendServer <- function(id, dataset_pool, active_dataset) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_data <- reactive({
      ds <- active_dataset(); req(!is.null(ds)); dataset_pool[[ds]]
    })

    profile_r <- reactive({
      df <- active_data(); req(!is.null(df), nrow(df) > 0)
      .profile_ds(df)
    })

    # Purpose-aware Y variable picker (shown inside "Ask a Question" panel)
    output$y_picker_ui <- renderUI({
      prof    <- tryCatch(profile_r(), error = function(e) NULL)
      req(!is.null(prof))
      purpose <- input$purpose %||% "explore"

      label_map <- c(
        predict   = "Which column do you want to predict (Y)?",
        classify  = "Which column do you want to predict or classify (Y)?",
        test      = "Which numeric column do you want to compare across groups?",
        relate    = "Which column is the main outcome (Y)?",
        forecast  = "Which column do you want to forecast (Y)?",
        describe  = "Focus on which column? (optional)",
        explore   = "Main column of interest (optional)"
      )

      choices_base <- switch(purpose,
        classify  = c(prof$fct_nms, if(length(prof$bin_nms)) prof$bin_nms),
        predict   = , forecast = , test = , relate = prof$num_nms,
        c(prof$num_nms, prof$fct_nms)
      )
      choices <- c("(let engine decide)" = "__auto__", choices_base)
      lbl     <- label_map[[purpose]] %||% "Target variable (Y)"

      tagList(
        hr(style="margin:10px 0 6px;"),
        selectInput(ns("y_var_main"), lbl, choices = choices, width = "100%")
      )
    })

    # Plain-language question → auto-set purpose
    observeEvent(input$parse_question, {
      q <- trimws(input$biz_question %||% "")
      req(nzchar(q))
      p <- .parse_biz_question(q)
      updateSelectInput(session, "purpose", selected = p)
      label_map <- c(
        explore="Explore structure & patterns",
        describe="Describe my data", test="Test a hypothesis",
        predict="Predict an outcome", classify="Classify / predict a category",
        relate="Understand relationships", forecast="Forecast future values"
      )
      showNotification(
        HTML(paste0("Question parsed → <b>", label_map[[p]], "</b><br>",
                    "Now select the target column below.")),
        type="message", duration=5
      )
    }, ignoreInit=TRUE)

    .domain_seeds <- list(
      ecology  = "Which site and soil factors best predict tree height and biomass?",
      medicine = "Which clinical variables predict patient survival or treatment outcome?",
      business = "Which marketing channel or product feature drives the most revenue?"
    )
    observeEvent(input$domain, {
      d <- input$domain %||% "general"
      if (!is.null(.domain_seeds[[d]]))
        updateTextAreaInput(session, "biz_question", value = .domain_seeds[[d]])
    }, ignoreInit = TRUE)

    recs_r <- reactive({
      prof <- tryCatch(profile_r(), error=function(e) NULL)
      req(!is.null(prof))
      # y_var_main (purpose-aware picker) takes precedence over manual filter
      y_var <- if (isTruthy(input$y_var_main) && input$y_var_main != "__auto__") input$y_var_main
               else NULL
      recs  <- .gen_recs(prof, input$purpose %||% "explore", y_var)
      filt  <- input$priority_filter %||% "all"
      if (filt == "high")     recs <- Filter(function(r) r$priority == "high", recs)
      if (filt == "high_med") recs <- Filter(function(r) r$priority %in% c("high","medium"), recs)
      recs
    })

    # Column-by-column data summary
    output$data_summary_ui <- renderUI({
      df <- tryCatch(active_data(), error = function(e) NULL)
      req(!is.null(df), ncol(df) > 0)

      n_dup      <- sum(duplicated(df))
      is_cleaned <- input$is_cleaned %||% "yes"

      clean_banner <- if (is_cleaned == "no") {
        tags$div(class="alert alert-warning d-flex align-items-center gap-2 py-2 mb-2 small",
          icon("triangle-exclamation"),
          HTML(paste0(
            "Data not yet cleaned. ",
            "<a href='#' onclick=\"Shiny.setInputValue('current_view','data',{priority:'event'});return false;\">",
            "<b>Go to Data Cleaning →</b></a>"
          ))
        )
      } else if (n_dup > 0) {
        tags$div(class="alert alert-warning py-1 mb-2 small",
          icon("copy"), HTML(sprintf(" <b>%d duplicate row(s)</b> detected.", n_dup)))
      }

      rows <- lapply(names(df), function(col) {
        x      <- df[[col]]
        n_na   <- sum(is.na(x))
        pct_na <- 100 * n_na / nrow(df)
        xc     <- na.omit(x)
        is_num <- is.numeric(x)
        is_cat <- is.factor(x) || is.character(x)
        type_l <- if (is_num) "num" else if (is_cat) "cat" else class(x)[1]

        detail <- if (is_num && length(xc) > 0)
          sprintf("min=%.3g  mean=%.3g  max=%.3g  sd=%.3g",
                  min(xc), mean(xc), max(xc), sd(xc))
        else if (is_cat) {
          lvls <- sort(unique(as.character(xc)))
          paste0(length(lvls), " levels: ",
                 paste(head(lvls, 4), collapse=", "),
                 if (length(lvls) > 4) "…" else "")
        } else "—"

        flag <- pct_na > 5 || (is_cat && length(unique(xc)) > 25)

        na_td <- if (n_na == 0)
          tags$td(style="padding:3px 8px;color:var(--forest);font-size:12px;", "0")
        else
          tags$td(style="padding:3px 8px;color:var(--warn);font-size:12px;",
                  sprintf("%d (%.1f%%)", n_na, pct_na))

        tags$tr(class = if (flag) "ea-row-warn" else NULL,
          tags$td(style="padding:3px 8px;font-weight:600;font-size:12px;", col),
          tags$td(style="padding:3px 8px;color:var(--bark);font-size:11px;", type_l),
          na_td,
          tags$td(style="padding:3px 8px;font-size:11px;color:var(--bark);", detail)
        )
      })

      card(
        card_header(class="d-flex justify-content-between align-items-center",
          tagList(icon("table-list"), tags$span(" Data Profile", style="margin-left:6px;")),
          tags$small(class="text-muted",
                     sprintf("%d rows × %d columns", nrow(df), ncol(df)))),
        tags$div(style="padding:8px;",
          clean_banner,
          tags$div(style="overflow-y:auto;max-height:260px;",
            tags$table(class="table table-sm table-hover mb-0",
              tags$thead(class="table-light",
                tags$tr(
                  tags$th(style="font-size:11px;padding:4px 8px;", "Column"),
                  tags$th(style="font-size:11px;padding:4px 8px;", "Type"),
                  tags$th(style="font-size:11px;padding:4px 8px;", "N/A"),
                  tags$th(style="font-size:11px;padding:4px 8px;", "Profile")
                )
              ),
              tags$tbody(rows)
            )
          )
        )
      )
    })

    # Data cleaning recommendations — generated from profile
    output$data_clean_ui <- renderUI({
      df   <- tryCatch(active_data(), error = function(e) NULL)
      req(!is.null(df))
      prof <- tryCatch(profile_r(), error = function(e) NULL)
      req(!is.null(prof))

      steps <- list()

      n_dup <- sum(duplicated(df))
      if (n_dup > 0)
        steps[[length(steps)+1]] <- list(
          icon = "copy", color = "#e65100",
          text = sprintf("<b>Remove %d duplicate row(s).</b> Duplicates inflate sample size and bias models.", n_dup),
          action = "Delete duplicates in the Data tab → Undo/Reset strip → or filter them out."
        )

      high_na <- names(df)[sapply(names(df), function(v) mean(is.na(df[[v]])) > 0.05)]
      if (length(high_na) > 0)
        steps[[length(steps)+1]] <- list(
          icon = "circle-question", color = "#1565c0",
          text = sprintf("<b>Handle missing values</b> in: %s.",
                         paste(sprintf("<i>%s</i>", head(high_na, 5)), collapse=", ")),
          action = "Use Data → Impute (mean/median) or delete rows with NA before modelling."
        )

      skewed <- prof$num_nms[sapply(prof$num_nms, function(v) {
        x <- na.omit(df[[v]]); if (length(x) < 5 || sd(x) == 0) return(FALSE)
        abs(mean((x - mean(x))^3) / sd(x)^3) > 2
      })]
      if (length(skewed) > 0)
        steps[[length(steps)+1]] <- list(
          icon = "chart-simple", color = "#6a1b9a",
          text = sprintf("<b>Log-transform skewed column(s):</b> %s.",
                         paste(sprintf("<i>%s</i>", head(skewed, 5)), collapse=", ")),
          action = "Apply log() in Data → Transform column, or use Poisson/GLM instead of linear regression."
        )

      many_levels <- prof$fct_nms[sapply(prof$fct_nms, function(v) {
        nlevels(as.factor(na.omit(df[[v]]))) > 15
      })]
      if (length(many_levels) > 0)
        steps[[length(steps)+1]] <- list(
          icon = "tags", color = "#2e7d32",
          text = sprintf("<b>Too many levels</b> in: %s.",
                         paste(sprintf("<i>%s</i>", head(many_levels, 4)), collapse=", ")),
          action = "Merge rare levels in Data → Merge Levels to reduce noise and avoid sparse cells."
        )

      near_zero_var <- prof$num_nms[sapply(prof$num_nms, function(v) {
        x <- na.omit(df[[v]]); if (length(x) < 2) return(FALSE)
        sd(x) / max(abs(mean(x)), 1e-12) < 0.01
      })]
      if (length(near_zero_var) > 0)
        steps[[length(steps)+1]] <- list(
          icon = "minus", color = "#757575",
          text = sprintf("<b>Near-zero variance</b> in: %s. These columns add little information.",
                         paste(sprintf("<i>%s</i>", head(near_zero_var, 4)), collapse=", ")),
          action = "Consider removing these columns before modelling."
        )

      if (length(steps) == 0) return(NULL)

      rows <- lapply(steps, function(s) {
        tags$div(
          class = "d-flex gap-2 mb-2",
          style = "align-items:flex-start;",
          tags$div(
            style = paste0("flex-shrink:0;width:28px;height:28px;border-radius:50%;",
                           "background:", s$color, "22;display:flex;align-items:center;",
                           "justify-content:center;margin-top:1px;"),
            icon(s$icon, style = paste0("color:", s$color, ";font-size:13px;"))
          ),
          tags$div(
            tags$div(style="font-size:12px;", HTML(s$text)),
            tags$div(style="font-size:11px;color:#888;margin-top:2px;", s$action)
          )
        )
      })

      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          tagList(icon("broom"), tags$span(" Data Cleaning Recommendations",
                                           style = "margin-left:6px;")),
          tags$small(class="text-muted", sprintf("%d item(s)", length(steps)))
        ),
        tags$div(style="padding:12px;", rows,
          tags$a(href="#",
            class="btn btn-sm btn-outline-success mt-2",
            onclick="Shiny.setInputValue('current_view','data',{priority:'event'});return false;",
            icon("arrow-right"), " Go to Data Cleaning"
          )
        )
      )
    })

    output$profile_row <- renderUI({
      prof <- tryCatch(profile_r(), error=function(e) NULL)
      if (is.null(prof))
        return(tags$div(class="p-5 text-center text-muted",
          icon("database", style="font-size:2em;"), tags$br(),
          tags$p("Load a dataset to see recommendations.")))

      norm_txt <- if(!is.na(prof$pct_normal))
        sprintf("%.0f%%", 100*prof$pct_normal) else "n/a"
      corr_txt <- if(!is.na(prof$max_r)) sprintf("%.2f", prof$max_r) else "n/a"

      layout_columns(col_widths = c(2,2,2,2,2,2),
        value_box("Observations", prof$n, showcase=icon("rows"), theme="success"),
        value_box("Variables", prof$p, showcase=icon("table-columns"), theme="secondary"),
        value_box("Numeric", prof$n_num, showcase=icon("hashtag"), theme="secondary"),
        value_box("Categorical", prof$n_fct, showcase=icon("tag"), theme="secondary"),
        value_box("Normal", norm_txt, showcase=icon("chart-bell"), theme="secondary"),
        value_box("Max |r|", corr_txt, showcase=icon("link"), theme="secondary")
      )
    })

    output$rec_cards <- renderUI({
      recs <- tryCatch(recs_r(), error=function(e) NULL)
      if (is.null(recs) || length(recs) == 0)
        return(tags$div(class="p-4 text-center text-muted",
          "No recommendations match the current filter. Try showing all."))

      layout_columns(col_widths = c(6, 6),
        lapply(seq(1, length(recs), by=2), function(i) {
          tagList(
            .rec_card_html(recs[[i]], ns, i),
            if (i+1 <= length(recs)) .rec_card_html(recs[[i+1]], ns, i+1)
          )
        })
      )
    })

    # AI Ask button — open copilot with pre-filled question
    observeEvent(input$ask_ai_btn, {
      val  <- input$ask_ai_btn
      req(isTruthy(val))
      parts  <- strsplit(val, ":")[[1]]
      rec_id <- parts[1]
      idx    <- suppressWarnings(as.integer(parts[2]))
      recs   <- tryCatch(recs_r(), error=function(e) NULL)
      req(!is.null(recs), !is.na(idx), idx >= 1, idx <= length(recs))
      rec    <- recs[[idx]]
      prof   <- tryCatch(profile_r(), error=function(e) NULL)
      n_str  <- if(!is.null(prof)) paste0("n=",prof$n) else "my dataset"
      why_plain <- gsub("<[^>]+>","", rec$why)
      msg <- sprintf(
        "I am on the Analysis Recommender screen. It suggested '%s' for my dataset (%s). Reason given: %s. Can you elaborate on this recommendation — when is it most appropriate, what are its key assumptions, and what should I check first?",
        rec$name, n_str, why_plain
      )
      session$sendCustomMessage("rec_pre_fill_chat", list(text=msg))
    })

    # Go-to button — show variable suggestion as a notification
    observeEvent(input$goto_rec, {
      idx  <- suppressWarnings(as.integer(input$goto_rec))
      recs <- tryCatch(recs_r(), error=function(e) NULL)
      req(!is.null(recs), !is.na(idx), idx >= 1, idx <= length(recs))
      rec  <- recs[[idx]]
      lines <- character(0)
      if (!is.null(rec$suggest_y) && length(rec$suggest_y) > 0 && nzchar(rec$suggest_y[1]))
        lines <- c(lines, paste0("<b>Outcome (Y):</b> ", rec$suggest_y[1]))
      if (!is.null(rec$suggest_x) && length(rec$suggest_x) > 0)
        lines <- c(lines, paste0("<b>Predictors (X):</b> ",
                                  paste(head(rec$suggest_x, 5), collapse=", ")))
      if (length(lines) > 0)
        showNotification(
          HTML(paste0("Navigating to <b>", rec$name, "</b><br>",
                      paste(lines, collapse="<br>"))),
          type = "message", duration = 10
        )
    })

    list(
      context = reactive({
        recs <- tryCatch(recs_r(), error=function(e) NULL)
        prof <- tryCatch(profile_r(), error=function(e) NULL)
        if (is.null(recs) || is.null(prof)) return("Recommender: no data loaded.")
        high <- Filter(function(r) r$priority=="high", recs)
        paste0("Analysis Recommender | Dataset: n=",prof$n,", ",prof$n_num," numeric, ",
               prof$n_fct," categorical\n",
               "Top recommendations: ",
               paste(sapply(head(high,4), `[[`, "name"), collapse="; "))
      }),
      plot = function() invisible()
    )
  })
}
