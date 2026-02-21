defmodule FetchFlight.PriceGraphRequestTest do
  use ExUnit.Case, async: true

  alias FetchFlight.PriceGraphRequest

  @base_query %{
    range_start_date: "2026-03-01",
    range_end_date: "2026-03-31",
    trip_length: 7,
    src_airports: ["SFO"],
    dst_airports: ["JFK"]
  }

  test "returns {:ok, binary} for valid params" do
    assert {:ok, body} = PriceGraphRequest.build(@base_query)
    assert is_binary(body)
  end

  test "body starts with f.req= and ends with &at=&" do
    assert {:ok, body} = PriceGraphRequest.build(@base_query)
    assert String.starts_with?(body, "f.req=")
    assert String.ends_with?(body, "&at=&")
  end

  test "deterministic for same input" do
    assert {:ok, body1} = PriceGraphRequest.build(@base_query)
    assert {:ok, body2} = PriceGraphRequest.build(@base_query)
    assert body1 == body2
  end

  test "round_trip produces different encoding than one_way" do
    {:ok, rt} = PriceGraphRequest.build(Map.put(@base_query, :trip, :round_trip))
    {:ok, ow} = PriceGraphRequest.build(Map.put(@base_query, :trip, :one_way))
    assert rt != ow
  end

  test "airport vs city location differs" do
    {:ok, airport_body} = PriceGraphRequest.build(@base_query)

    {:ok, city_body} =
      PriceGraphRequest.build(
        @base_query
        |> Map.put(:src_airports, [])
        |> Map.put(:src_cities, ["San Francisco"])
      )

    assert airport_body != city_body
  end

  test "return date is start_date + trip_length (including month boundary)" do
    # 2026-01-28 + 7 days crosses a month boundary → 2026-02-04
    query = Map.merge(@base_query, %{trip: :round_trip, range_start_date: "2026-01-28"})
    assert {:ok, body} = PriceGraphRequest.build(query)

    # The outer format is Google's non-standard concatenated format, not valid
    # JSON. Verify the return date appears literally in the URL-decoded body.
    decoded =
      body
      |> String.replace_prefix("f.req=", "")
      |> String.replace_suffix("&at=&", "")
      |> URI.decode_www_form()

    assert String.contains?(decoded, "2026-02-04")
  end
end
