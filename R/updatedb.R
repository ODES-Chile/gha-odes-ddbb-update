# Packages ----------------------------------------------------------------
stopifnot(require(agrometR))
stopifnot(require(dplyr))
stopifnot(require(stringr))
stopifnot(require(lubridate))
stopifnot(require(cli))

t0 <- Sys.time()
cli_h1("Start process in {t0}")

# Date parameters ---------------------------------------------------------
cli_h1("Date parameters")

date <- Sys.Date()
# delete this!
date <- date - days(3)

date_start <- date |>
  lubridate::floor_date(unit = "month") |>
  as_datetime()

date_end <- date_start + months(1) - seconds(1)

cli_alert_info("Sys.Date: {date}")
cli_alert_info("start - end: {date_start} - {date_end}")

# RAN ---------------------------------------------------------------------
cli_h1("RAN")

cli_h2("downloading")

data_ran <- agrometR::get_agro_data(
  estaciones_agromet[["ema"]],
  date_start = date_start,
  date_end = date_end,
  verbose = TRUE
)

glimpse(data_ran)

data_ran_daily <- agrometR:::daily_aggregation_ran(data_ran)

glimpse(data_ran_daily)

# DMC ---------------------------------------------------------------------
cli_h1("DMC")

cli_h2("downloading")

data_dmc <- agrometR::get_agro_data_dmc(
  agrometR::estaciones_dmc[["codigoNacional"]],
  date_start = date_start,
  date_end = date_end,
  verbose = TRUE
)

glimpse(data_dmc)

data_dmc_daily <- agrometR:::daily_aggregation_dmc(data_dmc)

glimpse(data_dmc_daily)


# Bind data ---------------------------------------------------------------
cli_h1("Bind data")

data <- bind_rows(
  data_ran_daily |> mutate(red = "ran", .before = 1),
  data_dmc_daily |> mutate(red = "dmc", .before = 1)
  ) |>
  mutate(fecha_hora = as_date(fecha_hora))

data

data |>
  count(red, year(fecha_hora), month(fecha_hora))

data <- data |>
  filter(
    year(fecha_hora)  == year(date),
    month(fecha_hora) == month(date),
    )

data |>
  count(red, year(fecha_hora), month(fecha_hora))

data <- data |>
  mutate_if(is.numeric, ~ ifelse(is.infinite(.x), NA, .x))

# DDBB Delete rows --------------------------------------------------------
cli_h1("DDBB Delete rows")

con <- RPostgres::dbConnect(
  RPostgres::Postgres(),
  host =  Sys.getenv("HOST"),
  user = "shiny",
  password = Sys.getenv("SHINY_PSQL_PWD"),
  dbname = "shiny"
)

DBI::dbListTables(con)

y <- year(date)
m <- month(date)

tbl(con, "estaciones_datos") |>
  filter(year(fecha_hora) == y, month(fecha_hora) == m) |>
  show_query()


query_delete_rows <-
  str_glue(
    "DELETE FROM estaciones_datos WHERE (EXTRACT(year FROM \"fecha_hora\") = {y}.0) AND (EXTRACT(MONTH FROM \"fecha_hora\") = {m}.0);"
    )

cat(query_delete_rows)

tbl(con, "estaciones_datos") |>
  filter(year(fecha_hora) == y, month(fecha_hora) == m) |>
  count()

DBI::dbSendQuery(con, query_delete_rows)

tbl(con, "estaciones_datos") |>
  filter(year(fecha_hora) == y, month(fecha_hora) == m) |>
  count()


# DDBB Upload rows --------------------------------------------------------
DBI::dbWriteTable(
  conn = con,
  name = "estaciones_datos",
  value = data,
  append = TRUE
)

tbl(con, "estaciones_datos") |>
  filter(year(fecha_hora) == y, month(fecha_hora) == m) |>
  count()


# Update readme.md --------------------------------------------------------
cli_h1("Update readme.md")

rmarkdown::render(here::here("readme.Rmd"))

file.remove(here::here("readme.html"))

# End ---------------------------------------------------------------------
tf <- Sys.time()
td <- tf - t0

cli_h1("End process in {tf} ({ round(td, 2)} {attr(td, \"units\")})")


