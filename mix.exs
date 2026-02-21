defmodule FetchFlight.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/samuelpordeus/fetch_flight"

  def project do
    [
      app: :fetch_flight,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "FetchFlight",
      source_url: @source_url,
      docs: [
        main: "FetchFlight",
        source_ref: "v#{@version}",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    "Google Flights scraper — encodes queries as protobuf, fetches the results page, " <>
      "and returns structured flight data. No API key required."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:floki, "~> 0.38"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
