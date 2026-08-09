-module(scenario_full_split).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"full_split/service">>).

-spec name() -> binary().
name() -> <<"full split">>.

-spec description() -> binary().
description() ->
    <<
        "Every node is cut off from every other node, so nobody has a "
        "majority. All three then try to own the same name at the same "
        "time, and the split is healed with three candidate owners."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {cut, n1, n2},
        {cut, n1, n3},
        {cut, n2, n3},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"Both other nodes claim the name as well.">>},
        {do, n2, start_process, ?KEY},
        {do, n3, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        heal,
        settle,
        {note, <<"After healing: how many owners survive?">>},
        {do_all, lookup, ?KEY}
    ].
