#!/usr/bin/env Rscript
#
# Custom validation layer (layer 2) using pointblank.
# Reads .xpt files via haven, applies study-specific rules from
# validation-rules.yaml, outputs JSON results for the Python pipeline.
#
# Usage:
#   Rscript validate_custom.R <delivery_dir> <rules_yaml> <output_json>
#
# Example:
#   Rscript validate_custom.R /workspace/incoming/d-001 \
#     /workspace/validation-rules.yaml /output/custom-findings.json

library(haven)
library(pointblank)
library(yaml)
library(jsonlite)
library(dplyr)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: validate_custom.R <delivery_dir> <rules_yaml> <output_json>")
}

delivery_dir <- args[1]
rules_path   <- args[2]
output_path  <- args[3]

load_domains <- function(dir) {
  xpt_files <- list.files(dir, pattern = "\\.xpt$", full.names = TRUE,
                          ignore.case = TRUE)
  domains <- list()
  for (f in xpt_files) {
    name <- toupper(tools::file_path_sans_ext(basename(f)))
    domains[[name]] <- haven::read_xpt(f)
  }
  domains
}

run_single_domain_check <- function(data, rule) {
  check_fn <- rule$check
  variable <- rule$variable
  params   <- rule$params %||% list()

  tryCatch({
    agent <- create_agent(data) |> (\(a) {
      switch(check_fn,
        col_vals_in_set = col_vals_in_set(a, !!sym(variable),
                            set = params$set),
        col_vals_not_null = col_vals_not_null(a, !!sym(variable)),
        col_vals_between = col_vals_between(a, !!sym(variable),
                             left = params$left, right = params$right),
        rows_distinct = rows_distinct(a, columns = vars(!!!syms(params$columns))),
        stop(paste("Unknown check function:", check_fn))
      )
    })() |>
      interrogate()

    report <- get_agent_report(agent, display_table = FALSE)

    # Pointblank report column names vary across versions and the report can
    # come back empty (e.g. variable not present in the data). Read defensively
    # from the agent's validation_set when the report doesn't carry the
    # expected columns. Always coerce to a scalar so downstream sapply()s see
    # a uniform shape.
    extract_scalar <- function(value) {
      if (is.null(value)) return(NA_integer_)
      if (length(value) == 0) return(NA_integer_)
      result <- suppressWarnings(as.integer(value[1]))
      if (is.na(result)) NA_integer_ else result
    }

    n_pass_raw <- tryCatch(report$n_passed, error = function(e) NULL)
    n_fail_raw <- tryCatch(report$n_failed, error = function(e) NULL)

    if (is.null(n_pass_raw) || is.null(n_fail_raw)) {
      validation_set <- tryCatch(agent$validation_set, error = function(e) NULL)
      if (!is.null(validation_set) && nrow(validation_set) > 0) {
        n_pass_raw <- validation_set$n_passed
        n_fail_raw <- validation_set$n_failed
      }
    }

    n_pass <- extract_scalar(n_pass_raw)
    n_fail <- extract_scalar(n_fail_raw)
    n_total <- if (is.na(n_pass) || is.na(n_fail)) NA_integer_ else n_pass + n_fail
    passed_value <- if (is.na(n_fail)) NA else isTRUE(n_fail == 0L)

    list(
      rule_id  = rule$id,
      domain   = rule$domain,
      variable = rule$variable %||% NA_character_,
      check    = check_fn,
      severity = rule$severity,
      message  = rule$message,
      passed   = passed_value,
      n_pass   = n_pass,
      n_fail   = n_fail,
      n_total  = n_total
    )
  }, error = function(e) {
    list(
      rule_id  = rule$id,
      domain   = rule$domain,
      variable = rule$variable %||% NA_character_,
      check    = check_fn,
      severity = rule$severity,
      message  = rule$message,
      passed   = NA,
      n_pass   = NA_integer_,
      n_fail   = NA_integer_,
      n_total  = NA_integer_,
      error    = conditionMessage(e)
    )
  })
}

run_cross_domain_check <- function(domains, rule) {
  params <- rule$params
  left_name  <- toupper(params$left_domain)
  right_name <- toupper(params$right_domain)
  join_key   <- params$join_key

  if (is.null(domains[[left_name]])) {
    return(list(
      rule_id = rule$id, domain = "cross",
      variable = join_key, check = "cross_domain_ref",
      severity = rule$severity, message = rule$message,
      passed = NA, n_pass = NA_integer_, n_fail = NA_integer_,
      n_total = NA_integer_,
      error = paste("Domain", left_name, "not found in delivery")
    ))
  }
  if (is.null(domains[[right_name]])) {
    return(list(
      rule_id = rule$id, domain = "cross",
      variable = join_key, check = "cross_domain_ref",
      severity = rule$severity, message = rule$message,
      passed = NA, n_pass = NA_integer_, n_fail = NA_integer_,
      n_total = NA_integer_,
      error = paste("Domain", right_name, "not found in delivery")
    ))
  }

  left_keys  <- unique(domains[[left_name]][[join_key]])
  right_keys <- unique(domains[[right_name]][[join_key]])
  orphans    <- setdiff(left_keys, right_keys)

  list(
    rule_id  = rule$id,
    domain   = "cross",
    variable = join_key,
    check    = "cross_domain_ref",
    severity = rule$severity,
    message  = rule$message,
    passed   = length(orphans) == 0,
    n_pass   = length(left_keys) - length(orphans),
    n_fail   = length(orphans),
    n_total  = length(left_keys)
  )
}

main <- function() {
  rules_config <- yaml::read_yaml(rules_path)
  rules <- rules_config$rules

  if (is.null(rules) || length(rules) == 0) {
    result <- list(
      scriptStatus = "ok",
      rulesFile = rules_path,
      findingsCount = 0L,
      findings = list()
    )
    jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE)
    message("validate_custom: 0 rules, 0 findings")
    return(invisible(NULL))
  }

  domains <- load_domains(delivery_dir)

  if (length(domains) == 0) {
    result <- list(
      scriptStatus = "failed",
      rulesFile = rules_path,
      findingsCount = 0L,
      findings = list(),
      error = paste("No .xpt files found in", delivery_dir)
    )
    jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE)
    message("validate_custom: FAILED - no .xpt files")
    return(invisible(NULL))
  }

  message(paste("validate_custom: loaded domains:",
                paste(names(domains), collapse = ", ")))

  results <- list()
  for (rule in rules) {
    if (identical(rule$domain, "cross")) {
      results <- c(results, list(run_cross_domain_check(domains, rule)))
    } else {
      domain_name <- toupper(rule$domain)
      if (is.null(domains[[domain_name]])) {
        results <- c(results, list(list(
          rule_id = rule$id, domain = domain_name,
          variable = rule$variable %||% NA_character_,
          check = rule$check, severity = rule$severity,
          message = rule$message, passed = NA,
          n_pass = NA_integer_, n_fail = NA_integer_,
          n_total = NA_integer_,
          error = paste("Domain", domain_name, "not in delivery")
        )))
      } else {
        results <- c(results, list(
          run_single_domain_check(domains[[domain_name]], rule)
        ))
      }
    }
  }

  # Defensive scalar extraction — some rules may have produced empty or
  # multi-element `passed` values; treat anything we can't reduce to a
  # single TRUE/FALSE as NA so the summary counts stay well-defined.
  passed_scalar <- function(r) {
    value <- r$passed
    if (is.null(value) || length(value) == 0) return(NA)
    value[[1]]
  }

  failed_results <- Filter(function(r) !isTRUE(passed_scalar(r)), results)

  result <- list(
    scriptStatus = "ok",
    rulesFile = rules_path,
    rulesTotal = length(rules),
    rulesPassed = sum(vapply(results, function(r) isTRUE(passed_scalar(r)), logical(1))),
    rulesFailed = sum(vapply(results, function(r) identical(passed_scalar(r), FALSE), logical(1))),
    rulesError = sum(vapply(results, function(r) {
      value <- passed_scalar(r)
      is.logical(value) && is.na(value)
    }, logical(1))),
    findingsCount = length(failed_results),
    findings = results
  )

  jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE)

  message(sprintf("validate_custom: %d rules, %d passed, %d failed, %d errors",
                  length(rules), result$rulesPassed, result$rulesFailed,
                  result$rulesError))
}

main()
