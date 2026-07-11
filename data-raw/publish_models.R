# publish_models.R
# Publish trained pannamodels model files to GitHub Releases, manifest-last.
#
# ECOSYSTEM-FIX-PLAN.md M5: routes the upload through vb_publish() (vendored
# in R/versebus.R) instead of an unverified `piggyback::pb_upload(...,
# overwrite = TRUE)` loop -- hash-first, bounded-retry upload, post-upload
# verify against the live asset list, then bus_manifest.json uploaded LAST
# and only if every file in the tag succeeded. A failed upload aborts before
# the manifest, so consumers (`.get_bus_manifest()` / `.pm_cache_is_fresh()`
# in R/load_model.R) keep seeing the last consistent tag snapshot instead of
# a torn one.
#
# NOTE: the production EPV/WP model promotion path today is
# `panna/.github/workflows/epv-pipeline.yml` (raw `gh release upload ...
# --clobber`, a workflow step in the panna repo, out of scope for this
# pass). This script is pannamodels' own vb_publish-routed producer path for
# models staged locally -- wiring it into that workflow (or running it
# ad-hoc after copying files locally) is a follow-up, not done here.
#
# Usage: Rscript data-raw/publish_models.R
# (Not run as part of this change -- no upload is performed by editing this
# file.)

devtools::load_all(".")

REPO <- "peteowen1/pannamodels"
MODELS_DIR <- getOption("pannamodels.publish_dir",
                        "C:/dev/pannaverse/pannadata/opta/models")

cli::cli_h1("Publish Models to pannamodels")

if (!dir.exists(MODELS_DIR)) {
  cli::cli_abort("Models directory not found: {MODELS_DIR}
                  (set options(pannamodels.publish_dir = ...) to override)")
}

releases <- list(
  epv = names(.EPV_MODELS),
  prediction = names(.PREDICTION_MODELS)
)

for (tag in names(releases)) {
  cli::cli_h2("Release: {tag}")

  files <- file.path(MODELS_DIR, paste0(releases[[tag]], ".rds"))
  present <- files[file.exists(files)]
  missing <- files[!file.exists(files)]
  for (m in missing) cli::cli_alert_warning("Not found, skipping: {basename(m)}")

  if (length(present) == 0) {
    cli::cli_alert_info("No local files for tag {tag}, nothing to publish")
    next
  }

  vb_publish(present, repo = REPO, tag = tag)
  cli::cli_alert_success("Published {length(present)} file(s) to {REPO}@{tag} (bus_manifest.json updated)")
}

cli::cli_h1("Publish Complete")
