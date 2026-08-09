-module(scenario_symmetric_split).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"symmetric_split/service">>).

-spec name() -> binary().
name() -> <<"symmetric split">>.

-spec description() -> binary().
description() ->
    <<
        "The cluster splits into a majority (n1, n2) and a minority (n3). "
        "The owner is on the majority side. The minority tries to claim the "
        "same name, then the split is healed."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {isolate, n3},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"The minority side claims the same name.">>},
        {do, n3, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {do, n1, renew_lease, ?KEY},
        heal,
        settle,
        {note, <<"After healing: does the cluster agree again?">>},
        {do_all, lookup, ?KEY}
    ].
