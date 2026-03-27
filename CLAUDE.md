# CLAUDE.md

Pre-trained ML models for football analytics, served via GitHub releases with local caching.

## Package Overview

**pannamodels** provides pre-trained models for the panna R package. Minimal package (2 R files) — no data processing, just model loading and caching.

## Development Commands

```r
devtools::load_all()
devtools::test()
devtools::check()
devtools::document()
```

## Model Categories

| Release Tag | Models | Format |
|-------------|--------|--------|
| `epv` | xg_model, xpass_model, epv_model | .rds |
| `prediction` | goals_home_model, goals_away_model, outcome_model | .rds |

## Caching

Models cache to `tools::R_user_dir("pannamodels", "cache")/models/`. Use `force_download = TRUE` to bypass.

## Related Projects

Part of the pannaverse ecosystem. See `~/OneDrive/Documents/pannaverse/CLAUDE.md` for monorepo overview. Mirrors torpmodels and bouncermodels pattern. For full ecosystem: `~/OneDrive/Documents/ECOSYSTEM.md`
