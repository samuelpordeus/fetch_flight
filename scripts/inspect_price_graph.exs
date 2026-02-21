tfs =
  FetchFlight.ProtoEncoder.to_tfs_param(%{
    data: [
      %{
        date: "2026-04-01",
        from_airport: %{code: "SFO"},
        to_airport: %{code: "JFK"},
        max_stops: nil,
        airlines: []
      },
      %{
        date: "2026-04-08",
        from_airport: %{code: "JFK"},
        to_airport: %{code: "SFO"},
        max_stops: nil,
        airlines: []
      }
    ],
    seat: :economy,
    trip: :round_trip,
    passengers: [:adult]
  })

url = "https://www.google.com/travel/flights?tfs=#{tfs}&hl=en&curr=USD"

{:ok, browser} = Playwright.launch(:chromium, %{headless: false})
page = Playwright.Browser.new_page(browser)

parent = self()

drain_messages = fn drain_messages, acc, timeout ->
  receive do
    {:xhr, url, body} -> drain_messages.(drain_messages, [{:xhr, url, body} | acc], timeout)
  after
    timeout -> Enum.reverse(acc)
  end
end

# Capture ALL XHR responses so we can identify which endpoint Price graph uses
Playwright.Page.on(page, :response, fn event ->
  response = event.params.response
  url = response.url

  if String.contains?(url, "FlightsFrontendService") do
    Task.start(fn ->
      body = Playwright.Response.body(response)
      send(parent, {:xhr, url, body})
    end)
  end
end)

Playwright.Page.goto(page, url, %{wait_until: "networkidle"})
Process.sleep(3_000)

IO.puts("Title: #{inspect(Playwright.Page.title(page))}\n")

# Drain any XHRs that fired on initial load
initial_xhrs = drain_messages.(drain_messages, [], 2_000)
IO.puts("=== XHRs on initial load ===")
Enum.each(initial_xhrs, fn {_, u, _} -> IO.puts("  #{u}") end)

# Dismiss popup
Playwright.Page.evaluate(page, "() => document.querySelector('[aria-label=\"Close\"]')?.click()")
Process.sleep(1_000)

# Scroll to bottom
Playwright.Page.evaluate(page, "() => window.scrollTo(0, document.body.scrollHeight)")
Process.sleep(3_000)

# Click Price graph tab
IO.puts("\n=== Clicking Price graph ===\n")

Playwright.Page.evaluate(page, """
  () => {
    Array.from(document.querySelectorAll('button'))
         .find(el => el.textContent.includes('Price graph'))?.click();
  }
""")

Process.sleep(10_000)

# Collect responses triggered by clicking Price graph
price_graph_xhrs = drain_messages.(drain_messages, [], 2_000)

IO.puts("=== XHRs triggered by Price graph click ===\n")

Enum.each(price_graph_xhrs, fn {_, u, body} ->
  IO.puts("URL: #{u}")
  IO.puts("Body (first 1000): #{binary_part(body, 0, min(1000, byte_size(body)))}\n")
end)

IO.puts("\nBrowser stays open for 60s.")
Process.sleep(60_000)
Playwright.Browser.close(browser)
