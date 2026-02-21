# FetchFlight

[![Hex.pm](https://img.shields.io/hexpm/v/fetch_flight.svg)](https://hex.pm/packages/fetch_flight)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/fetch_flight)

Elixir port of the Python [`fast_flights`](https://github.com/AWeirdDev/flights) library. Scrapes Google Flights by encoding a query as a protobuf binary, fetching the results page, and returning structured flight data — no API key required.

Two entry points:

- `get_flights/2` — fetch specific itineraries for a given date
- `get_price_graph/1` — fetch a calendar of cheapest prices across a date range

## Installation

```elixir
def deps do
  [
    {:fetch_flight, "~> 0.1"}
  ]
end
```

## Usage

### `get_flights/2` — flight search

```elixir
query = %{
  data: [
    %{
      date: "2026-03-15",
      from_airport: %{code: "SFO"},
      to_airport: %{code: "JFK"},
      max_stops: nil,
      airlines: []
    }
  ],
  seat: :economy,
  trip: :one_way,
  passengers: [:adult]
}

{:ok, {metadata, flights}} = FetchFlight.get_flights(query)
```

### Options

```elixir
FetchFlight.get_flights(query, language: "en", currency: "USD")
```

| Option | Default | Description |
|--------|---------|-------------|
| `:language` | `"en"` | BCP 47 language tag |
| `:currency` | `"USD"` | ISO 4217 currency code |

### Query fields

**Top-level**

| Field | Type | Values |
|-------|------|--------|
| `:seat` | atom | `:economy`, `:premium_economy`, `:business`, `:first` |
| `:trip` | atom | `:one_way`, `:round_trip`, `:multi_city` |
| `:passengers` | `[atom]` | `:adult`, `:child`, `:infant_in_seat`, `:infant_on_lap` |
| `:data` | `[flight_data]` | One entry per leg |

**Per leg (`data` list)**

| Field | Type | Notes |
|-------|------|-------|
| `:date` | `"YYYY-MM-DD"` | Departure date |
| `:from_airport` | `%{code: "SFO"}` | IATA origin code |
| `:to_airport` | `%{code: "JFK"}` | IATA destination code |
| `:max_stops` | `integer \| nil` | `nil` = any number of stops |
| `:airlines` | `[String.t()]` | Filter by IATA airline code, e.g. `["UA", "AA"]` |

### Multi-city example

```elixir
query = %{
  data: [
    %{date: "2026-04-01", from_airport: %{code: "SFO"}, to_airport: %{code: "LHR"}, max_stops: nil, airlines: []},
    %{date: "2026-04-10", from_airport: %{code: "LHR"}, to_airport: %{code: "CDG"}, max_stops: 0,   airlines: []}
  ],
  seat: :business,
  trip: :multi_city,
  passengers: [:adult, :adult]
}
```

### `get_price_graph/1` — price calendar

Returns the cheapest price for each departure date in a range — useful for finding the best days to fly.

```elixir
query = %{
  range_start_date: "2026-03-01",
  range_end_date:   "2026-03-31",
  trip_length:      7,
  src_airports:     ["SFO"],
  dst_airports:     ["JFK"]
}

{:ok, offers} = FetchFlight.get_price_graph(query)
```

Results are sorted by `start_date` ascending:

```
[
  %FetchFlight.PriceGraphOffer{start_date: "2026-03-01", return_date: "2026-03-08", price: 189.0},
  %FetchFlight.PriceGraphOffer{start_date: "2026-03-02", return_date: "2026-03-09", price: 210.0},
  ...
]
```

#### Price graph query fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `:range_start_date` | `"YYYY-MM-DD"` | yes | First departure date to check |
| `:range_end_date` | `"YYYY-MM-DD"` | yes | Last departure date to check |
| `:trip_length` | `integer` | yes | Length of stay in days |
| `:src_airports` | `[String.t()]` | one of src/dst required | Origin IATA codes |
| `:src_cities` | `[String.t()]` | one of src/dst required | Origin city names |
| `:dst_airports` | `[String.t()]` | one of src/dst required | Destination IATA codes |
| `:dst_cities` | `[String.t()]` | one of src/dst required | Destination city names |
| `:trip` | atom | no | `:round_trip` (default), `:one_way` |
| `:seat` | atom | no | `:economy` (default), `:premium_economy`, `:business`, `:first` |
| `:passengers` | `[atom]` | no | Same values as `get_flights/2`, defaults to `[:adult]` |
| `:stops` | atom | no | `:any` (default), `:nonstop`, `:one_stop`, `:two_stops` |

## Output

### `get_flights/2`

```elixir
{:ok, {%FetchFlight.JsMetadata{airlines: [...], alliances: [...]}, flights}}
```

`flights` is a list of `%FetchFlight.Flights{}`, sorted cheapest first:

```
%FetchFlight.Flights{
  type:     "DL",                      # IATA carrier code
  price:    344,                       # in the requested currency
  airlines: ["Delta"],
  carbon: %FetchFlight.CarbonEmission{
    emission_grams:          284_000,
    typical_on_route_grams:  354_000
  },
  flights: [
    %FetchFlight.SingleFlight{
      from_airport: %FetchFlight.Airport{code: "SFO", name: "San Francisco International Airport"},
      to_airport:   %FetchFlight.Airport{code: "JFK", name: "John F. Kennedy International Airport"},
      departure: %FetchFlight.SimpleDatetime{date: [2026, 3, 15], time: [7, 0]},
      arrival:   %FetchFlight.SimpleDatetime{date: [2026, 3, 15], time: [15, 28]},
      duration_minutes: 328,
      plane_type: "Boeing 767"
    }
  ]
}
```

**`SimpleDatetime` format**
- `:date` — `[year, month, day]`
- `:time` — `[hour, minute]`, or `[hour]` when minutes = 0

### `get_price_graph/1`

```elixir
{:ok, [%FetchFlight.PriceGraphOffer{}, ...]}
```

Each `%FetchFlight.PriceGraphOffer{}` has:

| Field | Type | Description |
|-------|------|-------------|
| `:start_date` | `String.t()` | Departure date (`"YYYY-MM-DD"`) |
| `:return_date` | `String.t()` | Return date (`"YYYY-MM-DD"`), `nil` for one-way |
| `:price` | `float()` | Cheapest price found for that departure date |

## How it works

### `get_flights/2`

1. **Encode** — the query is serialized as a protobuf binary (manually encoded, no generated code) and Base64-encoded into the `tfs` URL parameter.
2. **Fetch** — `GET https://www.google.com/travel/flights?tfs=...&hl=...&curr=...` with realistic browser headers via [`req`](https://github.com/wojtekmach/req).
3. **Parse** — [`floki`](https://github.com/philss/floki) locates the `<script class="ds:1">` tag; [`jason`](https://github.com/michalmuskala/jason) decodes the embedded JSON payload; specific array indices are navigated to extract flights, prices, and carbon data.

### `get_price_graph/1`

1. **Encode** — the query is serialized in Google's internal JSPB format (non-standard JSON built by string concatenation, reverse-engineered from [krisukox/google-flights-api](https://github.com/krisukox/google-flights-api)) and URL-encoded into the POST body.
2. **Fetch** — `POST` to the `GetCalendarGraph` internal endpoint with the capability bitmask header `x-goog-ext-259736195-jspb`.
3. **Parse** — the JSPB streaming response (prefixed with `)]}'\n`) is split into chunks, each decoded with `jason`, and offers are extracted and sorted by departure date.

## Disclaimer

This library scrapes a public web interface. Google may change the page structure without notice, which could break parsing. It is intended for personal and research use — check Google's Terms of Service before deploying at scale.

## License

MIT
