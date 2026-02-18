# pbiparams

An R package for safely extracting typed values from a Power BI parameter table (1 row, multiple columns) without string concatenation or injection of raw values into scripts.

> **Note:** This package is intended for use in **Power BI Desktop only**. It is not supported in the Power BI Service (cloud). See the [disclaimer](#power-bi-service-disclaimer) below.

---

## The Problem

Power BI passes parameters to R scripts as a data.frame. A common but unsafe pattern is concatenating those raw string values directly into R expressions.

### Example 1: file path injection

A report that reads a CSV from a user-supplied folder name:

```r
# Power Query R script — UNSAFE
# If dataset$ReportFolder is "../../Windows/System32" this traverses outside
# the intended directory entirely
report_path <- paste0("C:/Reports/", dataset$ReportFolder, "/data.csv")
output <- read.csv(report_path)
```

With `pbiparams`:

```r
library(pbiparams)

# Coerced to character and trimmed — still a string, but you control the shape
folder <- safe_param(dataset, "ReportFolder", target = "character", default = "default")

# Combine with a validated whitelist or fixed prefix after extraction
report_path <- file.path("C:/Reports", folder, "data.csv")
output <- read.csv(report_path)
```

### Example 2: numeric range injection

A report that filters rows by a user-supplied top-N count:

```r
# Power Query R script — UNSAFE
# If dataset$TopN is "0" you get nothing; if it is "-1" behaviour is undefined;
# if it is "1 + stop('error')" and this is ever eval()'d downstream, it executes
top_n_raw <- dataset$TopN
output <- head(dataset, as.numeric(top_n_raw))  # no bounds, no type guarantee
```

With `pbiparams`:

```r
library(pbiparams)

# Guaranteed integer, minimum 1, maximum 1000 — no surprises
top_n  <- safe_param(dataset, "TopN", target = "integer", default = 10L,
                     min_val = 1L, max_val = 1000L)
output <- head(dataset, top_n)
```

### Example 3: date arithmetic injection

```r
# Power Query R script — UNSAFE
# If dataset$StartDate is "" or "yesterday" this silently becomes NA or errors
filtered <- dataset[dataset$Date >= as.Date(dataset$StartDate), ]
```

With `pbiparams`:

```r
library(pbiparams)

# Returns a real Date or falls back to default — never a raw string
start_date <- safe_param(dataset, "StartDate", target = "date",
                         default = as.Date("2024-01-01"))
filtered   <- dataset[dataset$Date >= start_date, ]
output     <- filtered
```

`pbiparams` solves this by extracting and coercing each value to its proper R type programmatically, so values are never spliced as raw strings.

---

## Installation

`pbiparams` is not on CRAN. Install it directly from GitHub using `remotes` or `devtools`:

```r
# install.packages("remotes")
remotes::install_github("cbaragao/pbiparams")
```

Or from a local clone:

```r
# install.packages("devtools")
devtools::install("path/to/pbi-params")
```

---

## Quick Start

### 1. Create a parameter table in Power Query

In Power BI Desktop, open **Power Query Editor** and create a new blank query. Open **Advanced Editor** and paste:

```
let
    Source = #table(
        type table [StartDate = text, TopN = text, Region = text],
        {{"2024-01-01", "10", "North"}}
    )
in
    Source
```

Name it `ParamTable` and close Power Query.

### 2. Use it in an R visual

Add an R visual to your report, drag all columns from `ParamTable` into the field well, then paste:

```r
library(pbiparams)
library(gridExtra)
library(grid)

start_date <- safe_param(dataset, "StartDate", target = "date")
top_n      <- safe_param(dataset, "TopN",      target = "integer", default = 10L, min_val = 1L)
region     <- safe_param(dataset, "Region",    target = "character", default = "All")

tbl <- data.frame(
  Parameter = c("StartDate", "TopN", "Region"),
  Value     = c(as.character(start_date), as.character(top_n), region),
  Type      = c(class(start_date), class(top_n), class(region)),
  stringsAsFactors = FALSE
)

grid.newpage()
grid.table(tbl, rows = NULL)
```

### 3. Use it in a Power Query R script transform

Go to **Transform → Run R Script** and paste:

```r
library(pbiparams)

start_date <- safe_param(dataset, "StartDate", target = "date")
top_n      <- safe_param(dataset, "TopN",      target = "integer", default = 10L)
region     <- safe_param(dataset, "Region",    target = "character", default = "All")

# Use values safely — never paste() them into SQL strings
output <- dataset
```

---

## `safe_param()` reference

```r
safe_param(
  params_or_value,     # data.frame (PBI param table) or a bare scalar
  col = NULL,          # column name to extract
  row = 1,             # row index (always 1 for PBI param tables)
  target = c("numeric", "integer", "character", "logical", "date", "datetime"),
  default = NULL,      # returned when value is NA or missing
  integer_strategy = c("round", "floor", "ceiling", "truncate"),
  make_positive = FALSE,
  min_val = -Inf,
  max_val = Inf,
  trim_ws = TRUE,
  na_values = c("", "NA", "NaN", "null", "Null", "NULL"),
  date_formats = c("%Y-%m-%d", "%m/%d/%Y", "%d-%b-%Y", "%Y/%m/%d"),
  tz = "UTC"
)
```

| target | Accepts | Returns |
|---|---|---|
| `"character"` | anything | `character` |
| `"integer"` | numeric strings, numbers | `integer` |
| `"numeric"` | numeric strings, numbers | `double` |
| `"logical"` | `TRUE/FALSE`, `yes/no`, `1/0`, `t/f`, etc. | `logical` |
| `"date"` | ISO 8601, US, abbreviated month | `Date` |
| `"datetime"` | ISO 8601 with time, T-separator | `POSIXct` |

When a value is missing, blank, or cannot be coerced, `safe_param` returns `default` if supplied, otherwise a typed `NA`.

---

## Debugging column names

Power BI sometimes renames columns when they are added to an R visual's field well. If a param is returning its default unexpectedly, add this temporarily to inspect what arrived:

```r
library(gridExtra); library(grid)
grid.newpage()
grid.table(dataset, rows = NULL)
```

---

## Power BI Service Disclaimer

**This package is not supported in the Power BI Service (cloud publishing).**

The Power BI Service only allows R packages from an [approved list](https://learn.microsoft.com/en-us/power-bi/connect-data/service-r-packages-support). Custom packages installed from GitHub are not on that list and will cause R visuals and R script transforms to fail when the report is published.

`pbiparams` is designed for use in **Power BI Desktop** where your local R installation is used directly.

As a fallback for published reports, you can source the single function file directly — but this still requires the file to be accessible at a stable path on the machine running the gateway.

---

## Development

```r
devtools::load_all()   # load for interactive testing
devtools::test()       # run test suite (78 tests)
devtools::document()   # regenerate documentation
devtools::check()      # full package check
```

## License

MIT © Chris Aragao
