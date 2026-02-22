defmodule FetchFlight.Browser do
  @moduledoc """
  Holds a single shared Chromium browser instance for the lifetime of the application.

  All `PriceGraphBrowser` requests create pages from this shared browser rather than
  launching a new Chromium process per request. A full Chromium process uses ~150-200 MB
  of baseline memory; pages within a shared browser add ~20-50 MB each. This prevents
  OOM under concurrent load.

  The supervisor will restart this process (and relaunch the browser) if it crashes.
  """

  use GenServer, restart: :permanent

  @chromium_args [
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-gpu",
    "--disable-extensions",
    "--disable-background-networking",
    "--disable-default-apps",
    "--disable-sync",
    "--disable-translate",
    "--metrics-recording-only",
    "--mute-audio",
    "--no-first-run",
    "--safebrowsing-disable-auto-update"
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the shared browser reference."
  @spec get() :: Playwright.Browser.t()
  def get do
    GenServer.call(__MODULE__, :get, 30_000)
  end

  @impl true
  def init(_opts) do
    {:ok, browser} = launch()
    {:ok, browser}
  end

  @impl true
  def handle_call(:get, _from, browser) do
    {:reply, browser, browser}
  end

  # browser.session is the Channel.Session GenServer PID, which owns the
  # Connection and Transport processes. When Chromium crashes or the CDP
  # connection drops, that process dies and we receive this :DOWN message.
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, _stale_browser) do
    {:ok, browser} = launch()
    {:noreply, browser}
  end

  @impl true
  def terminate(_reason, browser) do
    Playwright.Browser.close(browser)
  end

  defp launch do
    {:ok, browser} = Playwright.launch(:chromium, %{headless: true, args: @chromium_args})
    Process.monitor(browser.session)
    {:ok, browser}
  end
end
