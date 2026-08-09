-module(scenario_one_sided_split).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"one_sided_split/service">>).

-spec name() -> binary().
name() -> <<"one sided split">>.

-spec description() -> binary().
description() ->
    <<
        "n1 stops hearing from n3, but n3 still hears n1. The two nodes "
        "disagree about whether the other one is alive, which is the case "
        "that breaks membership algorithms assuming symmetric failures."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {cut_one_way, n1, n3},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"n3 claims the same name while it still believes n1 is up.">>},
        {do, n3, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        heal,
        settle,
        {do_all, lookup, ?KEY}
    ].
