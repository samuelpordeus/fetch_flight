defmodule FetchFlight.Airport do
  @type t :: %__MODULE__{name: String.t() | nil, code: String.t() | nil}
  defstruct [:name, :code]
end

defmodule FetchFlight.SimpleDatetime do
  @type t :: %__MODULE__{date: [integer()] | nil, time: [integer()] | nil}
  defstruct [:date, :time]
end

defmodule FetchFlight.SingleFlight do
  @type t :: %__MODULE__{
          from_airport: FetchFlight.Airport.t() | nil,
          to_airport: FetchFlight.Airport.t() | nil,
          departure: FetchFlight.SimpleDatetime.t() | nil,
          arrival: FetchFlight.SimpleDatetime.t() | nil,
          duration_minutes: integer() | nil,
          plane_type: String.t() | nil
        }
  defstruct [:from_airport, :to_airport, :departure, :arrival, :duration_minutes, :plane_type]
end

defmodule FetchFlight.CarbonEmission do
  @type t :: %__MODULE__{
          typical_on_route_grams: integer() | nil,
          emission_grams: integer() | nil
        }
  defstruct [:typical_on_route_grams, :emission_grams]
end

defmodule FetchFlight.Airline do
  @type t :: %__MODULE__{code: String.t() | nil, name: String.t() | nil}
  defstruct [:code, :name]
end

defmodule FetchFlight.Alliance do
  @type t :: %__MODULE__{code: String.t() | nil, name: String.t() | nil}
  defstruct [:code, :name]
end

defmodule FetchFlight.JsMetadata do
  @type t :: %__MODULE__{
          airlines: [FetchFlight.Airline.t()],
          alliances: [FetchFlight.Alliance.t()],
          link: String.t() | nil
        }
  defstruct [:airlines, :alliances, :link]
end

defmodule FetchFlight.Flights do
  @type t :: %__MODULE__{
          type: String.t() | nil,
          price: integer() | nil,
          airlines: [String.t()],
          flights: [FetchFlight.SingleFlight.t()],
          carbon: FetchFlight.CarbonEmission.t() | nil
        }
  defstruct [:type, :price, :airlines, :flights, :carbon]
end

defmodule FetchFlight.PriceGraphOffer do
  @type t :: %__MODULE__{
          start_date: String.t() | nil,
          return_date: String.t() | nil,
          price: float() | nil
        }
  defstruct [:start_date, :return_date, :price]
end
