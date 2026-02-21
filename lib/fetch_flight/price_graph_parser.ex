defmodule FetchFlight.PriceGraphParser do
  @moduledoc """
  Parses the JSPB streaming response from the GetCalendarGraph endpoint.

  Response format:
      )]}'\n
      \n
      SIZE\n
      JSON_CHUNK\n
      SIZE\n
      JSON_CHUNK\n
      ...

  Chunks containing price data have shape: `[null, [offer, ...]]`
  Each offer: `["2026-03-01", "2026-03-08", [[null, 245.0]]]`
  """

  alias FetchFlight.PriceGraphOffer

  @jspb_prefix ")]}'\n"

  @doc """
  Parse a JSPB streaming response body into a sorted list of `PriceGraphOffer` structs.

  Returns `{:ok, [PriceGraphOffer.t()]}` or `{:error, :missing_jspb_prefix}`.
  """
  @spec parse(String.t()) :: {:ok, [PriceGraphOffer.t()]} | {:error, :missing_jspb_prefix}
  def parse(body) when is_binary(body) do
    if String.starts_with?(body, @jspb_prefix) do
      rest = String.slice(body, byte_size(@jspb_prefix)..-1//1)

      offers =
        rest
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.chunk_every(2)
        |> Enum.flat_map(&extract_offers/1)
        |> Enum.sort_by(& &1.start_date)

      {:ok, offers}
    else
      {:error, :missing_jspb_prefix}
    end
  end

  defp extract_offers([_size, json_line]) do
    try do
      case Jason.decode(json_line) do
        {:ok, [nil, offers]} when is_list(offers) -> Enum.flat_map(offers, &parse_offer/1)
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  defp extract_offers(_), do: []

  defp parse_offer([start_date, return_date, price_data]) do
    try do
      price = price_data |> at(0) |> at(1)

      if is_number(price) do
        [%PriceGraphOffer{start_date: start_date, return_date: return_date, price: price / 1}]
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp parse_offer(_), do: []

  defp at(nil, _), do: nil
  defp at(list, idx) when is_list(list), do: Enum.at(list, idx)
  defp at(_, _), do: nil
end
