-module(scenario_baseline).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"baseline/service">>).

-spec name() -> binary().
name() -> <<"baseline">>.

-spec description() -> binary().
description() ->
    <<
        "Healthy cluster. Establishes what the registry does when nothing "
        "is wrong: a name is visible everywhere, a second claim is refused, "
        "and the name is free again after an orderly stop."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {note, <<"A second node claims the same name.">>},
        {do, n2, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {do, n2, renew_lease, ?KEY},
        {do, n1, stop_process, ?KEY},
        {do_all, lookup, ?KEY}
    ].
