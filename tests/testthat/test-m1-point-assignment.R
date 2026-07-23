helper_path <- if (file.exists("scripts/lib/canonical_point_assignment.R")) {
  "scripts/lib/canonical_point_assignment.R"
} else {
  file.path("..", "..", "scripts", "lib", "canonical_point_assignment.R")
}

if (!file.exists(helper_path)) {
  testthat::test_that("canonical point-assignment helper is available", {
    testthat::skip(
      "Canonical point-assignment tests require a source checkout"
    )
  })
} else {
  source(helper_path)

  testthat::test_that("canonical assignment preserves matched and unmatched points", {
    testthat::skip_if_not_installed("sf")
    polygon <- function(xmin, xmax, ymin = 0, ymax = 10) {
      sf::st_polygon(list(matrix(
        c(
          xmin, ymin,
          xmax, ymin,
          xmax, ymax,
          xmin, ymax,
          xmin, ymin
        ),
        ncol = 2,
        byrow = TRUE
      )))
    }
    province <- sf::st_sf(
      PRUID = "35",
      geometry = sf::st_sfc(polygon(0, 10), crs = 4326)
    )
    db <- sf::st_sf(
      PRUID = c("35", "35", "24"),
      DBUID = c("DB1", "DB2", "QC1"),
      geometry = sf::st_sfc(
        polygon(0, 4),
        polygon(6, 10),
        polygon(10, 12),
        crs = 4326
      )
    )
    points <- data.frame(
      postal_code = c("K1A 0A1", "K1A 0A2", "K1A 0A3"),
      latitude = c(2, 5, 8),
      longitude = c(2, 5, 8),
      source_record_id = c("first", "gap", "last")
    )

    assigned <- assign_canonical_ontario_points(points, province, db)

    testthat::expect_equal(assigned$source_record_id, c("first", "gap", "last"))
    testthat::expect_equal(assigned$DBUID, c("DB1", NA, "DB2"))
    testthat::expect_equal(
      assigned$db_match_status,
      c(
        "matched_2021_ontario_db",
        "unmatched_no_2021_ontario_db",
        "matched_2021_ontario_db"
      )
    )
    report <- attr(assigned, "opcc_spatial_validation")
    testthat::expect_equal(report$input_points, 3L)
    testthat::expect_equal(report$matched_points, 2L)
    testthat::expect_equal(report$unmatched_points, 1L)
    testthat::expect_equal(report$outside_ontario_points, 0L)
  })

  testthat::test_that("canonical assignment rejects points outside Ontario", {
    testthat::skip_if_not_installed("sf")
    polygon <- function(xmin, xmax, ymin = 0, ymax = 10) {
      sf::st_polygon(list(matrix(
        c(
          xmin, ymin,
          xmax, ymin,
          xmax, ymax,
          xmin, ymax,
          xmin, ymin
        ),
        ncol = 2,
        byrow = TRUE
      )))
    }
    province <- sf::st_sf(
      PRUID = "35",
      geometry = sf::st_sfc(polygon(0, 10), crs = 4326)
    )
    db <- sf::st_sf(
      PRUID = "35",
      DBUID = "DB1",
      geometry = sf::st_sfc(polygon(0, 10), crs = 4326)
    )
    points <- data.frame(
      postal_code = c("K1A 0A1", "K1A 0A2"),
      latitude = c(5, 5),
      longitude = c(5, 11)
    )

    testthat::expect_error(
      assign_canonical_ontario_points(points, province, db),
      "outside the Ontario boundary"
    )
  })

  testthat::test_that("canonical assignment accepts the province outer boundary", {
    testthat::skip_if_not_installed("sf")
    projected <- function(longitude, latitude) {
      unname(sf::st_coordinates(sf::st_transform(
        sf::st_sfc(sf::st_point(c(longitude, latitude)), crs = 4326),
        3857
      ))[1, ])
    }
    lower <- projected(0, 0)
    upper <- projected(10, 10)
    polygon <- sf::st_polygon(list(matrix(
      c(
        lower[1], lower[2],
        upper[1], lower[2],
        upper[1], upper[2],
        lower[1], upper[2],
        lower[1], lower[2]
      ),
      ncol = 2,
      byrow = TRUE
    )))
    province <- sf::st_sf(
      PRUID = "35",
      geometry = sf::st_sfc(polygon, crs = 3857)
    )
    db <- sf::st_sf(
      PRUID = "35",
      DBUID = "DB1",
      geometry = sf::st_sfc(polygon, crs = 3857)
    )
    points <- data.frame(
      postal_code = "K1A 0A1",
      latitude = 5,
      longitude = 0
    )

    assigned <- assign_canonical_ontario_points(points, province, db)

    testthat::expect_equal(assigned$DBUID, "DB1")
    testthat::expect_equal(
      assigned$db_match_status,
      "matched_2021_ontario_db"
    )
  })

  testthat::test_that("canonical assignment rejects multiple DB intersections", {
    testthat::skip_if_not_installed("sf")
    projected <- function(longitude, latitude) {
      unname(sf::st_coordinates(sf::st_transform(
        sf::st_sfc(sf::st_point(c(longitude, latitude)), crs = 4326),
        3857
      ))[1, ])
    }
    ymin <- projected(0, 0)[2]
    ymax <- projected(0, 10)[2]
    polygon <- function(longitude_min, longitude_max) {
      xmin <- projected(longitude_min, 0)[1]
      xmax <- projected(longitude_max, 0)[1]
      sf::st_polygon(list(matrix(
        c(xmin, ymin, xmax, ymin, xmax, ymax, xmin, ymax, xmin, ymin),
        ncol = 2,
        byrow = TRUE
      )))
    }
    province <- sf::st_sf(
      PRUID = "35",
      geometry = sf::st_sfc(polygon(0, 10), crs = 3857)
    )
    db <- sf::st_sf(
      PRUID = c("35", "35"),
      DBUID = c("DB1", "DB2"),
      geometry = sf::st_sfc(polygon(0, 5), polygon(5, 10), crs = 3857)
    )
    points <- data.frame(
      postal_code = "K1A 0A1",
      latitude = 5,
      longitude = 5
    )

    testthat::expect_error(
      assign_canonical_ontario_points(points, province, db),
      "multiple 2021 Ontario DBs"
    )
  })

  testthat::test_that("canonical assignment validates spatial inputs", {
    testthat::skip_if_not_installed("sf")
    polygon <- sf::st_polygon(list(matrix(
      c(0, 0, 10, 0, 10, 10, 0, 10, 0, 0),
      ncol = 2,
      byrow = TRUE
    )))
    province <- sf::st_sf(
      PRUID = "35",
      geometry = sf::st_sfc(polygon, crs = 4326)
    )
    db <- sf::st_sf(
      PRUID = "35",
      DBUID = "DB1",
      geometry = sf::st_sfc(polygon, crs = 4326)
    )

    testthat::expect_error(
      assign_canonical_ontario_points(
        data.frame(postal_code = "K1A 0A1"),
        province,
        db
      ),
      "latitude and longitude"
    )
    testthat::expect_error(
      assign_canonical_ontario_points(
        data.frame(
          postal_code = "K1A 0A1",
          latitude = NA_real_,
          longitude = 5
        ),
        province,
        db
      ),
      "finite coordinates"
    )
    testthat::expect_error(
      assign_canonical_ontario_points(
        data.frame(
          postal_code = "K1A 0A1",
          latitude = 5,
          longitude = 5
        ),
        province[, "geometry"],
        db
      ),
      "PRUID"
    )
  })

  testthat::test_that("canonical point geography enforces status nullability", {
    points <- data.frame(
      DBUID = c("DB1", NA_character_),
      DAUID_ADIDU = c("DA1", NA_character_),
      db_match_status = c(
        "matched_2021_ontario_db",
        "unmatched_no_2021_ontario_db"
      )
    )

    report <- validate_canonical_point_geography(points)

    testthat::expect_equal(report$input_points, 2L)
    testthat::expect_equal(report$matched_points, 1L)
    testthat::expect_equal(report$unmatched_points, 1L)

    missing_da <- points
    missing_da$DAUID_ADIDU[1] <- NA_character_
    testthat::expect_error(
      validate_canonical_point_geography(missing_da),
      "inconsistent"
    )

    unknown <- points
    unknown$db_match_status[2] <- "maybe"
    testthat::expect_error(
      validate_canonical_point_geography(unknown),
      "unknown db_match_status"
    )
  })
}
