# Elixir as well as Erlang, because three of the registries are Elixir
# libraries. 1.19 because group requires it.
FROM elixir:1.19-otp-27

# iptables is how the workbench cuts the network between the nodes, and
# between a node and Postgres. The containers get NET_ADMIN for it in
# docker-compose.yml.
RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The Elixir side first: it changes least often. Its beams are put on
# ERL_LIBS by docker/entrypoint.sh, next to the ones rebar3 builds.
COPY elixir/mix.exs elixir/mix.lock ./elixir/
RUN cd elixir \
 && mix local.hex --force \
 && mix local.rebar --force \
 && mix deps.get \
 && MIX_ENV=prod mix deps.compile

COPY rebar.config rebar.lock ./
COPY src ./src
RUN rebar3 compile

COPY docker/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node"]
