%% Start a process and claim a name for it.
%%
%% If the claim fails the process is thrown away again, so a failed action
%% leaves nothing behind. `pending' means the registry took the claim but
%% has not decided who owns the name yet.
-module(action_start_process).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> start_process.

-spec describe() -> binary().
describe() -> <<"start a process and register it">>.

-spec run(workbench:key()) -> {started, workbench:pid_ref()} | pending | {error, term()}.
run(Key) ->
    case registry:claim(Key) of
        {ok, Pid} -> {started, workbench:describe(Pid)};
        pending -> await_owner(Key);
        {error, Reason} -> {error, Reason}
    end.

%% A registry that decides asynchronously gets a bounded chance to make up
%% its mind, so that the rest of the scenario measures the same thing it
%% does for a registry that answers straight away. The time it took is in
%% the report either way.
-spec await_owner(workbench:key()) -> {started, workbench:pid_ref()} | pending.
await_owner(Key) ->
    await_owner(Key, erlang:monotonic_time(millisecond) + workbench:claim_settle_ms()).

await_owner(Key, Deadline) ->
    case registry:whereis_name(Key) of
        Pid when is_pid(Pid) ->
            {started, workbench:describe(Pid)};
        undefined ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(100),
                    await_owner(Key, Deadline);
                false ->
                    pending
            end
    end.
