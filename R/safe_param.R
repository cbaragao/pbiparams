#' Safely extract and coerce a value from a Power BI parameter table
#'
#' Extracts a single value from a Power BI parameter data.frame (1 row,
#' multiple columns) and coerces it to the requested type. All coercion is
#' done programmatically — values are never spliced as raw strings into SQL,
#' DAX, or file paths, eliminating injection risk.
#'
#' @param params_or_value A `data.frame` (the Power BI parameter table) **or**
#'   a bare scalar value. When a scalar is supplied, `col` and `row` are
#'   ignored and the value is coerced directly.
#' @param col Character. Column name to extract from the data.frame. Required
#'   when `params_or_value` is a data.frame; ignored otherwise.
#' @param row Integer. Row index to extract (default `1`). Power BI parameter
#'   tables always have exactly one row, so this rarely needs changing.
#' @param target Character. Target type for coercion. One of `"numeric"`,
#'   `"integer"`, `"character"`, `"logical"`, `"date"`, `"datetime"`.
#' @param default The value returned when the extracted value is `NA` or
#'   missing. Defaults to `NULL`, which causes a typed `NA` to be returned.
#' @param integer_strategy Character. How to convert a non-integer numeric to
#'   integer. One of `"round"` (default), `"floor"`, `"ceiling"`,
#'   `"truncate"`.
#' @param make_positive Logical. If `TRUE`, the absolute value is taken before
#'   clamping. Only applies to `"numeric"` and `"integer"` targets.
#' @param min_val Numeric. Lower bound for numeric/integer output (inclusive).
#'   Default `-Inf` (no lower bound).
#' @param max_val Numeric. Upper bound for numeric/integer output (inclusive).
#'   Default `Inf` (no upper bound).
#' @param trim_ws Logical. If `TRUE` (default), leading/trailing whitespace is
#'   stripped from character values before processing.
#' @param na_values Character vector of strings that should be treated as `NA`.
#'   Default: `c("", "NA", "NaN", "null", "Null", "NULL")`.
#' @param date_formats Character vector of `strptime` format strings tried in
#'   order when parsing dates. Default covers ISO 8601, US, and abbreviated
#'   month formats.
#' @param tz Character. Time zone used for `"datetime"` targets and when
#'   converting between date and datetime types. Default `"UTC"`.
#'
#' @return A scalar of the requested type, or a typed `NA` / `default` when
#'   the value is missing or cannot be coerced.
#'
#' @examples
#' params <- data.frame(
#'   StartDate = "2024-01-01",
#'   TopN      = "10",
#'   Region    = "North",
#'   Debug     = "true",
#'   stringsAsFactors = FALSE
#' )
#'
#' safe_param(params, "StartDate", target = "date")
#' safe_param(params, "TopN",      target = "integer", default = 5L, min_val = 1L)
#' safe_param(params, "Region",    target = "character", default = "All")
#' safe_param(params, "Debug",     target = "logical",   default = FALSE)
#'
#' # Scalar usage (no data.frame)
#' safe_param("42.7", target = "integer", integer_strategy = "floor")
#'
#' @export
safe_param <- function(params_or_value,
                       col = NULL,
                       row = 1,
                       target = c("numeric", "integer", "character",
                                  "logical", "date", "datetime"),
                       default = NULL,
                       integer_strategy = c("round", "floor", "ceiling", "truncate"),
                       make_positive = FALSE,
                       min_val = -Inf,
                       max_val = Inf,
                       trim_ws = TRUE,
                       na_values = c("", "NA", "NaN", "null", "Null", "NULL"),
                       date_formats = c("%Y-%m-%d", "%m/%d/%Y",
                                        "%d-%b-%Y", "%Y/%m/%d"),
                       tz = "UTC") {

  target           <- match.arg(target)
  integer_strategy <- match.arg(integer_strategy)

  # -------------------------------------------------------------------------
  # 1. Extract raw value
  # -------------------------------------------------------------------------
  val <- if (is.data.frame(params_or_value)) {
    if (!is.null(col) &&
        col %in% colnames(params_or_value) &&
        row >= 1 &&
        row <= nrow(params_or_value)) {
      params_or_value[row, col, drop = TRUE]
    } else {
      # Column missing or row out of range — go straight to default
      return(.typed_default(default, target, tz))
    }
  } else {
    params_or_value
  }

  # -------------------------------------------------------------------------
  # 2. Normalize: factor → character, trim whitespace, blank → NA
  # -------------------------------------------------------------------------
  if (is.factor(val)) val <- as.character(val)
  if (is.character(val)) {
    if (trim_ws) val <- trimws(val)
    if (val %in% na_values) val <- NA_character_
  }

  # -------------------------------------------------------------------------
  # 3. Missing value → default or typed NA
  # -------------------------------------------------------------------------
  if (is.na(val)[1L]) {
    return(.typed_default(default, target, tz))
  }

  # -------------------------------------------------------------------------
  # 4. Coerce to target type
  # -------------------------------------------------------------------------
  switch(target,

    character = {
      tryCatch(as.character(val),
               error = function(e) .typed_default(default, "character", tz))
    },

    logical = {
      if (is.logical(val)) {
        val
      } else if (is.numeric(val)) {
        !is.na(val) && val != 0
      } else if (is.character(val)) {
        s <- tolower(trimws(val))
        if (s %in% c("true",  "t", "yes", "y", "1")) TRUE
        else if (s %in% c("false", "f", "no",  "n", "0")) FALSE
        else .typed_default(default, "logical", tz)
      } else {
        .typed_default(default, "logical", tz)
      }
    },

    numeric = ,
    integer = {
      num <- if (is.logical(val)) {
        as.integer(val)
      } else {
        suppressWarnings(as.numeric(val))
      }
      if (is.na(num)) return(.typed_default(default, target, tz))
      if (make_positive) num <- abs(num)
      if (target == "integer") {
        num <- switch(integer_strategy,
          round    = round(num),
          floor    = floor(num),
          ceiling  = ceiling(num),
          truncate = trunc(num)
        )
      }
      num <- pmax(pmin(num, max_val), min_val)
      if (target == "integer") as.integer(num) else as.double(num)
    },

    date = {
      if (inherits(val, "Date")) {
        val
      } else if (inherits(val, "POSIXct")) {
        as.Date(val, tz = tz)
      } else if (is.character(val)) {
        .parse_date(val, date_formats, default, tz)
      } else if (is.numeric(val)) {
        tryCatch(as.Date(val, origin = "1970-01-01"),
                 error = function(e) .typed_default(default, "date", tz))
      } else {
        .typed_default(default, "date", tz)
      }
    },

    datetime = {
      if (inherits(val, "POSIXct")) {
        val
      } else if (inherits(val, "Date")) {
        as.POSIXct(val, tz = tz)
      } else if (is.character(val)) {
        .parse_datetime(val, date_formats, default, tz)
      } else if (is.numeric(val)) {
        tryCatch(as.POSIXct(val, origin = "1970-01-01", tz = tz),
                 error = function(e) .typed_default(default, "datetime", tz))
      } else {
        .typed_default(default, "datetime", tz)
      }
    }
  )
}

# ---------------------------------------------------------------------------
# Internal helpers (not exported)
# ---------------------------------------------------------------------------

#' Return a typed NA or the supplied default
#' @noRd
.typed_default <- function(default, target, tz) {
  if (!is.null(default)) return(default)
  switch(target,
    numeric   = NA_real_,
    integer   = NA_integer_,
    character = NA_character_,
    logical   = NA,
    date      = as.Date(NA_character_),
    datetime  = as.POSIXct(NA_character_, tz = tz)
  )
}

#' Try a list of strptime formats and return the first successful Date parse
#' @noRd
.parse_date <- function(x, formats, default, tz) {
  for (fmt in formats) {
    parsed <- tryCatch(as.Date(x, format = fmt), error = function(e) NULL)
    if (!is.null(parsed) && !is.na(parsed)) return(parsed)
  }
  .typed_default(default, "date", tz)
}

#' Try a list of strptime formats and return the first successful POSIXct parse
#' @noRd
.parse_datetime <- function(x, formats, default, tz) {
  dt_formats <- c(
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%m/%d/%Y %H:%M:%S",
    "%Y/%m/%d %H:%M:%S",
    "%d-%b-%Y %H:%M:%S",
    formats
  )
  for (fmt in dt_formats) {
    parsed <- tryCatch(as.POSIXct(x, format = fmt, tz = tz),
                       error = function(e) NULL)
    if (!is.null(parsed) && !is.na(parsed)) return(parsed)
  }
  # Last resort: let R guess
  fallback <- tryCatch(suppressWarnings(as.POSIXct(x, tz = tz)),
                       error = function(e) NULL)
  if (!is.null(fallback) && !is.na(fallback)) fallback else .typed_default(default, "datetime", tz)
}
