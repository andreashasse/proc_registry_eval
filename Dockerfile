FROM erlang:27

# iptables is how the workbench cuts the network between the nodes.
# The containers get NET_ADMIN for it in docker-compose.yml.
RUN apt-get update \
 && apt-get install -y --no-install-recommends iptables iproute2 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY rebar.config rebar.lock ./
COPY src ./src
RUN rebar3 compile

COPY docker/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node"]
