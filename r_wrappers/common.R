#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

read_params <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) {
    stop("No JSON argument provided to R wrapper.")
  }
  jsonlite::fromJSON(args[[1]], simplifyVector = FALSE)
}

as_character_vector <- function(value, name) {
  if (is.null(value)) {
    stop(sprintf("Missing required parameter: %s", name))
  }
  as.character(unlist(value, use.names = FALSE))
}

as_numeric_vector <- function(value, name, expected_length = NULL) {
  if (is.null(value)) {
    stop(sprintf("Missing required parameter: %s", name))
  }
  vector <- as.numeric(unlist(value, use.names = FALSE))
  if (!is.null(expected_length) && length(vector) != expected_length) {
    stop(sprintf("%s must contain exactly %d values.", name, expected_length))
  }
  vector
}

as_nullable_numeric <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  as.numeric(value)
}

as_nullable_character_vector <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  as.character(unlist(value, use.names = FALSE))
}

as_scalar_logical <- function(value, default = FALSE) {
  if (is.null(value)) {
    return(default)
  }
  isTRUE(value)
}

as_scalar_integer <- function(value, default) {
  if (is.null(value)) {
    return(default)
  }
  as.integer(value)
}

ensure_file_exists <- function(path, label) {
  if (is.null(path) || !file.exists(path)) {
    stop(sprintf("%s not found: %s", label, path %||% "<NULL>"))
  }
  normalizePath(path, mustWork = TRUE)
}

ensure_output_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  normalizePath(path, mustWork = TRUE)
}

ensure_parent_dir <- function(path) {
  parent <- dirname(path)
  ensure_output_dir(parent)
  normalizePath(parent, mustWork = TRUE)
}

connect_from_config <- function(config_path) {
  ensure_file_exists(config_path, "fganalysis config")
  fganalysis::connect_fgdata(config_path)
}

existing_files <- function(paths) {
  paths <- as.character(unlist(paths, use.names = FALSE))
  paths <- paths[file.exists(paths)]
  as_json_array(paths)
}

as_json_array <- function(values) {
  if (is.null(values)) {
    return(I(list()))
  }
  values <- unlist(values, use.names = FALSE)
  I(as.list(values))
}

dataframe_preview <- function(data, limit) {
  if (is.null(data)) {
    return(data.frame())
  }
  utils::head(as.data.frame(data), limit)
}

json_result <- function(result) {
  cat(jsonlite::toJSON(
    result,
    auto_unbox = TRUE,
    dataframe = "rows",
    null = "null",
    na = "null",
    POSIXt = "ISO8601",
    pretty = FALSE
  ))
}

run_json_wrapper <- function(expr) {
  stdout <- character()
  warnings <- character()
  messages <- character()

  result <- withCallingHandlers(
    tryCatch({
      value <- NULL
      stdout <- capture.output({
        value <- force(expr)
      }, type = "output")

      if (is.null(value)) {
        value <- list(status = "success")
      }
      if (is.null(value$status)) {
        value$status <- "success"
      }
      value
    }, error = function(e) {
      list(
        status = "error",
        error_type = "r_error",
        message = conditionMessage(e),
        traceback = paste(utils::capture.output(traceback()), collapse = "\n")
      )
    }),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  if (length(stdout) > 0) {
    result$stdout <- stdout
  }
  if (length(warnings) > 0) {
    result$warnings <- unique(warnings)
  }
  if (length(messages) > 0) {
    result$messages <- unique(messages)
  }

  json_result(result)
  if (identical(result$status, "error")) {
    quit(status = 1, save = "no")
  }
}
