\name{OPCC}
\alias{OPCC-package}
\alias{normalize_postal_code}
\alias{list_vintages}
\alias{get_correspondence}
\alias{pc_to_geo}
\alias{pc_to_point}
\alias{release_manifest}
\alias{validate_release}
\title{Open Ontario Postal Code Correspondence}
\description{Checksum-verified, source-qualified correspondence releases and postal-code lookup helpers.}
\usage{
normalize_postal_code(x, strict = FALSE)
list_vintages()
get_correspondence(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
pc_to_geo(postal_code, level = c("DB", "DA"), all_links = TRUE, correspondence = NULL, ...)
pc_to_point(postal_code, vintage = "2026-07-19", point_file = NULL, cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
release_manifest(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
validate_release(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
}
\arguments{
  \item{x}{A vector of postal codes.}
  \item{strict}{Whether invalid postal codes are errors.}
  \item{vintage}{A supported release vintage.}
  \item{cache_dir}{Directory used for verified cached artifacts.}
  \item{offline}{Whether downloading is prohibited.}
  \item{postal_code}{A character vector of Canadian postal codes.}
  \item{level}{Requested census geography level.}
  \item{all_links}{Whether to retain every DB allocation link.}
  \item{correspondence}{Optional already-loaded correspondence data.}
  \item{point_file}{Optional local verified GeoNames point artifact.}
  \item{...}{Arguments passed to \code{get_correspondence}.}
}
\value{Data frames or release metadata, depending on the function.}
\details{OPCC does not substitute GeoNames point evidence for NAR address evidence.}
