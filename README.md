# pbiparams

An R package for safely extracting typed values from a Power BI parameter table (1 row, multiple columns) without string concatenation or injection of raw values into scripts.

> **Note:** This package is intended for use in **Power BI Desktop only**. It is not supported in the Power BI Service (cloud). See the [disclaimer](#power-bi-service-disclaimer) below.

---

## The Problem

### The root cause: `R.Execute()` with M string concatenation

The most common pattern for passing Power BI parameters into R is to build the entire R script as an M string using `&` concatenation inside `R.Execute()`:

```
// Power Query M — UNSAFE
let
    Source = R.Execute(
        "library(mylib)#(lf)" &
        "region     <- c(""" & Region    & """)#(lf)" &
        "category   <- c(""" & Category  & """)#(lf)" &
        "start_year <- c("   & StartYear & ")#(lf)" &
        "output     <- pull_metrics(region, category, start_year)"
    )
in
    Source
```

If any of those parameter values contain a `"` character, a `#(lf)` sequence, or valid R code, it gets injected verbatim into the script string before R ever sees it. For example:

| Parameter | Injected value | What R actually executes |
|---|---|---|
| `Region` | `East") #` | Closes the string early, comments out the rest |
| `StartYear` | `2020); system("del C:/data")` | Executes an arbitrary system command |
| `Category` | `""` (blank) | Silently passes an empty string — wrong type, no error |

### The fix: pass a parameter table, extract inside R

Instead of concatenating into the script string, load a parameter table into R and extract each value safely:

```
// Power Query M — SAFE
let
    Source = R.Execute(
        "library(pbiparams)#(lf)" &
        "library(mylib)#(lf)" &
        "region     <- safe_param(dataset, ""Region"",    target = ""character"")#(lf)" &
        "category   <- safe_param(dataset, ""Category"",  target = ""character"")#(lf)" &
        "start_year <- safe_param(dataset, ""StartYear"", target = ""integer"")#(lf)" &
        "output     <- pull_metrics(region, category, start_year)",
        [dataset = ParamTable]   // <-- ParamTable is passed as a data.frame
    )
in
    Source
```

The parameter values never touch the script string. They arrive as cells in a data.frame and are extracted and coerced by R.

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
