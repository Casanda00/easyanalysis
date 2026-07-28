# Methods catalog — research papers → implemented methodology

Each research paper the user supplies is distilled to **only the methodology we
implement in the app**, and named after its lead author + year (e.g. "Age model —
Kalliovirta & Tokola 2005"). The PDFs live in this folder; this file is the index.

**Workflow:** user drops a paper here → we extract the reusable method → name it
by author → record it below with status → implement in the relevant module.

Status legend: 🟢 implemented · 🟡 partial / in progress · ⚪ cataloged (not yet built)

---

## Kalliovirta & Tokola 2005 — stem diameter & tree age from height + crown width
- **File:** `Kalliovirta_Tokola_2005_stem_diameter_tree_age.pdf`
- **Citation:** Kalliovirta, J. & Tokola, T. 2005. Functions for estimating stem
  diameter and tree age using tree height, crown width and existing stand database
  information. *Silva Fennica* 39(2): 227–248.
- **Method names:**
  - **Diameter model — Kalliovirta & Tokola 2005**
  - **Age model — Kalliovirta & Tokola 2005**

### Methodology to apply
Regression with **transformed dependent variable**, then **bias-corrected
back-transformation** to the original scale (paper §, p.232 / eqs 1–7):

- **Diameter models** — response **square-root** transformed:
  `sqrt(d1.3) = f(h, dcrm, α) + ε` → back-transform `d̂ = f² + var(ε)`.
- **Age models** — response **log** transformed (log-log):
  `ln(age) = f(ln(h), ln(dcrm)) + ε` → back-transform
  `âge = exp(f) · exp(var(ε)/2)`.
- Predictors: tree height `h` (dm), maximum crown diameter `dcrm` (dm), optional
  stand variable `α`. sqrt/log transforms on predictors too (for normality &
  homoscedasticity).
- **Key reusable idea:** when Y is non-linearly transformed, the naive
  back-transform is biased low; add the correction term (`+σ²` for sqrt,
  `×exp(σ²/2)` for log). Verified numerically to recover the true mean.

### Status
- 🟢 **Dependent-variable transformation** (log / log1p / sqrt / inverse) added to
  Linear Regression (predictors were already transformable).
- 🟢 **Bias-corrected back-transformation** to original scale — "Back-transform to
  original scale (bias-corrected)" toggle appears when Y is transformed; the
  Performance Metrics card then reports on the original Y scale. Corrections:
  log/log1p `× exp(s²/2)`, sqrt `+ s²` (paper), inverse = naive `1/fit`
  (no stable correction; the paper doesn't use it). Verified numerically: the
  corrected mean recovers the true mean (sqrt exact; log/log1p close).
- ⚪ **Named presets** ("Diameter model / Age model — K&T 2005") — pending decision.

### Notes
- General, not forestry-locked: the transform-Y + bias-correction machinery
  applies to any response; the diameter/age presets are the worked example.
