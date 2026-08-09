-module(scenario_owner_isolated).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"owner_isolated/service">>).

-spec name() -> binary().
name() -> <<"owner isolated">>.

-spec description() -> binary().
description() ->
    <<
        "The node owning the name (n3) is cut off from the majority. This is "
        "the failover case: can the majority take the name over, and what "
        "happens to the old owner when the split heals?"
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n3, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {isolate, n3},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"The majority side tries to take the name over.">>},
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        heal,
        settle,
        {note, <<"After healing: one owner, or two?">>},
        {do_all, lookup, ?KEY}
    ].
