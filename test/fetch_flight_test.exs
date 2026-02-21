defmodule FetchFlightTest do
  use ExUnit.Case, async: true

  # Integration tests hit the real Google Flights and are skipped by default.
  # Run with: mix test --include integration
  @moduletag :integration

  @query %{
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

  setup do
    {:ok, {metadata, flights}} = FetchFlight.get_flights(@query)
    %{metadata: metadata, flights: flights}
  end

  test "returns a non-empty flight list", %{flights: flights} do
    assert length(flights) > 0
  end

  test "metadata contains airlines with code and name", %{metadata: meta} do
    assert length(meta.airlines) > 0

    Enum.each(meta.airlines, fn airline ->
      assert is_binary(airline.code) and byte_size(airline.code) == 2,
             "expected 2-char airline code, got #{inspect(airline.code)}"

      assert is_binary(airline.name) and byte_size(airline.name) > 0
    end)
  end

  test "every itinerary departs SFO and arrives JFK", %{flights: flights} do
    Enum.each(flights, fn itinerary ->
      first_leg = hd(itinerary.flights)
      last_leg = List.last(itinerary.flights)
      assert first_leg.from_airport.code == "SFO"
      assert last_leg.to_airport.code == "JFK"
    end)
  end

  test "every price is a positive integer", %{flights: flights} do
    Enum.each(flights, fn itinerary ->
      assert is_integer(itinerary.price) and itinerary.price > 0,
             "expected positive integer price, got #{inspect(itinerary.price)}"
    end)
  end

  test "prices are in ascending order (cheapest first)", %{flights: flights} do
    prices = Enum.map(flights, & &1.price)
    assert prices == Enum.sort(prices)
  end

  test "every leg has a positive duration and non-empty plane type", %{flights: flights} do
    all_legs = Enum.flat_map(flights, & &1.flights)

    Enum.each(all_legs, fn leg ->
      assert is_integer(leg.duration_minutes) and leg.duration_minutes > 0,
             "bad duration: #{inspect(leg.duration_minutes)}"

      assert is_binary(leg.plane_type) and byte_size(leg.plane_type) > 0,
             "bad plane_type: #{inspect(leg.plane_type)}"
    end)
  end

  test "every leg has valid [year, month, day] departure and arrival dates", %{flights: flights} do
    all_legs = Enum.flat_map(flights, & &1.flights)

    Enum.each(all_legs, fn leg ->
      for dt <- [leg.departure, leg.arrival] do
        [year, month, day] = dt.date
        assert is_integer(year) and year >= 2026
        assert is_integer(month) and month in 1..12
        assert is_integer(day) and day in 1..31
      end
    end)
  end

  test "every leg time is a list of 1-2 non-negative integers", %{flights: flights} do
    all_legs = Enum.flat_map(flights, & &1.flights)

    Enum.each(all_legs, fn leg ->
      for dt <- [leg.departure, leg.arrival] do
        assert is_list(dt.time) and length(dt.time) in 1..2,
               "expected [h] or [h, m], got #{inspect(dt.time)}"

        Enum.each(dt.time, fn v ->
          assert is_nil(v) or (is_integer(v) and v >= 0),
                 "expected non-negative integer in time, got #{inspect(v)}"
        end)
      end
    end)
  end

  test "every itinerary has carbon emission data", %{flights: flights} do
    Enum.each(flights, fn itinerary ->
      carbon = itinerary.carbon
      assert %FetchFlight.CarbonEmission{} = carbon
      assert is_integer(carbon.emission_grams) and carbon.emission_grams > 0
      assert is_integer(carbon.typical_on_route_grams) and carbon.typical_on_route_grams > 0
    end)
  end

  test "every itinerary has at least one airline name", %{flights: flights} do
    Enum.each(flights, fn itinerary ->
      assert is_list(itinerary.airlines) and length(itinerary.airlines) > 0
      Enum.each(itinerary.airlines, &assert(is_binary(&1)))
    end)
  end

  test "airport codes are 3 uppercase ASCII letters", %{flights: flights} do
    all_legs = Enum.flat_map(flights, & &1.flights)

    Enum.each(all_legs, fn leg ->
      for airport <- [leg.from_airport, leg.to_airport] do
        assert String.match?(airport.code, ~r/^[A-Z]{3}$/),
               "bad airport code: #{inspect(airport.code)}"

        assert is_binary(airport.name) and byte_size(airport.name) > 0
      end
    end)
  end
end
