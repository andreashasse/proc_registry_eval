-module(scenario_process_death).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"process_death/service">>).

-spec name() -> binary().
name() -> <<"process death">>.

-spec description() -> binary().
description() ->
    <<
        "The registered process is killed without unregistering. Shows "
        "whether the registry monitors the process and frees the name by "
        "itself, or keeps handing out a dead pid."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {do, n1, kill_process, ?KEY},
        {wait, 2000},
        {do_all, lookup, ?KEY},
        {note, <<"Another node tries to take the name over.">>},
        {do, n2, start_process, ?KEY},
        {do_all, lookup, ?KEY}
    ].
