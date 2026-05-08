#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()
  config_path <- params$config_path

  errors <- character()
  warnings_vec <- character()

  config <- NULL

  if (is.null(config_path) || !file.exists(config_path)) {
    errors <- c(errors, paste("Config file not found:", config_path %||% "<NULL>"))
  } else {
    config <- tryCatch(
      jsonlite::fromJSON(config_path, simplifyVector = FALSE),
      error = function(e) {
        errors <<- c(errors, paste("Config JSON could not be parsed:", conditionMessage(e)))
        NULL
      }
    )
  }

  if (length(errors) > 0) {
    list(
      status = "error",
      valid = FALSE,
      errors = as_json_array(errors),
      warnings = as_json_array(warnings_vec)
    )
  } else {
    required_sections <- c("pheno", "labs")
    missing_sections <- setdiff(required_sections, names(config))
    if (length(missing_sections) > 0) {
      errors <- c(errors, paste("Missing required config sections:", paste(missing_sections, collapse = ", ")))
    }

    supported_types <- c("parquet", "parquet-hive", "tsv")
    section_details <- list()

    for (section_name in names(config)) {
      section <- config[[section_name]]
      section_errors <- character()
      section_warnings <- character()

      if (!"path" %in% names(section)) {
        section_errors <- c(section_errors, "Missing `path`.")
      }
      if (!"type" %in% names(section)) {
        section_errors <- c(section_errors, "Missing `type`.")
      } else if (!section$type %in% supported_types) {
        section_errors <- c(
          section_errors,
          paste("Unsupported `type`:", section$type, "supported:", paste(supported_types, collapse = ", "))
        )
      }

      path_exists <- FALSE
      path <- section$path %||% NA_character_
      if (!is.na(path) && !grepl("^(gs://|s3://|https?://)", path)) {
        path_exists <- file.exists(path)
        if (!path_exists) {
          section_errors <- c(section_errors, paste("Local path does not exist:", path))
        }
      } else if (!is.na(path)) {
        section_warnings <- c(section_warnings, "Remote path existence was not checked locally.")
      }

      if (length(section_errors) > 0) {
        errors <- c(errors, paste(section_name, section_errors))
      }
      if (length(section_warnings) > 0) {
        warnings_vec <- c(warnings_vec, paste(section_name, section_warnings))
      }
      section_details[[section_name]] <- list(
        path = path,
        type = section$type %||% NULL,
        path_exists = path_exists,
        errors = section_errors,
        warnings = section_warnings
      )
    }

    errors <- errors[nzchar(errors)]
    warnings_vec <- warnings_vec[nzchar(warnings_vec)]

    list(
      status = if (length(errors) == 0) "success" else "error",
      valid = length(errors) == 0,
      config_path = normalizePath(config_path, mustWork = TRUE),
      errors = as_json_array(errors),
      warnings = as_json_array(warnings_vec),
      sections = section_details
    )
  }
})
