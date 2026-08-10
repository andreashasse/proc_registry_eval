-module(scenario_database_lost).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"database_lost/service">>).

-spec name() -> binary().
name() -> <<"database lost">>.

-spec description() ->
    binary().
description() ->
    <<
        "The node owning the name loses its connection to Postgres while "
        "the BEAM cluster stays intact. Only matters for a registry that "
        "keeps its state in the database; for the others nothing happens, "
        "which is itself the result."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"n1 can still reach the other nodes, but not the database.">>},
        {cut_db, n1},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"Does another node take the name over?">>},
        {do, n2, start_process, ?KEY},
        settle,
        {do_all, lookup, ?KEY},
        heal,
        settle,
        {do_all, lookup, ?KEY}
    ].
