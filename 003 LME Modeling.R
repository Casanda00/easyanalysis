# ============================================================
# Masters Thesis: Modeling Forest Road Trafficability Using Tree Growth Rates and Road Characteristics
# Author: Tim Casanda Gibson
# Date:   March 4, 2026
# ============================================================

rm(list = ls())
set.seed(123)

suppressPackageStartupMessages({
  library(nlme)
  library(dplyr)
  library(ggplot2)
  library(caret)
  library(MuMIn)
  library(tibble)
  library(forcats)
  library(lmfor)
  library(patchwork)
  library(car)
})

# -----------------------------
# Config
# -----------------------------
save_plots <- FALSE
out_dir    <- "plots"
if (save_plots && !dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# -----------------------------
# Utility metrics
# -----------------------------
rmse     <- function(y, yhat) sqrt(mean((y - yhat)^2, na.rm = TRUE))
rel_rmse <- function(y, yhat) rmse(y, yhat) / mean(y, na.rm = TRUE) * 100
r_sq     <- function(y, yhat) cor(y, yhat, use = "complete.obs")^2

# -----------------------------
# Load & prepare data
# -----------------------------
data_raw <- read.csv("modeling_data.csv")

# Drop the outlier row (if present)
if (nrow(data_raw) >= 126) data_raw <- data_raw[-126, ]

# Trafficability class as ordered factor (Winter < Dry Summer < Summer < All-year)========
traffic_levels <- c("Winter", "Dry Summer", "Summer", "All-year")
data_raw$Trafficability_Class <- factor(
  data_raw$Trafficability_Class, levels = traffic_levels, ordered = TRUE
)


# Make a working dataframe with only the relevant columns and drop rows with NAs in those columns.=====
df <- data_raw %>%
  dplyr::select(
    NEW_ID, FWD.avg, Trafficability_Class,
    Growth_Rate_Mean_Agg, Growth_Rate_Max_Agg,
    dtw_0.5mean, twimean, tsum, psum,
    roadwidth, ditchindex,
    Soil_Group, fertility_name
  ) %>%
  na.omit() %>%
  as.data.frame()

cat("Data:", nrow(df), "rows,", dplyr::n_distinct(df$NEW_ID), "sites\n")

# ============================================================
# EDA PLOT 1: Sample distributions (counts)
# ============================================================
p_count_soil <- ggplot(df, aes(x = fct_infreq(Soil_Group))) +
  geom_bar(fill = "#377eb8") +
  labs(title = "Count by Soil Group", x = "Soil Group", y = "Count") +
  theme_bw() + theme(axis.text.x = element_text(angle = 0, hjust = 1))

p_count_fert <- ggplot(df, aes(x = fct_infreq(fertility_name))) +
  geom_bar(fill = "#4daf4a") +
  labs(title = "Count by Fertility Class", x = "Fertility Class", y = "Count") +
  theme_bw() + theme(axis.text.x = element_text(angle = 0, hjust = 1))

p_count_traf <- ggplot(df, aes(x = fct_infreq(Trafficability_Class))) +
  geom_bar(fill = "#984ea3") +
  labs(title = "Count by Trafficability Class", x = "Trafficability", y = "Count") +
  theme_bw() + theme(axis.text.x = element_text(angle = 0, hjust = 1))

print(p_count_soil); print(p_count_fert); print(p_count_traf)
if (save_plots) {
  ggsave(file.path(out_dir, "count_by_soil.png"), p_count_soil, width = 6.5, height = 4.8, dpi = 300)
  ggsave(file.path(out_dir, "count_by_fertility.png"), p_count_fert, width = 6.5, height = 4.8, dpi = 300)
  ggsave(file.path(out_dir, "count_by_traffic.png"), p_count_traf, width = 6.5, height = 4.8, dpi = 300)
}

# -----------------------------
# Fit models (site-level random intercept)
# -----------------------------
# Remove negative growths and NAs in mean growth rate.
df <- df[df$Growth_Rate_Mean_Agg >= 0 & !is.na(df$Growth_Rate_Mean_Agg), ]

# Model 1: Linear (no transformations)
m_linear <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 2: Add quadratic term to mean growth rate
m_quad_mean <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
    Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 3: Add square root term to mean growth and quadratic term to road width
m_sqrt_quad <- lme(
  FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + I(roadwidth^2) + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 4: Add quadratic term to max growth rate

m_quad_max <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg +
    Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 5: Add quadratic terms to both mean and max growth rates
# Center road width
df$roadwidth_c <- scale(df$roadwidth, scale = FALSE)

m_quad_both <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
    Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
    dtw_0.5mean + twimean + tsum + psum + roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df,method = "REML"
)

# Model 6: Add square root transformation to mean growth rate
m_sqrt_mean <- lme(
  FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 7: Remove roadwidth and ditchindex to see if it improves fit
m_no_road <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 8: Add sqrt to mean growth and remove roadwidth and ditchindex
m_sqrt_no_road <- lme(
  FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 9: Focus only on mean growths between 1 - 8 m. so we need to extract the data, then fit the model
df_subset <- df[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 8, ]

# Fit model 9
m_subset <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df_subset, method = "REML"
)

# Model 10: Focus only on FWD between 0 to 60. See the impact growth between 1-8m.
m_subset_fwd <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df[df$FWD.avg <= 60, ], method = "REML"
)

# Model 11: Remove growths from the model. We will observe the error rates
m_no_growth <- lme(
  FWD.avg ~ dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df, method = "REML"
)

# Model 12: Focus only on mean growth between 1 - 4 m.
df_subset2 <- df[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4, ]

m_subset2 <- lme(
  FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + ditchindex,
  random = ~1 | NEW_ID, data = df_subset2, method = "REML"
)

# Model 13: Focus only on mean growth between 1 - 4 M, adding quadratic term to road width and sqrt to mean growth
df_subset_3 <- df[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4, ]

# Center road width
df_subset_3$roadwidth_c <- scale(df_subset_3$roadwidth, scale = FALSE)

m_subset_3 <- lme(
  FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
    dtw_0.5mean + twimean + tsum + psum +
    roadwidth + I(roadwidth^2) + ditchindex,
  random = ~1 | NEW_ID, data = df_subset2, method = "REML"
)
# ============================================================
# Plots to see if the relationships look quadratic or if transformations might help
# These plots helps us to understand if the variables have a non-linear relationship with a specific shape.
# 
# ============================================================

# Model 1: Linear
p1 <- ggplot(df, aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 1", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 2: Add quadratic term to mean growth rate
p2 <- ggplot(df, aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 2", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 3: Add squared term to mean growth and quadratic term to road width
p3 <- ggplot(df, aes(x = sqrt(Growth_Rate_Mean_Agg), y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 3", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 4: Add quadratic term to max growth rate
p4 <- ggplot(df, aes(x = Growth_Rate_Max_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 4", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 5: Add quadratic terms to both mean and max growth rates
p5 <- ggplot(df, aes(x = Growth_Rate_Max_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 5", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 6: Add square root transformation to mean growth rate
p6 <- ggplot(df, aes(x = sqrt(Growth_Rate_Mean_Agg), y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 6", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Roadwidth vs FWD
p7 <- ggplot(df, aes(x = roadwidth, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Road Width", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 7: Remove roadwidth and ditchindex to see if it improves fit
p8 <- ggplot(df, aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 7", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 8: Add sqrt to mean growth and remove roadwidth and ditchindex
p9 <- ggplot(df, aes(x = sqrt(Growth_Rate_Mean_Agg), y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 8", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 9: Mean growth between 1 - 8 m.
p10 <- ggplot(df_subset, aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 9 (subset)", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 10: FWD between 0 to 60
p11 <- ggplot(df[df$FWD.avg <= 60, ], aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 10 (subset FWD <= 60)", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 11: Remove growths from the model
p12 <- ggplot(df, aes(x = dtw_0.5mean, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 11 (no growth)", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 12: Mean growth between 1 - 4 m.
p13 <- ggplot(df_subset2, aes(x = Growth_Rate_Mean_Agg, y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 12 (subset mean growth 1-4)", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Model 13: Mean growth between 1 - 4 M, adding quadratic term to road width and sqrt to mean growth
p14 <- ggplot(df_subset2, aes(x = sqrt(Growth_Rate_Mean_Agg), y = FWD.avg)) +
  geom_point(alpha = 0.3) +
  geom_smooth(method = "loess", se = TRUE, color = "black") +  # flexible fit
  geom_smooth(method = "lm", formula = y ~ x + I(x^2), se = FALSE, color = "black", linetype = "dashed") +
  labs(x = "Model 13 (subset mean growth 1-4 + sqrt)", 
       y = expression(paste("Predicted FWD (MN/", m^2, ")")))

# Print plots
print(p1); print(p2); print(p3); print(p4); print(p5); print(p6); print(p7); print(p8); print(p9); print(p10); print(p11); print(p12); print(p13); print(p14)

# Print Plots Side by side
p1 + p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9 + p10 + p11 + p12 + p13 + p14 + plot_layout(ncol = 3)


# -----------------------------
# Training predictions (population-level: level = 0)
# -----------------------------
pred_linear     <- predict(m_linear,     level = 0)
pred_quad_mean  <- predict(m_quad_mean,  level = 0)
pred_quad_max   <- predict(m_quad_max,   level = 0)
pred_quad_both  <- predict(m_quad_both,  level = 0)
pred_sqrt_quad  <- predict(m_sqrt_quad, level = 0)
pred_sqrt_mean  <- predict(m_sqrt_mean, level = 0)
pred_no_road   <- predict(m_no_road,   level = 0)
pred_sqrt_no_road <- predict(m_sqrt_no_road, level = 0)
pred_subset     <- predict(m_subset,     level = 0)
pred_subset_fwd <- predict(m_subset_fwd, level = 0)
pred_no_growth <- predict(m_no_growth, level = 0)
pred_subset2    <- predict(m_subset2,    level = 0)
pred_subset_3  <- predict(m_subset_3,  level = 0)

# -----------------------------
# Training metrics (all models)
# -----------------------------
train_tab <- tibble(
  Model = c("Linear", "Quad - mean only", "Quad - max only", "Quad - both", 
            "Sqrt + Quad", "Sqrt - mean only", "No Road/Ditch", "Sqrt + No Road/Ditch", "Subset (mean growth 1-8)",
            "Subset (FWD <= 60)", "No Growth Variables", "Subset (mean growth 1-4)", "Subset (mean growth 1-4 + sqrt)"),
  RMSE  = c(
    rmse(df$FWD.avg, pred_linear),
    rmse(df$FWD.avg, pred_quad_mean),
    rmse(df$FWD.avg, pred_quad_max),
    rmse(df$FWD.avg, pred_quad_both),
    rmse(df$FWD.avg, pred_sqrt_quad),
    rmse(df$FWD.avg, pred_sqrt_mean),
    rmse(df$FWD.avg, pred_no_road),
    rmse(df$FWD.avg, pred_sqrt_no_road),
    rmse(df_subset$FWD.avg, pred_subset[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 8]),
    rmse(df[df$FWD.avg <= 60, ]$FWD.avg, pred_subset_fwd[df$FWD.avg <= 60]),
    rmse(df$FWD.avg, pred_no_growth),
    rmse(df_subset2$FWD.avg, pred_subset2[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4]),
    rmse(df_subset2$FWD.avg, pred_subset_3[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4])
  ),
  `relRMSE%` = c(
    rel_rmse(df$FWD.avg, pred_linear),
    rel_rmse(df$FWD.avg, pred_quad_mean),
    rel_rmse(df$FWD.avg, pred_quad_max),
    rel_rmse(df$FWD.avg, pred_quad_both),
    rel_rmse(df$FWD.avg, pred_sqrt_quad),
    rel_rmse(df$FWD.avg, pred_sqrt_mean),
    rel_rmse(df$FWD.avg, pred_no_road),
    rel_rmse(df$FWD.avg, pred_sqrt_no_road),
    rel_rmse(df_subset$FWD.avg, pred_subset[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 8]),
    rel_rmse(df[df$FWD.avg <= 60, ]$FWD.avg, pred_subset_fwd[df$FWD.avg <= 60]),
    rel_rmse(df$FWD.avg, pred_no_growth),
    rel_rmse(df_subset2$FWD.avg, pred_subset2[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4]),
    rel_rmse(df_subset2$FWD.avg, pred_subset_3[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4])
  ),
  R2 = c(
    r_sq(df$FWD.avg, pred_linear),
    r_sq(df$FWD.avg, pred_quad_mean),
    r_sq(df$FWD.avg, pred_quad_max),
    r_sq(df$FWD.avg, pred_quad_both),
    r_sq(df$FWD.avg, pred_sqrt_quad),
    r_sq(df$FWD.avg, pred_sqrt_mean),
    r_sq(df$FWD.avg, pred_no_road),
    r_sq(df$FWD.avg, pred_sqrt_no_road),
    r_sq(df_subset$FWD.avg, pred_subset[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 8]),
    r_sq(df[df$FWD.avg <= 60, ]$FWD.avg, pred_subset_fwd[df$FWD.avg <= 60]),
    r_sq(df$FWD.avg, pred_no_growth),
    r_sq(df_subset2$FWD.avg, pred_subset2[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4]),
    r_sq(df_subset2$FWD.avg, pred_subset_3[df$Growth_Rate_Mean_Agg >= 1 & df$Growth_Rate_Mean_Agg <= 4])
  )
)
cat("\n=== Training metrics (population-level predictions) ===\n")
print(train_tab)

# -----------------------------
# LOOCV function (returns metrics + per-row predictions)
# -----------------------------
run_loocv <- function(model_expr, name, data = df) {
  sites <- unique(data$NEW_ID)
  cv_pred <- rep(NA_real_, nrow(data))  
  cat("LOOCV:", name, "\n")
  for (s in sites) {
    train_d <- data[data$NEW_ID != s, , drop = FALSE]
    test_d  <- data[data$NEW_ID == s, , drop = FALSE]
    if (nrow(train_d) < 6) next
    m <- tryCatch(eval(model_expr), error = function(e) NULL)
    if (!is.null(m)) {
      p <- tryCatch(
        predict(m, newdata = test_d, level = 0),
        error = function(e) rep(NA_real_, nrow(test_d))
      )
      cv_pred[data$NEW_ID == s] <- p
    }
  }
  valid <- is.finite(cv_pred)
  list(
    rmse  = rmse(data$FWD.avg[valid], cv_pred[valid]),
    rel   = rel_rmse(data$FWD.avg[valid], cv_pred[valid]),
    r2    = r_sq(data$FWD.avg[valid], cv_pred[valid]),
    pred  = cv_pred,
    valid = valid
  )
}

# -----------------------------
# Run LOOCV for each model
# -----------------------------
loocv_linear     <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Linear")

loocv_quad_mean  <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
                                          Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Quad - mean only")

loocv_quad_max   <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg +
                                          Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Quad - max only")

loocv_quad_both  <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
                                          Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Quad - both")

loocv_sqrt_quad  <- run_loocv(quote(lme(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + I(roadwidth^2) + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Sqrt + Quad")

loocv_sqrt_mean <- run_loocv(quote(lme(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Sqrt - mean only")

loocv_no_road   <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "No Road/Ditch")

loocv_sqrt_no_road <- run_loocv(quote(lme(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Sqrt + No Road/Ditch")

loocv_subset     <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Subset (mean growth 1-8)", data = df_subset)

loocv_subset_fwd <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Subset (FWD <= 60)", data = df[df$FWD.avg <= 60, ])

loocv_no_growth <- run_loocv(quote(lme(FWD.avg ~ dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                       random = ~1 | NEW_ID, data = train_d, method = "REML")), "No Growth Variables")

loocv_subset2 <- run_loocv(quote(lme(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Subset (mean growth 1-4)", data = df_subset2)
loocv_subset_3 <- run_loocv(quote(lme(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                                          dtw_0.5mean + twimean + tsum + psum +
                                          roadwidth + I(roadwidth^2) + ditchindex,
                                        random = ~1 | NEW_ID, data = train_d, method = "REML")), "Subset (mean growth 1-4 + sqrt)", data = df_subset2)

# -----------------------------
# LOOCV metrics table
# -----------------------------
cv_tab <- tibble(
  Model  = c("Linear", "Quad - mean only", "Quad - max only", "Quad - both", "Sqrt + Quad", 
             "Sqrt - mean only", "No Road/Ditch", "Sqrt + No Road/Ditch", "Subset (mean growth 1-8)",
             "Subset (FWD <= 60)", "No Growth Variables", "Subset (mean growth 1-4)", "Subset (mean growth 1-4 + sqrt)"),
  RMSE   = c(loocv_linear$rmse, loocv_quad_mean$rmse, loocv_quad_max$rmse, 
             loocv_quad_both$rmse, loocv_sqrt_quad$rmse, loocv_sqrt_mean$rmse,
             loocv_no_road$rmse, loocv_sqrt_no_road$rmse, loocv_subset$rmse, loocv_subset_fwd$rmse, 
             loocv_no_growth$rmse, loocv_subset2$rmse, loocv_subset_3$rmse),
  `relRMSE%`= c(loocv_linear$rel,  loocv_quad_mean$rel,  loocv_quad_max$rel,  loocv_quad_both$rel, 
                loocv_sqrt_quad$rel, loocv_sqrt_mean$rel, loocv_no_road$rel, loocv_sqrt_no_road$rel, loocv_subset$rel,
                loocv_subset_fwd$rel, loocv_no_growth$rel, loocv_subset2$rel, loocv_subset_3$rel),
  R2     = c(loocv_linear$r2,   loocv_quad_mean$r2,   loocv_quad_max$r2,   loocv_quad_both$r2,   
             loocv_sqrt_quad$r2, loocv_sqrt_mean$r2, loocv_no_road$r2, loocv_sqrt_no_road$r2, loocv_subset$r2,
             loocv_subset_fwd$r2, loocv_no_growth$r2, loocv_subset2$r2, loocv_subset_3$r2)
)
cat("\n=== LOOCV metrics (population-level predictions) ===\n")
print(cv_tab)

# -----------------------------
# Nakagawa R^2 (MuMIn)
# -----------------------------
cat("\n=== Nakagawa-style R^2 (MuMIn::r.squaredGLMM) ===\n")
mods <- list(
  Linear = m_linear,
  "Quad - mean only" = m_quad_mean,
  "Quad - max only"  = m_quad_max,
  "Quad - both"      = m_quad_both,
  "Sqrt + Quad"      = m_sqrt_quad,
  "Sqrt - mean only" = m_sqrt_mean,
  "No Road/Ditch"    = m_no_road,
  "Sqrt + No Road/Ditch" = m_sqrt_no_road,
  "Subset (mean growth 1-8)" = m_subset,
  "Subset (FWD <= 60)" = m_subset_fwd,
  "No Growth Variables" = m_no_growth,
  "Subset (mean growth 1-4)" = m_subset2,
  "Subset (mean growth 1-4 + sqrt)" = m_subset_3
)
for (nm in names(mods)) {
  r2 <- r.squaredGLMM(mods[[nm]])
  cat(sprintf("%-16s  R2m = %.3f,  R2c = %.3f\n", nm, r2[1, "R2m"], r2[1, "R2c"]))
}

# ============================================================
# AIC/BIC table
# ============================================================
aic_tab <- tibble(
  Model = c("Linear", "Quad - mean only", "Quad - max only", "Quad - both", "Sqrt + Quad", 
            "Sqrt - mean only", "No Road/Ditch", "Sqrt + No Road/Ditch", "Subset (mean growth 1-8)",
            "Subset (FWD <= 60)", "No Growth Variables", "Subset (mean growth 1-4)", "Subset (mean growth 1-4 + sqrt)"),
  AIC   = as.character(c(AIC(m_linear), AIC(m_quad_mean), AIC(m_quad_max), AIC(m_quad_both), 
                         AIC(m_sqrt_quad), AIC(m_sqrt_mean), AIC(m_no_road), AIC(m_sqrt_no_road), AIC(m_subset),
                         AIC(m_subset_fwd), AIC(m_no_growth), AIC(m_subset2), AIC(m_subset_3))),
  BIC   = as.character(c(BIC(m_linear), BIC(m_quad_mean), BIC(m_quad_max), BIC(m_quad_both), BIC(m_sqrt_quad), 
                         BIC(m_sqrt_mean), BIC(m_no_road), BIC(m_sqrt_no_road), BIC(m_subset),
                         BIC(m_subset_fwd), BIC(m_no_growth), BIC(m_subset2), BIC(m_subset_3)))
)
# Print AIC/BIC table
cat("\n=== AIC/BIC for all models ===\n")
print(aic_tab)

# ============================================================
# Print Model Summaries
# ============================================================
cat("\n=== Model Summaries ===\n")
for (nm in names(mods)) {
  cat("\n---", nm, "---\n")
  print(summary(mods[[nm]]))
}

# ============================================================
# Multicollinearity check (VIF)
# ============================================================
# Model 1 Linear VIF
vif_linear <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                       dtw_0.5mean + twimean + tsum + psum +
                       roadwidth + ditchindex, data = df))
cat("\n=== VIF for Linear Model ===\n")
print(vif_linear)

# Model 2 Quad - mean only VIF
vif_quad_mean <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
                          Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df))
cat("\n=== VIF for Quad - mean only Model ===\n")
print(vif_quad_mean)

# Model 3 Quad - max only VIF
vif_quad_max <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg +
                          Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df))
cat("\n=== VIF for Quad - max only Model ===\n")
print(vif_quad_max)

# Model 4 Quad - both VIF
vif_quad_both <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + I(Growth_Rate_Mean_Agg^2) +
                          Growth_Rate_Max_Agg + I(Growth_Rate_Max_Agg^2) +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df))
cat("\n=== VIF for Quad - both Model ===\n")
print(vif_quad_both)

# Model 5 Sqrt + Quad VIF
vif_sqrt_quad <- vif(lm(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                      dtw_0.5mean + twimean + tsum + psum +
                      roadwidth_c + I(roadwidth_c^2) + ditchindex,
                    data = df))
cat("\n=== VIF for Sqrt + Quad Model ===\n")
print(vif_sqrt_quad)

# Model 6 Sqrt - mean only VIF
vif_sqrt_mean <- vif(lm(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df))
cat("\n=== VIF for Sqrt - mean only Model ===\n")
print(vif_sqrt_mean)

# Model 7 No Road/Ditch VIF
vif_no_road <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum, data = df))
cat("\n=== VIF for No Road/Ditch Model ===\n")
print(vif_no_road)

# Model 8 Sqrt + No Road/Ditch VIF
vif_sqrt_no_road <- vif(lm(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum, data = df))
cat("\n=== VIF for Sqrt + No Road/Ditch Model ===\n")
print(vif_sqrt_no_road)

# Model 9 Subset (mean growth 1-8) VIF
vif_subset <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df_subset))
cat("\n=== VIF for Subset (mean growth 1-8) Model ===\n")
print(vif_subset)

# Model 10 Subset (FWD <= 60) VIF
vif_subset_fwd <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df[df$FWD.avg <= 60, ]))
cat("\n=== VIF for Subset (FWD <= 60) Model ===\n")
print(vif_subset_fwd)

# Model 11 No Growth Variables VIF
vif_no_growth <- vif(lm(FWD.avg ~ dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df))
cat("\n=== VIF for No Growth Variables Model ===\n")
print(vif_no_growth)

# Model 12 Subset (mean growth 1-4) VIF
vif_subset2 <- vif(lm(FWD.avg ~ Growth_Rate_Mean_Agg + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + ditchindex, data = df_subset2))
cat("\n=== VIF for Subset (mean growth 1-4) Model ===\n")
print(vif_subset2)

# Model 13 Subset (mean growth 1-4 + sqrt) VIF
vif_subset_3 <- vif(lm(FWD.avg ~ sqrt(Growth_Rate_Mean_Agg) + Growth_Rate_Max_Agg +
                          dtw_0.5mean + twimean + tsum + psum +
                          roadwidth + I(roadwidth^2) + ditchindex, data = df_subset2))
cat("\n=== VIF for Subset (mean growth 1-4 + sqrt) Model ===\n")
print(vif_subset_3)

# ============================================================
# CORE PLOT 3: Calibration (binned means) — LOOCV (all models)
# ============================================================
make_binned_means <- function(observed, predicted, n_bins = 15) {
  dfp <- data.frame(observed, predicted) %>% filter(is.finite(observed), is.finite(predicted))
  brks <- quantile(dfp$predicted, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)
  brks[1] <- floor(min(dfp$predicted, na.rm = TRUE)) - 1e-6
  brks[length(brks)] <- ceiling(max(dfp$predicted, na.rm = TRUE)) + 1e-6
  dfp$bin <- cut(dfp$predicted, breaks = brks, include.lowest = TRUE)
  dfp %>%
    group_by(bin) %>%
    summarise(mean_pred = mean(predicted), mean_obs = mean(observed), n = n(), .groups = "drop")
}
make_cal_plot <- function(bm, title) {
  ggplot(bm, aes(x = mean_pred, y = mean_obs, size = n)) +
    geom_point(alpha = 0.85) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray40") +
    geom_smooth(method = "lm", se = FALSE, color = "#1f78b4") +
    scale_size_continuous(name = "Bin count") +
    labs(title = title, x = "Mean predicted (per bin)", y = "Mean observed (per bin)") +
    theme_bw()
}

bm_linear    <- make_binned_means(df$FWD.avg, loocv_linear$pred)
bm_quad_mean <- make_binned_means(df$FWD.avg, loocv_quad_mean$pred)
bm_quad_max  <- make_binned_means(df$FWD.avg, loocv_quad_max$pred)
bm_quad_both <- make_binned_means(df$FWD.avg, loocv_quad_both$pred)
bm_sqrt_quad <- make_binned_means(df$FWD.avg, loocv_sqrt_quad$pred)
bm_sqrt_mean <- make_binned_means(df$FWD.avg, loocv_sqrt_mean$pred)
bm_no_road   <- make_binned_means(df$FWD.avg, loocv_no_road$pred)
bm_sqrt_no_road <- make_binned_means(df$FWD.avg, loocv_sqrt_no_road$pred)
bm_subset     <- make_binned_means(df_subset$FWD.avg, loocv_subset$pred)
bm_subset_fwd <- make_binned_means(df[df$FWD.avg <= 60, ]$FWD.avg, loocv_subset_fwd$pred)
bm_no_growth <- make_binned_means(df$FWD.avg, loocv_no_growth$pred)
bm_subset2    <- make_binned_means(df_subset2$FWD.avg, loocv_subset2$pred)
bm_subset_3  <- make_binned_means(df_subset2$FWD.avg, loocv_subset_3$pred)

p_cal_linear    <- make_cal_plot(bm_linear,    "Calibration (Binned Means) — LOOCV (Linear)")
p_cal_quad_mean <- make_cal_plot(bm_quad_mean, "Calibration (Binned Means) — LOOCV (Quad - mean only)")
p_cal_quad_max  <- make_cal_plot(bm_quad_max,  "Calibration (Binned Means) — LOOCV (Quad - max only)")
p_cal_quad_both <- make_cal_plot(bm_quad_both, "Calibration (Binned Means) — LOOCV (Quad - both)")
p_cal_sqrt_quad <- make_cal_plot(bm_sqrt_quad, "Calibration (Binned Means) — LOOCV (Sqrt + Quad)")
p_cal_sqrt_mean <- make_cal_plot(bm_sqrt_mean, "Calibration (Binned Means) — LOOCV (Sqrt - mean only)")
p_cal_no_road   <- make_cal_plot(bm_no_road,   "Calibration (Binned Means) — LOOCV (No Road/Ditch)")
p_cal_sqrt_no_road <- make_cal_plot(bm_sqrt_no_road, "Calibration (Binned Means) — LOOCV (Sqrt + No Road/Ditch")
p_cal_subset     <- make_cal_plot(bm_subset,     "Calibration (Binned Means) — LOOCV (Subset mean growth 1-8)")
p_cal_subset_fwd <- make_cal_plot(bm_subset_fwd, "Calibration (Binned Means) — LOOCV (Subset FWD <= 60)")
p_cal_no_growth <- make_cal_plot(bm_no_growth, "Calibration (Binned Means) — LOOCV (No Growth Variables)")
p_cal_subset_2    <- make_cal_plot(bm_subset2,    "Calibration (Binned Means) — LOOCV (Subset mean growth 1-4)")
p_cal_subset_3  <- make_cal_plot(bm_subset_3,  "Calibration (Binned Means) — LOOCV (Subset mean growth 1-4 + sqrt)")

print(p_cal_linear); print(p_cal_quad_mean); print(p_cal_quad_max); print(p_cal_quad_both); print(p_cal_sqrt_quad); 
print(p_cal_sqrt_mean); print(p_cal_no_road); print(p_cal_sqrt_no_road); print(p_cal_subset); print(p_cal_subset_fwd); print(p_cal_no_growth)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_calibration_linear.png"),     p_cal_linear,    width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_quad_mean.png"),  p_cal_quad_mean, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_quad_max.png"),   p_cal_quad_max,  width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_quad_both.png"),  p_cal_quad_both, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_sqrt_quad.png"),  p_cal_sqrt_quad, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_sqrt_mean.png"),  p_cal_sqrt_mean, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_no_road.png"),    p_cal_no_road,   width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_sqrt_no_road.png"), p_cal_sqrt_no_road, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_subset.png"),     p_cal_subset,     width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_subset_fwd.png"), p_cal_subset_fwd, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_no_growth.png"), p_cal_no_growth, width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_subset2.png"),    p_cal_subset2,    width = 6.5, height = 5.5, dpi = 300)
  ggsave(file.path(out_dir, "cv_calibration_subset_3.png"),  p_cal_subset_3,  width = 6.5, height = 5.5, dpi = 300)
}

# ============================================================
# Plot Predicted vs Residuals (LOOCV) — all models
# ============================================================
# Model 1: Linear
par(mfrow = c(5, 3), mar = c(4, 4, 2, 1))
plot(loocv_linear$pred, loocv_linear$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_linear$pred, loocv_linear$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 2: Quad - mean only
plot(loocv_quad_mean$pred, loocv_quad_mean$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_quad_mean$pred, loocv_quad_mean$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 3: Quad - max only
plot(loocv_quad_max$pred, loocv_quad_max$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_quad_max$pred, loocv_quad_max$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 4: Quad - both
plot(loocv_quad_both$pred, loocv_quad_both$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_quad_both$pred, loocv_quad_both$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 5: Sqrt + Quad
plot(loocv_sqrt_quad$pred, loocv_sqrt_quad$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_sqrt_quad$pred, loocv_sqrt_quad$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 6: Sqrt - mean only
plot(loocv_sqrt_mean$pred, loocv_sqrt_mean$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_sqrt_mean$pred, loocv_sqrt_mean$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 7: No Road/Ditch
plot(loocv_no_road$pred, loocv_no_road$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_no_road$pred, loocv_no_road$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 8: Sqrt + No Road/Ditch
plot(loocv_sqrt_no_road$pred, loocv_sqrt_no_road$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_sqrt_no_road$pred, loocv_sqrt_no_road$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 9: Subset (mean growth 1-8)
plot(loocv_subset$pred, loocv_subset$pred - df_subset$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_subset$pred, loocv_subset$pred - df_subset$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 10: Subset (FWD <= 60)
plot(loocv_subset_fwd$pred, loocv_subset_fwd$pred - df[df$FWD.avg <= 60, ]$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_subset_fwd$pred, loocv_subset_fwd$pred - df[df$FWD.avg <= 60, ]$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 11: No Growth Variables
plot(loocv_no_growth$pred, loocv_no_growth$pred - df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_no_growth$pred, loocv_no_growth$pred - df$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 12: Subset (mean growth 1-4)
plot(loocv_subset2$pred, loocv_subset2$pred - df_subset2$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_subset2$pred, loocv_subset2$pred - df_subset2$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# Model 13: Subset (mean growth 1-4 + sqrt)
plot(loocv_subset_3$pred, loocv_subset_3$pred - df_subset2$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Residuals")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
mywhiskers(loocv_subset_3$pred, loocv_subset_3$pred - df_subset2$FWD.avg, add = TRUE, se = FALSE, lwd = 3.5)
abline(h = 0, lwd = 3)

# ============================================================
# Observed vs Predicted Plots for the model using Base R
# ============================================================
# Model 1: Linear
par(mfrow = c(5, 3), mar = c(5, 5, 1, 2))
plot(loocv_linear$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_linear$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 2: Quad - mean only
plot(loocv_quad_mean$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_quad_mean$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 3: Quad - max only
plot(loocv_quad_max$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_quad_max$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 4: Quad - both
plot(loocv_quad_both$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_quad_both$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 5: Sqrt + Quad
plot(loocv_sqrt_quad$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_sqrt_quad$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 6: Sqrt - mean only
plot(loocv_sqrt_mean$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_sqrt_mean$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 7: No Road/Ditch
plot(loocv_no_road$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_no_road$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 8: Sqrt + No Road/Ditch
plot(loocv_sqrt_no_road$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_sqrt_no_road$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 9: Subset (mean growth 1-8)
plot(loocv_subset$pred, df_subset$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df_subset$FWD.avg ~ loocv_subset$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 10: Subset (FWD <= 60)
plot(loocv_subset_fwd$pred, df[df$FWD.avg <= 60, ]$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df[df$FWD.avg <= 60, ]$FWD.avg ~ loocv_subset_fwd$pred)

# Model 11: No Growth Variables
plot(loocv_no_growth$pred, df$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df$FWD.avg ~ loocv_no_growth$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 12: Subset (mean growth 1-4)
plot(loocv_subset2$pred, df_subset2$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df_subset2$FWD.avg ~ loocv_subset2$pred)
abline(lm_fit, lwd = 3, col = "black")

# Model 13: Subset (mean growth 1-4 + sqrt)
plot(loocv_subset_3$pred, df_subset2$FWD.avg,
  xlab = expression(bold("Predicted FWD (MN/m"^2*")")),
  ylab = expression(bold("Observed FWD (MN/m"^2*")")),
  pch = 1, cex = 1.5,
  cex.lab = 1,        
  cex.axis = 1,
  col = rgb(0, 0, 0, 0.4))
abline(a = 0, b = 1, lwd = 3, lty = "dashed", col = "black")
lm_fit <- lm(df_subset2$FWD.avg ~ loocv_subset_3$pred)
abline(lm_fit, lwd = 3, col = "black")


# ============================================================
# Observed vs Predicted (LOOCV) plots - Soil Group
# ============================================================
# Helper function: Faceted Observed vs Predicted (LOOCV)
make_facet_cv_plot <- function(df, pred, title) {
  ggplot(data.frame(predicted = pred, observed = df$FWD.avg, Soil = df$Soil_Group) %>%
           filter(is.finite(predicted), is.finite(observed)),
         aes(predicted, observed)) +
    geom_point(alpha = 0.9) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "black") +
    geom_smooth(method = "lm", se = TRUE, color = "black") +
    labs(title = title,
         x = expression("Predicted FWD(MN/m"^2*")"), y = expression("Observed FWD(MN/m"^2*")")) +
    facet_wrap(~ Soil) +
    theme_bw()
}

# Model 1: Linear
p_cv_soil_linear <- make_facet_cv_plot(df, loocv_linear$pred, "Observed vs Predicted — LOOCV (Linear) by Soil Group")
print(p_cv_soil_linear)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_linear.png"), p_cv_soil_linear, width = 8, height = 6, dpi = 300)}


# Model 2: Quad - mean only
p_cv_soil_quad_mean <- make_facet_cv_plot(df, loocv_quad_mean$pred, "Observed vs Predicted — LOOCV (Quad - mean only) by Soil Group")
print(p_cv_soil_quad_mean)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_quad_mean.png"), p_cv_soil_quad_mean, width = 8, height = 6, dpi = 300)}

# Model 3: Quad - max only
p_cv_soil_quad_max <- make_facet_cv_plot(df, loocv_quad_max$pred, "Observed vs Predicted — LOOCV (Quad - max only) by Soil Group")
print(p_cv_soil_quad_max)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_quad_max.png"), p_cv_soil_quad_max, width = 8, height = 6, dpi = 300)}

# Model 4: Quad - both
p_cv_soil_quad_both <- make_facet_cv_plot(df, loocv_quad_both$pred, "Observed vs Predicted — LOOCV (Quad - both) by Soil Group")
print(p_cv_soil_quad_both)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_quad_both.png"), p_cv_soil_quad_both, width = 8, height = 6, dpi = 300)}

# Model 5: Sqrt + Quad
p_cv_soil_sqrt_quad <- make_facet_cv_plot(df, loocv_sqrt_quad$pred, "")
print(p_cv_soil_sqrt_quad)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_sqrt_quad.png"), p_cv_soil_sqrt_quad, width = 8, height = 6, dpi = 300)}

# Model 6: Sqrt - mean only
p_cv_soil_sqrt_mean <- make_facet_cv_plot(df, loocv_sqrt_mean$pred, "")
print(p_cv_soil_sqrt_mean)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_sqrt_mean.png"), p_cv_soil_sqrt_mean, width = 8, height = 6, dpi = 300)}

# Model 7: No Road/Ditch
p_cv_soil_no_road <- make_facet_cv_plot(df, loocv_no_road$pred, "Observed vs Predicted — LOOCV (No Road/Ditch) by Soil Group")
print(p_cv_soil_no_road)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_no_road.png"), p_cv_soil_no_road, width = 8, height = 6, dpi = 300)}

# Model 8: Sqrt + No Road/Ditch
p_cv_soil_sqrt_no_road <- make_facet_cv_plot(df, loocv_sqrt_no_road$pred, "Observed vs Predicted — LOOCV (Sqrt + No Road/Ditch) by Soil Group")
print(p_cv_soil_sqrt_no_road)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_sqrt_no_road.png"), p_cv_soil_sqrt_no_road, width = 8, height = 6, dpi = 300)}

# Model 9: Subset (mean growth 1-8)
p_cv_soil_subset <- make_facet_cv_plot(df_subset, loocv_subset$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-8) by Soil Group")
print(p_cv_soil_subset)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_subset.png"), p_cv_soil_subset, width = 8, height = 6, dpi = 300)}

# Model 10: Subset (FWD <= 60)
p_cv_soil_subset_fwd <- make_facet_cv_plot(df[df$FWD.avg <= 60, ], loocv_subset_fwd$pred, "Observed vs Predicted — LOOCV (Subset FWD <= 60) by Soil Group")
print(p_cv_soil_subset_fwd)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_subset_fwd.png"), p_cv_soil_subset_fwd, width = 8, height = 6, dpi = 300)}

# Model 11: No Growth Variables
p_cv_soil_no_growth <- make_facet_cv_plot(df, loocv_no_growth$pred, "Observed vs Predicted — LOOCV (No Growth Variables) by Soil Group")
print(p_cv_soil_no_growth)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_no_growth.png"), p_cv_soil_no_growth, width = 8, height = 6, dpi = 300)}

# Model 12: Subset (mean growth 1-4)
p_cv_soil_subset2 <- make_facet_cv_plot(df_subset2, loocv_subset2$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-4) by Soil Group")
print(p_cv_soil_subset2)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_subset2.png"), p_cv_soil_subset2, width = 8, height = 6, dpi = 300)}

# Model 13: Subset (mean growth 1-4 + sqrt)
p_cv_soil_subset_3 <- make_facet_cv_plot(df_subset2, loocv_subset_3$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-4 + sqrt) by Soil Group")
print(p_cv_soil_subset_3)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_soil_subset_3.png"), p_cv_soil_subset_3, width = 8, height = 6, dpi = 300)}

# ============================================================
# Observed vs Predicted (LOOCV) plots - Fertility Class
# ============================================================
# Helper function: Faceted Observed vs Predicted (LOOCV) by Fertility
make_facet_cv_plot_fert <- function(df, pred, title) {
  ggplot(data.frame(predicted = pred, observed = df$FWD.avg, Fertility = df$fertility_name) %>%
           filter(is.finite(predicted), is.finite(observed)),
         aes(predicted, observed)) +
    geom_point(alpha = 0.9) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "black") +
    geom_smooth(method = "lm", se = TRUE, color = "black") +
    labs(title = title,
         x = expression("Predicted FWD(MN/m"^2*")"), y = expression("Observed FWD(MN/m"^2*")")) +
    facet_wrap(~ Fertility) +
    theme_bw()
}

# Model 1: Linear
p_cv_fert_linear <- make_facet_cv_plot_fert(df, loocv_linear$pred, "Observed vs Predicted — LOOCV (Linear) by Fertility Class")
print(p_cv_fert_linear)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_linear.png"), p_cv_fert_linear, width = 8, height = 6, dpi = 300)}

# Model 2: Quad - mean only
p_cv_fert_quad_mean <- make_facet_cv_plot_fert(df, loocv_quad_mean$pred, "Observed vs Predicted — LOOCV (Quad - mean only) by Fertility Class")
print(p_cv_fert_quad_mean)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_quad_mean.png"), p_cv_fert_quad_mean, width = 8, height = 6, dpi = 300)}

# Model 3: Quad - max only
p_cv_fert_quad_max <- make_facet_cv_plot_fert(df, loocv_quad_max$pred, "Observed vs Predicted — LOOCV (Quad - max only) by Fertility Class")
print(p_cv_fert_quad_max)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_quad_max.png"), p_cv_fert_quad_max, width = 8, height = 6, dpi = 300)}

# Model 4: Quad - both
p_cv_fert_quad_both <- make_facet_cv_plot_fert(df, loocv_quad_both$pred, "Observed vs Predicted — LOOCV (Quad - both) by Fertility Class")
print(p_cv_fert_quad_both)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_quad_both.png"), p_cv_fert_quad_both, width = 8, height = 6, dpi = 300)}

# Model 5: Sqrt + Quad
p_cv_fert_sqrt_quad <- make_facet_cv_plot_fert(df, loocv_sqrt_quad$pred, "")
print(p_cv_fert_sqrt_quad)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_sqrt_quad.png"), p_cv_fert_sqrt_quad, width = 8, height = 6, dpi = 300)}

# Model 6: Sqrt - mean only
p_cv_fert_sqrt_mean <- make_facet_cv_plot_fert(df, loocv_sqrt_mean$pred, "")
print(p_cv_fert_sqrt_mean)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_sqrt_mean.png"), p_cv_fert_sqrt_mean, width = 8, height = 6, dpi = 300)}

# Model 7: No Road/Ditch
p_cv_fert_no_road <- make_facet_cv_plot_fert(df, loocv_no_road$pred, "Observed vs Predicted — LOOCV (No Road/Ditch) by Fertility Class")
print(p_cv_fert_no_road)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_no_road.png"), p_cv_fert_no_road, width = 8, height = 6, dpi = 300)}

# Model 8: Sqrt + No Road/Ditch
p_cv_fert_sqrt_no_road <- make_facet_cv_plot_fert(df, loocv_sqrt_no_road$pred, "Observed vs Predicted — LOOCV (Sqrt + No Road/Ditch) by Fertility Class")
print(p_cv_fert_sqrt_no_road)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_sqrt_no_road.png"), p_cv_fert_sqrt_no_road, width = 8, height = 6, dpi = 300)}

# Model 9: Subset (mean growth 1-8)
p_cv_fert_subset <- make_facet_cv_plot_fert(df_subset, loocv_subset$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-8) by Fertility Class")
print(p_cv_fert_subset)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_subset.png"), p_cv_fert_subset, width = 8, height = 6, dpi = 300)}

# Model 10: Subset (FWD <= 60)
p_cv_fert_subset_fwd <- make_facet_cv_plot_fert(df[df$FWD.avg <= 60, ], loocv_subset_fwd$pred, "Observed vs Predicted — LOOCV (Subset FWD <= 60) by Fertility Class")
print(p_cv_fert_subset_fwd)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_subset_fwd.png"), p_cv_fert_subset_fwd, width = 8, height = 6, dpi = 300)}

# Model 11: No Growth Variables
p_cv_fert_no_growth <- make_facet_cv_plot_fert(df, loocv_no_growth$pred, "Observed vs Predicted — LOOCV (No Growth Variables) by Fertility Class")
print(p_cv_fert_no_growth)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_no_growth.png"), p_cv_fert_no_growth, width = 8, height = 6, dpi = 300)}

# Model 12: Subset (mean growth 1-4)
p_cv_fert_subset2 <- make_facet_cv_plot_fert(df_subset2, loocv_subset2$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-4) by Fertility Class")
print(p_cv_fert_subset2)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_subset2.png"), p_cv_fert_subset2, width = 8, height = 6, dpi = 300)}

# Model 13: Subset (mean growth 1-4 + sqrt)
p_cv_fert_subset_3 <- make_facet_cv_plot_fert(df_subset2, loocv_subset_3$pred, "Observed vs Predicted — LOOCV (Subset mean growth 1-4 + sqrt) by Fertility Class")
print(p_cv_fert_subset_3)
if (save_plots) {
  ggsave(file.path(out_dir, "cv_scatter_fert_subset_3.png"), p_cv_fert_subset_3, width = 8, height = 6, dpi = 300)}

# ============================================================

