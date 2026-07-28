
##############################################                                             
#### ALS-BASED FOREST INVENTORY WITH LIDR ####
#### UEF ADVANCED REMOTE SENSING COURSE   ####
#### Code template                        #### 
#### Lauri Korhonen 2024                  #### 
##############################################


#==================================
# Initialize R
#==================================

# Clear memory of old stuff
rm(list = ls())
dev.off()

options(install.packages.check.source = "no")

# install.packages("sf"", type = "binary")
# install.packages("lidR"", type = "binary")
# install.packages("terra"", type = "binary")
# install.packages("microbenchmark"", type = "binary")

# Load installed libraries into active use
require(sf)
require(terra)
require(lidR)
require(microbenchmark)

# Check if the help page of the following command shows up. 
# If yes, the installation is ok.
?polygon_metrics

# Set working directory path - all your files should be here
#setwd("C:\\Users\\myusername\\OneDrive - University of Eastern Finland\\Documents\\adresen\\lidr")

# Load a set of custom functions
source("lidr_functions.r")
source("evaluation_function.r")


#==================================
# Read data sets into R
#==================================

# Read background and plot aerial image
ortho <- rast("kiihtelys_ortho.tif")
plotRGB(ortho)

# Read field plot shapefile from the working directory
field <- st_read("ars_plots.shp")

# Check the structure of the field plot data
str(field)

# Show field plot locations over the aerial image
plot(st_geometry(field), add=TRUE, col="red")

# View the attributes of the field plots
View(field)

# Read laser data file into R's LAS object
las <- lidR::readLAS("kiihtelys.laz")

# View a summary of the LAS object
summary(las)

# Show the records of the LAS object
tail(las@data)

# View the a table of classifications of the las object
table(las$Classification)

# Add echo type to User Data, overwrite the previous las object
las <- add_echo_type(las)

# View the updated User Data field in tabular form
table(las$UserData)

# Check laser data integrity
las_check(las)


#========================================
# Visualization 
#========================================

# Clip a smaller portion of the las file for a better view
subarea <- clip_rectangle(las, 665000, 6934700, 665300, 6935000)
plot(subarea)

# Plot the smaller area in different ways
plot(subarea, color="Z", legend=T) # Elevation (Use Z)
plot(subarea, color="UserData", legend=T) # User Data (Use UserData)
plot(subarea, color="Classification", legend=T) # Classification 
plot(subarea, color="Intensity", legend=T) # Intensity

# Re-plot Intensity with rescaled colors
plot(subarea, color="Intensity", breaks = "quantile", nbreaks = 50, legend=T)

# Clip point clouds of plots from the LAS object
plots_clipped <- clip_roi(las, field)

# View point clouds of plots
length(plots_clipped) # 33 plots
plot(plots_clipped[[28]], color="UserData", legend=T)


#=================================================
# Height normalization and removal of outliers
#=================================================

# Construct a Digital Terrain Model
# Set output file, input file, spatial resolution, and interpolation method
dtm <- rasterize_terrain(las, res=1, algorithm=tin())

# View the DTM in 2D and 3D hillshade
plot(dtm)
plot_dtm3d(dtm)

# Height normalize LAS object by subtracting the DTM. dzlas is the normalized las object
dzlas <- las-dtm

# Remove the non-normalized LAS object and the DTM to free memory
#rm(dtm)
#rm(las)

# Reset graphical parameters
dev.off()

# View normalized Z and intensity histograms
hist(dzlas$Z, main="Histogram of height (Z) after normalization")
hist(dzlas$Intensity, main = "Histogram of Intensity after normalization")

# Remove noise echoes
dzlas <- classify_noise(dzlas, ivf(res = 5, n = 2))
dzlas <- filter_poi(dzlas, Classification != LASNOISE)

# Remove echoes with unrealistic intensities
dzlas <- filter_poi(dzlas, Intensity < 300)

# Review echo histograms (normalized elevation (Z) and intensity histogram)
hist(dzlas$Z)
hist(dzlas$Intensity)

# Set negative elevations as zero
dzlas$Z[dzlas$Z < 0] <- 0

max(dzlas$Z) # View Z maximum
min(dzlas$Z) # View Z minimum

max(dzlas$Intensity) # View Intensity maximum
min(dzlas$Intensity) # View Intensity minimum

#============================================
# Computation of predictor variables
#============================================

# Compute preditor variables for each plot into data frame d
# Inputs: LAS file, function that computes the variables, plot polygons
d <- polygon_metrics(dzlas, ~uef_metrics(Z, Intensity, UserData), field)

tail(d)      # View structure of the predictor file
class(d)     # Note that it can be treated as a georeferenced data frame

# Merge with field plots using column bind
d <- cbind(field, d)

# Convert into a normal data frame
d <- st_set_geometry(d, NULL)

tail(d)      # View structure of the predictor file
class(d)     # Note that it can be treated as a georeferenced data frame

# Make a scatter plot of max echo height (f_hmax) and dominant height (hdom)
# If the predictors are OK, there should be a high correlation
plot(d$f_hmax, d$hdom, xlim=c(0,30), ylim=c(0,30)); abline(0,1)
cor(d$f_hmax, d$hdom)
#=================================================
# Construct a regression model for plot volume
#=================================================
# Try the exhaustive variable search
exh_var_search(d, 3, "v", 12, 68)

# Choose the best model based on the output
m <- lm(v~f_hmean + l_p80 + l_p40, data=d) # sqrt was not in the EVS output. Check later
summary(m)

# Make your own plot level volume model 
plot(fitted(m), resid(m), xlab="Fitted Values", ylab="Residuals", abline(h=0))

# Run the evaluation of the model (Experiment with the others and select the model with the lowest RMSE)
rmse(d$v, fitted(m))

#==================================================
# Wall-to-wall prediction
#==================================================

# Compute a raster stack of ALS metrics for the whole area
# Parameters: LAS object, function to compute, resolution
abagrid <- pixel_metrics(dzlas, ~ uef_metrics(Z, Intensity, UserData), res = 15)

# Plot the the predictors from the model
plot(abagrid$f_hmean)
plot(abagrid$l_p80)
plot(abagrid$l_p40)

# Predict volume using the raster stack and your model object
# Save as v_pred
v_pred <- 10469.107 + 27.866*abagrid$f_hmean - 15228.098*abagrid$l_p80 + 4745.741*abagrid$l_p40

# Force areas where top echo is height is < 2 m as 0
v_pred[abagrid$f_hmax < 2] <- 0

# Reset graphics and plot volume grid
dev.off()
plot(v_pred, main="Volume m3/ha")

# Save volume grid as a .tif file and view it in a GIS
?writeRaster
terra::writeRaster(v_pred, "Volume_grid_raster.tif", overwrite=T)

# Free memory
rm(abagrid)

#============================================
# Construction of a canopy height model
#============================================

# Interpolate a CHM
# Parameters: LAS object, spatial resolution, interpolation algorithm
?rasterize_canopy

# Algorithm
pitfree(thresholds = c(0, 5, 10, 15, 20, 25))
?pitfree

chm <- rasterize_canopy(dzlas, res = 0.5, algorithm = pitfree(thresholds = c(0, 5, 10, 15, 20, 25)))

# Plot CHM
plot(chm, main = "CHM")

# Add field plot polygons 
plot(st_geometry(field), add=TRUE, col="red")

# Crop a smaller area from the CHM for closer inspection and plot it
subchm <-crop(chm, ext(664030, 664090, 6935380, 6935440))
plot(subchm, main="Small area CHM(subCHM)")


#============================================
# Individual tree detection
#============================================

# Define a function for computing a height-dependent moving window size
window_size <- function(height){ 1.2 + 0.003*height^2 } 

# Compute a georeferenced data frame with tree top coordinates and heights
tops <- locate_trees(chm, lmf(window_size))

tail(tops) # View output
names(tops)
head(tops$h)
tail(tops$h)


# Visualize tree locations
plot(subchm, main = "Detected tree tops of sub-CHM") # Re-plot the small-area CHM

# Re-add plot polygons as transparent
plot(st_geometry(field), add=T, lwd=2, col=rgb(0,0,0,0)) 

# Add detected tree locations on top
plot(tops, add=T)


# Apply height correction model with the tree top data frame
#tops$h <- ... + ...$...*...
tops$h <- 1.2 + tops$Z*1.01

names(tops)
tail(tops) # View the result


#============================================
# Construction of a tree level volume model
#============================================

dev.off() # Reset graphics

# Read in tree file
trees <- read.csv("ars_trees.csv", header=T, sep=",", dec=".")

# Make your own tree level volume model 
tree_vol <- lm(v ~ h, data=trees)
summary(tree_vol)
#plot(tree_vol)


# Apply your model to predict a new column in the tree top file
tops$v_itd <- predict(tree_vol, newdata = tops)
#tops$v_itd <- -0.2419208 + 0.0308999*tops$h

# Scatter plot of the model
plot(trees$h, trees$v, xlab="Height (m)", ylab="Volume (m3)", main="Tree level volume model")

# Add regression line
x <- seq(0,30,1)
y <- -0.2419208 + 0.0308999*x
lines(x, y, col="red")

#============================================
# Plot level accuracy assessment for ITD
#============================================

# Convert the detected trees to a different spatial format
topsf <- st_as_sf(tops)         
  
# Set the coordinate system of this object to be the same as the field plots
st_crs(topsf) <- 3067 

# Make a spatial overlay of field plots and detected trees 
plot_tops <- st_join(field,topsf) 

# View the last rows of the new object with plot-labeled itd trees
head(plot_tops)

# Compute a new column called v_itd in your FIELD PLOT TABLE using function 
# tapply with your *plot-labeled itd trees*. Tapply applies a function (here sum())
# to the values of a given column (v_itd) using a given grouping variable (plot).
field$v_itd <- tapply(plot_tops$v_itd, plot_tops$plot_id, sum)

# Repeat, but now compute the plot level stem number by using the length() function
# instead of sum() and save it as n_itd
field$n_itd <- tapply(plot_tops$v_itd, plot_tops$plot_id, length)

# Scale v_itd and n_itd to per hectare using plot radius
scale_factor <- 10000/(pi*10^2)
field$v_itd <- field$v_itd * scale_factor
field$n_itd <- field$n_itd * scale_factor

# View the last rows of the field plot table
tail(field)

# Make scatter plots of plot level predicted vs observed volume and stem number
plot(field$v_itd, field$v,
     xlab="Predicted volume (ITD, m3/ha)",
     ylab="Observed volume (field, m3/ha)",
     main="ITD plot-level volume accuracy")
abline(0,1,col="red")

# Plot stem number
plot(field$n_itd, field$n,
     xlab="Predicted stem number (ITD, n/ha)",
     ylab="Observed stem number (field, n/ha)",
     main="ITD plot-level stem number accuracy")

# Compute plot level RMSE-% and bias-% of both volume and stem number
relrmse(field$v, field$v_itd)
relbias(field$v, field$v_itd)

relrmse(field$n, field$itd_n)
relbias(field$n, field$itd_n)

