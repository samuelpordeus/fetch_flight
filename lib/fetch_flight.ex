defmodule FetchFlight do
  @moduledoc """
  Elixir port of the Python `fast_flights` library.

  Scrapes Google Flights and returns structured flight data — no API key required.
  Provides two entry points:

  - `get_flights/2` — fetch itineraries for a specific date
  - `get_price_graph/1` — fetch a calendar of cheapest prices across a date range

  ## `get_flights/2`

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

  ## `get_price_graph/1`

  Returns the cheapest price for each departure date in a range, sorted by
  `start_date` — useful for finding the best days to fly.

      query = %{
        range_start_date: "2026-03-01",
        range_end_date:   "2026-03-31",
        trip_length:      7,
        src_airports:     ["SFO"],
        dst_airports:     ["JFK"]
      }

      {:ok, offers} = FetchFlight.get_price_graph(query)
      # => [%FetchFlight.PriceGraphOffer{start_date: "2026-03-01", return_date: "2026-03-08", price: 189.0}, ...]
  """

  alias FetchFlight.{Client, Parser, ProtoEncoder, PriceGraphRequest, PriceGraphParser}

  @type flight_data :: %{
          required(:date) => String.t(),
          required(:from_airport) => %{code: String.t()},
          required(:to_airport) => %{code: String.t()},
          optional(:max_stops) => non_neg_integer() | nil,
          optional(:airlines) => [String.t()]
        }

  @type query :: %{
          required(:data) => [flight_data()],
          required(:seat) => :economy | :premium_economy | :business | :first,
          required(:trip) => :round_trip | :one_way | :multi_city,
          required(:passengers) => [:adult | :child | :infant_in_seat | :infant_on_lap]
        }

  @doc """
  Fetch and parse Google Flights results for the given query.

  ## Options

    * `:language` - BCP 47 language tag, e.g. `"en"` (default: `"en"`)
    * `:currency` - ISO 4217 currency code, e.g. `"USD"` (default: `"USD"`)

  Returns `{:ok, {JsMetadata.t(), [Flights.t()]}}` or `{:error, reason}`.
  """
  @type price_graph_query() :: %{
          required(:range_start_date) => String.t(),
          required(:range_end_date) => String.t(),
          required(:trip_length) => pos_integer(),
          optional(:src_airports) => [String.t()],
          optional(:src_cities) => [String.t()],
          optional(:dst_airports) => [String.t()],
          optional(:dst_cities) => [String.t()],
          optional(:seat) => :economy | :premium_economy | :business | :first,
          optional(:trip) => :round_trip | :one_way,
          optional(:passengers) => [:adult | :child | :infant_in_seat | :infant_on_lap],
          optional(:stops) => :any | :nonstop | :one_stop | :two_stops
        }

  @spec get_flights(query(), keyword()) ::
          {:ok, {FetchFlight.JsMetadata.t(), [FetchFlight.Flights.t()]}} | {:error, term()}
  def get_flights(query, opts \\ []) do
    language = Keyword.get(opts, :language, "en")
    currency = Keyword.get(opts, :currency, "USD")

    with tfs <- ProtoEncoder.to_tfs_param(query),
         {:ok, html} <- Client.fetch(tfs, language, currency),
         {:ok, result} <- Parser.parse(html) do
      {:ok, result}
    end
  end

  @doc """
  Fetch a calendar of prices across a date range from Google Flights.

  Returns the cheapest prices for each departure date in the given range,
  useful for finding the best days to fly.

  Returns `{:ok, [PriceGraphOffer.t()]}` sorted by `start_date`, or `{:error, reason}`.
  """
  @spec get_price_graph(price_graph_query()) ::
          {:ok, [FetchFlight.PriceGraphOffer.t()]} | {:error, term()}
  def get_price_graph(query) do
    with {:ok, body} <- PriceGraphRequest.build(query),
         {:ok, resp} <- Client.fetch_price_graph(body),
         {:ok, offers} <- PriceGraphParser.parse(resp) do
      {:ok, offers}
    end
  end
end
