# Functions to calculate evaluation metrics like RMSE, R2, Bias, RelBias, RRMSE,

uef_evaluation <- function(pred, obs) {
  # Calculate evaluation metrics
  rmse <- sqrt(mean((pred - obs)^2))
  r2 <- 1 - sum((pred - obs)^2) / sum((obs - mean(obs))^2)
  bias <- mean(pred - obs)
  rel_bias <- bias / mean(obs)
  rrmse <- rmse / mean(obs)
  
  # Return a list of evaluation metrics
  return(list(RMSE = rmse, R2 = r2, Bias = bias, RelBias = rel_bias, RRMSE = rrmse))
}
