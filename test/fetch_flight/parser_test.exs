defmodule FetchFlight.ParserTest do
  use ExUnit.Case, async: true

  alias FetchFlight.Parser

  # Minimal HTML fixture that mirrors the structure Google Flights embeds.
  # The ds:1 script contains AF_initDataCallback({...data:[<payload>]...}).
  @alliances_data [[["*A", "Star Alliance"], ["OW", "Oneworld"]]]
  @airlines_data [[["UA", "United Airlines"], ["AA", "American Airlines"]]]

  defp build_payload do
    # payload[3][0] = flight rows
    # payload[7][1][0] = alliances, payload[7][1][1] = airlines
    single_flight = List.duplicate(nil, 22)

    single_flight =
      single_flight
      |> List.replace_at(3, "SFO")
      |> List.replace_at(4, "San Francisco International")
      |> List.replace_at(5, "John F. Kennedy International")
      |> List.replace_at(6, "JFK")
      |> List.replace_at(8, "8:00 AM")
      |> List.replace_at(10, "4:30 PM")
      |> List.replace_at(11, 330)
      |> List.replace_at(17, "Boeing 737")
      |> List.replace_at(20, "2026-03-15")
      |> List.replace_at(21, "2026-03-15")

    carbon_extras =
      List.duplicate(nil, 9) |> List.replace_at(7, 180_000) |> List.replace_at(8, 200_000)

    flight = ["Best", ["UA"], [single_flight]] ++ List.duplicate(nil, 19) ++ [carbon_extras]
    row = [flight, [["$350", 350, "USD"]]]

    # Build sparse top-level payload using nil padding
    # Index 3 → flight rows, index 7 → metadata
    meta_section = [nil, [@alliances_data |> hd(), @airlines_data |> hd()]]

    payload = List.duplicate(nil, 8)
    payload = List.replace_at(payload, 3, [[row]])
    payload = List.replace_at(payload, 7, meta_section)
    payload
  end

  defp build_html(payload) do
    json = Jason.encode!(payload)

    """
    <html>
    <head></head>
    <body>
    <script class="ds:1">AF_initDataCallback({key: 'ds:1', data:#{json},null});</script>
    </body>
    </html>
    """
  end

  test "returns error for missing ds:1 script" do
    assert {:error, :ds1_script_not_found} = Parser.parse("<html></html>")
  end

  test "returns error when data key is missing" do
    html = ~s(<html><body><script class="ds:1">no data here</script></body></html>)
    assert {:error, :data_key_not_found} = Parser.parse(html)
  end

  test "parses metadata (airlines and alliances)" do
    html = build_html(build_payload())
    assert {:ok, {meta, _flights}} = Parser.parse(html)
    assert length(meta.alliances) == 2
    assert length(meta.airlines) == 2
    assert hd(meta.alliances).code == "*A"
    assert hd(meta.airlines).code == "UA"
  end

  test "parses flight results" do
    html = build_html(build_payload())
    assert {:ok, {_meta, flights}} = Parser.parse(html)
    assert length(flights) > 0
  end

  test "parses single flight legs" do
    html = build_html(build_payload())
    assert {:ok, {_meta, [first | _]}} = Parser.parse(html)
    assert length(first.flights) == 1
    leg = hd(first.flights)
    assert leg.from_airport.code == "SFO"
    assert leg.to_airport.code == "JFK"
    assert leg.duration_minutes == 330
    assert leg.plane_type == "Boeing 737"
    assert leg.departure.time == "8:00 AM"
    assert leg.arrival.time == "4:30 PM"
  end

  test "parses carbon emissions" do
    html = build_html(build_payload())
    assert {:ok, {_meta, [first | _]}} = Parser.parse(html)
    assert first.carbon.emission_grams == 180_000
    assert first.carbon.typical_on_route_grams == 200_000
  end

  test "returns empty flights when payload[3][0] is nil" do
    payload = List.duplicate(nil, 8)
    meta = [nil, [[], []]]
    payload = List.replace_at(payload, 3, [[nil]])
    payload = List.replace_at(payload, 7, meta)
    html = build_html(payload)
    assert {:ok, {_meta, []}} = Parser.parse(html)
  end
end
