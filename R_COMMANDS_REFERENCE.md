# R Data Manipulation & Processing Commands Reference

This document provides a breakdown of 100 R data engineering, spatial, and analytical commands in **SimpleAnalysis**, explicitly distinguishing between **pre-existing tools** in the codebase and **newly added/refined tools** introduced in Round 3.

---

## 📌 Summary Breakdown

- 🆕 **Newly Added / Refined in Round 3**: `add_col` (constant, index, formula, scale, log), `remove_rows` (NAs, condition, index range), `remove_cols`, `transform_col` (log, z-score, min-max normalize, sqrt, abs), and R Console `on_data_change` real-time sync.
- ⚡ **Pre-Existing Built-in Tools**: `keep_cols`, `drop_cols`, `rename_col`, `mutate`, `filter`, `convert`, `rename_lvl`, `merge_lvl`, `delete_lvl`, `aggregate`, `bin`, `impute`, `join`, `batch`, `lm`, `lme`, `anova`, `logistic`, `rf`, `clustering`, `pca`, `dtm`, `dsm`, `chm`, `ndsm`, `itd`, `ndvi`, `ndwi`, `nbr`, `zonal_stats`, `buffer`, `dissolve`, `centroids`, etc.
- 💻 **R Console / Core Expressions**: Native R commands executable directly on the active dataset (`df`) with immediate reactive UI refresh.

---

## 1. Column & Feature Engineering Commands (1–15)

1. **Keep Columns (`keep_cols`)** `[Pre-existing]`
   - **R Code**: `df <- df[, c("col1", "col2")]`
   - **Description**: Subsets dataset to retain selected columns.

2. **Remove Columns (`remove_cols` / `drop_cols`)** `[Pre-existing / Refined]`
   - **R Code**: `df <- df[, !(names(df) %in% c("col1", "col2"))]`
   - **Description**: Removes selected columns from the dataset.

3. **Rename Column (`rename_col`)** `[Pre-existing]`
   - **R Code**: `names(df)[names(df) == "old_name"] <- "new_name"`
   - **Description**: Renames target column.

4. **Add Column (`add_col`)** `[Newly Added in Round 3]`
   - **R Code**: `df$new_col <- value` (supports formula, constant, index, log, scale)
   - **Description**: Point-and-click tool to add derived or custom columns.

5. **Filter Rows (`filter`)** `[Pre-existing]`
   - **R Code**: `df <- df[df$val > 10, ]`
   - **Description**: Filters rows based on numeric or categorical conditions.

6. **Remove Rows (`remove_rows`)** `[Newly Added in Round 3]`
   - **R Code**: `df <- df[!is.na(df$col), ]` (or condition / index range)
   - **Description**: Dedicated tool to remove rows by NA, condition, or index range.

7. **Transform Column (`transform_col`)** `[Newly Added in Round 3]`
   - **R Code**: `df$col_log <- log(df$col + 1)`
   - **Description**: Applies log, z-score, min-max normalize, sqrt, or absolute value transforms.

8. **Z-Score Standardization (`transform_col` - zscore)** `[Newly Added in Round 3]`
   - **R Code**: `df$col_z <- scale(df$col)`
   - **Description**: Standardizes column to mean 0 and SD 1.

9. **Min-Max Normalization (`transform_col` - minmax)** `[Newly Added in Round 3]`
   - **R Code**: `df$col_norm <- (df$col - min(df$col, na.rm=T)) / (max(df$col, na.rm=T) - min(df$col, na.rm=T))`
   - **Description**: Rescales numeric values to range [0, 1].

10. **Square Root Transform (`transform_col` - sqrt)** `[Newly Added in Round 3]`
    - **R Code**: `df$col_sqrt <- sqrt(pmax(0, df$col, na.rm=T))`
    - **Description**: Applies square root transform.

11. **Absolute Value (`transform_col` - abs)** `[Newly Added in Round 3]`
    - **R Code**: `df$col_abs <- abs(df$col)`
    - **Description**: Converts numeric values to non-negative absolute values.

12. **Bin Numeric Variable (`bin`)** `[Pre-existing]`
    - **R Code**: `df$binned <- cut(df$col, breaks = c(-Inf, 30, 50, Inf))`
    - **Description**: Discretizes numeric variable into categorical classes.

13. **Cumulative Sum** `[R Console / Core]`
    - **R Code**: `df$cumsum_val <- cumsum(df$col)`
    - **Description**: Computes running cumulative sum down a column.

14. **Percentage of Total** `[R Console / Core]`
    - **R Code**: `df$pct_total <- (df$col / sum(df$col, na.rm=TRUE)) * 100`
    - **Description**: Calculates percentage contribution to total.

15. **Lag / Lead Shift** `[R Console / Core]`
    - **R Code**: `df$lag_val <- c(NA, head(df$col, -1))`
    - **Description**: Shifts column values by 1 step.

---

## 2. Row Filtering & Subsetting Commands (16–30)

16. **Remove Rows Tool (`remove_rows`)** `[Newly Added in Round 3]`
    - **R Code**: `df <- df[!is.na(df$col), ]` (or condition / indices)
    - **Description**: Dedicated tool to remove rows by NA, condition, or index range.

17. **Filter Rows (`filter`)** `[Pre-existing]`
    - **R Code**: `df <- df[df$val > 10, ]`
    - **Description**: Filters rows based on numeric or categorical conditions.

18. **Remove Duplicate Rows (`remove_duplicates`)** `[R Console / Core]`
    - **R Code**: `df <- df[!duplicated(df), ]`
    - **Description**: Removes exact duplicate rows.

19. **Remove Outliers (|Z| > 3)** `[R Console / Core]`
    - **R Code**: `df <- df[abs(scale(df$col)) <= 3, ]`
    - **Description**: Filters out numeric outliers.

20. **Random Sampling (`sample_n`)** `[R Console / Core]`
    - **R Code**: `df <- df[sample(nrow(df), 100), ]`
    - **Description**: Extracts random sample of N rows.

21. **Head Subsetting (`head`)** `[R Console / Core]`
    - **R Code**: `df <- head(df, 50)`
    - **Description**: Retains first N rows.

22. **Tail Subsetting (`tail`)** `[R Console / Core]`
    - **R Code**: `df <- tail(df, 50)`
    - **Description**: Retains last N rows.

23. **Filter Non-Zero** `[R Console / Core]`
    - **R Code**: `df <- df[df$col != 0, ]`
    - **Description**: Removes zero-valued rows.

24. **Filter Positive Numbers** `[R Console / Core]`
    - **R Code**: `df <- df[df$col > 0, ]`
    - **Description**: Keeps strictly positive values.

25. **String Regex Filter** `[R Console / Core]`
    - **R Code**: `df <- df[grepl("pattern", df$str_col), ]`
    - **Description**: Filters text rows matching regular expression.

26. **Complete Cases Subset** `[R Console / Core]`
    - **R Code**: `df <- df[complete.cases(df), ]`
    - **Description**: Subsets complete rows without NAs.

27. **Filter Categorical Match** `[Pre-existing]`
    - **R Code**: `df <- df[df$cat %in% c("A", "B"), ]`
    - **Description**: Subsets specific categorical categories.

28. **Filter Categorical Exclude** `[Pre-existing]`
    - **R Code**: `df <- df[!(df$cat %in% c("Ex1", "Ex2")), ]`
    - **Description**: Excludes specific categories.

29. **Remove Rows by Index Range (`remove_rows` - indices)** `[Newly Added in Round 3]`
    - **R Code**: `df <- df[-c(1:5, 10), ]`
    - **Description**: Removes rows by index range e.g. `1:5, 10`.

30. **Remove NAs in Selected Column (`remove_rows` - na_col)** `[Newly Added in Round 3]`
    - **R Code**: `df <- df[!is.na(df[[col]]), ]`
    - **Description**: Removes rows where target column is NA.

---

## 3. Data Type Conversions (31–40)

31. **Convert to Numeric (`convert` - num)** `[Pre-existing]`
    - **R Code**: `df$col <- as.numeric(as.character(df$col))`
    - **Description**: Coerces column to numeric type.

32. **Convert to Factor/Categorical (`convert` - cat)** `[Pre-existing]`
    - **R Code**: `df$col <- as.factor(df$col)`
    - **Description**: Converts column to factor.

33. **Convert to Character** `[R Console / Core]`
    - **R Code**: `df$col <- as.character(df$col)`
    - **Description**: Converts column to text character string.

34. **Convert to Date** `[R Console / Core]`
    - **R Code**: `df$col <- as.Date(df$col)`
    - **Description**: Converts column to Date object.

35. **Convert to Integer** `[R Console / Core]`
    - **R Code**: `df$col <- as.integer(df$col)`
    - **Description**: Converts floats to integer values.

36. **Convert to Logical** `[R Console / Core]`
    - **R Code**: `df$col <- as.logical(df$col)`
    - **Description**: Converts values to Boolean TRUE/FALSE.

37. **Ordered Factor Conversion** `[R Console / Core]`
    - **R Code**: `df$col <- factor(df$col, levels = c("L", "M", "H"), ordered = TRUE)`
    - **Description**: Converts text to ordered factor.

38. **Trim String Whitespace** `[R Console / Core]`
    - **R Code**: `df$col <- trimws(df$col)`
    - **Description**: Trims leading/trailing spaces.

39. **Uppercase Text** `[R Console / Core]`
    - **R Code**: `df$col <- toupper(df$col)`
    - **Description**: Converts text to uppercase.

40. **Lowercase Text** `[R Console / Core]`
    - **R Code**: `df$col <- tolower(df$col)`
    - **Description**: Converts text to lowercase.

---

## 4. Missing Values & Imputation (41–50)

41. **Impute with Secondary Column (`impute` - coalesce)** `[Pre-existing]`
    - **R Code**: `df$col1[is.na(df$col1)] <- df$col2[is.na(df$col1)]`
    - **Description**: Fills missing values from a secondary source column.

42. **Impute with Mean (`impute` - mean)** `[Newly Added in Round 3]`
    - **R Code**: `df$col[is.na(df$col)] <- mean(df$col, na.rm = TRUE)`
    - **Description**: Fills NAs with column mean.

43. **Impute with Median (`impute` - median)** `[Newly Added in Round 3]`
    - **R Code**: `df$col[is.na(df$col)] <- median(df$col, na.rm = TRUE)`
    - **Description**: Fills NAs with column median.

44. **Impute with Constant Zero** `[R Console / Core]`
    - **R Code**: `df$col[is.na(df$col)] <- 0`
    - **Description**: Fills NAs with 0.

45. **Forward Fill (LOCF)** `[R Console / Core]`
    - **R Code**: `df$col <- zoo::na.locf(df$col, na.rm = FALSE)`
    - **Description**: Propagates last known value.

46. **Backward Fill (NOCB)** `[R Console / Core]`
    - **R Code**: `df$col <- zoo::na.locf(df$col, fromLast = TRUE, na.rm = FALSE)`
    - **Description**: Propagates next known value backward.

47. **Flag Missing Indicator** `[R Console / Core]`
    - **R Code**: `df$col_na <- as.integer(is.na(df$col))`
    - **Description**: Creates 1/0 missing flag column.

48. **Replace Empty Strings with NA** `[R Console / Core]`
    - **R Code**: `df$col[trimws(df$col) == ""] <- NA`
    - **Description**: Converts blank strings to NA.

49. **Replace Inf with NA** `[R Console / Core]`
    - **R Code**: `df$col[is.infinite(df$col)] <- NA`
    - **Description**: Replaces Inf/-Inf with NA.

50. **Drop Empty NA Columns** `[R Console / Core]`
    - **R Code**: `df <- df[, sapply(df, function(x) !all(is.na(x)))]`
    - **Description**: Drops columns containing only NAs.

---

## 5. Factor & Level Management (51–60)

51. **Rename Factor Levels (`rename_lvl`)** `[Pre-existing]`
    - **R Code**: `levels(df$col)[levels(df$col) == "Old"] <- "New"`
    - **Description**: Renames factor level labels.

52. **Merge Factor Levels (`merge_lvl`)** `[Pre-existing]`
    - **R Code**: `levels(df$col)[levels(df$col) %in% c("A", "B")] <- "Combined"`
    - **Description**: Merges factor categories.

53. **Delete Factor Levels (`delete_lvl`)** `[Pre-existing]`
    - **R Code**: `df <- df[!(df$col %in% c("Level")), ]; df$col <- droplevels(df$col)`
    - **Description**: Deletes factor level and rows.

54. **Drop Unused Levels (`droplevels`)** `[R Console / Core]`
    - **R Code**: `df$col <- droplevels(df$col)`
    - **Description**: Cleans up unused levels.

55. **Reorder Levels by Frequency** `[R Console / Core]`
    - **R Code**: `df$col <- reorder(df$col, df$col, FUN = length)`
    - **Description**: Orders levels by frequency.

56. **Recode Factor Values** `[R Console / Core]`
    - **R Code**: `df$col <- dplyr::recode(df$col, "Old"="New")`
    - **Description**: Re-maps factor levels.

57. **Top-N Levels & Other** `[R Console / Core]`
    - **R Code**: `df$col <- forcats::fct_lump(df$col, n = 5)`
    - **Description**: Keeps top N levels, lumps rest into Other.

58. **Reverse Factor Order** `[R Console / Core]`
    - **R Code**: `df$col <- factor(df$col, levels = rev(levels(df$col)))`
    - **Description**: Reverses level order.

59. **Collapse Rare Levels (< 1%)** `[R Console / Core]`
    - **R Code**: `df$col <- forcats::fct_lump_prop(df$col, prop = 0.01)`
    - **Description**: Collapses rare categories.

60. **Factor Level to Integer** `[R Console / Core]`
    - **R Code**: `df$col_code <- as.integer(df$col)`
    - **Description**: Converts factor levels to integers.

---

## 6. Aggregation & Group Summaries (61–70)

61. **Aggregate Group Means (`aggregate` - mean)** `[Pre-existing]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = mean)`
    - **Description**: Computes group averages.

62. **Aggregate Group Sums (`aggregate` - sum)** `[Pre-existing]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = sum)`
    - **Description**: Computes group totals.

63. **Aggregate Group Medians (`aggregate` - median)** `[Pre-existing]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = median)`
    - **Description**: Computes group medians.

64. **Aggregate Group Min/Max (`aggregate` - min/max)** `[Pre-existing]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = min)`
    - **Description**: Computes group minimum/maximum.

65. **Frequency Count Table (`table`)** `[R Console / Core]`
    - **R Code**: `as.data.frame(table(df$cat))`
    - **Description**: Generates category frequency table.

66. **2-Way Cross-Tabulation (`crosstab`)** `[R Console / Core]`
    - **R Code**: `as.data.frame(table(df$cat1, df$cat2))`
    - **Description**: Two-way contingency table.

67. **Correlation Matrix (`cor`)** `[R Console / Core]`
    - **R Code**: `cor(df[sapply(df, is.numeric)], use = "pairwise.complete.obs")`
    - **Description**: Pearson correlation matrix.

68. **Group Standard Deviation** `[R Console / Core]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = sd)`
    - **Description**: Group standard deviation.

69. **Group Row Count** `[R Console / Core]`
    - **R Code**: `aggregate(. ~ group, data = df, FUN = length)`
    - **Description**: Group observation count.

70. **Weighted Average** `[R Console / Core]`
    - **R Code**: `weighted.mean(df$val, df$weight, na.rm = TRUE)`
    - **Description**: Weighted average calculation.

---

## 7. Dataset Reshaping & Joins (71–80)

71. **Left Join (`join` - left)** `[Pre-existing]`
    - **R Code**: `merge(df1, df2, by = "id", all.x = TRUE)`
    - **Description**: Left outer join.

72. **Inner Join (`join` - inner)** `[Pre-existing]`
    - **R Code**: `merge(df1, df2, by = "id", all = FALSE)`
    - **Description**: Inner join.

73. **Full Outer Join (`join` - full)** `[Pre-existing]`
    - **R Code**: `merge(df1, df2, by = "id", all = TRUE)`
    - **Description**: Full outer join.

74. **Right Join (`join` - right)** `[Pre-existing]`
    - **R Code**: `merge(df1, df2, by = "id", all.y = TRUE)`
    - **Description**: Right outer join.

75. **Row Bind (`rbind`)** `[R Console / Core]`
    - **R Code**: `rbind(df1, df2)`
    - **Description**: Vertical dataset concatenation.

76. **Column Bind (`cbind`)** `[R Console / Core]`
    - **R Code**: `cbind(df1, df2)`
    - **Description**: Horizontal dataset combination.

77. **Transpose Matrix (`t`)** `[R Console / Core]`
    - **R Code**: `as.data.frame(t(df))`
    - **Description**: Flips rows and columns.

78. **Pivot Wide to Long** `[R Console / Core]`
    - **R Code**: `reshape(df, direction = "long", ...)`
    - **Description**: Reshapes wide table to long format.

79. **Pivot Long to Wide** `[R Console / Core]`
    - **R Code**: `reshape(df, direction = "wide", ...)`
    - **Description**: Reshapes long table to wide format.

80. **Batch Apply Processing (`batch`)** `[Pre-existing]`
    - **R Code**: `lapply(target_datasets, function(n) apply_pipeline(dataset_pool[[n]]))`
    - **Description**: Applies cleaning pipeline across datasets.

---

## 8. Spatial & Remote Sensing Operations (81–90)

81. **XY Coordinates to Point Layer (`xy_to_sf`)** `[Newly Added / Planned]`
    - **R Code**: `sf::st_as_sf(df, coords = c("X", "Y"), crs = 4326)`
    - **Description**: Converts coordinate columns into spatial point layer.

82. **Vector Buffer (`algo_buffer`)** `[Pre-existing]`
    - **R Code**: `sf::st_buffer(vec_sf, dist = 100)`
    - **Description**: Buffer geometry creation.

83. **Vector Dissolve (`algo_dissolve`)** `[Pre-existing]`
    - **R Code**: `sf::st_union(vec_sf)`
    - **Description**: Geometry dissolve.

84. **Vector Centroids (`algo_centroids`)** `[Pre-existing]`
    - **R Code**: `sf::st_centroid(vec_sf)`
    - **Description**: Centroid point calculation.

85. **Raster Clip (`algo_raster_clip`)** `[Pre-existing]`
    - **R Code**: `terra::crop(rast, vec_sf) |> terra::mask(vec_sf)`
    - **Description**: Raster spatial clipping.

86. **Raster Reproject (`algo_reproject`)** `[Pre-existing]`
    - **R Code**: `terra::project(rast, "EPSG:3067")`
    - **Description**: Raster CRS reprojection.

87. **NDVI Calculation (`algo_ndvi`)** `[Pre-existing]`
    - **R Code**: `(nir - red) / (nir + red)`
    - **Description**: Normalized Difference Vegetation Index.

88. **NDWI Calculation (`algo_ndwi`)** `[Pre-existing]`
    - **R Code**: `(green - nir) / (green + nir)`
    - **Description**: Normalized Difference Water Index.

89. **NBR Calculation (`algo_nbr`)** `[Pre-existing]`
    - **R Code**: `(nir - swir2) / (nir + swir2)`
    - **Description**: Normalized Burn Ratio.

90. **Zonal Statistics (`algo_zonal_stats`)** `[Pre-existing]`
    - **R Code**: `exactextractr::exact_extract(rast, vec_sf, "mean")`
    - **Description**: Raster zonal statistics by polygon.

---

## 9. LiDAR & Surface Processing (91–95)

91. **Digital Terrain Model (`algo_dtm`)** `[Pre-existing]`
    - **R Code**: `lidR::rasterize_terrain(las, res = 1, algorithm = lidR::tin())`
    - **Description**: Bare-earth elevation interpolation.

92. **Canopy Height Model (`algo_chm`)** `[Pre-existing]`
    - **R Code**: `lidR::rasterize_canopy(las, res = 0.5, algorithm = lidR::p2r())`
    - **Description**: Canopy height surface generation.

93. **Height Normalization (`algo_normalize_height`)** `[Pre-existing]`
    - **R Code**: `lidR::normalize_height(las, dtm)`
    - **Description**: Elevation normalization of point cloud.

94. **Individual Tree Detection (`algo_itd`)** `[Pre-existing]`
    - **R Code**: `lidR::locate_trees(chm, algorithm = lidR::lmf(ws = 3))`
    - **Description**: Tree crown detection.

95. **LiDAR Metric Extraction (`algo_lidar_metrics`)** `[Pre-existing]`
    - **R Code**: `lidR::pixel_metrics(las, ~list(mean_z = mean(Z), p95 = quantile(Z, 0.95)), res = 10)`
    - **Description**: Structural canopy metric extraction.

---

## 10. Statistical Modeling & Machine Learning (96–100)

96. **Linear Regression (`mod_linear_regression`)** `[Pre-existing]`
    - **R Code**: `lm(y ~ x1 + x2, data = df)`
    - **Description**: OLS linear model fitting.

97. **Linear Mixed Effects (`mod_lme`)** `[Pre-existing]`
    - **R Code**: `nlme::lme(y ~ x1, random = ~1|group, data = df)`
    - **Description**: Mixed-effects model fitting.

98. **Random Forest (`mod_rf`)** `[Pre-existing]`
    - **R Code**: `randomForest::randomForest(y ~ ., data = df, ntree = 500)`
    - **Description**: Random forest classification/regression.

99. **K-Means Clustering (`mod_clustering`)** `[Pre-existing]`
    - **R Code**: `kmeans(scale(df[sapply(df, is.numeric)]), centers = 3)`
    - **Description**: K-means clustering.

100. **Principal Component Analysis (`mod_pca`)** `[Pre-existing]`
     - **R Code**: `prcomp(df[sapply(df, is.numeric)], scale. = TRUE)`
     - **Description**: PCA feature reduction.
