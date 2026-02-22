defmodule FetchFlight.ProtoEncoder do
  import Bitwise

  @moduledoc """
  Manual protobuf encoder for the Google Flights query schema.

  Proto schema (flights.proto):
    message Airport   { string airport = 2; }
    message FlightData {
      string date = 2; optional int32 max_stops = 5; repeated string airlines = 6;
      Airport from_airport = 13; Airport to_airport = 14;
    }
    message Info {
      repeated FlightData data = 3; repeated Passenger passengers = 8;
      Seat seat = 9; Trip trip = 19;
    }
  """

  @seat_map %{economy: 1, premium_economy: 2, business: 3, first: 4}
  @trip_map %{round_trip: 1, one_way: 2, multi_city: 3}
  @passenger_map %{adult: 1, child: 2, infant_in_seat: 3, infant_on_lap: 4}

  # --- Public API ---

  @doc "Encode a query map to a Base64 tfs parameter string."
  def to_tfs_param(query) do
    query
    |> encode_info()
    |> Base.encode64()
  end

  # --- Varint ---

  @doc false
  def encode_varint(n) when n < 128, do: <<n>>
  def encode_varint(n), do: <<(n &&& 0x7F) ||| 0x80>> <> encode_varint(n >>> 7)

  # --- Tag helpers ---

  defp tag(field, 0), do: encode_varint(field <<< 3)
  defp tag(field, 2), do: encode_varint(field <<< 3 ||| 2)

  # --- Field encoders ---

  defp encode_int(field, value), do: tag(field, 0) <> encode_varint(value)

  defp encode_string(field, value) when is_binary(value) do
    tag(field, 2) <> encode_varint(byte_size(value)) <> value
  end

  defp encode_embedded(field, bytes) when is_binary(bytes) do
    tag(field, 2) <> encode_varint(byte_size(bytes)) <> bytes
  end

  # --- Message encoders ---

  defp encode_airport(%{code: code}), do: encode_string(2, code)

  defp encode_flight_data(%{date: date, from_airport: from, to_airport: to} = fd) do
    base =
      encode_string(2, date) <>
        encode_embedded(13, encode_airport(from)) <>
        encode_embedded(14, encode_airport(to))

    with_stops =
      case Map.get(fd, :max_stops) do
        nil -> base
        stops -> base <> encode_int(5, stops)
      end

    with_dep =
      case Map.get(fd, :departure_time) do
        nil -> with_stops
        {min_h, max_h} -> with_stops <> encode_int(8, min_h) <> encode_int(9, max_h)
      end

    with_arr =
      case Map.get(fd, :arrival_time) do
        nil -> with_dep
        {min_h, max_h} -> with_dep <> encode_int(10, min_h) <> encode_int(11, max_h)
      end

    airlines = Map.get(fd, :airlines, [])

    Enum.reduce(airlines, with_arr, fn airline, acc ->
      acc <> encode_string(6, airline)
    end)
  end

  defp encode_info(%{data: flight_data_list, seat: seat, trip: trip, passengers: passengers}) do
    fd_bytes =
      Enum.reduce(flight_data_list, <<>>, fn fd, acc ->
        acc <> encode_embedded(3, encode_flight_data(fd))
      end)

    passenger_bytes =
      Enum.reduce(passengers, <<>>, fn p, acc ->
        acc <> encode_int(8, @passenger_map[p])
      end)

    seat_bytes = encode_int(9, @seat_map[seat])
    trip_bytes = encode_int(19, @trip_map[trip])

    fd_bytes <> passenger_bytes <> seat_bytes <> trip_bytes
  end
end
