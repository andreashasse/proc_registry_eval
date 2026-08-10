%% Give up the name and stop the process, the orderly shutdown.
-module(action_stop_process).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> stop_process.

-spec describe() -> binary().
describe() -> <<"unregister the name and stop the process">>.

%% Giving up the name can already have stopped the process, when the
%% registry is the one that started it.
-spec stop(pid()) -> ok.
stop(Pid) ->
    try
        gen_server:stop(Pid)
    catch
        exit:noproc -> ok
    end.

-spec run(workbench:key()) -> stopped | not_found | {error, term()}.
run(Key) ->
    case registry:whereis_name(Key) of
        undefined ->
            not_found;
        Pid ->
            case registry:unregister_name(Key) of
                ok ->
                    ok = stop(Pid),
                    stopped;
                {error, Reason} ->
                    {error, Reason}
            end
    end.
