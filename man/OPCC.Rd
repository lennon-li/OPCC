\name{OPCC}
\alias{OPCC-package}
\alias{normalize_postal_code}
\alias{list_vintages}
\alias{get_correspondence}
\alias{geonames_supplementary_adapter}
\alias{new_source_adapter}
\alias{pc_to_geo}
\alias{pc_to_point}
\alias{validate_source_data}
\alias{build_source_layer}
\alias{profile_source_layer}
\alias{contribution_bundle}
\alias{release_manifest}
\alias{validate_release}
\title{Open Ontario Postal Code Correspondence}
\description{Checksum-verified, source-qualified correspondence releases and postal-code lookup helpers.}
\usage{
normalize_postal_code(x, strict = FALSE)
list_vintages()
get_correspondence(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
geonames_supplementary_adapter()
new_source_adapter(source_id, licence, lineage, retrieval_date = Sys.Date(), schema_map = list(postal_code = "postal_code"), endpoint = NULL, checksum = NULL)
pc_to_geo(postal_code, level = c("DB", "DA"), all_links = TRUE, correspondence = NULL, ...)
pc_to_point(postal_code, vintage = "2026-07-19", point_file = NULL, cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
validate_source_data(data, adapter)
build_source_layer(data, adapter)
profile_source_layer(layer)
contribution_bundle(layer, output_dir = getwd(), fixture_rows = 100L)
release_manifest(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
validate_release(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
}
\arguments{
  \item{x}{A vector of postal codes.}
  \item{strict}{Whether invalid postal codes are errors.}
  \item{vintage}{A supported release vintage.}
  \item{cache_dir}{Directory used for verified cached artifacts.}
  \item{offline}{Whether downloading is prohibited.}
  \item{source_id}{A stable lower-case source identifier.}
  \item{licence}{The source licence or permission statement.}
  \item{lineage}{The source lineage and collection method.}
  \item{retrieval_date}{The source retrieval or creation date.}
  \item{schema_map}{A named mapping containing a postal_code field.}
  \item{endpoint}{An optional source retrieval endpoint.}
  \item{checksum}{An optional SHA-256 checksum of the source artifact.}
  \item{postal_code}{A character vector of Canadian postal codes.}
  \item{level}{Requested census geography level.}
  \item{all_links}{Whether to retain every DB allocation link.}
  \item{correspondence}{Optional already-loaded correspondence data.}
  \item{point_file}{Optional local verified GeoNames point artifact.}
  \item{data}{A user-supplied postal-code evidence data frame.}
  \item{adapter}{Source metadata created by \code{new_source_adapter}.}
  \item{layer}{A local source layer created by \code{build_source_layer}.}
  \item{output_dir}{Directory where a new contribution bundle is created.}
  \item{fixture_rows}{Maximum normalized sample rows in the bundle.}
  \item{...}{Arguments passed to \code{get_correspondence}.}
}
\value{Data frames or release metadata, depending on the function.}
\details{OPCC does not substitute GeoNames point evidence for NAR address evidence.
Local source layers are always source-separated and never modify a canonical
OPCC release. Canada Post, PCCF, and PCCF+ data are rejected. Each local-data
function invites users to contribute redistributable evidence through a
reviewable bundle.}
