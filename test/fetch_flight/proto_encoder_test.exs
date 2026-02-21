defmodule FetchFlight.ProtoEncoderTest do
  use ExUnit.Case, async: true

  alias FetchFlight.ProtoEncoder

  describe "encode_varint/1" do
    test "encodes 0" do
      assert ProtoEncoder.encode_varint(0) == <<0>>
    end

    test "encodes single-byte values" do
      assert ProtoEncoder.encode_varint(1) == <<1>>
      assert ProtoEncoder.encode_varint(127) == <<127>>
    end

    test "encodes multi-byte values" do
      # 128 = 0x80 → <<0x80, 0x01>>
      assert ProtoEncoder.encode_varint(128) == <<0x80, 0x01>>
      # 150 → <<0x96, 0x01>>
      assert ProtoEncoder.encode_varint(150) == <<0x96, 0x01>>
      # 300 → <<0xAC, 0x02>>
      assert ProtoEncoder.encode_varint(300) == <<0xAC, 0x02>>
    end
  end

  describe "to_tfs_param/1" do
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

    test "returns a non-empty Base64 string" do
      result = ProtoEncoder.to_tfs_param(@query)
      assert is_binary(result)
      assert String.length(result) > 0
      assert {:ok, _} = Base.decode64(result)
    end

    test "encodes deterministically" do
      assert ProtoEncoder.to_tfs_param(@query) == ProtoEncoder.to_tfs_param(@query)
    end

    test "round-trip query differs from one-way" do
      round_trip_query = Map.put(@query, :trip, :round_trip)
      assert ProtoEncoder.to_tfs_param(@query) != ProtoEncoder.to_tfs_param(round_trip_query)
    end

    test "different airports produce different encoding" do
      other_query =
        Map.update!(@query, :data, fn [fd | rest] ->
          [Map.put(fd, :from_airport, %{code: "LAX"}) | rest]
        end)

      assert ProtoEncoder.to_tfs_param(@query) != ProtoEncoder.to_tfs_param(other_query)
    end

    test "multiple passengers encodes all of them" do
      multi = Map.put(@query, :passengers, [:adult, :adult, :child])
      result = ProtoEncoder.to_tfs_param(multi)
      assert is_binary(result)
    end

    test "max_stops included when set" do
      with_stops =
        Map.update!(@query, :data, fn [fd | rest] ->
          [Map.put(fd, :max_stops, 1) | rest]
        end)

      assert ProtoEncoder.to_tfs_param(@query) != ProtoEncoder.to_tfs_param(with_stops)
    end
  end
end
