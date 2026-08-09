%% locker with a replica, reading through a master.
%%
%% The same layout as registry_locker_replica: n1 and n2 are masters, n3 is
%% a replica. The only difference is the read, which goes through
%% `locker:master_dirty_read/1': local on a master, over rpc to a random
%% master on the replica.
%%
%% This is the variant where a read can fail rather than be stale.
-module(registry_locker_master).
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
    registry_locker:read(master, Key).

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    registry_locker:unregister_name(Key, master).

-spec renew_lease(workbench:key(), pid()) -> ok | {error, term()}.
renew_lease(Key, Pid) ->
    registry_locker:renew_lease(Key, Pid).

-spec application() -> atom().
application() ->
    locker.

-spec settings() -> [{binary(), binary()}].
settings() ->
    {Masters, Replicas} = topology(),
    registry_locker:settings(master, Masters, Replicas).

topology() ->
    registry_locker:split_topology(workbench:peers()).
