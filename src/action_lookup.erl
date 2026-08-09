%% Ask this node who owns a name.
%%
%% This is the action that shows disagreement between nodes: it is always
%% answered from the point of view of the node it runs on.
-module(action_lookup).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> lookup.

-spec describe() -> binary().
describe() -> <<"look up which process owns the name">>.

-spec run(workbench:key()) -> {found, workbench:pid_ref()} | not_found.
run(Key) ->
    case registry:whereis_name(Key) of
        undefined -> not_found;
        Pid -> {found, workbench:describe(Pid)}
    end.
