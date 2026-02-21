defmodule FetchFlight do
  @moduledoc """
  Elixir port of the Python `fast_flights` library.

  Scrapes Google Flights by encoding a query as a protobuf binary → Base64
  `tfs` URL parameter, fetching the results page, and parsing the embedded JSON.

  ## Example

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
  """

  alias FetchFlight.{Client, Parser, ProtoEncoder}

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
end
