defmodule FetchFlight.Parser do
  @moduledoc """
  Parses Google Flights HTML response into structured flight data.

  Locates `<script class="ds:1">` containing an embedded JSON payload,
  then navigates specific indices discovered by @kftang.
  """

  alias FetchFlight.{
    Airport,
    Airline,
    Alliance,
    CarbonEmission,
    Flights,
    JsMetadata,
    SimpleDatetime,
    SingleFlight
  }

  @doc """
  Parse HTML from Google Flights into `{:ok, {JsMetadata.t(), [Flights.t()]}}`.
  """
  def parse(html) when is_binary(html) do
    with {:ok, doc} <- parse_html(html),
         {:ok, js} <- extract_script(doc),
         {:ok, payload} <- extract_payload(js) do
      parse_payload(payload)
    end
  end

  # --- HTML ---

  defp parse_html(html) do
    {:ok, Floki.parse_document!(html)}
  rescue
    e -> {:error, {:html_parse_error, e}}
  end

  defp extract_script(doc) do
    scripts = Floki.find(doc, "script")

    # Match class attribute exactly to handle the colon in "ds:1"
    case Enum.find(scripts, fn {_tag, attrs, _children} ->
           List.keyfind(attrs, "class", 0) == {"class", "ds:1"}
         end) do
      nil ->
        {:error, :ds1_script_not_found}

      {_tag, _attrs, children} ->
        text = children |> Enum.filter(&is_binary/1) |> Enum.join()
        {:ok, text}
    end
  end

  # --- Payload extraction ---

  defp extract_payload(js) do
    case String.split(js, "data:", parts: 2) do
      [_, rest] ->
        data = rsplit_comma(rest)

        case Jason.decode(data) do
          {:ok, payload} -> {:ok, payload}
          {:error, _} = err -> err
        end

      _ ->
        {:error, :data_key_not_found}
    end
  end

  # Equivalent to Python's rsplit(",", 1)[0] — remove everything after the last comma
  defp rsplit_comma(str) do
    case :binary.matches(str, ",") do
      [] ->
        str

      matches ->
        {last_pos, _} = List.last(matches)
        binary_part(str, 0, last_pos)
    end
  end

  # --- Payload navigation ---

  defp parse_payload(payload) do
    alliances = payload |> at(7) |> at(1) |> at(0) |> parse_alliances()
    airlines = payload |> at(7) |> at(1) |> at(1) |> parse_airlines()
    meta = %JsMetadata{alliances: alliances, airlines: airlines}

    # payload[2][0] = "Top flights" curated picks (may include flights absent from [3][0])
    # payload[3][0] = full "All flights" list
    top_rows = payload |> at(2) |> at(0)
    all_rows = payload |> at(3) |> at(0)

    flights =
      [top_rows, all_rows]
      |> Enum.flat_map(fn rows ->
        if is_list(rows), do: Enum.flat_map(rows, &parse_row/1), else: []
      end)
      |> Enum.uniq_by(fn f -> {f.price, f.airlines, f.type} end)

    {:ok, {meta, flights}}
  end

  defp at(nil, _), do: nil
  defp at(list, idx) when is_list(list), do: Enum.at(list, idx)
  defp at(_, _), do: nil

  defp parse_alliances(nil), do: []

  defp parse_alliances(data) do
    Enum.map(data, fn [code, name] -> %Alliance{code: code, name: name} end)
  end

  defp parse_airlines(nil), do: []

  defp parse_airlines(data) do
    Enum.map(data, fn [code, name] -> %Airline{code: code, name: name} end)
  end

  # --- Flight rows ---

  defp parse_row(k) do
    try do
      flight = Enum.at(k, 0)
      price = k |> at(1) |> at(0) |> at(1)
      typ = Enum.at(flight, 0)
      airlines = Enum.at(flight, 1)

      single_flights =
        flight
        |> Enum.at(2)
        |> List.wrap()
        |> Enum.map(&parse_single_flight/1)

      extras = Enum.at(flight, 22)
      carbon = parse_carbon(extras)

      [
        %Flights{
          type: typ,
          price: price,
          airlines: airlines,
          flights: single_flights,
          carbon: carbon
        }
      ]
    rescue
      _ -> []
    end
  end

  defp parse_single_flight(sf) do
    %SingleFlight{
      from_airport: %Airport{code: Enum.at(sf, 3), name: Enum.at(sf, 4)},
      to_airport: %Airport{code: Enum.at(sf, 6), name: Enum.at(sf, 5)},
      departure: %SimpleDatetime{time: Enum.at(sf, 8), date: Enum.at(sf, 20)},
      arrival: %SimpleDatetime{time: Enum.at(sf, 10), date: Enum.at(sf, 21)},
      duration_minutes: Enum.at(sf, 11),
      plane_type: Enum.at(sf, 17)
    }
  end

  defp parse_carbon(nil), do: nil

  defp parse_carbon(extras) do
    %CarbonEmission{
      typical_on_route_grams: Enum.at(extras, 8),
      emission_grams: Enum.at(extras, 7)
    }
  end
end
