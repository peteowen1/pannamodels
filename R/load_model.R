# Model Loading Functions
# =======================
# Functions for loading pre-trained football models from local cache or GitHub releases.

#' @noRd
.EPV_MODELS <- c(
  "xg_model" = "Expected Goals (xG) model — XGBoost binary classifier for shot conversion",
  "xgot_model" = "Expected Goals On Target (xGOT / post-shot xG) — XGBoost classifier using goal-mouth placement",
  "xpass_model" = "Expected Pass (xPass) model — pass completion probability",
  "epv_model" = "Expected Possession Value (EPV) model — action-level player valuation",
  "wp_model" = "Win Probability (WP) model — XGBoost binary classifier (possession-POV outcome)",
  "duel_model" = "xDuel model — 5 context-only XGBoost classifiers (aerial win/possession, take-on, tackle, containment) producing above-expected duel WOE features for PSR/PSV"
)

#' @noRd
.PREDICTION_MODELS <- c(
  "goals_home_model" = "Home goals prediction — XGBoost Poisson model",
  "goals_away_model" = "Away goals prediction — XGBoost Poisson model",
  "outcome_model" = "Match outcome (H/D/A) — XGBoost multinomial model"
)

#' Get the pannamodels repository
#' @keywords internal
get_pannamodels_repo <- function() {
  getOption("pannamodels.repo", "peteowen1/pannamodels")
}

#' Get the local models directory
#' @keywords internal
get_models_dir <- function() {
  cache_dir <- getOption("pannamodels.cache_dir", NULL)
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    return(cache_dir)
  }
  cache_base <- tools::R_user_dir("pannamodels", "cache")
  models_dir <- file.path(cache_base, "models")
  if (!dir.exists(models_dir)) dir.create(models_dir, recursive = TRUE)
  return(models_dir)
}

# Manifest-verified cache freshness (ECOSYSTEM-FIX-PLAN.md M5)
# -----------------------------------------------------------------
# pannamodels has no manifest layer of its own (unlike torpmodels'
# models_manifest.json) -- it uses versebus's generic bus_manifest.json
# directly. `.get_bus_manifest()` wraps `vb_read_manifest()` (vendored in
# versebus.R) with a session-local, rate-limited cache (one fetch per
# (repo, tag) per 15-minute window) so a cache-hit check doesn't hit the
# network on every single load. `vb_read_manifest()` already implements the
# "exactly one legacy-mode warning per session per tag" rule internally
# (via its own `.vb_state` env) for the confirmed-absent case; what it does
# NOT do is degrade gracefully on a *transient* fetch failure -- it
# propagates those (by design, for producer callers that must not silently
# treat a network blip as "no manifest"). A read-only cache-freshness check
# must not hard-fail a load that could otherwise succeed from a good local
# cache, so that propagated error is caught here and degraded to "skip
# verification this session" instead.

#' @noRd
.pm_manifest_state <- new.env(parent = emptyenv())

#' @noRd
.pm_manifest_ttl_secs <- 900L

#' Session-cached, rate-limited fetch of a tag's bus_manifest.json
#' @keywords internal
.get_bus_manifest <- function(repo, tag, verbose = TRUE) {
  key <- paste0(repo, "@", tag)
  cached <- .pm_manifest_state[[key]]
  if (!is.null(cached) &&
      as.numeric(Sys.time() - cached$fetched_at, units = "secs") < .pm_manifest_ttl_secs) {
    return(cached$manifest)
  }

  manifest <- tryCatch(
    vb_read_manifest(repo, tag, required = FALSE),
    error = function(e) {
      if (verbose) {
        cli::cli_warn("Could not fetch bus_manifest.json for {.val {tag}} ({conditionMessage(e)}) -- skipping cache verification this session")
      }
      NULL
    }
  )
  .pm_manifest_state[[key]] <- list(manifest = manifest, fetched_at = Sys.time())
  manifest
}

#' Is a locally cached model file still valid against bus_manifest.json?
#'
#' TRUE (serve from cache) when there's no manifest to check against
#' (legacy mode) or no entry for this specific file (an untracked asset --
#' can't validate it, so don't punish it); otherwise delegates to
#' versebus's sidecar-based `vb_cache_validate()`.
#' @keywords internal
.pm_cache_is_fresh <- function(repo, tag, file_name, local_path, verbose = TRUE) {
  manifest <- .get_bus_manifest(repo, tag, verbose)
  if (is.null(manifest) || is.null(manifest$assets)) return(TRUE)
  entry <- .vb_manifest_entry_for(manifest, file_name)
  if (is.null(entry) || is.null(entry$sha256)) return(TRUE)
  vb_cache_validate(local_path, entry)
}


#' Load a Panna Model
#'
#' Loads a pre-trained model from local cache or downloads from GitHub releases.
#'
#' @param model_name Character. Name of the model. See [list_available_models()].
#' @param force_download Logical. If TRUE, downloads fresh copy even if cached.
#' @param verbose Logical. If TRUE, prints status messages.
#'
#' @return The loaded model object
#' @export
#'
#' @examples
#' \dontrun{
#' xg <- load_panna_model("xg_model")
#' epv <- load_panna_model("epv_model")
#' }
load_panna_model <- function(model_name, force_download = FALSE, verbose = TRUE) {
  model_name <- tolower(model_name)
  info <- resolve_model(model_name)

  if (is.null(info)) {
    all_names <- unlist(lapply(list_available_models(), names))
    cli::cli_abort(c(
      "Unknown model: {model_name}",
      "i" = "Available: {paste(all_names, collapse = ', ')}"
    ))
  }

  local_path <- file.path(get_models_dir(), info$tag, info$file)
  repo <- get_pannamodels_repo()

  if (file.exists(local_path) && !force_download) {
    if (.pm_cache_is_fresh(repo, info$tag, info$file, local_path, verbose)) {
      if (verbose) cli::cli_inform("Loading {model_name} from local cache")
      return(safe_read_rds(local_path, model_name))
    }
    if (verbose) cli::cli_inform("Cached {model_name} does not match bus_manifest.json -- re-downloading")
  }

  if (verbose) cli::cli_inform("Downloading {model_name} from GitHub releases...")
  download_model(info$file, info$tag, local_path, verbose)

  if (!file.exists(local_path)) {
    cli::cli_abort("Failed to download model: {model_name}")
  }

  safe_read_rds(local_path, model_name)
}


#' List Available Models
#'
#' @return A list with epv and prediction model categories
#' @export
#'
#' @examples
#' list_available_models()
list_available_models <- function() {
  list(
    epv = .EPV_MODELS,
    prediction = .PREDICTION_MODELS
  )
}


#' Check Model Cache Status
#'
#' @return Data frame with model names, cached status, and sizes
#' @export
check_model_cache <- function() {
  models_dir <- get_models_dir()
  all_models <- c(.EPV_MODELS, .PREDICTION_MODELS)

  results <- data.frame(
    model = character(), type = character(),
    cached = logical(), size_mb = numeric(),
    stringsAsFactors = FALSE
  )

  for (nm in names(all_models)) {
    info <- resolve_model(nm)
    if (is.null(info)) next
    path <- file.path(models_dir, info$tag, info$file)
    cached <- file.exists(path)
    size <- if (cached) round(file.size(path) / 1024^2, 2) else NA_real_
    results <- rbind(results, data.frame(
      model = nm, type = info$tag, cached = cached, size_mb = size,
      stringsAsFactors = FALSE
    ))
  }
  results
}


#' Clear Model Cache
#'
#' @param type Character. "all", "epv", or "prediction".
#' @param verbose Logical. Print messages.
#' @return Invisible NULL
#' @export
clear_model_cache <- function(type = "all", verbose = TRUE) {
  type <- match.arg(type, c("all", "epv", "prediction"))
  models_dir <- get_models_dir()
  tags <- if (type == "all") c("epv", "prediction") else type

  for (tag in tags) {
    tag_dir <- file.path(models_dir, tag)
    if (dir.exists(tag_dir)) {
      files <- list.files(tag_dir, full.names = TRUE)
      if (length(files) > 0) {
        unlink(files)
        if (verbose) cli::cli_inform("Cleared {length(files)} {tag} model(s)")
      }
    }
  }
  invisible(NULL)
}


# Internal helpers

#' @keywords internal
resolve_model <- function(model_name) {
  if (model_name %in% names(.EPV_MODELS)) {
    return(list(file = paste0(model_name, ".rds"), tag = "epv"))
  }
  if (model_name %in% names(.PREDICTION_MODELS)) {
    return(list(file = paste0(model_name, ".rds"), tag = "prediction"))
  }
  NULL
}

#' @keywords internal
safe_read_rds <- function(path, label = basename(path)) {
  tryCatch(
    readRDS(path),
    error = function(e) {
      msg <- conditionMessage(e)
      is_corruption <- grepl(
        "unknown input format|not an RDS file|decompression|bad restore file",
        msg, ignore.case = TRUE
      )
      if (is_corruption) {
        unlink(path)
        unlink(paste0(path, ".sha256"))
        cli::cli_abort("Model {label} corrupted: {msg}. Cache cleared, try again.")
      }
      cli::cli_abort("Failed to load {label}: {msg}")
    }
  )
}

#' Download model from GitHub release
#'
#' Verifies sha256 against `bus_manifest.json` when the tag's manifest
#' tracks this file -- replacing the old `file.size > 100` heuristic, which
#' is now only a last-resort fallback for tags with no manifest entry to
#' compare against (legacy mode). Each download attempt lands in a tempdir
#' created beside the destination and is moved into place atomically via
#' `vb_atomic_write()`, with a `<local_path>.sha256` sidecar written
#' alongside on success. A failed integrity check deletes the temp and
#' retries the SAME method once before falling through to the next method
#' (piggyback, then a direct release URL); a pre-existing `local_path` is
#' never touched by a failed download.
#' @keywords internal
#' @importFrom cli cli_inform cli_warn cli_abort
download_model <- function(file_name, release_tag, local_path, verbose = TRUE) {
  repo <- get_pannamodels_repo()
  parent_dir <- dirname(local_path)
  if (!dir.exists(parent_dir)) dir.create(parent_dir, recursive = TRUE)

  manifest <- .get_bus_manifest(repo, release_tag, verbose)
  entry <- .vb_manifest_entry_for(manifest, file_name)

  # One fetch+verify+place attempt. `fetch_fn(tmpdir)` must leave `file_name`
  # inside `tmpdir`; raises a vb_error_integrity on a corrupt/undersized/
  # mismatched download, otherwise propagates whatever error the download
  # call itself raised (network, 404, ...).
  attempt <- function(fetch_fn) {
    tmpdir <- tempfile(".pm_dl_", tmpdir = parent_dir)
    dir.create(tmpdir)
    on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

    fetch_fn(tmpdir)

    tmp <- file.path(tmpdir, file_name)
    if (!file.exists(tmp) || file.size(tmp) == 0L) {
      .vb_abort("{file_name}: download produced no/empty file", "vb_error_integrity")
    }
    if (!is.null(entry) && !is.null(entry$sha256)) {
      got <- vb_sha256(tmp)
      if (!identical(got, entry$sha256)) {
        .vb_abort(
          "{file_name}: sha256 mismatch vs bus_manifest.json (got {substr(got, 1, 12)}..., want {substr(entry$sha256, 1, 12)}...)",
          "vb_error_integrity"
        )
      }
    } else if (file.size(tmp) <= 100L) {
      # No manifest entry to verify against -- legacy size heuristic.
      .vb_abort("{file_name}: downloaded file is too small (likely an error page)", "vb_error_integrity")
    }

    vb_atomic_write(function(p) file.copy(tmp, p, overwrite = TRUE), local_path)
    writeLines(vb_sha256(local_path), paste0(local_path, ".sha256"))
    invisible(TRUE)
  }

  with_retry <- function(fetch_fn, label) {
    result <- tryCatch(attempt(fetch_fn), error = function(e) e)
    if (inherits(result, "vb_error_integrity")) {
      if (verbose) {
        cli::cli_warn("{label} download of {file_name} failed integrity check ({conditionMessage(result)}); retrying once")
      }
      result <- tryCatch(attempt(fetch_fn), error = function(e) e)
    }
    result
  }

  # Try piggyback first (preferred method)
  pb_result <- with_retry(function(tmpdir) {
    piggyback::pb_download(file = file_name, repo = repo, tag = release_tag,
                           dest = tmpdir, overwrite = TRUE)
  }, "piggyback")

  if (!inherits(pb_result, "error")) {
    if (verbose) cli::cli_inform("Downloaded {file_name}")
    return(invisible(TRUE))
  }
  if (verbose) cli::cli_warn("piggyback failed: {conditionMessage(pb_result)}")

  # Fallback to direct URL download
  url_result <- with_retry(function(tmpdir) {
    url <- paste0("https://github.com/", repo, "/releases/download/", release_tag, "/", file_name)
    if (verbose) cli::cli_inform("Trying direct download from {url}")
    # Qualified on purpose (not an unqualified `@importFrom` binding): a bare
    # `download.file()` resolves to the copy captured in this package's
    # namespace at load time, which testthat's
    # `local_mocked_bindings(.package = "utils")` cannot reach -- only a
    # live `utils::` lookup sees the mocked binding.
    utils::download.file(url, file.path(tmpdir, file_name), mode = "wb", quiet = !verbose)
  }, "direct URL")

  if (!inherits(url_result, "error")) {
    if (verbose) cli::cli_inform("Downloaded {file_name}")
    return(invisible(TRUE))
  }

  # Both methods failed -- report both; type as vb_error_integrity if either
  # failure was a corruption signal (never silently downgrade that to a
  # generic error).
  details <- paste0(
    "piggyback: ", conditionMessage(pb_result), "; ",
    "direct URL: ", conditionMessage(url_result)
  )
  is_integrity <- inherits(pb_result, "vb_error_integrity") || inherits(url_result, "vb_error_integrity")
  cli::cli_abort(
    "Failed to download {file_name} from {release_tag}. {details}",
    class = if (is_integrity) c("vb_error_integrity", "vb_error") else "vb_error"
  )
}
