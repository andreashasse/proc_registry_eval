-module(scenario_node_added_during_split).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"node_added_during_split/service">>).

-spec name() -> binary().
name() -> <<"node added during a split">>.

-spec description() -> binary().
description() ->
    <<
        "A node is added while the cluster is partitioned, and it can only "
        "reach the side that does not own the name. It is the case an "
        "operator walks into by growing a cluster that is already in "
        "trouble: the newcomer's whole picture of the registry comes from "
        "one side of a split."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {note, <<"n1 keeps the name and loses the cluster. n4 will never see n1.">>},
        {cut, n1, n4},
        {isolate, n1},
        settle,
        {join, n4},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"The new node claims the name its side of the split cannot see.">>},
        {do, n4, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        heal,
        settle,
        {do_all, lookup, ?KEY}
    ].
