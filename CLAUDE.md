# CLAUDE.md

Pre-trained ML models for football analytics, served via GitHub releases with local caching.

## Package Overview

**pannamodels** provides pre-trained models for the panna R package. Minimal package — no data processing, just model loading and caching.

**R files**: `load_model.R` (model download/cache logic), `pannamodels-package.R` (package docs). No GitHub Actions — CI runs in the parent `panna` package which depends on this.

## Development Commands

```r
devtools::load_all()
devtools::test()
devtools::check()
devtools::document()
```

Smoke test: `Rscript data-raw/test_load.R` — lists available models, checks the cache, and downloads + loads `xg_model` from GitHub Releases end-to-end.

## Model Categories

| Release Tag | Models | Format |
|-------------|--------|--------|
| `epv` | xg_model, xpass_model, epv_model, wp_model | .rds |
| `prediction` | goals_home_model, goals_away_model, outcome_model | .rds |

## Usage

```r
# Load a model (downloads on first use, then cached locally)
xg <- pannamodels::load_panna_model("xg_model")
epv <- pannamodels::load_panna_model("epv_model")

# See all available models
pannamodels::list_available_models()

# Check what's cached locally
pannamodels::check_model_cache()

# Force re-download
pannamodels::load_panna_model("xg_model", force_download = TRUE)

# Clear cache
pannamodels::clear_model_cache()          # all
pannamodels::clear_model_cache("epv")     # just EPV models
```

## Key Functions

| Function | Purpose |
|----------|---------|
| `load_panna_model()` | Load model from cache or download from GitHub Releases |
| `list_available_models()` | List all available models by category |
| `check_model_cache()` | Show cache status and sizes |
| `clear_model_cache()` | Clear cached models |

## Caching

Models cache to `tools::R_user_dir("pannamodels", "cache")/models/{tag}/`. Use `force_download = TRUE` to bypass. Override cache dir with `options(pannamodels.cache_dir = "path")`.

## Gotchas

- **First load requires network** — models are downloaded from GitHub Releases via piggyback, with a direct-URL fallback
- **Corrupted models auto-clear** — if an RDS fails to load (decompression error), the cache entry is deleted and you're prompted to retry
- **panna depends on this** — `panna` xMetrics pipeline calls `pannamodels::load_panna_model()` for xG/xPass/EPV models
- **Re-publishing a model does NOT bust local caches** — `gh release upload <tag> model.rds --clobber` replaces the GitHub Release asset, but any machine that already cached that model under `R_user_dir("pannamodels","cache")/models/{tag}/` keeps loading the STALE copy. `load_panna_model()` downloads only when the cache file is *absent* — it never checks remote freshness. After a re-publish, run `clear_model_cache("{tag}")` (or `load_panna_model(..., force_download = TRUE)`) before any local pipeline run, or pass an explicit model override. This bit the 2026-06-19 EPV/WP model swap — the game-logs regen used `epv_model_override` / `wp_model_override` precisely to sidestep it.

## Related Projects

Part of the pannaverse ecosystem. See `C:\dev\pannaverse\CLAUDE.md` for monorepo overview. Mirrors torpmodels and bouncermodels pattern. For full ecosystem: `C:\dev\ECOSYSTEM.md`
