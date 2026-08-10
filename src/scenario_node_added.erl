-module(scenario_node_added).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"node_added/service">>).
-define(NEW_KEY, <<"node_added/newcomer">>).

-spec name() -> binary().
name() -> <<"node added">>.

-spec description() -> binary().
description() ->
    <<
        "A fourth node is added to a healthy cluster. Three questions: does "
        "the new node learn a name that was registered before it existed, "
        "is its claim on that name refused, and do the nodes that were "
        "there all along see what it registers itself?"
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {join, n4},
        settle,
        {note, <<"The new node looks up a name that predates it.">>},
        {do_all, lookup, ?KEY},
        {note, <<"...and then claims it.">>},
        {do, n4, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {note, <<"A name registered on the new node, seen from the old ones.">>},
        {do, n4, start_process, ?NEW_KEY},
        {do_all, lookup, ?NEW_KEY}
    ].
