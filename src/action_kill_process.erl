%% Kill the process without giving up the name.
%%
%% Shows whether the registry notices that the owner is gone by itself, or
%% keeps handing out a dead pid.
-module(action_kill_process).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> kill_process.

-spec describe() -> binary().
describe() -> <<"kill the process without unregistering">>.

-spec run(workbench:key()) -> killed | not_found.
run(Key) ->
    case registry:whereis_name(Key) of
        undefined ->
            not_found;
        Pid ->
            true = exit(Pid, kill),
            killed
    end.
