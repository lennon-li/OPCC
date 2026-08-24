app_da_fixture <- function() {
  data.frame(
    postal_code = c("M4V 1A1", "M5V 3A8", "M5V 3A8", "P0T 1A0", "P0T 1A0"),
    DAUID = c("35202806", "35204841", "35204842", "35580016", "35580017"),
    allocation_weight = c(1, 0.7, 0.3, 0.6, 0.4),
    n_contributing_dbs = c(1L, 1L, 2L, 3L, 1L),
    contributing_dbuids = c(
      "35202806007", "35204841009", "35204841010|35204841011",
      "35580016001|35580016002|35580016003", "35580017001"
    ),
    source_vintages = rep("2026-06-26", 5L),
    census_vintages = rep("2021", 5L),
    evidence_classes = NA_character_,
    best_link = c(TRUE, TRUE, FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
}

opcc_source_checkout_path <- function(...) {
  candidates <- c(
    file.path(...),
    testthat::test_path("..", "..", ...)
  )
  candidates[which(file.exists(candidates))[1]]
}
