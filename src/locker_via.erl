%% locker behind OTP's `{via, Module, Name}' protocol.
%%
%% With this you can write `gen_server:start_link({via, locker_via, Key},
%% ...)' and have locker hold the name, the same way you would with
%% `global'. Two things do not survive the translation:
%%
%%   * The protocol only lets a registration answer yes or no, so the
%%     difference between a name that is taken and a write that could not
%%     reach a quorum is lost. Call locker directly if you need it.
%%   * locker does not monitor the process, so the name outlives it. The
%%     process has to give the name back on the way out, see
%%     workbench_worker:terminate/2.
-module(locker_via).

-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).

-spec register_name(workbench:key(), pid()) -> yes | no.
register_name(Key, Pid) ->
    case locker:lock(Key, Pid, workbench:lease_ms()) of
        {ok, _W, _Votes, _Commits} -> yes;
        {error, _Reason} -> no
    end.

-spec unregister_name(workbench:key()) -> ok.
unregister_name(Key) ->
    case whereis_name(Key) of
        undefined ->
            ok;
        Pid ->
            _ = locker:release(Key, Pid),
            ok
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    case locker:dirty_read(Key) of
        {ok, Pid} when is_pid(Pid) -> Pid;
        {error, not_found} -> undefined
    end.

-spec send(workbench:key(), term()) -> pid().
send(Key, Message) ->
    case whereis_name(Key) of
        undefined ->
            exit({badarg, {Key, Message}});
        Pid ->
            Pid ! Message,
            Pid
    end.
