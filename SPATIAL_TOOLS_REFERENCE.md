# 50 Spatial & Remote Sensing Tools Reference

This document provides a complete breakdown of all **50 spatial tools** in **SimpleAnalysis**, explicitly distinguishing between the **33 pre-existing tools** and the **17 newly added tools** introduced in Round 3.

---

## 📌 Summary Breakdown

- ⚡ **Pre-Existing Spatial Tools (33 Tools)**: `dtm`, `dsm`, `chm`, `ndsm`, `itd`, `tpi`, `tri`, `roughness`, `slope_deg`, `slope_pct`, `aspect`, `hillshade`, `profc`, `planc`, `twi`, `flowdir`, `streams`, `sca`, `fill_wb`, `flowacc_wb`, `clip_vec`, `mosaic`, `reproject`, `resample`, `bandcalc`, `ndvi`, `ndwi`, `nbr`, `ndre`, `zonal`, `buffer`, `dissolve`, `centroid`.
- 🆕 **Newly Added Spatial Tools (17 Tools)**: `xy_to_sf` (XY coordinates to vector), `vec_reproject`, `vec_clip`, `vec_bbox`, `vec_convex_hull`, `vec_simplify`, `vec_spatial_join`, `focal_mean`, `focal_sd`, `rast_mask_range`, `rast_reclass`, `point_density`, `las_decimate_algo`, `las_metrics_grid_algo`, `multidir_hillshade`, `las_normalize_algo`, `vec_area_length`.

---

## 1. Surfaces & LiDAR Tools (1–10)

1. **Digital Terrain Model (`dtm`)** `[Pre-existing]`
   - **R Code**: `lidR::rasterize_terrain(las, res = 1, algorithm = lidR::tin())`
   - **Description**: Bare-earth elevation raster interpolated from point cloud ground returns via TIN.

2. **Digital Surface Model (`dsm`)** `[Pre-existing]`
   - **R Code**: `lidR::rasterize_canopy(las, res = 1, algorithm = lidR::p2r())`
   - **Description**: Top-of-surface canopy elevation raster using highest returns per cell.

3. **Canopy Height Model (`chm`)** `[Pre-existing]`
   - **R Code**: `lidR::rasterize_canopy(las, res = 0.5, algorithm = lidR::pitfree())`
   - **Description**: Smooth canopy height surface using the pit-free algorithm.

4. **Normalized Surface Model (`ndsm`)** `[Pre-existing]`
   - **R Code**: `dsm - dtm`
   - **Description**: Calculates height above ground by subtracting bare-earth DTM from top-surface DSM.

5. **Individual Tree Detection (`itd`)** `[Pre-existing]`
   - **R Code**: `lidR::locate_trees(chm, lidR::lmf(ws))`
   - **Description**: Detects individual treetops and extracts point stem locations using local maximum filter.

6. **LiDAR Structural Metrics Grid (`las_metrics_grid_algo`)** `[Newly Added in Round 3]`
   - **R Code**: `lidR::pixel_metrics(las, ~list(mean_z = mean(Z), p95 = quantile(Z, 0.95)), res = 10)`
   - **Description**: Extracts structural metrics (mean Z, 95th percentile height, density) across cells.

7. **Decimate Point Cloud (`las_decimate_algo`)** `[Newly Added in Round 3]`
   - **R Code**: `lidR::decimate_points(las, lidR::random(fraction))`
   - **Description**: Subsamples a LAS point cloud to a lower random point density fraction.

8. **Normalize Point Cloud Heights (`las_normalize_algo`)** `[Newly Added in Round 3]`
   - **R Code**: `lidR::normalize_height(las, dtm)`
   - **Description**: Subtracts ground elevation from point cloud Z coordinates to produce relative canopy heights.

9. **Spatial Point Density Heatmap (`point_density`)** `[Newly Added in Round 3]`
   - **R Code**: `terra::rasterize(vect(v), rast(ext, res), fun = "length")`
   - **Description**: Computes a continuous point density raster grid from vector point features.

10. **Tabular XY Coordinates to Vector (`xy_to_sf`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_as_sf(df, coords = c("X", "Y"), crs = 4326)`
    - **Description**: Converts tabular coordinate columns into a spatial `sf` vector point layer with CRS selection.

---

## 2. Terrain Analysis Derivatives (11–18)

11. **Slope (Degrees) (`slope_deg`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "slope", unit = "degrees")`
    - **Description**: Calculates surface steepness in degrees.

12. **Slope (Percent Rise) (`slope_pct`)** `[Pre-existing]`
    - **R Code**: `tan(terra::terrain(dem, "slope", unit = "radians")) * 100`
    - **Description**: Computes terrain slope as a percentage rise.

13. **Aspect (`aspect`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "aspect", unit = "degrees")`
    - **Description**: Derives downslope compass direction (0–360°).

14. **Hillshade (`hillshade`)** `[Pre-existing]`
    - **R Code**: `terra::shade(slope, aspect, angle = alt, direction = azim)`
    - **Description**: Generates single-sun shaded relief for 3D terrain visualization.

15. **Multidirectional Hillshade (`multidir_hillshade`)** `[Newly Added in Round 3]`
    - **R Code**: `(shade(alt, 225) + shade(alt, 315)) / 2`
    - **Description**: Blends multiple solar illumination angles to illuminate terrain features without dark shadows.

16. **Topographic Position Index (`tpi`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "tpi")`
    - **Description**: Measures cell height relative to its surrounding neighbourhood to delineate ridges and valleys.

17. **Terrain Ruggedness Index (`tri`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "tri")`
    - **Description**: Measures mean elevation difference between a cell and its 8 neighbours.

18. **Roughness (`roughness`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "roughness")`
    - **Description**: Calculates the maximum minus minimum elevation in a local window.

---

## 3. Curvature & Geomorphometry (19–20)

19. **Profile Curvature (`profc`)** `[Pre-existing]`
    - **R Code**: `.ea_curvature(dem, "profile")`
    - **Description**: Measures curvature along the direction of maximum slope.

20. **Plan Curvature (`planc`)** `[Pre-existing]`
    - **R Code**: `.ea_curvature(dem, "plan")`
    - **Description**: Measures curvature perpendicular to the direction of slope.

---

## 4. Hydrology & Watershed Processing (21–27)

21. **Topographic Wetness Index (`twi`)** `[Pre-existing]`
    - **R Code**: `log(cell_area / (tan(slope) + 1e-6))`
    - **Description**: Models spatial pattern of soil moisture and wetness potential.

22. **Flow Direction D8 (`flowdir`)** `[Pre-existing]`
    - **R Code**: `terra::terrain(dem, "flowdir")`
    - **Description**: Determines D8 direction of steepest descent for each grid cell.

23. **Stream Network Extraction (`streams`)** `[Pre-existing]`
    - **R Code**: `slope >= threshold`
    - **Description**: Delineates potential surface drainage channels based on slope steepness thresholds.

24. **Slope x Contributing Area (`sca`)** `[Pre-existing]`
    - **R Code**: `slope * cell_area`
    - **Description**: Approximates stream transport capacity and sediment erosion potential.

25. **Fill Depressions (`fill_wb`)** `[Pre-existing]`
    - **R Code**: `whitebox::wbt_fill_depressions(dem_in, dem_out)`
    - **Description**: Removes sinks and depressions from DEM to ensure hydrologic connectivity.

26. **Flow Accumulation (`flowacc_wb`)** `[Pre-existing]`
    - **R Code**: `whitebox::wbt_d8_flow_accumulation(dem_filled, flow_acc)`
    - **Description**: Computes accumulated upslope contributing cell count per cell.

27. **Distance to Vector Features (`rast_dist_vector`)** `[Newly Added in Round 3]`
    - **R Code**: `terra::distance(raster_ref, vector_geom)`
    - **Description**: Generates continuous raster grid of Euclidean distance to nearest vector stream or boundary.

---

## 5. Spectral & Remote Sensing Indices (28–31)

28. **NDVI - Vegetation Index (`ndvi`)** `[Pre-existing]`
    - **R Code**: `(NIR - Red) / (NIR + Red)`
    - **Description**: Normalized Difference Vegetation Index for canopy greenness and vigor.

29. **NDWI - Water Index (`ndwi`)** `[Pre-existing]`
    - **R Code**: `(Green - NIR) / (Green + NIR)`
    - **Description**: Normalized Difference Water Index for surface water body delineation.

30. **NBR - Burn Ratio (`nbr`)** `[Pre-existing]`
    - **R Code**: `(NIR - SWIR) / (NIR + SWIR)`
    - **Description**: Normalized Burn Ratio for wildfire severity and burn scar mapping.

31. **NDRE - Red-Edge Index (`ndre`)** `[Pre-existing]`
    - **R Code**: `(RedEdge - Red) / (RedEdge + Red)`
    - **Description**: Normalized Difference Red Edge Index for chlorophyll concentration monitoring.

---

## 6. Raster Grid Operations & Filters (32–40)

32. **Clip Raster to Vector (`clip_vec`)** `[Pre-existing]`
    - **R Code**: `terra::crop(r, vect(v), mask = TRUE)`
    - **Description**: Crops and masks a raster grid to a vector polygon boundary.

33. **Mosaic Rasters (`mosaic`)** `[Pre-existing]`
    - **R Code**: `terra::mosaic(terra::sprc(rasters))`
    - **Description**: Merges multiple adjacent raster tiles into a unified spatial grid.

34. **Reproject Raster (`reproject`)** `[Pre-existing]`
    - **R Code**: `terra::project(r, target_crs)`
    - **Description**: Warps raster dataset to a new Coordinate Reference System (CRS).

35. **Resample Resolution (`resample`)** `[Pre-existing]`
    - **R Code**: `terra::resample(r, template_grid, method = "bilinear")`
    - **Description**: Resamples raster grid cell size using bilinear, nearest, or cubic interpolation.

36. **Band Calculator (`bandcalc`)** `[Pre-existing]`
    - **R Code**: `eval(parse(text = "(b4 - b3) / (b4 + b3)"))`
    - **Description**: Evaluates custom mathematical formulas across raster bands.

37. **Focal Mean Filter (`focal_mean`)** `[Newly Added in Round 3]`
    - **R Code**: `terra::focal(r, w = matrix(1, sz, sz), fun = "mean")`
    - **Description**: Smooths raster noise using a moving 3x3 (or N x N) mean filter window.

38. **Focal Standard Deviation Filter (`focal_sd`)** `[Newly Added in Round 3]`
    - **R Code**: `terra::focal(r, w = matrix(1, sz, sz), fun = "sd")`
    - **Description**: Calculates local variance and structural heterogeneity across cells.

39. **Mask Value Range (`rast_mask_range`)** `[Newly Added in Round 3]`
    - **R Code**: `terra::clamp(r, lower = min_v, upper = max_v, values = FALSE)`
    - **Description**: Sets raster cells outside a min/max range to NA.

40. **Reclassify Raster (`rast_reclass`)** `[Newly Added in Round 3]`
    - **R Code**: `terra::classify(r, reclass_matrix)`
    - **Description**: Maps continuous raster value ranges into discrete integer land cover or suitability classes.

---

## 7. Vector Spatial Geometry Tools (41–50)

41. **Buffer (`buffer`)** `[Pre-existing]`
    - **R Code**: `sf::st_buffer(v, dist = distance)`
    - **Description**: Creates fixed-distance spatial buffer polygons around points, lines, or polygons.

42. **Dissolve (`dissolve`)** `[Pre-existing]`
    - **R Code**: `sf::st_union(v)`
    - **Description**: Merges adjacent or overlapping geometries, optionally grouped by attribute field.

43. **Centroids (`centroid`)** `[Pre-existing]`
    - **R Code**: `sf::st_centroid(v)`
    - **Description**: Calculates geometric center points for polygon or line features.

44. **Reproject Vector (`vec_reproject`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_transform(v, target_crs)`
    - **Description**: Reprojects vector layer to a new target CRS.

45. **Clip Vector by Polygon (`vec_clip`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_intersection(v, mask_polygon)`
    - **Description**: Intersects vector features with a bounding polygon boundary.

46. **Bounding Box Polygon (`vec_bbox`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_as_sfc(sf::st_bbox(v))`
    - **Description**: Computes spatial envelope bounding box polygon around geometries.

47. **Convex Hull (`vec_convex_hull`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_convex_hull(sf::st_union(v))`
    - **Description**: Computes the minimum convex hull polygon enclosing geometries.

48. **Simplify Geometries (`vec_simplify`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_simplify(v, dTolerance = tol)`
    - **Description**: Simplifies geometric boundary complexity using Douglas-Peucker algorithm.

49. **Spatial Join (`vec_spatial_join`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_join(target_v, source_v)`
    - **Description**: Transfers attributes from a source vector layer based on spatial overlap.

50. **Geometry Area & Length Calculation (`vec_area_length`)** `[Newly Added in Round 3]`
    - **R Code**: `sf::st_area(v); sf::st_length(v)`
    - **Description**: Calculates spatial polygon surface area ($m^2$ and hectares) and line perimeter/length.
