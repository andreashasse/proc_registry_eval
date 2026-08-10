defmodule WorkbenchElixir.MixProject do
  use Mix.Project

  # HighlanderPG and Horde are Elixir packages, so they cannot be built by
  # rebar3. This project exists only to fetch and compile them; the compiled
  # beams end up on the Erlang node's ERL_LIBS (see docker/entrypoint.sh)
  # and are called from registry_highlander_pg and registry_horde.
  def project do
    [
      app: :workbench_elixir,
      version: "1.0.0",
      elixir: "~> 1.18",
      deps: [{:highlander_pg, "1.0.8"}, {:horde, "0.10.0"}]
    ]
  end
end
