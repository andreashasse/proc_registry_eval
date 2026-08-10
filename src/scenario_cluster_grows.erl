-module(scenario_cluster_grows).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"cluster_grows/service">>).
-define(NEW_KEY, <<"cluster_grows/newcomer">>).

-spec name() -> binary().
name() -> <<"cluster grows to five">>.

-spec description() -> binary().
description() ->
    <<
        "Two nodes are added one after the other, so the cluster goes from "
        "three to four to five while a name stays registered on the first "
        "node. The size matters to a registry that counts votes: a quorum "
        "of four is three, the same as a quorum of five, so the step that "
        "buys nothing is the one that makes the cluster even."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {join, n4},
        settle,
        {do_all, lookup, ?KEY},
        {join, n5},
        settle,
        {do_all, lookup, ?KEY},
        {note, <<"A name claimed on the node that joined last.">>},
        {do, n5, start_process, ?NEW_KEY},
        {do_all, lookup, ?NEW_KEY},
        {note, <<"The original owner gives the name back to a cluster twice its size.">>},
        {do, n1, stop_process, ?KEY},
        {do_all, lookup, ?KEY}
    ].
