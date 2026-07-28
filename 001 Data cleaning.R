rm(list = ls())

# 1. Load Data
data <- read.csv("Thesis_data.csv")

# 2. Create Subsets
parents <- subset(data, Point_type == 'field_data')
lefts   <- subset(data, Point_type == 'offset' & SIDE == 'left')
rights  <- subset(data, Point_type == 'offset' & SIDE == 'right')

# 3. Match Indices (Link Parents to Children)
match_l <- match(parents$NEW_ID, lefts$NEW_ID)
match_r <- match(parents$NEW_ID, rights$NEW_ID)

# ---------------------------------------------------------
# 4. TRAFFICABILITY CLASSES
# ---------------------------------------------------------
parents$Trafficability_Class <- cut(parents$FWD.avg,
                                    breaks = c(-Inf, 30, 50, 60, Inf),
                                    labels = c("Winter", "Dry Summer", "Summer", "All-year"),
                                    right = FALSE)

# ---------------------------------------------------------
# 5. TREE DATA TRANSFER
# ---------------------------------------------------------
# Growth_Rate_Max (Differential max)
g_max_left <- lefts$dCHM_max[match_l]
g_max_right <- rights$dCHM_max[match_r]
parents$Growth_Rate_Max_Agg <- rowMeans(cbind(g_max_left, g_max_right), na.rm = TRUE)

# Growth_Rate_Mean (Differential mean)
g_mean_left <- lefts$dCHM_mean[match_l]
g_mean_right <- rights$dCHM_mean[match_r]
parents$Growth_Rate_Mean_Agg <- rowMeans(cbind(g_mean_left, g_mean_right), na.rm = TRUE)

# ---------------------------------------------------------
# 6. CATEGORICAL TRANSFER (Priority: Left > Right > Parent)
# ---------------------------------------------------------
# Soil Type
final_soil <- lefts$soiltype[match_l]
final_soil[is.na(final_soil)] <- rights$soiltype[match_r][is.na(final_soil)]
final_soil[is.na(final_soil)] <- parents$soiltype[is.na(final_soil)]
parents$soiltype <- final_soil

# Fertility Class
final_fert <- lefts$fertilityclass[match_l]
final_fert[is.na(final_fert)] <- rights$fertilityclass[match_r][is.na(final_fert)]
final_fert[is.na(final_fert)] <- parents$fertilityclass[is.na(final_fert)]
parents$fertilityclass <- final_fert

# Tree Species
final_species <- lefts$treespecies[match_l]
final_species[is.na(final_species)] <- rights$treespecies[match_r][is.na(final_species)]
final_species[is.na(final_species)] <- parents$treespecies[is.na(final_species)]
parents$treespecies <- final_species

# ---------------------------------------------------------
# 6b. MAPPING CODES TO NAMES
# ---------------------------------------------------------
soil_names <- c(
  "10" = "Medium-coarse/coarse mineral",
  "11" = "Coarse till",
  "12" = "Coarse sorted sediment",
  "20" = "Fine-textured mineral",
  "21" = "Fine-grained till",
  "30" = "Stony mineral",
  "60" = "Peatland",
  "61" = "Sedge peat",
  "62" = "Sphagnum peat"
)
parents$soiltype_name <- soil_names[as.character(parents$soiltype)]
parents$soiltype_name[is.na(parents$soiltype_name)] <- "Unknown"

fert_names <- c(
  "2" = "OMT (Rich)",
  "3" = "MT (Medium)",
  "4" = "VT (Dryish)",
  "5" = "CT (Dry)",
  "6" = "CIT (Barren)"
)
parents$fertility_name <- fert_names[as.character(parents$fertilityclass)]
parents$fertility_name[is.na(parents$fertility_name)] <- "Unknown"

# Tree species mapping (added)
tree_names <- c(
  "1"  = "Scots pine",
  "2"  = "Norway spruce",
  "3"  = "Silver birch",
  "29" = "Broadleaved tree"
)
parents$treespecies_name <- tree_names[as.character(parents$treespecies)]
parents$treespecies_name[is.na(parents$treespecies_name)] <- "Unknown"

# ---------------------------------------------------------
# 7. NEW: Create analysis-ready grouping variables
# ---------------------------------------------------------
# Soil grouping (same logic as in RF/modeling scripts)
parents$soiltype_name <- as.factor(parents$soiltype_name)

parents$Soil_Group <- "Other"
peat_group   <- c("Peatland", "Sedge peat", "Sphagnum peat")
fine_group   <- c("Fine-textured mineral", "Fine-grained till")
coarse_group <- c("Medium-coarse/coarse mineral", "Coarse till",
                  "Coarse sorted sediment", "Stony mineral")

parents$Soil_Group[parents$soiltype_name %in% peat_group]   <- "Peatland"
parents$Soil_Group[parents$soiltype_name %in% fine_group]   <- "Fine Mineral"
parents$Soil_Group[parents$soiltype_name %in% coarse_group] <- "Coarse Mineral"
parents$Soil_Group <- as.factor(parents$Soil_Group)

# Road identifier (Takes only the integer part from the NEW_ID of the parents.)
parents$Road_ID <- as.numeric(sub("\\..*$", "", parents$NEW_ID))

# ---------------------------------------------------------
# 8. FINAL OUTPUT
# ---------------------------------------------------------
datasets <- c(
  "NEW_ID",
  "Road_ID",                   
  "Trafficability_Class",
  "FWD.avg",
  "Growth_Rate_Max_Agg",   #imax
  "Growth_Rate_Mean_Agg",  #imean
  "Soil_Group",               
  "soiltype_name",
  "fertility_name",
  "treespecies",               # original code kept
  "treespecies_name",          # ← new human-readable name
  "roadwidth",
  "ditchindex",
  "tsum",
  "twimean",
  "dtw_0.5mean",
  "psum"                      
)

final <- parents[, datasets]

# Optional: Drop rows with NA in key columns (uncomment for strict cleaning)
# final <- na.omit(final)

write.csv(final, "modeling_data.csv", row.names = FALSE)

# Summary print
cat("Cleaning complete. Output saved to: modeling_data.csv\n")
cat("Rows in final dataset:", nrow(final), "\n")
cat("Columns:", paste(colnames(final), collapse = ", "), "\n")

# Quick check of the new column
cat("\nTree species distribution:\n")
print(table(final$treespecies_name, useNA = "ifany"))