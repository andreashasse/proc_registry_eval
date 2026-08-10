%% `global' from OTP kernel.
%%
%% Names are replicated to every connected node and a registration takes a
%% cluster wide lock, so a registration needs every visible node to answer.
%% On a name clash after a healed partition the default resolver
%% (`global:random_exit_name/3') kills one of the two processes.
-module(registry_global).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-spec setup([node()]) -> ok.
setup(_Peers) ->
    % global is part of kernel and always running
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [].

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    ok.

%% Names disappear with the processes that hold them, which
%% workbench_workers already stops.
-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    % global monitors the process
    true.

-spec application() -> atom().
application() ->
    kernel.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [].

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    case global:register_name(Key, Pid) of
        yes -> {ok, Pid};
        no -> registry:discard(Pid, name_taken)
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    global:whereis_name(Key).

-spec unregister_name(workbench:key()) -> ok.
unregister_name(Key) ->
    _ = global:unregister_name(Key),
    ok.

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    % global holds a name until the process or node dies
    not_supported.
