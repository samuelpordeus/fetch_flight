defmodule FetchFlight.PriceGraphBrowser do
  @moduledoc """
  Fetches the Google Flights price calendar using Playwright browser automation.

  Navigates to the Google Flights search results page, clicks the "Price graph"
  tab (which fires a `GetCalendarGraph` XHR), intercepts that response, and
  parses the date + price pairs. The Price graph covers a wide date window
  (~2 months) and returns one entry per departure date at exactly the requested
  trip length — making it ideal for finding the cheapest days to fly.
  """

  alias FetchFlight.{ProtoEncoder, PriceGraphOffer}

  @google_flights_url "https://www.google.com/travel/flights"
  @calendar_graph_path "GetCalendarGraph"
  @response_timeout_ms 30_000

  @doc """
  Fetch a calendar of cheapest prices for the given price-graph query.

  Launches a headless Chromium browser, navigates to Google Flights, clicks
  the "Price graph" tab to trigger the `GetCalendarGraph` XHR, intercepts the
  response, and returns a sorted list of `PriceGraphOffer` structs filtered
  to the requested date range.

  Returns `{:ok, [PriceGraphOffer.t()]}` or `{:error, reason}`.
  """
  @spec fetch(FetchFlight.price_graph_query(), String.t()) ::
          {:ok, [PriceGraphOffer.t()]} | {:error, term()}
  def fetch(query, currency \\ "USD") do
    tfs = build_tfs(query)
    url = "#{@google_flights_url}?tfs=#{tfs}&hl=en&curr=#{currency}"

    browser = FetchFlight.Browser.get()
    page = Playwright.Browser.new_page(browser)

    # Block resources that are never needed — images, fonts, stylesheets.
    # This reduces per-page memory by ~30-60% and speeds up navigation.
    # Route.abort/1 is not yet implemented in this library version; we fulfill
    # with an empty 200 response instead, which has the same effect.
    Playwright.Page.route(page, "**/*", fn route, request ->
      if request.resource_type in ["image", "font", "stylesheet", "media"] do
        Playwright.Route.fulfill(route, %{status: 200, body: ""})
      else
        Playwright.Route.continue(route)
      end
    end)

    # The response listener must be registered before navigation.
    # Calling Response.body/1 from within the GenServer callback deadlocks,
    # so we spawn a Task for the blocking body fetch.
    parent = self()

    Playwright.Page.on(page, :response, fn event ->
      response = event.params.response

      if String.contains?(response.url, @calendar_graph_path) do
        Task.start(fn ->
          body = Playwright.Response.body(response)
          send(parent, {:calendar_response, body})
        end)
      end
    end)

    try do
      Playwright.Page.goto(page, url, %{wait_until: "domcontentloaded"})

      # Dismiss the "Travel … for $N" deal popup if it is present
      Playwright.Page.evaluate(
        page,
        "() => document.querySelector('[aria-label=\"Close\"]')?.click()"
      )

      Process.sleep(1_000)

      # Scroll to reveal the "Prices for nearby dates" section
      Playwright.Page.evaluate(page, "() => window.scrollTo(0, document.body.scrollHeight)")
      Process.sleep(2_000)

      # Click "Price graph" tab — this fires the GetCalendarGraph XHR.
      # The Price graph covers ~2 months of departure dates, each at exactly
      # the trip_length encoded in the tfs param.
      Playwright.Page.evaluate(page, """
        () => {
          Array.from(document.querySelectorAll('button'))
               .find(el => el.textContent.includes('Price graph'))?.click();
        }
      """)

      receive do
        {:calendar_response, body} ->
          parse_calendar_response(body, query)
      after
        @response_timeout_ms ->
          {:error, :calendar_graph_timeout}
      end
    after
      if Process.alive?(page.session), do: Playwright.Page.close(page)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Encode a full round-trip (outbound + return) so Google knows the trip_length.
  # This ensures GetCalendarGraph returns entries at exactly trip_length days.
  defp build_tfs(query) do
    src = query |> Map.get(:src_airports, []) |> List.first()
    dst = query |> Map.get(:dst_airports, []) |> List.first()
    dep_date = Map.fetch!(query, :range_start_date)
    trip_length = Map.fetch!(query, :trip_length)

    ret_date =
      dep_date
      |> Date.from_iso8601!()
      |> Date.add(trip_length)
      |> Date.to_iso8601()

    outbound =
      %{
        date: dep_date,
        from_airport: %{code: src},
        to_airport: %{code: dst},
        max_stops: nil,
        airlines: []
      }
      |> maybe_put(:departure_time, Map.get(query, :departure_time))
      |> maybe_put(:arrival_time, Map.get(query, :arrival_time))

    flight_query = %{
      data: [
        outbound,
        %{
          date: ret_date,
          from_airport: %{code: dst},
          to_airport: %{code: src},
          max_stops: nil,
          airlines: []
        }
      ],
      seat: Map.get(query, :seat, :economy),
      trip: :round_trip,
      passengers: Map.get(query, :passengers, [:adult])
    }

    ProtoEncoder.to_tfs_param(flight_query)
  end

  # Response body format:
  #   )]}'
  #   <empty line>
  #   <hex chunk size>
  #   [["wrb.fr", null, "<inner_json_string>", ...], ...]
  #
  # inner_json_string:
  #   [[null, [session_info], ...], [[dep, ret, [[null, price], token], 1], ...]]
  defp parse_calendar_response(body, query) do
    range_start = Map.fetch!(query, :range_start_date)
    range_end = Map.fetch!(query, :range_end_date)
    trip_length = Map.fetch!(query, :trip_length)

    with {:ok, start_date} <- Date.from_iso8601(range_start),
         {:ok, end_date} <- Date.from_iso8601(range_end),
         {:ok, entries} <- extract_entries(body) do
      offers =
        entries
        |> Enum.flat_map(&to_offer(&1, trip_length, start_date, end_date))
        |> Enum.sort_by(& &1.start_date)

      {:ok, offers}
    end
  end

  defp extract_entries(body) do
    json_line =
      body
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "["))

    with false <- is_nil(json_line),
         {:ok, outer} <- Jason.decode(json_line),
         inner_str when is_binary(inner_str) <- get_in(outer, [Access.at(0), Access.at(2)]),
         {:ok, inner} <- Jason.decode(inner_str),
         entries when is_list(entries) <- Enum.at(inner, 1) do
      {:ok, entries}
    else
      true -> {:error, :no_json_line_found}
      nil -> {:error, :inner_json_not_found}
      {:error, reason} -> {:error, {:json_parse_failed, reason}}
    end
  end

  # Each entry: [dep_date, ret_date, [[null, price_int], booking_token], 1]
  defp to_offer([dep_str, ret_str, [[_, price] | _] | _], trip_length, start_date, end_date)
       when is_binary(dep_str) and is_binary(ret_str) and is_integer(price) do
    with {:ok, dep} <- Date.from_iso8601(dep_str),
         {:ok, ret} <- Date.from_iso8601(ret_str),
         true <- Date.diff(ret, dep) == trip_length,
         true <- Date.compare(dep, start_date) != :lt,
         true <- Date.compare(dep, end_date) != :gt do
      [%PriceGraphOffer{start_date: dep_str, return_date: ret_str, price: price * 1.0}]
    else
      _ -> []
    end
  end

  defp to_offer(_, _, _, _), do: []

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
