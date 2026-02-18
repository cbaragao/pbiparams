test_that("character extraction from data.frame works", {
  params <- data.frame(Region = "North", stringsAsFactors = FALSE)
  expect_equal(safe_param(params, "Region", target = "character"), "North")
})

test_that("missing column returns default", {
  params <- data.frame(Region = "North", stringsAsFactors = FALSE)
  expect_equal(safe_param(params, "Missing", target = "character", default = "All"), "All")
})

test_that("missing column with no default returns typed NA", {
  params <- data.frame(Region = "North", stringsAsFactors = FALSE)
  expect_true(is.na(safe_param(params, "Missing", target = "character")))
  expect_true(is.na(safe_param(params, "Missing", target = "numeric")))
  expect_true(is.na(safe_param(params, "Missing", target = "integer")))
  expect_true(is.na(safe_param(params, "Missing", target = "logical")))
  expect_true(is.na(safe_param(params, "Missing", target = "date")))
  expect_true(is.na(safe_param(params, "Missing", target = "datetime")))
})

# ---------------------------------------------------------------------------
# NA value handling
# ---------------------------------------------------------------------------

test_that("blank string treated as NA", {
  params <- data.frame(x = "", stringsAsFactors = FALSE)
  expect_true(is.na(safe_param(params, "x", target = "character")))
})

test_that("known NA strings treated as NA", {
  for (v in c("NA", "NaN", "null", "Null", "NULL")) {
    params <- data.frame(x = v, stringsAsFactors = FALSE)
    expect_true(is.na(safe_param(params, "x", target = "character")),
                label = paste("na_values:", v))
  }
})

test_that("NA value returns default when supplied", {
  params <- data.frame(x = "NA", stringsAsFactors = FALSE)
  expect_equal(safe_param(params, "x", target = "character", default = "fallback"), "fallback")
})

# ---------------------------------------------------------------------------
# Whitespace trimming
# ---------------------------------------------------------------------------

test_that("whitespace is trimmed by default", {
  params <- data.frame(x = "  hello  ", stringsAsFactors = FALSE)
  expect_equal(safe_param(params, "x", target = "character"), "hello")
})

test_that("whitespace preserved when trim_ws = FALSE", {
  params <- data.frame(x = "  hello  ", stringsAsFactors = FALSE)
  expect_equal(safe_param(params, "x", target = "character", trim_ws = FALSE), "  hello  ")
})

# ---------------------------------------------------------------------------
# Numeric
# ---------------------------------------------------------------------------

test_that("numeric coercion from string", {
  params <- data.frame(x = "3.14", stringsAsFactors = FALSE)
  result <- safe_param(params, "x", target = "numeric")
  expect_equal(result, 3.14)
  expect_type(result, "double")
})

test_that("numeric scalar input", {
  expect_equal(safe_param(42.5, target = "numeric"), 42.5)
})

test_that("min_val clamping", {
  expect_equal(safe_param(-5, target = "numeric", min_val = 0), 0)
})

test_that("max_val clamping", {
  expect_equal(safe_param(200, target = "numeric", max_val = 100), 100)
})

test_that("make_positive takes absolute value", {
  expect_equal(safe_param(-7.5, target = "numeric", make_positive = TRUE), 7.5)
})

# ---------------------------------------------------------------------------
# Integer
# ---------------------------------------------------------------------------

test_that("integer coercion from string", {
  params <- data.frame(x = "10", stringsAsFactors = FALSE)
  result <- safe_param(params, "x", target = "integer")
  expect_equal(result, 10L)
  expect_type(result, "integer")
})

test_that("integer_strategy: round", {
  expect_equal(safe_param(2.5, target = "integer", integer_strategy = "round"), 2L)
  expect_equal(safe_param(3.5, target = "integer", integer_strategy = "round"), 4L)
})

test_that("integer_strategy: floor", {
  expect_equal(safe_param(3.9, target = "integer", integer_strategy = "floor"), 3L)
})

test_that("integer_strategy: ceiling", {
  expect_equal(safe_param(3.1, target = "integer", integer_strategy = "ceiling"), 4L)
})

test_that("integer_strategy: truncate", {
  expect_equal(safe_param(3.9, target = "integer", integer_strategy = "truncate"), 3L)
  expect_equal(safe_param(-3.9, target = "integer", integer_strategy = "truncate"), -3L)
})

test_that("unparseable numeric returns typed NA", {
  expect_true(is.na(safe_param("abc", target = "numeric")))
  expect_true(is.na(safe_param("abc", target = "integer")))
})

# ---------------------------------------------------------------------------
# Logical
# ---------------------------------------------------------------------------

test_that("logical TRUE strings", {
  for (v in c("true", "TRUE", "True", "t", "T", "yes", "YES", "y", "Y", "1")) {
    expect_true(safe_param(v, target = "logical"), label = paste("TRUE string:", v))
  }
})

test_that("logical FALSE strings", {
  for (v in c("false", "FALSE", "False", "f", "F", "no", "NO", "n", "N", "0")) {
    expect_false(safe_param(v, target = "logical"), label = paste("FALSE string:", v))
  }
})

test_that("logical from numeric", {
  expect_true(safe_param(1, target = "logical"))
  expect_false(safe_param(0, target = "logical"))
})

test_that("logical passthrough", {
  expect_true(safe_param(TRUE, target = "logical"))
  expect_false(safe_param(FALSE, target = "logical"))
})

test_that("unrecognised string returns default for logical", {
  expect_equal(safe_param("maybe", target = "logical", default = FALSE), FALSE)
})

# ---------------------------------------------------------------------------
# Date
# ---------------------------------------------------------------------------

test_that("date: ISO 8601 format", {
  result <- safe_param("2024-01-15", target = "date")
  expect_s3_class(result, "Date")
  expect_equal(result, as.Date("2024-01-15"))
})

test_that("date: US format", {
  result <- safe_param("01/15/2024", target = "date")
  expect_s3_class(result, "Date")
  expect_equal(result, as.Date("2024-01-15"))
})

test_that("date: abbreviated month format", {
  result <- safe_param("15-Jan-2024", target = "date")
  expect_s3_class(result, "Date")
  expect_equal(result, as.Date("2024-01-15"))
})

test_that("date: passthrough when already Date", {
  d <- as.Date("2024-06-01")
  expect_equal(safe_param(d, target = "date"), d)
})

test_that("date: POSIXct converted to Date", {
  dt <- as.POSIXct("2024-06-01 12:00:00", tz = "UTC")
  expect_equal(safe_param(dt, target = "date"), as.Date("2024-06-01"))
})

test_that("date: unparseable returns typed NA", {
  result <- safe_param("not-a-date", target = "date")
  expect_true(is.na(result))
  expect_s3_class(result, "Date")
})

test_that("date: unparseable returns default", {
  default_date <- as.Date("2000-01-01")
  result <- safe_param("not-a-date", target = "date", default = default_date)
  expect_equal(result, default_date)
})

# ---------------------------------------------------------------------------
# Datetime
# ---------------------------------------------------------------------------

test_that("datetime: ISO 8601 with time", {
  result <- safe_param("2024-01-15 09:30:00", target = "datetime", tz = "UTC")
  expect_s3_class(result, "POSIXct")
  expect_equal(format(result, "%Y-%m-%d %H:%M:%S"), "2024-01-15 09:30:00")
})

test_that("datetime: ISO 8601 T separator", {
  result <- safe_param("2024-01-15T09:30:00", target = "datetime", tz = "UTC")
  expect_s3_class(result, "POSIXct")
})

test_that("datetime: passthrough when already POSIXct", {
  dt <- as.POSIXct("2024-01-15 09:30:00", tz = "UTC")
  expect_equal(safe_param(dt, target = "datetime", tz = "UTC"), dt)
})

test_that("datetime: Date converted to POSIXct", {
  d <- as.Date("2024-06-01")
  result <- safe_param(d, target = "datetime", tz = "UTC")
  expect_s3_class(result, "POSIXct")
})

test_that("datetime: unparseable returns typed NA", {
  result <- safe_param("not-a-datetime", target = "datetime")
  expect_true(is.na(result))
  expect_s3_class(result, "POSIXct")
})

# ---------------------------------------------------------------------------
# Factor input
# ---------------------------------------------------------------------------

test_that("factor value is coerced via character", {
  params <- data.frame(x = factor("hello"), stringsAsFactors = TRUE)
  expect_equal(safe_param(params, "x", target = "character"), "hello")
})

# ---------------------------------------------------------------------------
# Scalar (non-data.frame) input
# ---------------------------------------------------------------------------

test_that("scalar numeric coerced to character", {
  expect_equal(safe_param(42, target = "character"), "42")
})

test_that("scalar character coerced to numeric", {
  expect_equal(safe_param("3.14", target = "numeric"), 3.14)
})
