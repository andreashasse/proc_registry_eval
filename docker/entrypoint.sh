#!/bin/sh
# The only place where an Erlang VM is started, so this file shows exactly
# how the cluster under test is configured.
set -eu

export ERL_LIBS=/app/_build/default/lib

# Distributed Erlang requires the same tick time on every node. 5 seconds
# instead of the 60 second default, so a node notices a broken connection
# while a scenario is still running.
erl_node() {
    exec erl -setcookie workbench -kernel net_ticktime 5 -noinput "$@"
}

case "${1:-}" in
    node)
        # A cluster node. Its name is workbench@<container hostname>, which
        # is what the PEERS environment variable lists.
        erl_node -sname "workbench@$(hostname)" -eval "workbench:boot()"
        ;;
    scenarios)
        # The controller. Hidden, so it takes no part in the registries it
        # measures, and on the same docker network, so it can still reach a
        # node that has been cut off from its peers.
        erl_node -hidden -sname "controller@$(hostname)" -eval "runner:main()"
        ;;
    report)
        # Pure rendering of results/*.result, no cluster involved.
        exec erl -noinput -eval "report:main()"
        ;;
    shell)
        exec erl -setcookie workbench -kernel net_ticktime 5 -hidden \
            -sname "shell@$(hostname)"
        ;;
    *)
        echo "usage: entrypoint.sh node|scenarios|report|shell" >&2
        exit 64
        ;;
esac
