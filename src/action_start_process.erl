%% Start a process and claim a name for it.
%%
%% If the claim fails the process is thrown away again, so a failed action
%% leaves nothing behind.
-module(action_start_process).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> start_process.

-spec describe() -> binary().
describe() -> <<"start a process and register it">>.

-spec run(workbench:key()) -> {started, workbench:pid_ref()} | {error, term()}.
run(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    case registry:register_name(Key, Pid) of
        ok ->
            {started, workbench:describe(Pid)};
        {error, Reason} ->
            ok = gen_server:stop(Pid),
            {error, Reason}
    end.
