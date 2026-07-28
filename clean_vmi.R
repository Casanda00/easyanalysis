# ==============================================================================
# FUNCTION 1: DATA CLEANING & AGGREGATION
# ==============================================================================
clean_data <- function(vmi_dataframe) {
  
  # 1. DYNAMICALLY FIND AND RENAME THE ID COLUMN
  id_col_index <- grep("final_id", names(vmi_dataframe), ignore.case = TRUE)
  if (length(id_col_index) > 0) {
    names(vmi_dataframe)[id_col_index[1]] <- "final_id"
  } else {
    warning("Could not find any column containing 'final_id'.")
  }
  
  # 2. Define all possible variables we care about
  target_vars <- c("ih5_dm", "id5_dm", "Soil_c", "Soil_add", "Soil_ch", "Maintype", 
                   "Mixed", "Nutrient_class", "Nutrient_add", "Soiltype2", "Texture",
                   "Organisc_quality", "Organic_depth", "Soil_Depth", "Stones", "Ditches", "final_id")
  
  available_vars <- intersect(target_vars, names(vmi_dataframe))
  data <- vmi_dataframe[, available_vars, drop = FALSE]
  
  # 3. Identify categorical variables
  categorical_vars <- c("Soil_c", "Soil_add", "Soil_ch", "Maintype", 
                        "Mixed", "Nutrient_class", "Nutrient_add", "Soiltype2", "Texture",
                        "Organisc_quality", "Organic_depth", "Soil_Depth", "Stones", "Ditches")
  available_factors <- intersect(categorical_vars, names(data))
  
  if (length(available_factors) > 0) {
    data[available_factors] <- lapply(data[available_factors], as.factor)
  }
  
  # 4. Aggregate metrics per final ID
  if (all(c("final_id", "ih5_dm", "id5_dm") %in% names(data))) {
    aggregate_data <- aggregate(cbind(ih5_dm, id5_dm) ~ final_id, data = data, FUN = mean)
    add_categories <- unique(data[, c("final_id", available_factors), drop = FALSE])
    data <- merge(aggregate_data, add_categories, by = "final_id")
  }
  
  # 5. DYNAMICALLY ADD LABELS
  if ("Soil_c" %in% names(data)) {
    names(data)[names(data) == "Soil_c"] <- "land_class"
    data$land_class <- factor(data$land_class, levels = c(1, 2), labels = c("Forest land", "Poorly productive forest land"))
  }
  if ("Soil_add" %in% names(data)) {
    data$Soil_add <- factor(data$Soil_add, levels = c(0, 1, 2, 3, 4), labels = c("No specification", "Stand among classes 5–8 (0.25–1 ha)", "Small natural stand (<0.25 ha)", "Island stand (≤1 ha)", "Island stand (1–100 ha)"))
  }
  if ("Soil_ch" %in% names(data)) {
    data$Soil_ch <- factor(data$Soil_ch, levels = c(0, 1, 2, 3, 4, 5, 6), labels = c("No change", "Was forest land", "Was poorly productive forest land", "Was unproductive forest land", "Was other forestry land", "Converted from agricultural land", "Converted from built-up land"))
  }
  if ("Maintype" %in% names(data)) {
    names(data)[names(data) == "Maintype"] <- "habitat_type"
    data$habitat_type <- factor(data$habitat_type, levels = c(1, 2, 3, 4), labels = c("Mineral soil / Heathland", "Spruce mire", "Pine mire", "Treeless mire/bog"))
  }
  if ("Mixed" %in% names(data)) {
    data$Mixed <- factor(data$Mixed, levels = c(0, 1, 2, 3, 4, 5, 6), labels = c("Pure, genuine mire or heathland", "Heath-forest-like", "Spruce mire-like", "Pine mire-like", "Treeless bog-like", "Fen-like", "Afforested former other land classes"))
  }
  if ("Nutrient_class" %in% names(data)) {
    data$Nutrient_class <- factor(data$Nutrient_class, levels = c(1, 2, 3, 4, 5, 6, 7), labels = c("Herb-rich forests and fens", "Herb-rich heath forests", "Mesic heath forests", "Sub-xeric heath forests", "Xeric heath forests", "Barren heath forests", "Rocky lands, sands, and alluvial lands")) 
  }
  if ("Nutrient_add" %in% names(data)) {
    data$Nutrient_add <- factor(data$Nutrient_add, levels = c(0, 1, 2, 3, 4, 5, 6, 7), labels = c("No additional qualifier", "Flarky / very wet", "Purple moor-grass dominant", "Sphagnum hummock dominant", "Flooding impact", "Swampy/springy surface water influence", "Thin peat layer (<30 cm)", "Pyrola-type heath"))
  }
  if ("Soiltype2" %in% names(data)) {
    data$Soiltype2 <- factor(data$Soiltype2, levels = c(0, 1, 2, 3, 4), labels = c("Organic soil (>30cm peat)", "Bedrock", "Stony/boulder field", "Moraine / Till", "Sorted mineral soil"))
  }
  if ("Texture" %in% names(data)) {
    data$Texture <- factor(data$Texture, levels = c(0, 1, 2, 3), labels = c("Not applicable", "Fine (clay, silt, fine sand)", "Medium coarse (coarse silt, fine sand)", "Coarse (coarse sand, gravel)"))
  }
  if ("Organisc_quality" %in% names(data)) {
    names(data)[names(data) == "Organisc_quality"] <- "organic_quality"
    data$organic_quality <- factor(data$organic_quality, levels = c(0, 1, 2, 3, 4, 5, 6), labels = c("Very thin <1 cm or absent", "Mor/raw forest humus", "Moder", "Mull/crumbly mould", "Peat", "Mor humus on top of a peat layer", "Peaty mull"))
  }
  if ("Soil_Depth" %in% names(data)) {
    data$Soil_Depth <- factor(data$Soil_Depth, levels = c(1, 2, 3), labels = c("Lots of exposed bedrock/stones", "Bedrock is detectable", "No bedrock visible"))
  }
  if ("Ditches" %in% names(data)) {
    data$Ditches <- factor(data$Ditches, levels = c(0, 1, 2, 3, 4), labels = c("Unditched", "Ditched mineral soil", "Recently drained peatland", "Transforming drained peatland", "Transformed peatland"))
  }
  return(data)
}


# ==============================================================================
# FUNCTION 2: ADAPTIVE METRIC PLOTTING (HANDLES NUMERIC & CATEGORICAL DATATYPES)
# ==============================================================================
plot_relationships <- function(data, cat_columns) {
  
  # Ensure legacy column names are handled
  if ("Soil_c" %in% cat_columns && !"Soil_c" %in% names(data) && "land_class" %in% names(data)) {
    cat_columns[cat_columns == "Soil_c"] <- "land_class"
  }
  
  valid_cat_cols <- intersect(cat_columns, names(data))
  if (length(valid_cat_cols) == 0) return(invisible(NULL))
  
  has_height <- "ih5_dm" %in% names(data) && any(!is.na(data$ih5_dm))
  has_diameter <- "id5_dm" %in% names(data) && any(!is.na(data$id5_dm))
  
  if (!has_height && !has_diameter) {
    message("Notice: Height and/or Diameter data is missing. Skipping plots.")
    return(invisible(NULL))
  }
  
  old_par <- par(
    mfrow    = c(1, 3), 
    mar      = c(9.5, 6, 5, 2) + 0.1, 
    cex.main = 2.0,                 
    cex.lab  = 1.8,                 
    cex.axis = 1.4                  
  )
  on.exit(par(old_par)) 
  
  for (col_name in valid_cat_cols) {
    if (all(is.na(data[[col_name]]))) next 
    
    # NEW LOGIC: Check if we are dealing with a Continuous Numeric Variable
    is_numeric_var <- is.numeric(data[[col_name]])
    
    if (is_numeric_var) {
      # ---------------------------------------------------------
      # SCATTERPLOTS FOR CONTINUOUS VARIABLES (e.g. Organic_depth)
      # ---------------------------------------------------------
      if (has_height) {
        plot(data[[col_name]], data$ih5_dm, main = paste("Height vs", col_name), 
             xlab = col_name, ylab = "Height (ih5_dm)", pch = 16, col = rgb(0,0,0,0.3))
        # Add linear trendline
        abline(lm(data$ih5_dm ~ data[[col_name]]), col = "red", lwd = 3)
      }
      
      if (has_diameter) {
        plot(data[[col_name]], data$id5_dm, main = paste("Diameter vs", col_name), 
             xlab = col_name, ylab = "Diameter (id5_dm)", pch = 16, col = rgb(0,0,0,0.3))
        abline(lm(data$id5_dm ~ data[[col_name]]), col = "blue", lwd = 3)
      }
      
      if (has_height && has_diameter) {
        plot(data$ih5_dm, data$id5_dm, main = "Height vs Diameter", 
             xlab = "Height (ih5_dm)", ylab = "Diameter (id5_dm)", pch = 16, col = rgb(0,0,0,0.3))
      }
      
    } else {
      # ---------------------------------------------------------
      # BOXPLOTS FOR CATEGORICAL VARIABLES
      # ---------------------------------------------------------
      fac <- as.factor(data[[col_name]])
      if (length(levels(fac)) == 0) next
      
      wrapped_fac <- fac
      levels(wrapped_fac) <- sapply(levels(wrapped_fac), function(label) {
        paste(strwrap(label, width = 12), collapse = "\n")
      })
      
      if (has_height) {
        plot(wrapped_fac, data$ih5_dm, main = paste("Height by", col_name), xlab = "", ylab = "Height (ih5_dm)", xaxt = "n")
        stripchart(data$ih5_dm ~ wrapped_fac, vertical = TRUE, method = "jitter", pch = 16, col = "black", cex = 0.6, add = TRUE)
        axis(1, at = 1:length(levels(wrapped_fac)), labels = FALSE)
        text(x = 1:length(levels(wrapped_fac)), y = par("usr")[3] - ((par("usr")[4] - par("usr")[3]) * 0.04), labels = levels(wrapped_fac), xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.4)
        title(xlab = col_name, line = 7.5)
      }
      
      if (has_diameter) {
        plot(wrapped_fac, data$id5_dm, main = paste("Diameter by", col_name), xlab = "", ylab = "Diameter (id5_dm)", xaxt = "n")
        stripchart(data$id5_dm ~ wrapped_fac, vertical = TRUE, method = "jitter", pch = 16, col = "black", cex = 0.6, add = TRUE)
        axis(1, at = 1:length(levels(wrapped_fac)), labels = FALSE)
        text(x = 1:length(levels(wrapped_fac)), y = par("usr")[3] - ((par("usr")[4] - par("usr")[3]) * 0.04), labels = levels(wrapped_fac), xpd = NA, srt = 0, adj = c(0.5, 1), cex = 1.4)
        title(xlab = col_name, line = 7.5)
      }
      
      if (has_height && has_diameter) {
        plot(data$ih5_dm, data$id5_dm, col = fac, main = paste("Height vs Diameter by", col_name), xlab = "", ylab = "Diameter (id5_dm)")
        title(xlab = "Height (ih5_dm)", line = 3.5)
        legend("topleft", legend = levels(fac), col = 1:length(levels(fac)), pch = 1, cex = 1.5) 
      }
    }
  }
}