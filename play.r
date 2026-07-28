# Load required libraries
library(ggplot2)
library(dplyr)
library(patchwork)

# 1. Generate Synthetic 1D Data
set.seed(42)
n <- 300
df <- data.frame(
  x = c(rnorm(n/3, mean = 2, sd = 0.6), 
        rnorm(n/3, mean = 4, sd = 0.9), 
        rnorm(n/3, mean = 6, sd = 0.6)),
  Actual = factor(rep(c("Class 1", "Class 2", "Class 3"), each = n/3))
)

# 2. Define Decision Boundaries and Background Grid
# Let's say our model learned boundaries at x = 3.2 and x = 5.0
boundaries <- c(3.2, 5.0)

grid <- data.frame(x = seq(min(df$x) - 0.5, max(df$x) + 0.5, length.out = 500))
grid$Predicted <- factor(
  ifelse(grid$x < boundaries[1], "Class 1",
         ifelse(grid$x < boundaries[2], "Class 2", "Class 3"))
)

# Common color palette
class_colors <- c("Class 1" = "#F8766D", "Class 2" = "#00BA38", "Class 3" = "#619CFF")

# ---------------------------------------------------------
# Option A — Explicit Boundaries + Rug
# ---------------------------------------------------------
plot_a <- ggplot() +
  # Background tiles for predicted regions
  geom_tile(data = grid, aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
  # Vertical lines for explicit boundaries
  geom_vline(xintercept = boundaries, linetype = "dashed", color = "black", linewidth = 0.8) +
  # Rug plot for actual data points
  geom_rug(data = df, aes(x = x, color = Actual), sides = "b", length = unit(0.1, "npc"), linewidth = 0.5) +
  scale_fill_manual(values = class_colors) +
  scale_color_manual(values = class_colors) +
  theme_minimal() +
  theme(legend.position = "none", axis.text.y = element_blank(), axis.title.y = element_blank()) +
  labs(title = "Option A: Boundaries + Rug", x = "Feature X")

# ---------------------------------------------------------
# Option B — Class Lanes
# ---------------------------------------------------------
plot_b <- ggplot() +
  # Background tiles mapped to the full y-axis height
  geom_tile(data = grid, aes(x = x, y = 2, height = 4, fill = Predicted), alpha = 0.2) +
  # Points mapped to their actual class index (y-lanes)
  geom_point(data = df, aes(x = x, y = as.numeric(Actual), color = Actual), 
             size = 2, alpha = 0.8, shape = 16) +
  scale_fill_manual(values = class_colors) +
  scale_color_manual(values = class_colors) +
  scale_y_continuous(breaks = 1:3, labels = c("Class 1", "Class 2", "Class 3"), limits = c(0.5, 3.5)) +
  theme_minimal() +
  theme(legend.position = "none", panel.grid.minor.y = element_blank()) +
  labs(title = "Option B: Class Lanes", x = "Feature X", y = "Actual Class")

# ---------------------------------------------------------
# Option C — Density Curves over Regions
# ---------------------------------------------------------
plot_c <- ggplot() +
  # Background tiles
  geom_tile(data = grid, aes(x = x, y = 0, height = Inf, fill = Predicted), alpha = 0.2) +
  # Density curves overlay
  geom_density(data = df, aes(x = x, fill = Actual, color = Actual), alpha = 0.5, linewidth = 0.5) +
  scale_fill_manual(values = class_colors) +
  scale_color_manual(values = class_colors) +
  theme_minimal() +
  theme(legend.position = "bottom") +
  labs(title = "Option C: Density Curves", x = "Feature X", y = "Density")

# ---------------------------------------------------------
# Combine and Render 
# ---------------------------------------------------------
# Uses the patchwork library to stack them cleanly
combined_plot <- plot_a / plot_b / plot_c + 
  plot_layout(guides = "collect") & theme(legend.position = "bottom")

# Display
print(combined_plot)