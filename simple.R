rm(list=ls())

data <- read.csv("cleaned_VMI9-NEW.xlsx_2026-06-24.csv")
names(data)
unique(data$Nutrient_class)


library(nnet)

data$Soiltype2 <- as.factor(data$Soiltype2)

model_multi_soil <- multinom(Soiltype2 ~ ih5_dm, data = data)
summary(model_multi_soil)

#- Convert
z <- summary(model_multi_soil)$coefficients / summary(model_multi_soil)$standard.errors
p <- 2 * (1 - pnorm(abs(z)))
p


###-----
classes <- unique(data$Nutrient_class)

results <- lapply(classes, function(cl) {
  data$flag <- ifelse(data$Nutrient_class == cl, 1, 0)
  model <- glm(flag ~ ih5_dm, family = binomial, data = data)
  summary(model)$coefficients
})

names(results) <- classes
results



results <- list()

for (soil in unique(data$Soiltype2)) {
  
  # Create binary variable
  data$target <- ifelse(data$Soiltype2 == soil, 1, 0)
  
  # Fit logistic model
  model <- glm(target ~ ih5_dm, data = data, family = binomial)
  
  # Predict probabilities
  probs <- predict(model, type = "response")
  
  # Convert to class predictions (threshold = 0.5)
  preds <- ifelse(probs > 0.5, 1, 0)
  
  # Confusion matrix
  TP <- sum(preds == 1 & data$target == 1)
  TN <- sum(preds == 0 & data$target == 0)
  FP <- sum(preds == 1 & data$target == 0)
  FN <- sum(preds == 0 & data$target == 1)
  
  # Metrics
  accuracy  <- (TP + TN) / (TP + TN + FP + FN)
  precision <- ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  recall    <- ifelse((TP + FN) == 0, NA, TP / (TP + FN))
  
  # Store results
  results[[soil]] <- data.frame(
    Soiltype = soil,
    Accuracy = accuracy,
    Precision = precision,
    Recall = recall
  )
}

# Combine all results
final_results <- do.call(rbind, results)

final_results


# Get unique nutrient classes
classes <- unique(data$Soiltype2)

results <- list()

for (cl in classes) {
  
  # 1. Create binary variable (one-vs-all)
  data$target <- ifelse(data$Soiltype2 == cl, 1, 0)
  
  # 2. Fit logistic regression
  model <- glm(target ~ ih5_dm + Nutrient_class + Nutrient_add, data = data, family = binomial)
  
  # 3. Predict probabilities
  probs <- predict(model, type = "response")
  
  # 4. Convert to class prediction (threshold = 0.5) (should be tunable)
  preds <- ifelse(probs > 0.2, 1, 0)
  
  # 5. Confusion matrix components
  TP <- sum(preds == 1 & data$target == 1)
  TN <- sum(preds == 0 & data$target == 0)
  FP <- sum(preds == 1 & data$target == 0)
  FN <- sum(preds == 0 & data$target == 1)
  
  # 6. Metrics
  accuracy  <- (TP + TN) / (TP + TN + FP + FN)
  precision <- ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  recall    <- ifelse((TP + FN) == 0, NA, TP / (TP + FN))
  
  # F1-score
  f1 <- ifelse(
    is.na(precision) | is.na(recall) | (precision + recall) == 0,
    NA,
    2 * (precision * recall) / (precision + recall)
  )
  
  # 7. Store results
  results[[cl]] <- data.frame(
    Class = cl,
    Accuracy = accuracy,
    Precision = precision,
    Recall = recall,
    F1 = f1
  )
}

# Combine results
final_results <- do.call(rbind, results)

final_results

library(ggplot2)

ggplot(final_results, aes(x = Class, y = F1)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  ylim(0, 1) +
  theme_minimal() +
  labs(title = "Classification performance by nutrient class")


#------
# Remove rare soil types
data_filtered <- subset(data, !Soiltype2 %in% c("Bedrock", "Stony/boulder field"))

# Drop unused factor
data_filtered$Soiltype2 <- droplevels(data_filtered$Soiltype2)

# Check remaining classes
table(data_filtered$Soiltype2)

# Run classification
soil_types <- unique(data_filtered$Soiltype2)

results <- list()

threshold <- 0.2  # keep same threshold for consistency

for (soil in soil_types) {
  
  data_filtered$target <- ifelse(data_filtered$Soiltype2 == soil, 1, 0)
  
  model <- glm(target ~ ih5_dm + Nutrient_class + Nutrient_add,
               data = data_filtered, family = binomial)
  
  probs <- predict(model, type = "response")
  preds <- ifelse(probs > threshold, 1, 0)
  
  TP <- sum(preds == 1 & data_filtered$target == 1)
  TN <- sum(preds == 0 & data_filtered$target == 0)
  FP <- sum(preds == 1 & data_filtered$target == 0)
  FN <- sum(preds == 0 & data_filtered$target == 1)
  
  accuracy  <- (TP + TN) / (TP + TN + FP + FN)
  precision <- ifelse((TP + FP) == 0, NA, TP / (TP + FP))
  recall    <- ifelse((TP + FN) == 0, NA, TP / (TP + FN))
  
  f1 <- ifelse(
    is.na(precision) | is.na(recall) | (precision + recall) == 0,
    NA,
    2 * (precision * recall) / (precision + recall)
  )
  
  results[[soil]] <- data.frame(
    Class = soil,
    Accuracy = accuracy,
    Precision = precision,
    Recall = recall,
    F1 = f1
  )
}

final_results <- do.call(rbind, results)
final_results

###------ WEIGHTED LDA
library(MASS)
data_filtered$Soiltype2 <- as.factor(data_filtered$Soiltype2)
# Inverse frequency weights
class_counts <- table(data_filtered$Soiltype2)
weights <- 1 / class_counts[data_filtered$Soiltype2]
lda_model <- lda(Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
                 data = data_filtered,
                 weights = weights)
pred <- predict(lda_model)

# predicted classes
pred_class <- pred$class
# cONFUSION MATRIX
table(Predicted = pred_class, Actual = data_filtered$Soiltype2)
# VARIABLE IMPORTANCE
lda_model$scaling
# PLOT MODEL
plot(lda_model)

### ---QDA
library(MASS)

qda_model <- qda(Soiltype2 ~ ih5_dm + Nutrient_class,
                 data = data_filtered)

pred_qda <- predict(qda_model)
pred_class <- pred_qda$class
# VARIABLE IMPORTANCE
qda_model$scaling
# Confusion matrix
table(Predicted = pred_class, Actual = data_filtered$Soiltype2)
plot(qda_model)




# Check sample size and distribution of categorical variables
#table(data_filtered$Soiltype2, data_filtered$Nutrient_class)
#table(data_filtered$Soiltype2, data_filtered$Nutrient_add)

# Check variance of continuous variables within the group
#by(data_filtered$ih5_dm, data_filtered$Soiltype2, var)

###---- REGULARIZED LINEAR DISCRIMINANT ANALYSIS (RLDA)-----
library(klaR)
rlda_model <- rda(
  Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
  data = data_filtered,
  gamma = seq(0, 1, 0.1),
  lambda = seq(0, 1, 0.1)
)
pred <- predict(rlda_model)
pred_class <- pred$class

# Confusion matrix
table(Predicted = pred_class, Actual = data_filtered$Soiltype2)
plot(rlda_model)

###--- Kernel Discriminant Analysis (KDA)----
#install.packages("kernlab")
library(kernlab)
# FIT MODEL
kda_model <- ksvm(
  Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
  data = data_filtered,
  kernel = "rbfdot",
  kpar = list(sigma = 0.01),  # controls flexibility
  C = 0.1,
  prob.model = TRUE
)
#PREDICT
pred_class <- predict(kda_model)

# Confusion matrix
table(Predicted = pred_class, Actual = data_filtered$Soiltype2)

### Locally Linear Discriminant Analysis (LLDA)----
# Remove rows where either variable is missing
data_clean <- data_filtered[!is.na(data_filtered$ih5_dm) & !is.na(data_filtered$Soiltype2), ]
data_clean$ih5_dm <- jitter(data_clean$ih5_dm, amount = 0.0001)
#MODEL
llda_model <- loclda(
  Soiltype2 ~ ih5_dm,
  data = data_clean,
  k = 5  # number of neighbors (important parameter) CAN TRY 5, 10, 20
)
# PREDICT
pred <- predict(llda_model)
pred_class <- pred$class

# Confusion matrix
table(Predicted = pred_class, Actual = data_clean$Soiltype2)

### Maximum Margin Criterion (MMC)-----
library(kernlab)
mmc_model <- ksvm(
  Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
  data = data_filtered,
  kernel = "vanilladot",   # linear kernel → maximum margin
  C = 1
)
#PREDICT
pred_class <- predict(mmc_model)

# Confusion matrix
table(Predicted = pred_class, Actual = data_filtered$Soiltype2)


############################
# NON PARAMETRIC METHODS
############################
### RANDOM FORESTS ----
library(randomForest)
rf_model <- randomForest(
  Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
  data = data_filtered,
  ntree = 1000,      # number of trees
  mtry = 2,         # variables tried at each split
  importance = TRUE
)
# PREDICTIONS
pred_class <- predict(rf_model)

table(Predicted = pred_class, Actual = data_filtered$Soiltype2)
# VARIABLE IMPORTANCE
importance(rf_model)
varImpPlot(rf_model)

### NEURAL NETWORK
library(nnet)
data_filtered$Soiltype2 <- as.factor(data_filtered$Soiltype2)
# FIT NEURAL NETWORK
nn_model <- nnet(
  Soiltype2 ~ ih5_dm + Nutrient_class + Nutrient_add,
  data = data_filtered,
  size = 5,      # number of hidden neurons
  decay = 0.01,  # regularization
  maxit = 200,
  trace = FALSE
)
# PREDICT
pred_class <- predict(nn_model, data_filtered, type = "class")

table(Predicted = pred_class, Actual = data_filtered$Soiltype2)

