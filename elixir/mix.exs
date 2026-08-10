defmodule WorkbenchElixir.MixProject do
  use Mix.Project

  # group, HighlanderPG and Horde are Elixir packages, so they cannot be
  # built by rebar3. This project exists only to fetch and compile them; the
  # compiled beams end up on the Erlang node's ERL_LIBS (see
  # docker/entrypoint.sh) and are called from the matching registry_* module.
  def project do
    [
      app: :workbench_elixir,
      version: "1.0.0",
      elixir: "~> 1.19",
      deps: [{:group, "0.2.1"}, {:highlander_pg, "1.0.8"}, {:horde, "0.10.0"}]
    ]
  end
end
