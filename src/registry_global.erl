%% `global' from OTP kernel.
%%
%% Names are replicated to every connected node and a registration takes a
%% cluster wide lock, so a registration needs every visible node to answer.
%% On a name clash after a healed partition the default resolver
%% (`global:random_exit_name/3') kills one of the two processes.
-module(registry_global).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

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

-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    case global:register_name(Key, Pid) of
        yes -> ok;
        no -> {error, name_taken}
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
