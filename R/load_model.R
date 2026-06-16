# Model Loading Functions
# =======================
# Functions for loading pre-trained football models from local cache or GitHub releases.

#' @noRd
.EPV_MODELS <- c(
  "xg_model" = "Expected Goals (xG) model — XGBoost binary classifier for shot conversion",
  "xgot_model" = "Expected Goals On Target (xGOT / post-shot xG) — XGBoost classifier using goal-mouth placement",
  "xpass_model" = "Expected Pass (xPass) model — pass completion probability",
  "epv_model" = "Expected Possession Value (EPV) model — action-level player valuation",
  "wp_model" = "Win Probability (WP) model — XGBoost binary classifier (possession-POV outcome)"
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

  if (file.exists(local_path) && !force_download) {
    if (verbose) cli::cli_inform("Loading {model_name} from local cache")
    return(safe_read_rds(local_path, model_name))
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
        cli::cli_abort("Model {label} corrupted: {msg}. Cache cleared, try again.")
      }
      cli::cli_abort("Failed to load {label}: {msg}")
    }
  )
}

#' @keywords internal
#' @importFrom cli cli_inform cli_warn cli_abort
#' @importFrom utils download.file
download_model <- function(file_name, release_tag, local_path, verbose = TRUE) {
  repo <- get_pannamodels_repo()
  parent_dir <- dirname(local_path)
  if (!dir.exists(parent_dir)) dir.create(parent_dir, recursive = TRUE)

  tryCatch({
    temp_dir <- tempdir()
    piggyback::pb_download(file = file_name, repo = repo, tag = release_tag, dest = temp_dir)
    temp_path <- file.path(temp_dir, file_name)
    if (file.exists(temp_path) && file.size(temp_path) > 100) {
      file.copy(temp_path, local_path, overwrite = TRUE)
      unlink(temp_path)
      if (verbose) cli::cli_inform("Downloaded {file_name}")
      return(invisible(TRUE))
    }
    stop("File not found or too small")
  }, error = function(e) {
    if (verbose) cli::cli_warn("piggyback failed: {e$message}")
  })

  tryCatch({
    url <- paste0("https://github.com/", repo, "/releases/download/", release_tag, "/", file_name)
    if (verbose) cli::cli_inform("Trying direct download...")
    download.file(url, local_path, mode = "wb", quiet = !verbose)
    if (file.exists(local_path) && file.size(local_path) > 100) return(invisible(TRUE))
  }, error = function(e) {
    cli::cli_warn("Direct download failed: {e$message}")
  })

  cli::cli_abort("Failed to download {file_name} from {release_tag}")
}
