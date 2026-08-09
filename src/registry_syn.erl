%% syn, https://github.com/ostinelli/syn
%%
%% Names live in a scope; every node in the scope keeps a full copy and
%% gossips changes, so a lookup is a local ETS read and never blocks.
%% Conflicts after a partition are resolved by keeping the most recently
%% registered process and killing the other one.
-module(registry_syn).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

-define(SCOPE, workbench).

-spec setup([node()]) -> ok.
setup(_Peers) ->
    {ok, _Started} = application:ensure_all_started(syn),
    ok = syn:add_node_to_scopes([?SCOPE]).

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [].

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    ok.

-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    case syn:register(?SCOPE, Key, Pid) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    case syn:lookup(?SCOPE, Key) of
        {Pid, _Meta} -> Pid;
        undefined -> undefined
    end.

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    case syn:unregister(?SCOPE, Key) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    % syn holds a name until the process dies
    not_supported.
