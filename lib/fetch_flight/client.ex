defmodule FetchFlight.Client do
  @url "https://www.google.com/travel/flights"

  @headers [
    {"User-Agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"},
    {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
    {"Accept-Language", "en-US,en;q=0.9"},
    {"Accept-Encoding", "gzip, deflate"},
    {"Connection", "keep-alive"}
  ]

  @price_graph_url "https://www.google.com/_/FlightsFrontendUi/data/travel.frontend.flights.FlightsFrontendService/GetCalendarGraph"

  # x-goog-ext-259736195-jspb is a capability bitmask sent to the Google Flights
  # internal API. The feature IDs (48764689, 47907128, etc.) were extracted from
  # the Go reference implementation at krisukox/google-flights-api. If Google
  # rotates this header, requests will return 403.
  @price_graph_headers [
    {"Content-Type", "application/x-www-form-urlencoded;charset=UTF-8"},
    {"x-goog-ext-259736195-jspb",
     ~s(["en-US","US","USD",1,null,[-120],null,[[48764689,47907128,48676280,48710756,48627726,48480739,47907128]],1])},
    {"User-Agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"},
    {"Accept-Language", "en-US,en;q=0.9"}
  ]

  @doc """
  Fetch Google Flights HTML for the given tfs parameter.
  Returns `{:ok, html_body}` or `{:error, reason}`.
  """
  def fetch(tfs_param, language \\ "en", currency \\ "USD") do
    case Req.get(@url,
           params: [tfs: tfs_param, hl: language, curr: currency],
           headers: @headers
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  POST to the GetCalendarGraph endpoint with a pre-built form body.
  Returns `{:ok, body}` or `{:error, reason}`.
  """
  def fetch_price_graph(form_body) do
    case Req.post(@price_graph_url,
           params: [hl: "en", gl: "US"],
           headers: @price_graph_headers,
           body: form_body,
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
