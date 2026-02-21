defmodule FetchFlight.PriceGraphRequest do
  @moduledoc """
  Builds the `f.req=...&at=&` POST body for the GetCalendarGraph endpoint.

  Google's `_/FlightsFrontendUi/data` endpoints use a custom non-standard
  format (not valid JSON) that is built by string concatenation and then
  URL-encoded. Structure reverse-engineered from krisukox/google-flights-api.
  """

  @trip_map %{round_trip: 1, one_way: 2}
  @seat_map %{economy: 1, premium_economy: 2, business: 3, first: 4}
  # Stops encoded as unquoted integer strings in the segment array
  @stops_map %{any: "0", nonstop: "1", one_stop: "2", two_stops: "3"}

  @doc """
  Build the URL-encoded POST body for the GetCalendarGraph request.

  Required keys: `range_start_date`, `range_end_date` (ISO 8601 strings),
  `trip_length` (integer days), and at least one of `src_airports`/`src_cities`
  and `dst_airports`/`dst_cities`.

  Optional keys: `seat`, `trip`, `passengers`, `stops`.
  """
  @spec build(map()) :: {:ok, String.t()}
  def build(
        %{
          range_start_date: range_start,
          range_end_date: range_end,
          trip_length: trip_length
        } = query
      ) do
    trip = Map.get(query, :trip, :round_trip)
    seat = Map.get(query, :seat, :economy)
    stops = Map.get(query, :stops, :any)
    passengers = Map.get(query, :passengers, [:adult])

    src_airports = Map.get(query, :src_airports, [])
    src_cities = Map.get(query, :src_cities, [])
    dst_airports = Map.get(query, :dst_airports, [])
    dst_cities = Map.get(query, :dst_cities, [])

    srcs = serialize_locations(src_airports, src_cities)
    dsts = serialize_locations(dst_airports, dst_cities)

    trip_int = @trip_map[trip]
    seat_int = @seat_map[seat]
    stops_str = @stops_map[stops]
    travelers_str = build_travelers_str(passengers)
    segments_str = build_segments_str(trip, srcs, dsts, range_start, trip_length, stops_str)

    # Inner flight data: 14-element positional array matching Google's JSPB schema.
    # Indices: 0=null, 1=null, 2=trip_type, 3=null, 4=[], 5=seat, 6=travelers,
    #          7-12=null, 13=[segments]
    inner_data =
      "[null,null,#{trip_int},null,[],#{seat_int},#{travelers_str}," <>
        "null,null,null,null,null,null,[#{segments_str}]]"

    # Outer wrapper uses Google's non-standard concatenated format. The entire
    # value is URL-encoded into f.req= before being POSTed. The "strings" inside
    # intentionally contain unescaped `"` characters that Google's custom parser
    # handles. Format derived from krisukox/google-flights-api (Go reference).
    outer =
      ~s([null,"[null,) <>
        inner_data <>
        ~s(],null,null,null,1,null,null,null,null,null,[]]","[) <>
        range_start <>
        ~s(",") <>
        range_end <>
        ~s(],null,[#{trip_length},#{trip_length}]]")

    encoded = URI.encode_www_form(outer)
    {:ok, "f.req=#{encoded}&at=&"}
  end

  # Airports encode as ["IATA", 0] and cities as ["Name", 5] (integer type codes).
  defp serialize_locations(airports, cities) do
    parts =
      Enum.map(airports, &~s(["#{&1}",0])) ++
        Enum.map(cities, &~s(["#{&1}",5]))

    Enum.join(parts, ",")
  end

  defp build_travelers_str(passengers) when is_list(passengers) do
    adults = Enum.count(passengers, &(&1 == :adult))
    children = Enum.count(passengers, &(&1 == :child))
    infant_on_lap = Enum.count(passengers, &(&1 == :infant_on_lap))
    infant_in_seat = Enum.count(passengers, &(&1 == :infant_in_seat))
    "[#{adults},#{children},#{infant_on_lap},#{infant_in_seat}]"
  end

  defp build_segments_str(:one_way, srcs, dsts, start_date, _trip_length, stops_str) do
    build_segment_str(srcs, dsts, start_date, stops_str)
  end

  defp build_segments_str(:round_trip, srcs, dsts, start_date, trip_length, stops_str) do
    return_date =
      start_date
      |> Date.from_iso8601!()
      |> Date.add(trip_length)
      |> Date.to_string()

    build_segment_str(srcs, dsts, start_date, stops_str) <>
      "," <>
      build_segment_str(dsts, srcs, return_date, stops_str)
  end

  # Segment: 15-element positional array.
  # [[[srcs]], [[dsts]], null, stops, [], [], "date", null, [], [], [], null, null, [], 3]
  defp build_segment_str(srcs_str, dsts_str, date, stops_str) do
    ~s([[[#{srcs_str}]],[[#{dsts_str}]],null,#{stops_str},[],[],"#{date}",null,[],[],[],null,null,[],3])
  end
end
