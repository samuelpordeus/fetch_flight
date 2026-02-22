defmodule FetchFlight.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [FetchFlight.Browser]

    Supervisor.start_link(children, strategy: :one_for_one, name: FetchFlight.Supervisor)
  end
end
