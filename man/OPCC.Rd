\name{OPCC}
\alias{OPCC-package}
\alias{normalize_postal_code}
\alias{list_vintages}
\alias{get_correspondence}
\alias{get_da_correspondence}
\alias{aggregate_da_correspondence}
\alias{geonames_supplementary_adapter}
\alias{new_source_adapter}
\alias{pc_to_geo}
\alias{pc_to_point}
\alias{validate_source_data}
\alias{build_source_layer}
\alias{profile_source_layer}
\alias{contribution_bundle}
\alias{contribution_issue_url}
\alias{open_contribution_issue}
\alias{release_manifest}
\alias{validate_release}
\title{Open Ontario Postal Code Correspondence}
\description{Checksum-verified, source-qualified correspondence releases and postal-code lookup helpers.}
\usage{
normalize_postal_code(x, strict = FALSE)
list_vintages(level = c("DB", "DA"))
get_correspondence(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
get_da_correspondence(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE)
aggregate_da_correspondence(correspondence)
geonames_supplementary_adapter()
new_source_adapter(source_id, licence, lineage, retrieval_date = Sys.Date(), schema_map = list(postal_code = "postal_code"), endpoint = NULL, checksum = NULL)
pc_to_geo(postal_code, level = c("DB", "DA"), all_links = TRUE, correspondence = NULL, ...)
pc_to_point(postal_code, vintage = "2026-07-19", point_file = NULL, cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE, source = NULL)
validate_source_data(data, adapter, on_invalid = c("error", "drop", "quarantine"))
build_source_layer(data, adapter, on_invalid = c("error", "drop", "quarantine"))
profile_source_layer(layer)
contribution_bundle(layer, output_dir = NULL, fixture_rows = 100L)
contribution_issue_url(bundle, repository = "lennon-li/OPCC")
open_contribution_issue(bundle, repository = "lennon-li/OPCC", open = FALSE)
release_manifest(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE, level = c("DB", "DA"))
validate_release(vintage = "2026-06-26", cache_dir = tools::R_user_dir("OPCC", "cache"), offline = FALSE, level = c("DB", "DA"))
}
\arguments{
  \item{x}{A vector of postal codes.}
  \item{strict}{Whether invalid postal codes are errors.}
  \item{vintage}{A supported release vintage.}
  \item{level}{The requested census geography level, either \code{"DB"} or \code{"DA"}.}
  \item{cache_dir}{Directory used for verified cached artifacts.}
  \item{offline}{Whether downloading is prohibited.}
  \item{source_id}{A stable lower-case source identifier.}
  \item{licence}{The source licence or permission statement.}
  \item{lineage}{The source lineage and collection method.}
  \item{retrieval_date}{The source retrieval or creation date.}
  \item{schema_map}{A named mapping from normalized OPCC fields to source fields.
  It must contain a \code{postal_code} entry and may contain additional fields.}
  \item{endpoint}{An optional source retrieval endpoint.}
  \item{checksum}{An optional SHA-256 checksum of the source artifact.}
  \item{postal_code}{A character vector of Canadian postal codes.}
  \item{all_links}{Whether to retain every allocated geography link.}
  \item{correspondence}{Optional already-loaded postal-code-to-DB correspondence data.}
  \item{point_file}{Optional local verified source-qualified point artifact.}
  \item{source}{Optional character vector of \code{point_source} values to
  retain. By default, observations from every source are returned.}
  \item{data}{A user-supplied postal-code evidence data frame.}
  \item{adapter}{Source metadata created by \code{new_source_adapter}.}
  \item{on_invalid}{How invalid rows are handled: error, drop, or attach them
  to the accepted output as \code{opcc_quarantine}.}
  \item{layer}{A local source layer created by \code{build_source_layer}.}
  \item{output_dir}{Explicit directory where a new contribution bundle is created.}
  \item{fixture_rows}{Maximum normalized sample rows in the bundle.}
  \item{bundle}{A contribution bundle returned by \code{contribution_bundle}.}
  \item{repository}{GitHub repository in \code{owner/repository} form.}
  \item{open}{Whether to open the issue-composer URL in an interactive browser.}
  \item{...}{Arguments passed to the selected correspondence getter.}
}
\value{Data frames or release metadata, depending on the function.
\code{pc_to_point()} returns every matching source-qualified point observation.
Local-source validation rejects coordinate-bearing rows outside the inclusive
broad Ontario bounds (latitude 41.6 to 56.9, longitude -95.2 to -74.3) and
records \code{outside_ontario_bounds_rows}.}
\details{OPCC does not substitute GeoNames point evidence for NAR address evidence.
Local source layers are always source-separated and never modify a canonical
OPCC release. Adapter mappings are applied before validation, and accepted
output carries an \code{opcc_validation_report} attribute. The broad Ontario
rectangle is a coarse guardrail, not proof of provincial membership; canonical
candidate builds still require boundary and DB intersection checks. Canada
Post, PCCF, and PCCF+ data are rejected. Each local-data
function invites users to contribute redistributable evidence through a
reviewable bundle. Use \code{contribution_issue_url} to create a prefilled
GitHub Source Proposal URL from a bundle's provenance. In an interactive R
session, \code{open_contribution_issue(bundle, open = TRUE)} opens that URL.
GitHub issue URLs cannot attach files, so the contributor must attach the
bundle's fixture, adapter configuration, quality report, and provenance files
before submitting. The package never uploads local data automatically.}
