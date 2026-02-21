defmodule FetchFlight.PriceGraphParserTest do
  use ExUnit.Case, async: true

  alias FetchFlight.PriceGraphParser

  defp build_jspb_body(offers) do
    chunk = Jason.encode!([nil, offers])
    ")]}'\n\n#{byte_size(chunk)}\n#{chunk}\n"
  end

  test "returns error for malformed body (missing prefix)" do
    assert {:error, :missing_jspb_prefix} = PriceGraphParser.parse("not valid")
  end

  test "returns {:ok, []} for body with no matching chunks" do
    chunk = Jason.encode!([nil, "not a list"])
    body = ")]}'\n\n#{byte_size(chunk)}\n#{chunk}\n"
    assert {:ok, []} = PriceGraphParser.parse(body)
  end

  test "parses single offer correctly" do
    raw = [["2026-03-01", "2026-03-08", [[nil, 245.0]]]]
    body = build_jspb_body(raw)
    assert {:ok, [offer]} = PriceGraphParser.parse(body)
    assert offer.start_date == "2026-03-01"
    assert offer.return_date == "2026-03-08"
    assert offer.price == 245.0
  end

  test "parses multiple offers correctly" do
    raw = [
      ["2026-03-01", "2026-03-08", [[nil, 245.0]]],
      ["2026-03-08", "2026-03-15", [[nil, 189.0]]]
    ]

    body = build_jspb_body(raw)
    assert {:ok, offers} = PriceGraphParser.parse(body)
    assert length(offers) == 2
  end

  test "skips non-matching chunks" do
    chunk1 = Jason.encode!(["some", "garbage"])
    chunk2 = Jason.encode!([nil, [["2026-03-01", "2026-03-08", [[nil, 300.0]]]]])

    body =
      ")]}'\n\n#{byte_size(chunk1)}\n#{chunk1}\n#{byte_size(chunk2)}\n#{chunk2}\n"

    assert {:ok, [offer]} = PriceGraphParser.parse(body)
    assert offer.price == 300.0
  end

  test "skips offers with nil price" do
    raw = [["2026-03-01", "2026-03-08", [[nil, nil]]]]
    body = build_jspb_body(raw)
    assert {:ok, []} = PriceGraphParser.parse(body)
  end

  test "coerces integer price to float" do
    raw = [["2026-03-01", "2026-03-08", [[nil, 300]]]]
    body = build_jspb_body(raw)
    assert {:ok, [offer]} = PriceGraphParser.parse(body)
    assert offer.price == 300.0
    assert is_float(offer.price)
  end

  test "results are sorted by start_date" do
    raw = [
      ["2026-03-15", "2026-03-22", [[nil, 250.0]]],
      ["2026-03-01", "2026-03-08", [[nil, 300.0]]],
      ["2026-03-08", "2026-03-15", [[nil, 200.0]]]
    ]

    body = build_jspb_body(raw)
    assert {:ok, offers} = PriceGraphParser.parse(body)
    dates = Enum.map(offers, & &1.start_date)
    assert dates == Enum.sort(dates)
  end
end
