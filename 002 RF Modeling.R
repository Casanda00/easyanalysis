rm(list = ls())
# dev.off()

library(randomForest)
library(caret)     # CV + confusionMatrix
library(ggplot2)
library(dplyr)
library(ggpmisc)
library(pdp)

# ---------------------------------------------------------
# 1. Load the processed data
# ---------------------------------------------------------
data <- read.csv("modeling_data.csv")
data <- data[-126, ]  # Remove one outlier in OMT (Rich)
cat("Initial data loaded:", nrow(data), "rows\n")

# Ensure factors are factors
data$Soil_Group <- as.factor(data$Soil_Group)
data$fertility_name <- as.factor(data$fertility_name)
data$Trafficability_Class <- factor(
  data$Trafficability_Class,
  levels = c("Winter", "Dry Summer", "Summer", "All-year"),
  ordered = TRUE
)

# Sample sizes
cat("\nSample size by Soil Group:\n")
print(table(data$Soil_Group))

cat("\nSample size by Fertility Class:\n")
print(table(data$fertility_name))

cat("\nSample size by Trafficability Class:\n")
print(table(data$Trafficability_Class))

# Missing values before filtering
cat("\nMissing values per column (before complete-case filtering):\n")
print(colSums(is.na(data[, c(
  "FWD.avg", "Trafficability_Class",
  "Growth_Rate_Max_Agg", "Growth_Rate_Mean_Agg",
  "Soil_Group", "fertility_name",
  "dtw_0.5mean", "roadwidth", "ditchindex",
  "tsum", "twimean", "psum"
)])))

# ---------------------------------------------------------
# 2. Define predictors
# ---------------------------------------------------------
predictors <- c(
  "Growth_Rate_Max_Agg", "Growth_Rate_Mean_Agg",
  "Soil_Group", "fertility_name",
  "roadwidth", "ditchindex",
  "tsum", "twimean", "dtw_0.5mean", "psum"
)

formula_reg <- as.formula(
  paste("FWD.avg ~", paste(predictors, collapse = " + "))
)

# ---------------------------------------------------------
# 3. Prepare complete-case dataset for RF
# ---------------------------------------------------------
model_data <- na.omit(data[, c("FWD.avg", "Trafficability_Class", predictors)])

cat("\nFinal complete-case sample size for RF:", nrow(model_data), "rows\n")

# ---------------------------------------------------------
# 4. Random Forest Regression (apparent fit)
# ---------------------------------------------------------
set.seed(123)
model_rf_reg <- randomForest(
  FWD.avg ~ .,
  data = model_data[, c("FWD.avg", predictors)],
  ntree = 1000,
  importance = TRUE
)

# Apparent predictions on the same complete-case data
model_data$Predicted <- predict(model_rf_reg, model_data)
model_data$residuals <- model_data$Predicted - model_data$FWD.avg

# Apparent regression performance
rmse_app <- sqrt(mean((model_data$Predicted - model_data$FWD.avg)^2))
mae_app  <- mean(abs(model_data$Predicted - model_data$FWD.avg))
r2_app   <- cor(model_data$Predicted, model_data$FWD.avg)^2

cat("\n=== Apparent Random Forest Regression Performance ===\n")
cat("RMSE:", round(rmse_app, 3), "\n")
cat("MAE:", round(mae_app, 3), "\n")
cat("R-squared:", round(r2_app, 3), "\n")

# ---------------------------------------------------------
# 5. Apparent classification from predicted FWD bins
#    NOTE: This is training/apparent classification, not CV.
# ---------------------------------------------------------
model_data$pred_class <- cut(
  model_data$Predicted,
  breaks = c(-Inf, 30, 50, 60, Inf),
  labels = c("Winter", "Dry Summer", "Summer", "All-year"),
  right = FALSE
)

cat("\n=== Apparent Classification Performance (from Predicted FWD Bins) ===\n")
conf_mat_app <- confusionMatrix(
  model_data$pred_class,
  model_data$Trafficability_Class,
  mode = "everything"
)
print(conf_mat_app)
cat("Overall Accuracy:", round(conf_mat_app$overall["Accuracy"], 3), "\n")

# ---------------------------------------------------------
# 6A. Stratified analysis by Soil_Group (APPARENT)
# ---------------------------------------------------------
cat("\n=== Apparent Analysis by Soil Group ===\n")

rmse_by_soil <- model_data %>%
  group_by(Soil_Group) %>%
  summarise(
    RMSE = sqrt(mean((Predicted - FWD.avg)^2)),
    MAE  = mean(abs(Predicted - FWD.avg)),
    R2   = cor(Predicted, FWD.avg)^2,
    n    = n(),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))

print(rmse_by_soil)

plot_facet_pred_soil <- ggplot(model_data, aes(x = FWD.avg, y = Predicted)) +
  geom_point(alpha = 0.5, shape = 1, color = "black") +
  geom_smooth(method = "loess", se = TRUE, color = "black", span = 0.8) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "black") +
  facet_wrap(~ Soil_Group, scales = "free") +
  stat_poly_eq(
    formula = y ~ x,
    aes(label = after_stat(rr.label)),
    parse = TRUE,
    size = 3.5,
    color = "darkgreen"
  ) +
  geom_text(
    data = rmse_by_soil,
    aes(label = paste("RMSE:", RMSE, "\nn:", n)),
    x = Inf, y = -Inf,
    hjust = 1.1, vjust = -0.5,
    size = 3.5,
    color = "darkred"
  ) +
  labs(
    title = "Predicted vs Actual FWD.avg by Soil Group",
    x = "Actual FWD.avg",
    y = "Predicted FWD.avg"
  ) +
  theme_bw(base_size = 12) +
  theme(
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold", hjust = 0.5),
    axis.title = element_text(face = "bold")
  )

print(plot_facet_pred_soil)

plot_facet_resid_soil <- ggplot(model_data, aes(x = Predicted, y = residuals)) +
  geom_point(alpha = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(se = FALSE, color = "blue") +
  facet_wrap(~ Soil_Group, scales = "free") +
  labs(
    title = "Residuals vs Predicted by Soil Group",
    x = "Predicted FWD.avg",
    y = "Residuals"
  ) +
  theme_minimal()

print(plot_facet_resid_soil)

# ---------------------------------------------------------
# 6B. Stratified analysis by fertility_name (APPARENT)
# ---------------------------------------------------------
cat("\n=== Apparent Analysis by Fertility Class ===\n")

rmse_by_fert <- model_data %>%
  group_by(fertility_name) %>%
  summarise(
    RMSE = sqrt(mean((Predicted - FWD.avg)^2)),
    MAE  = mean(abs(Predicted - FWD.avg)),
    R2   = cor(Predicted, FWD.avg)^2,
    n    = n(),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))

print(rmse_by_fert)

plot_facet_pred_fert <- ggplot(model_data, aes(x = FWD.avg, y = Predicted)) +
  geom_point(alpha = 0.6, color = "blue") +
  geom_smooth(method = "loess", se = TRUE, color = "red", span = 0.8) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "black") +
  facet_wrap(~ fertility_name, scales = "free") +
  stat_poly_eq(
    formula = y ~ x,
    aes(label = after_stat(rr.label)),
    parse = TRUE,
    size = 3.5,
    color = "darkgreen"
  ) +
  geom_text(
    data = rmse_by_fert,
    aes(label = paste("RMSE:", RMSE, "\nn:", n)),
    x = Inf, y = -Inf,
    hjust = 1.1, vjust = -0.5,
    size = 3.5,
    color = "darkred"
  ) +
  labs(
    title = "Predicted vs Actual FWD.avg by Fertility Class",
    x = "Actual FWD.avg",
    y = "Predicted FWD.avg"
  ) +
  theme_minimal()

print(plot_facet_pred_fert)

plot_facet_resid_fert <- ggplot(model_data, aes(x = Predicted, y = residuals)) +
  geom_point(alpha = 0.5, shape = 1, color = "black") +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_smooth(se = FALSE, color = "black") +
  facet_wrap(~ fertility_name, scales = "free") +
  labs(
    title = "Residuals vs Predicted by Fertility Class",
    x = "Predicted FWD.avg",
    y = "Residuals"
  ) +
  theme_bw(base_size = 12) +
  theme(
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold", hjust = 0.5),
    axis.title = element_text(face = "bold")
  )

print(plot_facet_resid_fert)

# ---------------------------------------------------------
# 7. Variable importance
# ---------------------------------------------------------
cat("\n=== Variable Importance ===\n")
imp <- importance(model_rf_reg)
print(imp)

varImpPlot(model_rf_reg, main = "")

imp_df <- as.data.frame(imp)
imp_df$Variable <- rownames(imp_df)

imp_df <- imp_df |>
  arrange(`%IncMSE`) |>
  mutate(Variable = factor(Variable, levels = Variable))

# %IncMSE plot
ggplot(imp_df, aes(x = `%IncMSE`, y = Variable)) +
  geom_col(fill = "black") +
  geom_text(aes(label = sprintf("%.1f", `%IncMSE`)),
            hjust = -0.1, size = 3.2) +
  labs(
    title = "",
    x = "% Increase in MSE",
    y = NULL
  ) +
  coord_cartesian(xlim = c(0, max(imp_df$`%IncMSE`) * 1.15)) +
  theme_minimal()

# IncNodePurity plot
ggplot(imp_df, aes(x = IncNodePurity, y = Variable)) +
  geom_col(fill = "grey50") +
  geom_text(aes(label = sprintf("%.1f", IncNodePurity)),
            hjust = -0.1, size = 3.2) +
  labs(
    title = "",
    x = "Increase in Node Purity",
    y = NULL
  ) +
  coord_cartesian(xlim = c(0, max(imp_df$IncNodePurity) * 1.15)) +
  theme_minimal()

# ---------------------------------------------------------
# 8. Partial dependence plots
# ---------------------------------------------------------
dev.off() # Resets the device
par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))

# Plot for Mean
partialPlot(
  model_rf_reg,
  pred.data = model_data[, c("FWD.avg", predictors)],
  x.var = "Growth_Rate_Mean_Agg",
  ylab = expression("Predicted FWD (MN/m"^2*")"),
  xlab = expression("Mean Growth Rate ("*i[mean]*")"),
  main = ""
)

# Plot for Max
partialPlot(
  model_rf_reg,
  pred.data = model_data[, c("FWD.avg", predictors)],
  x.var = "Growth_Rate_Max_Agg",
  ylab = expression("Predicted FWD (MN/m"^2*")"),
  xlab = expression("Max Growth Rate ("*i[max]*")"),
  main = ""
)


# By Soil_Group
soil_groups <- levels(model_data$Soil_Group)
par(mfrow = c(1, length(soil_groups)), mar = c(5, 5, 4, 2))

for (soil in soil_groups) {
  subset_data <- model_data[model_data$Soil_Group == soil, c("FWD.avg", predictors)]
  partialPlot(
    model_rf_reg,
    pred.data = subset_data,
    x.var = "Growth_Rate_Mean_Agg",
    ylab = expression("Predicted FWD (MN/m"^2*")"),
    xlab = expression("Mean Growth ("*i[max]*")"),
    main = soil
  )
}

for (soil in soil_groups) {
  subset_data <- model_data[model_data$Soil_Group == soil, c("FWD.avg", predictors)]
  partialPlot(
    model_rf_reg,
    pred.data = subset_data,
    x.var = "Growth_Rate_Max_Agg",
    ylab = expression("Predicted FWD (MN/m"^2*")"),
    xlab = expression("Max Growth ("*i[max]*")"),
    main = soil
  )
}

# By fertility_name
fertility_classes <- levels(model_data$fertility_name)
par(mfrow = c(1, length(fertility_classes)), mar = c(5, 5, 4, 2))
for (fert in fertility_classes) {
  subset_data <- model_data[model_data$fertility_name == fert, c("FWD.avg", predictors)]
  partialPlot(
    model_rf_reg,
    pred.data = subset_data,
    x.var = "Growth_Rate_Max_Agg",
    ylab = expression("Predicted FWD (MN/m"^2*")"),
    xlab = expression("Max Growth ("*i[max]*")"),
    main = paste(fert)
  )
}

for (fert in fertility_classes) {
  subset_data <- model_data[model_data$fertility_name == fert, c("FWD.avg", predictors)]
  partialPlot(
    model_rf_reg,
    pred.data = subset_data,
    x.var = "Growth_Rate_Mean_Agg",
    ylab = expression("Predicted FWD (MN/m"^2*")"),
    xlab = expression("Mean Growth ("*i[max]*")"),
    main = paste(fert)
  )
}

# ---------------------------------------------------------
# 9. 10-fold CV RF regression (MAIN VALIDATION)
# ---------------------------------------------------------
ctrl <- trainControl(method = "cv", number = 10)

set.seed(123)
model_rf_reg_cv <- train(
  formula_reg,
  data = model_data[, c("FWD.avg", predictors)],
  method = "rf",
  trControl = ctrl,
  tuneLength = 5
)

cat("\n=== 10-fold CV Random Forest Regression Results ===\n")
print(model_rf_reg_cv)

# Plot CV RMSE across mtry
cv_res <- model_rf_reg_cv$results

ggplot(cv_res, aes(x = mtry, y = RMSE)) +
  geom_line(color = "blue") +
  geom_point(size = 3, color = "red") +
  labs(
    title = "10-fold CV RMSE Across mtry Values",
    x = "mtry",
    y = "RMSE"
  ) +
  theme_minimal()

# ---------------------------------------------------------
# 10. 10-fold CV classification from out-of-fold RF predictions
# ---------------------------------------------------------
cat("\n=== 10-fold CV Classification Performance ===\n")

set.seed(123)
folds <- createFolds(model_data$FWD.avg, k = 10, returnTrain = FALSE)

oof_pred <- rep(NA_real_, nrow(model_data))

for (i in seq_along(folds)) {
  test_idx <- folds[[i]]
  train_idx <- setdiff(seq_len(nrow(model_data)), test_idx)
  
  fold_model <- randomForest(
    FWD.avg ~ .,
    data = model_data[train_idx, c("FWD.avg", predictors)],
    ntree = 1000,
    importance = FALSE
  )
  
  oof_pred[test_idx] <- predict(fold_model, model_data[test_idx, predictors])
}

model_data$oof_pred <- oof_pred
model_data$oof_class <- cut(
  model_data$oof_pred,
  breaks = c(-Inf, 30, 50, 60, Inf),
  labels = c("Winter", "Dry Summer", "Summer", "All-year"),
  right = FALSE
)

cv_conf_mat <- confusionMatrix(
  model_data$oof_class,
  model_data$Trafficability_Class,
  mode = "everything"
)

print(cv_conf_mat)
cat("CV Overall Accuracy:", round(cv_conf_mat$overall["Accuracy"], 3), "\n")

# Confusion matrix heatmap
cf <- as.data.frame(cv_conf_mat$table)
colnames(cf) <- c("Prediction", "Reference", "Freq")

ggplot(cf, aes(x = Reference, y = Prediction, fill = Freq)) +
  geom_tile(color = "black") +
  geom_text(aes(label = Freq), size = 4) +
  scale_fill_gradient(low = "#f7fbff", high = "#08306b") +
  labs(
    title = "10-fold Cross-validated Confusion Matrix",
    x = "Observed Class",
    y = "Predicted Class",
    fill = "Count"
  ) +
  theme_minimal(base_size = 12)

# CV performance metrics by Soil_Group
cv_by_soil <- model_data %>%
  group_by(Soil_Group) %>%
  summarise(
    n = n(),
    RMSE_CV = sqrt(mean((oof_pred - FWD.avg)^2, na.rm = TRUE)),
    MAE_CV  = mean(abs(oof_pred - FWD.avg), na.rm = TRUE),
    R2_CV   = cor(oof_pred, FWD.avg, use = "complete.obs")^2,
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))

# CV performance metrics by fertility_name
cv_by_fert <- model_data %>%
  group_by(fertility_name) %>%
  summarise(
    n = n(),
    RMSE_CV = sqrt(mean((oof_pred - FWD.avg)^2, na.rm = TRUE)),
    MAE_CV  = mean(abs(oof_pred - FWD.avg), na.rm = TRUE),
    R2_CV   = cor(oof_pred, FWD.avg, use = "complete.obs")^2,
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))

print(cv_by_fert)

print(cv_by_soil)




# ---------------------------------------------------------
# 11. Optional: save model
# ---------------------------------------------------------
# saveRDS(model_rf_reg, file = "final_rf_regression_model.rds")
# cat("\nModel saved.\n")

