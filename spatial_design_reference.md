# SimpleAnalysis — Spatial Analysis Design Reference
## How GIS Platforms Work (QGIS / ArcGIS Pro Model)

> **NOTE (2026-07-27):** the ASCII mockups below use emoji purely as sketch shorthand.
> The app itself is **emoji-free** — real UI uses Font Awesome icons and colour dots
> (see DESIGN.md visual language). Do not copy these glyphs into the app.


This document describes the UX patterns, functional architecture, and data workflows of
desktop GIS platforms (primarily QGIS 3.x and ArcGIS Pro 3.x). It is the design blueprint
for the SimpleAnalysis Spatial Analysis screen.

---

## 1. Overall UI Shell

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  [Menu bar]  File  Edit  Layer  Plugins  Raster  Vector  Processing  Help       │
├─────────────────────────────────────────────────────────────────────────────────┤
│  [Toolbars]  🔍+ 🔍- 🤚 ➡ ⬜ 📏 ℹ️   Layer tools   Plugin bars                  │
├──────────────────┬──────────────────────────────────────┬───────────────────────┤
│                  │                                      │                       │
│  LAYERS PANEL    │       M A P   C A N V A S            │  PROPERTIES /         │
│  (left, ~240px)  │                                      │  PROCESSING PANEL     │
│                  │   Fills remaining width; never       │  (right, ~300px)      │
│  ▸ Group A       │   shrinks. All panels dock around    │                       │
│    ☑ Raster 1    │   it and can collapse.               │  (shows symbology,    │
│    ☑ Vector 1    │                                      │   tool params, etc.   │
│  ▸ Group B       │   [Tile basemap at bottom]           │   for active layer)   │
│    ☑ Raster 2    │   [Rasters stacked above]            │                       │
│    ☐ Vector 2    │   [Vectors on top]                   │                       │
│                  │                                      │                       │
│  (drag to        │                                      │                       │
│   reorder)       │                                      │                       │
│                  │                                      │                       │
├──────────────────┴──────────────────────────────────────┴───────────────────────┤
│  [Status bar]  CRS: EPSG:3067   X: 378,422   Y: 6,672,140   Scale 1:25,000     │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Core principle:** the map canvas is always the primary surface. It fills the center and
never shrinks. Side panels are secondary and can be collapsed to give the map more space.

---

## 2. Layer Panel (Left Rail)

### 2.1 What it shows
A tree of all loaded layers, ordered by draw order (top = rendered last = appears on top
of everything else). Each layer entry has:

- **Visibility checkbox** — the single most-used toggle in GIS. Hides/shows the layer
  without removing it. Users rapidly check/uncheck to compare layers.
- **Layer type icon** — instant visual cue: raster grid, polygon fill, line, point dot,
  WMS tile server.
- **Layer name** — double-click to rename. Descriptive names matter: "DTM_2m_ETRS" beats
  "raster_1".
- **Expand arrow** — expands to reveal the layer's **legend** (color ramp swatch with
  breakpoints for rasters; fill/stroke swatches for vectors).
- **Opacity slider** — some platforms show a mini opacity slider per-layer directly in
  the panel without opening properties.

### 2.2 Draw order (z-order)
Bottom of the list renders first (background); top of the list renders last (foreground).
- Base imagery (satellite tile): always at the very bottom.
- Rasters (DEMs, CHMs): above imagery.
- Vector polygons: above rasters.
- Vector lines and points: above polygons.
- Labels: always on top of everything.

Users drag rows to reorder. This is continuous and live — the map canvas re-renders as
you drag.

### 2.3 Groups
- Named folders that contain multiple layers.
- Group has its own visibility toggle: unchecking a group hides all children at once.
- Collapsible in the panel. Useful for organizing "DTM products", "Field plots", "Outputs".
- Nested groups are supported (but rare in practice).

### 2.4 Right-click context menu (critical actions)
| Action | Description |
|---|---|
| **Zoom to Layer** | Fit the map to this layer's full extent — the #1 most-used action |
| Open Attribute Table | Spreadsheet view of vector data |
| Layer Properties | Full dialog: symbology, labels, CRS, metadata, histogram |
| Export / Save As | GeoTIFF, GeoPackage, CSV, Shapefile... |
| Rename Layer | Edit the display name (does not rename the file) |
| Duplicate Layer | Copy with same data, different style |
| Remove Layer | Remove from project (file on disk is untouched) |
| Set Layer CRS | Assign or override the CRS tag without reprojecting data |
| Copy Layer Style | Copy symbology to clipboard |
| Paste Layer Style | Paste style onto another layer |

### 2.5 Legend / symbology preview
Expanding a raster layer in the panel shows the color ramp inline:
```
▼ ☑ CHM_2m_pitfree            (layer row)
      ████████████  25.0        (top of ramp = max value)
      ▓▓▓▓▓▓▓▓▓▓▓▓  12.5
      ░░░░░░░░░░░░   0.0        (bottom of ramp = min value)
```

For a categorized vector:
```
▼ ☑ Trafficability_classes
      🟢  Passable (245 features)
      🟡  Marginal (88 features)
      🔴  Impassable (132 features)
```

---

## 3. Map Canvas Interactions

### 3.1 Navigation tools
| Tool | Icon | Action |
|---|---|---|
| Pan | ✋ | Click-drag to move the map |
| Zoom in | 🔍+ | Click to zoom in; draw rectangle to zoom to area |
| Zoom out | 🔍- | Click to zoom out |
| Zoom full extent | ⌂ | Fit all loaded layers in view |
| Zoom to layer | 🎯 | (via layer panel right-click or toolbar button) |
| Zoom to selection | | Fit selected features |
| Previous/next extent | ← → | Undo/redo the zoom/pan navigation |
| Identify/Info | ℹ️ | Click a point on the map → popup with attribute values |
| Select features | ⬜ | Rectangle selection on vector layers |
| Measure distance | 📏 | Click two or more points → running distance shown |
| Measure area | ⬜📏 | Draw polygon → area shown |

### 3.2 Mouse wheel behavior
- Scroll up = zoom in (centred on cursor position).
- Scroll down = zoom out.
- Ctrl+scroll = finer zoom steps.
- Middle-click + drag = pan (alternative to pan tool).

### 3.3 Keyboard shortcuts (QGIS defaults)
| Key | Action |
|---|---|
| Space | Toggle pan tool temporarily |
| Ctrl+Shift+F | Zoom to full extent |
| F11 | Full-screen canvas |
| Ctrl+Z / Ctrl+Shift+Z | Undo/redo edits (only in edit mode) |
| Delete | Delete selected features (only in edit mode) |
| Ctrl+I | Open Identify Results |
| Ctrl+K | Open Attribute Table |

### 3.4 Coordinate display
The status bar shows live X/Y coordinates as the mouse moves over the map canvas — in
whatever CRS the project is using. This lets users navigate to known coordinates and
verify that data landed in the right place.

### 3.5 Identify / info tool
Click anywhere on the map with the Identify tool active → a panel opens listing attribute
values for all features at that pixel location. For rasters: shows band values. For
vectors: shows all field values. Indispensable for QA/QC.

---

## 4. Raster Layers — Deep Dive

### 4.1 File formats
| Format | Extension | Notes |
|---|---|---|
| GeoTIFF | .tif, .tiff | Universal; supports single/multi-band, float, int |
| Cloud-Optimized GeoTIFF | .tif (COG) | Tiled + overviews for web streaming |
| ERDAS Imagine | .img | Common in forestry / remote sensing |
| ASCII Grid | .asc | Human-readable, large files, no CRS embedded |
| NetCDF | .nc | Time-series rasters (climate, modelling output) |
| Esri Grid | .grd, .adf | ArcGIS native format |
| JPEG2000 | .jp2 | Satellite imagery archives (Sentinel-2) |
| HDF5 | .h5, .he5 | NASA/ESA satellite data |

### 4.2 Single-band raster display modes
| Mode | When to use |
|---|---|
| **Singleband pseudocolor** | Any continuous raster: DEM, CHM, NDVI, slope. Color ramp maps value range to colors. |
| **Singleband gray** | Quick visual check; gray = monotone. Works for any raster. |
| **Hillshade** | DEM only. Simulates 3D relief by shading from a virtual light source. |
| **Contours** | DEM only. Auto-generates contour lines at regular value intervals on the fly. |

### 4.3 Color ramp options (pseudocolor mode)
Common ramps used in GIS:
| Ramp name | Typical use |
|---|---|
| Viridis | General purpose: perceptually uniform, colorblind-safe |
| RdYlGn | NDVI, change detection (red = bad/low, green = good/high) |
| Spectral | Diverging: centered on mid-range value |
| Terrain | DEM visualization (blue=low, green=mid, brown=high, white=peak) |
| Greys | Single-band imagery, quick checks |
| Hot | Heatmaps, intensity |
| Blues / Greens | Precipitation, vegetation density |

### 4.4 Stretch / contrast enhancement
| Method | Description |
|---|---|
| Min/Max | Uses actual global min and max of the raster. Shows full range but extreme values dominate. |
| Mean ± 2×StdDev | Clips to mean±2σ. Best for satellite imagery — ignores hot/cold outliers. |
| Percentile clip (2–98%) | Ignores bottom 2% and top 2% of values. Similar to StdDev clip. |
| Manual | User types exact min and max. Full control. |
| Cumulative count cut | Uses a count-based cut (e.g. cut bottom 1000 pixels by count). |

### 4.5 Transparency controls
- **Global opacity**: slider 0–100%. Affects the whole layer uniformly.
- **No-data / null**: specific pixel value rendered as fully transparent. Typical: -9999,
  NaN, 0, 255.
- **Min/max transparency**: values below min or above max become transparent (useful for
  masking clouds, water, non-forest).
- **Alpha band**: a dedicated band in the raster file encoding per-pixel transparency.

### 4.6 Resampling
When the display pixel size ≠ the raster cell size:

**Zoomed in** (one raster cell fills many screen pixels):
- Nearest Neighbor — shows crisp square pixels. Correct for classified/categorical rasters.
- Bilinear — smooth interpolation between 4 neighbors. Good for continuous rasters (DEM).
- Cubic/Cubic Spline — even smoother, slightly slower.

**Zoomed out** (many raster cells per screen pixel):
- Average — correct visual summary. Default for overviews.
- Mode — most common value. Correct for classified rasters when zoomed out.

### 4.7 Multi-band rasters (RGB / false color)
Three bands assigned to Red, Green, Blue channels for display:
| Combination | Bands (Sentinel-2) | Visual effect |
|---|---|---|
| Natural color | B4(R), B3(G), B2(B) | How the scene looks to humans |
| False color (CIR) | B8(R), B4(G), B3(B) | Vegetation appears bright red |
| SWIR composite | B12(R), B8A(G), B4(B) | Shows moisture, fire scars |
| Agriculture | B11(R), B8(G), B2(B) | Crop health and soil |

### 4.8 Raster statistics
QGIS computes (and caches in a sidecar .aux.xml file):
- Min, max, mean, standard deviation per band.
- Pixel count (total, valid, no-data).
- These are used for auto-stretch, legend, and histogram display.

### 4.9 Overviews (pyramids)
Pre-computed lower-resolution versions of a raster stored inside the file (or in a
companion .ovr file). Without overviews, zooming out over a large raster is slow because
all original pixels must be read. With overviews: instant. QGIS builds overviews
automatically (or on demand via Raster → Build Overviews).

In SimpleAnalysis: `terra::aggregate()` or `gdal_translate` with `-outsize` can pre-compute
a downsampled version for leaflet display.

---

## 5. Vector Layers — Deep Dive

### 5.1 File formats
| Format | Extension | Notes |
|---|---|---|
| Shapefile | .shp + .shx + .dbf + .prj | Legacy standard; 3-file minimum; no null values; field names ≤10 chars |
| GeoPackage | .gpkg | Modern SQLite-based; single file; multiple layers; recommended |
| GeoJSON | .geojson | Web-friendly; WGS84 assumed; large files get slow |
| KML/KMZ | .kml, .kmz | Google Earth format |
| File Geodatabase | .gdb | ArcGIS proprietary; readable by GDAL |
| PostGIS | (database) | Server-side spatial database |
| CSV with XY | .csv | Point layers only; read via "Add delimited text layer" |
| WKT | .txt, .csv | Well-Known Text geometry column in a table |

### 5.2 Geometry types
| Type | What it is | Example use |
|---|---|---|
| Point | Single X,Y coordinate | Sample plots, GPS waypoints, tree tops |
| MultiPoint | Collection of points as one feature | |
| LineString | Ordered sequence of X,Y nodes | Roads, streams, transects |
| MultiLineString | Multiple lines as one feature | Road network |
| Polygon | Closed ring of nodes defining an area | Stand polygons, watersheds, parcels |
| MultiPolygon | Multiple polygons as one feature | Country with islands |

### 5.3 Symbology options
| Style type | Description |
|---|---|
| **Single symbol** | All features same appearance. Good for plot boundaries, reference layers. |
| **Categorized** | Unique color per category value. E.g. species, forest type, trafficability class. |
| **Graduated** | Color ramp or size range mapped to numeric field. E.g. volume, basal area. |
| **Rule-based** | Arbitrary logical expressions to assign symbol per feature. Most flexible. |
| **Heatmap** | Point layer → kernel density surface. |
| **Point cluster** | Aggregate nearby points into a count circle (for dense point clouds). |

### 5.4 Symbol properties (polygon)
- Fill color + opacity.
- Stroke (outline) color, width, dash pattern (solid, dashed, dotted).
- Fill pattern: solid, hatching, no fill (outline only).
- Fill effects: inner glow, drop shadow, blur.

### 5.5 Labels
- Field to display (or an expression: `concat("PlotID", ' (', "area_ha", ' ha)')`).
- Font: family, size, bold/italic.
- Color + buffer/halo (white halo around text for legibility over complex backgrounds).
- Placement:
  - Polygons: centroid, around centroid, inside polygon only.
  - Lines: curved along line, horizontal, parallel.
  - Points: around point (8 positions), offset.
- Overlapping: "Allow overlaps", "Prevent overlaps" (QGIS picks best non-overlapping
  arrangement automatically).
- Scale visibility: show labels only between zoom levels (e.g. only at scale < 1:10,000).
- Data-defined override: label size or color can be driven by an attribute field.

### 5.6 Attribute table
- Every vector feature = one row; every field = one column.
- Linked to the map: selecting rows highlights features on the map and vice versa.
- **Edit mode**: pencil icon → cells become editable → save changes to file.
- **Field calculator**: expression-based field creation/update. Can reference geometry
  (`$area`, `$length`, `$perimeter`, `x($geometry)`, `y($geometry)`), other fields, or
  string/math functions.
- **Statistics panel**: select a column → get min/max/mean/sum/count/quartiles instantly.
- **Sort**: click column header. Secondary sort: Shift+click another header.
- **Filter/select by expression**: `"Height" > 20 AND "Species" = 'Pine'`.

---

## 6. Coordinate Reference Systems

### 6.1 The CRS chain
Every geographic dataset exists in some CRS. When layers are loaded with different CRSes,
GIS platforms apply **on-the-fly reprojection**: coordinate values are transformed
mathematically for display only — the source file is unchanged.

```
File on disk (EPSG:3067) ──transform──▶ Map canvas (EPSG:3857 Web Mercator)
     378,422 N / 6,672,140 E        ──▶     27.123°E / 60.234°N
```

### 6.2 EPSG codes relevant to SimpleAnalysis (Finnish context)
| EPSG | Name | Notes |
|---|---|---|
| 4326 | WGS84 Geographic | GPS coordinates, GeoJSON default, web APIs |
| 3857 | Web Mercator | Web tile basemaps (OSM, Google, Esri) — ONLY for display |
| 3067 | ETRS-TM35FIN | Finnish national grid; all NLS/VMI/LiDAR data; metre units |
| 25832 | ETRS89/UTM 32N | Western Finland border areas |
| 25833 | ETRS89/UTM 33N | Eastern Finland |
| 32635 | WGS84/UTM 35N | Generic UTM for the Finland area |
| 4258 | ETRS89 Geographic | European geodetic datum, degree units |

### 6.3 Assign CRS vs. Reproject

**Assign (Set) CRS** — changes the CRS tag in memory/metadata without touching
coordinate values. Use when: file was created with the wrong label but coordinates are
already correct (e.g. a Finnish LiDAR file missing the EPSG:3067 tag).

**Reproject (Warp)** — mathematically transforms every coordinate into the new CRS and
writes a new file. Use when: you need data in a specific CRS for an analysis that
requires matching projections (e.g. overlaying two rasters for band math).

### 6.4 Why CRS matters for display
Leaflet renders in WGS84 (EPSG:4326). Any data in another CRS must be reprojected to
WGS84 before passing to leaflet. In R: `terra::project(r, "EPSG:4326")` for rasters,
`sf::st_transform(v, 4326)` for vectors.

For auto-zoom on upload, we need the extent in WGS84 regardless of source CRS.

---

## 7. Raster Processing Operations

### 7.1 Format and geometry
| Operation | What it does | R / terra equivalent |
|---|---|---|
| Clip by extent | Crop to a bounding box | `terra::crop(r, ext)` |
| Clip by mask layer | Crop to a polygon and set pixels outside to NoData | `terra::mask(r, v)` |
| Merge / Mosaic | Stitch multiple adjacent rasters into one | `terra::mosaic(r1, r2)` |
| Reproject | Transform CRS + resample to new grid | `terra::project(r, crs)` |
| Resample | Change cell size (up or down) | `terra::resample(r, template)` |
| Aggregate | Reduce resolution by averaging N×N cells | `terra::aggregate(r, n)` |
| Disaggregate | Increase resolution (nearest / bilinear) | `terra::disagg(r, n)` |
| Translate | Format conversion without changing CRS or values | `terra::writeRaster()` |
| Build overviews | Pre-compute pyramid levels for fast display | `gdalUtils` |

### 7.2 Analysis
| Operation | What it does | R / terra equivalent |
|---|---|---|
| Raster calculator | Pixel-wise math across bands/layers | `terra::lapp()`, `r1 - r2` |
| Zonal statistics | Per-polygon summary of raster values | `exactextractr::exact_extract()` |
| Slope | Gradient angle from DEM (degrees or percent) | `terra::terrain(r, "slope")` |
| Aspect | Direction of slope (0–360°, N=0/360) | `terra::terrain(r, "aspect")` |
| Hillshade | Illumination simulation from azimuth/elevation | `terra::shade()` |
| Contour lines | Isolines at regular value intervals | `terra::as.contour()` |
| Viewshed | Visible area from a point on a DEM | custom lidR / viewshed |
| Reclassify | Map value ranges to new discrete values | `terra::classify()` |
| Proximity | Distance to nearest non-NA pixel | `terra::distance()` |
| Focal statistics | Moving-window statistics (mean, max, etc.) | `terra::focal()` |
| Smoothing | Gaussian / low-pass filter | `terra::focal()` with Gaussian kernel |

### 7.3 Spectral indices (pixel math on band combinations)
| Index | Formula | Detects |
|---|---|---|
| NDVI | (NIR − Red) / (NIR + Red) | Vegetation density and health |
| NDWI | (Green − NIR) / (Green + NIR) | Water bodies, soil moisture |
| NBR | (NIR − SWIR) / (NIR + SWIR) | Burn severity |
| EVI | 2.5 × (NIR − Red) / (NIR + 6×Red − 7.5×Blue + 1) | Improved vegetation (reduces saturation) |
| NDRE | (RedEdge − Red) / (RedEdge + Red) | Chlorophyll content (requires RedEdge band) |
| NDSI | (Green − SWIR) / (Green + SWIR) | Snow cover |
| SAVI | ((NIR − Red) / (NIR + Red + L)) × (1 + L) | Vegetation over sparse areas (L=0.5) |
| BSI | ((Red + SWIR) − (NIR + Blue)) / ((Red + SWIR) + (NIR + Blue)) | Bare soil |

For Sentinel-2 (10m bands: B2=Blue, B3=Green, B4=Red, B8=NIR; 20m: B8A, B11=SWIR, B5=RedEdge).

### 7.4 Surface model operations (from LiDAR)
| Product | How it's derived |
|---|---|
| DTM (Digital Terrain Model) | Ground-classified points → TIN interpolation |
| DSM (Digital Surface Model) | First return / max Z per cell |
| CHM (Canopy Height Model) | DSM − DTM = vegetation height |
| nDSM (normalized DSM) | Synonym for CHM in some contexts |
| Intensity raster | Mean/max LiDAR return intensity per cell |
| Point density | Count of returns per cell |
| Return density | Count of all returns (echoes) per cell |

---

## 8. Vector Processing Operations

### 8.1 Geometric operations
| Operation | What it does | R / sf equivalent |
|---|---|---|
| Buffer | Expand geometry by distance | `sf::st_buffer(v, dist)` |
| Intersect | Geometry where two layers overlap | `sf::st_intersection(a, b)` |
| Union | Combine, keeping all geometry + attributes | `sf::st_union(a, b)` |
| Difference | Subtract B from A | `sf::st_difference(a, b)` |
| Dissolve | Merge features by shared attribute | `dplyr::group_by() + sf::summarise()` |
| Clip | Crop to polygon boundary | `sf::st_intersection(a, clip_poly)` |
| Convex hull | Minimum convex polygon around point set | `sf::st_convex_hull()` |
| Centroid | Point at polygon centroid | `sf::st_centroid()` |
| Voronoi | Tessellation from point layer | `sf::st_voronoi()` |
| Triangulate (TIN) | Delaunay triangulation | `sf::st_triangulate()` |
| Snap to grid | Round coordinates to grid (clean up slivers) | `sf::st_snap_to_grid()` |
| Fix geometries | Repair self-intersections, open rings | `sf::st_make_valid()` |
| Simplify | Reduce vertex count (Douglas-Peucker) | `sf::st_simplify()` |
| Smooth | Chaikin / Bézier smoothing of edges | `smoothr::smooth()` |

### 8.2 Attribute / table operations
| Operation | What it does | R equivalent |
|---|---|---|
| Spatial join | Attach attributes based on spatial location | `sf::st_join(a, b, join = st_intersects)` |
| Join by attribute | Table join on matching field | `dplyr::left_join()` |
| Select by attribute | Filter rows by field values | `dplyr::filter()` |
| Select by location | Select rows that spatially intersect another layer | `sf::st_filter()` |
| Statistics by category | Group-by aggregation | `dplyr::group_by() + summarise()` |
| Field calculator | Compute/update fields | `dplyr::mutate()` |
| Rasterize | Convert vector to raster grid | `terra::rasterize()` |

### 8.3 Coordinate conversion
| Operation | What it does | R / sf equivalent |
|---|---|---|
| Reproject | Transform to a new CRS | `sf::st_transform(v, crs)` |
| Assign CRS | Set CRS without transforming | `sf::st_set_crs(v, crs)` |
| To WKT | Export geometry as text | `sf::st_as_text()` |
| XY to points | CSV with lat/lon columns → point layer | `sf::st_as_sf(df, coords=c("lon","lat"))` |

---

## 9. The "Add Layer → Zoom to It" Workflow (Critical)

This is the most fundamental GIS workflow and the one users expect most:

```
1. User clicks "Add Layer" / uploads a file
2. File is parsed and stored in memory
3. App automatically:
   a. Computes the bounding box (extent) in the file's native CRS
   b. Projects that bounding box to WGS84 (EPSG:4326)
   c. Calls fitBounds(west, south, east, north) on the map
   d. Map smoothly pans and zooms to show the full layer extent
4. Layer appears in the Layer Panel on the left with its name and type icon
5. Map renders the layer on the canvas (raster color-ramped, vector with default style)
```

If step 3 is missing or delayed, users think "nothing happened" — even if the layer was
loaded correctly into memory. **The zoom is the feedback that loading succeeded.**

### Padding / buffer
Most GIS tools add ~5–10% padding around the extent so the edges aren't flush with the
canvas border. In leaflet: use `fitBounds()` with the `options` parameter or simply
expand the bbox slightly before calling `fitBounds`.

### Multiple layers
When multiple layers are loaded, "Zoom to All" (or Zoom to Full Extent) computes the
union of all bounding boxes and zooms to fit everything.

---

## 10. Map Decorations (Overlays on the Canvas)

Elements rendered on top of the map content (not interactive, just informational):

| Element | Description |
|---|---|
| Scale bar | Shows distance at current zoom. "100 m" → "1 km" as you zoom. |
| North arrow | Arrow pointing to geographic north. |
| Copyright / attribution | Required by tile provider licenses (OSM, Esri). |
| Coordinate grid | Graticule lines at regular lat/lon or projected intervals. |
| Legend | Color ramp / category swatches for active layers. |
| Layer credits | Data source, vintage, accuracy statement. |

Leaflet: `addScaleBar()`, attribution in `addTiles()`, legend via `addLegend()`.

---

## 11. Processing Toolbox Pattern

In QGIS / ArcGIS, processing tools follow a consistent pattern:

```
┌─────────────────────────────────────────────────┐
│ Tool: Clip Raster by Mask Layer                 │
├─────────────────────────────────────────────────┤
│ Input layer:     [CHM_2m ▾]                     │  ← pick from loaded layers
│ Mask layer:      [Study_area ▾]                 │  ← pick from loaded layers
│                                                 │
│ Resampling:      [Nearest Neighbor ▾]           │  ← params
│ Keep resolution: [✓]                            │
│ No-data value:   [-9999        ]                │
│                                                 │
│ Output layer:    [CHM_clipped       ] [📁 Browse]│  ← output name / path
│                                                 │
│ [Run in Background]  [Close]  [✓ Run]           │  ← action buttons
└─────────────────────────────────────────────────┘
```

Key UX patterns:
- **Input pickers** always list currently loaded layers (not file browser by default).
- **Output name** defaults to `input_name + "_clipped"` etc. User can override.
- **Run in Background** executes asynchronously — user can continue working.
- On completion: result layer auto-added to the layer panel and auto-zoomed.
- **Log tab**: shows GDAL/GEOS output, warnings, errors — essential for debugging.
- **Algorithm History**: every run is recorded with all parameters — can be re-run or
  exported as a script.

---

## 12. Print Layout / Map Export

Separate from the map canvas — a dedicated layout editor:

```
┌──────────────────────────────────────────────────────────┐
│ Layout Editor                                            │
├──────────────┬───────────────────────────────────────────┤
│ Items panel  │                                           │
│ ▸ Map Frame  │   [Page canvas — A4 / Letter / custom]   │
│ ▸ Scale bar  │                                           │
│ ▸ North arr. │   ┌──────────────────────────────┐       │
│ ▸ Legend     │   │  Map Frame (linked to canvas)│       │
│ ▸ Title      │   │  [renders current map view]  │       │
│ ▸ Logo       │   └──────────────────────────────┘       │
│              │                                           │
│ Export:      │   [Scale bar]  [Title text]               │
│ PDF / PNG /  │   [Legend]     [North arrow]              │
│ SVG          │                                           │
└──────────────┴───────────────────────────────────────────┘
```

Each element is independently positionable with handles (like PowerPoint).
The map frame is "linked" to the main canvas view but can have an independent scale/extent.

For SimpleAnalysis: a simpler "Download Map" button that uses `mapview::mapshot()` to
render the current leaflet view as a PNG is sufficient for MVP.

---

## 13. SimpleAnalysis Spatial Analysis — Design Specification

Based on all of the above, here is the exact design for SimpleAnalysis's spatial screen.

### 13.1 Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SimpleAnalysis top menubar — Spatial Analysis selected                          │
├───────────────────┬─────────────────────────────────────┬───────────────────┤
│  LAYER MANAGER    │         LEAFLET MAP CANVAS          │  PROCESSING TOOLS │
│  (left, 220px)    │         (fills center)              │  (right, 320px)   │
│                   │                                     │                   │
│  [Zoom All] [+]   │  [OSM | Satellite | Topo]  (top)   │  accordion:       │
│                   │                                     │  ▸ Symbology      │
│  ▸ (rst) raster1 ×│                                     │  ▸ Clip           │
│      opacity 80%  │                                     │  ▸ Reproject      │
│  ▸ (rst) raster2 ×│                                     │  ▸ Band Math      │
│      opacity 100% │                                     │  ▸ Zonal Stats    │
│  ▸ (vec) plots.shp×│                                    │  ▸ Vector Ops     │
│      opacity 100% │  [Scale bar]  [N↑]  (bottom-left)  │  ▸ Export         │
│                   │  [CRS] [X:... Y:...]  (bottom-right)│                   │
├───────────────────┴─────────────────────────────────────┴───────────────────┤
│  Status: CHM_2m | EPSG:3067 | 1050×980 cells | 2.0m res | Min:0 Max:28.4m  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 13.2 Layer Manager (on-canvas overlay, left side of the leaflet map)
- Floating panel overlaid on the map (CSS absolute position, top-left, z-index:800).
- Shows only layers currently added to the map (subset of what's in the Datasets panel).
- Each row: `[👁 toggle] [icon] [name] [opacity mini-slider] [🎯 zoom] [×]`
- Drag-to-reorder (HTML5 draggable, or Up/Down arrow buttons as simpler alternative).
- "Add Layer" button opens a modal to pick from `raster_pool` / `vector_pool`.
- "Zoom All" button: `fitBounds(union of all extents)`.
- Collapsible (click the panel header to minimize to just the title bar).

### 13.3 Auto-zoom behavior
- Any time a layer is added to the map (from pool), call `fitBounds` immediately.
- Any time a new raster/vector is uploaded (via left-rail Add Data), AND the user is on
  the Spatial Analysis screen, auto-add it to the map layer list and zoom to it.
- The zoom must happen in the same reactive chain as the upload, not deferred.

### 13.4 Processing Tools (right panel)
Each operation is an `accordion_panel`:

**Symbology** (shown when a raster layer is active):
- Color ramp picker (dropdown: Viridis, RdYlGn, Greys, Terrain, Spectral).
- Stretch method (Min/Max, Percentile 2-98%, StdDev ±2).
- Custom min/max input.
- Opacity slider.
- Band picker (for multi-band rasters).
- Apply button → `leafletProxy %>% clearImages() %>% addGeoRaster(...)`.

**Clip**:
- Input: layer picker.
- Clip by: extent (drawn on map) or mask layer (vector layer picker).
- Output name.
- Run → `terra::crop()` / `terra::mask()` → `raster_pool[[name]]` → auto-add to map.

**Reproject**:
- Input: layer picker.
- Target EPSG input.
- Run → `terra::project()` → save to pool.

**Band Math / Raster Calculator**:
- Expression input (e.g. `(b1 - b2) / (b1 + b2)` where b1/b2 refer to uploaded rasters).
- Run → parse expression → `terra::lapp()` or arithmetic → save to pool.

**Spectral Indices**:
- Preset buttons: NDVI, NDWI, NBR, EVI, NDRE.
- Pick which band from which layer maps to NIR/Red/Green/SWIR.
- Run → formula → save to pool.

**Zonal Statistics**:
- Zone layer (vector): picker.
- Value raster: picker.
- Statistics: checkboxes (mean, max, min, std, count).
- Run → `exactextractr::exact_extract()` → append to vector layer attributes → save to
  `vector_pool`.

**Vector Operations**:
- Tool picker: Buffer / Dissolve / Clip / Spatial Join.
- Parameters specific to each tool.
- Run → `sf::*` operation → `vector_pool[[name]]` → auto-add to map.

**Export**:
- Layer picker.
- Format: GeoTIFF / GeoPackage / GeoJSON / CSV.
- `downloadButton` → `terra::writeRaster()` or `sf::st_write()`.

### 13.5 Status bar
Shows metadata for the active (selected) layer:
- Name, type icon.
- CRS (EPSG code + name).
- For rasters: rows × cols, cell resolution, min value, max value, no-data value.
- For vectors: feature count, geometry type.

### 13.6 Module wiring
```r
# In ui.R:
.viewPanel("spatial", spatialCanvasUI("spatial"))
.viewPanel("spatial", spatialToolsUI("spatial"))

# In server.R:
spatial_ctx <- spatialServer("spatial", raster_pool, vector_pool, active_dataset)

# Module signature:
spatialServer <- function(id, raster_pool = NULL, vector_pool = NULL, active_dataset = NULL)
```

The existing `mod_raster.R` becomes the base for this new unified spatial module, with
the on-canvas layer manager added and the processing tools accordion expanded.

---

## 14. Implementation Phases

### Phase 1 — Core display (MVP)
- [ ] Leaflet canvas with OSM/Satellite basemap switcher.
- [ ] Auto-add any newly uploaded raster/vector to the map.
- [ ] Auto-zoom to each layer on upload.
- [ ] On-canvas layer manager overlay (visibility toggle + zoom-to + remove + opacity).
- [ ] Raster display via `leafem::addGeoRaster()` with Viridis default color ramp.
- [ ] Vector display via `leaflet::addPolygons()` / `addCircleMarkers()`.
- [ ] Scale bar + CRS badge overlay.

### Phase 2 — Symbology
- [ ] Color ramp picker per raster layer.
- [ ] Stretch method (min/max / percentile).
- [ ] Opacity slider per layer.
- [ ] Band picker for multi-band rasters.
- [ ] Vector symbology: fill color, stroke color, size.

### Phase 3 — Processing
- [ ] Clip raster by extent (draw on map).
- [ ] Reproject raster to new EPSG.
- [ ] Spectral indices calculator (NDVI, NDWI presets).
- [ ] Zonal statistics.
- [ ] Vector buffer + dissolve.
- [ ] Results auto-added to map + zoom.

### Phase 4 — Advanced
- [ ] Raster calculator with expression input.
- [ ] Vector spatial join.
- [ ] Map export (PNG download).
- [ ] Layer reordering (drag or Up/Down buttons).
- [ ] Identify tool (click map → show pixel/feature values).
- [ ] Histogram panel for active raster layer.
