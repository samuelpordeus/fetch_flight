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
end
