%% Give up the name and stop the process, the orderly shutdown.
-module(action_stop_process).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> stop_process.

-spec describe() -> binary().
describe() -> <<"unregister the name and stop the process">>.

-spec run(workbench:key()) -> stopped | not_found | {error, term()}.
run(Key) ->
    case registry:whereis_name(Key) of
        undefined ->
            not_found;
        Pid ->
            case registry:unregister_name(Key) of
                ok ->
                    ok = gen_server:stop(Pid),
                    stopped;
                {error, Reason} ->
                    {error, Reason}
            end
    end.
