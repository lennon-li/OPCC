# M4 GeoNames Coverage and Disagreement Report

This report is reproduced from the versioned M2 baseline, GeoNames amendment,
and M1 GeoNames point artifact with:

```r
Rscript scripts/m4_coverage_report.R
```

## Coverage

| Measure | Count |
| --- | ---: |
| NAR baseline postal codes | 282,409 |
| GeoNames-amendment postal codes | 299,743 |
| Added postal codes | 17,334 |
| GeoNames supplementary rows and postal codes | 17,334 |
| Source GeoNames points | 17,373 |
| Source points with 2021 Ontario DB and DA | 17,334 |
| Source points explicitly unmatched | 39 |

The amendment adds only source-separated GeoNames point-in-polygon evidence.
It does not overwrite NAR rows or convert a point reference into address
evidence.

## Disagreement and uncertainty result

There are zero GeoNames point postal codes in common with the 282,409-code NAR
baseline, and zero GeoNames amendment postal codes in common with it. Therefore
the current artifacts contain no paired NAR/GeoNames postal-code evidence from
which to estimate source disagreement, calibrate candidate DB/DA probabilities,
or compare point-only, equal-weight, and population-only uncertainty models.

The reproducible report emits:

```text
disagreement_status = not_estimable_no_shared_postal_codes
calibration_status = not_run_no_paired_nar_geonames_evidence
```

This is an explicit non-result, not a zero-uncertainty claim. M4 retains all
17,373 source-labeled points and their GeoNames accuracy metadata, including the
39 unassigned points, until an independent open source supplies valid paired
evidence for calibration.
