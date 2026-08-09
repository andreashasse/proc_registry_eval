%% locker with a replica, reading locally.
%%
%% n1 and n2 are masters, n3 is a replica: it takes part in no quorum and
%% gets the data pushed to it by the masters. Reads on n3 are still local
%% ets lookups, so this variant shows how far behind a replica can be.
%%
%% Compare with registry_locker_master, which has the same layout and
%% differs only in the read.
-module(registry_locker_replica).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

-spec setup([node()]) -> ok.
setup(Peers) ->
    registry_locker:setup(Peers).

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    {Masters, _Replicas} = topology(),
    registry_locker:child_specs(registry_locker:quorum(Masters)).

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    {Masters, Replicas} = topology(),
    registry_locker:announce(Masters, Replicas).

-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    registry_locker:register_name(Key, Pid).

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    registry_locker:read(local, Key).

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    registry_locker:unregister_name(Key, local).

-spec renew_lease(workbench:key(), pid()) -> ok | {error, term()}.
renew_lease(Key, Pid) ->
    registry_locker:renew_lease(Key, Pid).

-spec application() -> atom().
application() ->
    locker.

-spec settings() -> [{binary(), binary()}].
settings() ->
    {Masters, Replicas} = topology(),
    registry_locker:settings(local, Masters, Replicas).

topology() ->
    registry_locker:split_topology(workbench:peers()).
