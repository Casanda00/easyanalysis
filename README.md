# EasyAnalysis (R Shiny Application)

EasyAnalysis is an integrated, modular R Shiny application designed as a comprehensive analytics, modeling, and spatial data processing platform. Developed to support environmental and forestry research—such as tree growth, trafficability modeling, and National Forest Inventory (NFI) analysis—it provides a powerful "GeoLibre-inspired" graphical interface. 

Users can upload diverse datasets, perform rich data engineering and exploratory data analysis (EDA), and seamlessly flow into statistical modeling, machine learning, and specialized LiDAR/Spatial analyses—all within a single, persistent workspace.

## Key Features & Architecture

EasyAnalysis operates on a persistent, single-frame shell. Instead of entirely separate full-screen tabs, the interface utilizes a top menubar, a unified left-rail dataset manager, a dynamic center canvas, and a contextual right-side tools panel that update in lockstep based on the active module.

### 1. Data Engineering & EDA (`mod_data.R`)
* **Global Dataset Pool:** Upload standard files (.csv, .xlsx, .txt) which are loaded into a shared memory pool accessible by all modules.
* **ETL Toolbox:** Rename columns, filter rows, impute missing data, perform joins, and apply data type conversions.
* **Level Management:** Rename, merge, or delete factor levels with automatic data-type correction.
* **Aggregation & Binning:** Aggregate data by mean, sum, median, min, or max dynamically, and bin continuous variables into categorical classes.
* **Batch Apply:** Instantly deploy cleaning and processing pipelines from the working dataset to multiple other datasets in the global pool.
* **Exploratory Plots:** Auto-generated structural overviews, distribution plots, and dynamic relationship mapping (scatter/boxplots).

### 2. Statistical Modeling
* **Linear Regression (`mod_linear_regression.R`)**
* **Linear Mixed Effects / LME (`mod_lme.R`):** Includes powerful tuning for models with fixed and random effects, utilizing the `nlme` package.
* **ANOVA (`mod_anova.R`)**
* **Logistic Regression (`mod_logistic.R`):** Utilizing the `nnet` package for multinomial regression capabilities.

### 3. Machine Learning
* **Random Forest (`mod_rf.R`):** Integrated with partial dependence plots (PDPs) and variable importance evaluations.
* **Discriminant Analysis (`mod_da.R`):** Extensive support for LDA, Weighted LDA, QDA, Regularized LDA, Kernel DA (SVM-RBF), Locally Linear DA, and Maximum Margin (Linear SVM).
* **Clustering Analysis (`mod_clustering.R`):** Robust algorithms generating dendrograms, silhouette widths, and principal component visualisations.
* **Classification (`mod_classification.R`)**

### 4. Spatial & LiDAR Processing (`mod_lidar.R`)
* *Powered heavily by `lidR`, `sf`, `terra`, and interactive `rgl` widgets, the system accommodates large `.laz` point clouds up to 3 GB in size.*
* **Point Cloud & 3D Viewer:** Downsample, filter, and render massive raw aerial point clouds directly into an interactive 3D browser canvas.
* **CHM & Individual Tree Detection (ITD):** Process Canopy Height Models and delineate individual tree crowns dynamically.
* **Metric Extraction:** Extract complex spatial and structural metrics from spatial geometries.

### 5. AI Co-Analyst (`mod_chat.R`)
* The application features a floating AI Co-Analyst widget that retains context of the current active dataset, the active mathematical model outputs, confusion matrices, and the specific plots being shown on the user's screen to provide robust analytical support.

## Dependencies

Core required packages:
* **UI & Core:** `shiny`, `bslib`, `shinyWidgets`, `DT`, `readxl`
* **Modeling & ML:** `nnet`, `nlme`, `MuMIn`, `randomForest`, `pdp`, `MASS`
* **Clustering & Visualization:** `ggplot2`, `cluster`, `factoextra`, `ape`
* **Spatial/LiDAR:** `lidR`, `sf`, `terra`, `rgl`, `scatterplot3d`

*Note: Some algorithms require optional packages (`klaR`, `kernlab`, `heplots`, `ggord`) which are prompted internally by the application when requested.*

## Installing (users)

You do **not** need to clone this repo or know R to use EasyAnalysis. The installer fetches R
if you don't have it, installs the packages into a private library, and starts the app. No
admin rights and no Docker.

Run this once:

```sh
# Windows (PowerShell)
iwr -useb https://easyanalysis.dev/install.ps1 | iex

# macOS / Linux
curl -fsSL https://easyanalysis.dev/install.sh | sh
```

The first run downloads what it needs and takes a few minutes; after that it starts in seconds
and opens at `http://127.0.0.1:7788`.

On Windows the installer also creates an **EasyAnalysis** shortcut on the Desktop and in the
Start Menu, so you never need the terminal again. (Desktop shortcuts are Windows-only for now.)
Close the app with the **Quit** button at the top right.

## Launching the App (development)

Ensure all dependencies are installed. You can verify the build without launching by running:
```sh
Rscript -e "suppressMessages({library(shiny);library(bslib);library(shinyWidgets)}); source('global.R'); source('ui.R'); source('server.R'); cat('OK', paste(class(ui),collapse=','), '\n')"
```
To run the app, set your working directory to the `Shiny_app` folder and run:
```R
shiny::runApp()
```

## Documentation

- **[Getting started](https://easyanalysis.dev/documentation)** — installing it, the workspace,
  menus, file formats, projects, privacy, troubleshooting.
- **[Reference](https://easyanalysis.dev/reference)** — what the app actually computes: the R
  function behind each analysis, the variables it needs, its options and what the metrics mean.
  **Generated from the method registries**, so it cannot drift from the code.
- **[How to use](https://easyanalysis.dev/how-to-use)** — a walkthrough from install to a mapped
  result.

## How to cite

If EasyAnalysis contributed to your work, please cite it. Replace the version with the one you
used — it is shown in **Help ▸ About** and in the app's status bar.

> Gibson, T. C. (2026). *EasyAnalysis: point-and-click statistical, machine-learning and spatial
> analysis* (Version 0.10.16) [Computer software]. https://easyanalysis.dev

```bibtex
@software{gibson_easyanalysis,
  author  = {Gibson, Tim Casanda},
  title   = {{EasyAnalysis: point-and-click statistical, machine-learning and spatial analysis}},
  year    = {2026},
  version = {0.10.16},
  url     = {https://easyanalysis.dev},
  note    = {Computer software}
}
```

[`CITATION.cff`](CITATION.cff) carries the same details in machine-readable form, so GitHub's
**Cite this repository** button offers APA and BibTeX directly.

Where a screen implements a published method, that method's own paper is listed on the app's
**References** screen and should be cited alongside this one — citing the tool does not replace
citing the method.

## Licence

EasyAnalysis is free software under the **GNU General Public License v3.0 or later**
(see [LICENSE](LICENSE)).

That is not a stylistic choice: the app cannot run without R packages that are GPL-3 and offer no
permissive alternative — among them `lidR`, `terra`, `MASS`, `nnet`, `ape`, `shinyWidgets`,
`leaflet.extras`, `base64enc` and `ggspatial`. A work that requires GPL-3 libraries has to be
distributed on GPL-3-compatible terms, so GPL-3 is an honest description of what you receive
rather than a restriction added on top. See [COPYRIGHT](COPYRIGHT) for the full reasoning.

Each dependency remains under its own licence.
