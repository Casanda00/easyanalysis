# _deps.R — NOT sourced by the app.
# Exists ONLY so shinylive's dependency scanner bundles packages that are
# otherwise invisible to it because the app references them exclusively through
# requireNamespace() guards (or `pkg::fn`), which the scanner does not follow.
# Every package below HAS a WebAssembly build on repo.r-wasm.org; listing it in
# a (never-executed) library() call is what makes shinylive include it.
#
#   rstac, exactextractr : STAC search + zonal stats (spatial screens)
#   klaR                 : DA screen — LLDA (loclda), RLDA (rda)
#   kernlab              : DA screen — KDA, MMC
#   xgboost              : XGBoost screen
#   glmnet               : Linear Regression screen — Ridge / Lasso
#   mgcv                 : GAM screen
#   survival             : Survival screen
#   rpart                : Decision Tree screen
#   car                  : Linear Regression / Night-time Lights (VIF, tests)
#   lavaan               : SEM screen
#   tseries              : Time Series screen
#   trend                : Climate Trend (Mann-Kendall) screen
#   Hmisc                : Night-time Lights screen
#   BayesFactor          : Bayesian screen
#
# NOTE: heplots, ggord, mda have NO WebAssembly build — they are handled
# separately via string-indirection (see webapp_export.R .hide_nonwasm_pkgs()),
# NOT here. e1071 is already attached at boot (lidR dependency tree), so the SVM
# screen needs nothing added.
#
# The if (FALSE) means none of this ever executes.
if (FALSE) {
  library(rstac)
  library(exactextractr)
  library(writexl)   # Data screen — export the working dataset to .xlsx
  library(klaR)
  library(kernlab)
  library(xgboost)
  library(glmnet)
  library(mgcv)
  library(survival)
  library(rpart)
  library(car)
  library(lavaan)
  library(tseries)
  library(trend)
  library(Hmisc)
  library(BayesFactor)
}
