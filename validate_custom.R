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
    n_pass <- report$n_passed[1]
    n_fail <- report$n_failed[1]
    n_total <- n_pass + n_fail

    list(
      rule_id  = rule$id,
      domain   = rule$domain,
      variable = rule$variable %||% NA_character_,
      check    = check_fn,
      severity = rule$severity,
      message  = rule$message,
      passed   = isTRUE(n_fail == 0),
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

  failed_results <- Filter(function(r) !isTRUE(r$passed), results)

  result <- list(
    scriptStatus = "ok",
    rulesFile = rules_path,
    rulesTotal = length(rules),
    rulesPassed = sum(vapply(results, function(r) isTRUE(r$passed), logical(1))),
    rulesFailed = sum(vapply(results, function(r) identical(r$passed, FALSE), logical(1))),
    rulesError = sum(vapply(results, function(r) isTRUE(is.na(r$passed)), logical(1))),
    findingsCount = length(failed_results),
    findings = results
  )

  jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE)

  message(sprintf("validate_custom: %d rules, %d passed, %d failed, %d errors",
                  length(rules), result$rulesPassed, result$rulesFailed,
                  result$rulesError))
}

tryCatch({
  main()
}, error = function(e) {
  err_msg <- conditionMessage(e)
  err_type <- class(e)[1]
  result <- list(
    scriptStatus = "failed",
    error = err_msg,
    errorType = err_type,
    rulesPassed = 0L,
    rulesFailed = 0L,
    rulesError = 0L,
    results = list()
  )
  tryCatch(
    jsonlite::write_json(result, output_path, auto_unbox = TRUE, pretty = TRUE),
    error = function(e2) {
      message(paste("validate_custom: failed to write error envelope:",
                    conditionMessage(e2)))
    }
  )
  message(paste("validate_custom: FAILED -", err_msg))
  quit(status = 0)
})
