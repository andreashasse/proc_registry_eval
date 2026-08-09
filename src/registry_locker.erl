%% locker, https://github.com/wooga/locker
%%
%% A quorum based key-value store with leases. A write needs W of the N
%% masters to agree. Unlike the other three registries locker knows nothing
%% about processes: it stores the pid as an opaque value, does not monitor
%% it, and drops the key when the lease expires rather than when the
%% process dies.
%%
%% This module is both the plain variant (every node a master, names read
%% from the local ets table) and the implementation shared with
%% registry_locker_replica and registry_locker_master, which differ only in
%% the cluster layout and in how a name is read back.
-module(registry_locker).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

%% Shared with the other locker variants.
-export([child_specs/1, announce/2, split_topology/1, quorum/1]).
-export([read/2, unregister_name/2, settings/3]).

-type read() :: local | master.
-export_type([read/0]).

-define(DEFAULT_TIMEOUT_MS, "5000").

%%%===================================================================
%%% The plain variant: every node a master, local reads
%%%===================================================================

-spec setup([node()]) -> ok.
setup(_Peers) ->
    % locker is a plain gen_server, started from child_specs/0
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    child_specs(quorum(workbench:peers())).

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(Peers) ->
    announce(Peers, []).

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    read(local, Key).

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    unregister_name(Key, local).

-spec application() -> atom().
application() ->
    locker.

-spec settings() -> [{binary(), binary()}].
settings() ->
    settings(local, workbench:peers(), []).

%%%===================================================================
%%% Shared by every locker variant
%%%===================================================================

-spec child_specs(pos_integer()) -> [supervisor:child_spec()].
child_specs(Quorum) ->
    [
        #{
            id => locker,
            start => {locker, start_link, [Quorum]}
        }
    ].

%% Tell every node who the masters are and how many have to agree.
%% Idempotent, so it does not matter that every node runs it.
-spec announce([node()], [node()]) -> ok.
announce(Masters, Replicas) ->
    Cluster = workbench:peers(),
    ok = locker:set_w(Cluster, quorum(Masters)),
    ok = locker:set_nodes(Cluster, Masters, Replicas).

%% All but the last node are masters, so that the last one is a node that
%% has to go somewhere else for a fresh read. With two masters a write
%% needs both of them, which is what makes this layout interesting: any
%% split between the masters stops writes entirely.
-spec split_topology([node()]) -> {[node()], [node()]}.
split_topology(Peers) ->
    {lists:droplast(Peers), [lists:last(Peers)]}.

%% A strict majority, so two sides of a partition can never both write.
-spec quorum([node()]) -> pos_integer().
quorum(Masters) ->
    length(Masters) div 2 + 1.

-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    case locker:lock(Key, Pid, workbench:lease_ms(), timeout_ms()) of
        {ok, _W, _Votes, _Commits} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% locker:extend_lease/4 takes a timeout but is not exported, so a lease
%% renewal is stuck with locker's own 5s default however LOCKER_TIMEOUT_MS
%% is set.
-spec renew_lease(workbench:key(), pid()) -> ok | {error, term()}.
renew_lease(Key, Pid) ->
    case locker:extend_lease(Key, Pid, workbench:lease_ms()) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec unregister_name(workbench:key(), read()) -> ok | {error, term()}.
unregister_name(Key, Read) ->
    case read(Read, Key) of
        undefined ->
            {error, not_registered};
        Pid ->
            case locker:release(Key, Pid, timeout_ms()) of
                {ok, _W, _Votes, _Commits} -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.

%% locker offers exactly two reads. `dirty_read/1' is an ets lookup in
%% whatever this node happens to have replicated. `master_dirty_read/1' is
%% the same lookup, but done on a master: locally if this node is one, over
%% rpc to a random master if it is not.
-spec read(read(), workbench:key()) -> pid() | undefined.
read(local, Key) ->
    found(locker:dirty_read(Key));
read(master, Key) ->
    found(locker:master_dirty_read(Key)).

found({ok, Pid}) when is_pid(Pid) -> Pid;
found({error, not_found}) -> undefined;
%% Only master_dirty_read/1 can get here, when the master it picked is on
%% the other side of a partition.
found({badrpc, Reason}) -> error({master_unreachable, Reason}).

-spec settings(read(), [node()], [node()]) -> [{binary(), binary()}].
settings(Read, Masters, Replicas) ->
    [
        {<<"locker write quorum">>,
            fmt:format("~p of ~p masters", [quorum(Masters), length(Masters)])},
        {<<"locker replicas">>, fmt:text(length(Replicas))},
        {<<"locker read">>, read_name(Read)},
        {<<"locker call timeout">>, fmt:format("~pms", [timeout_ms()])}
    ].

read_name(local) -> <<"dirty_read, local ets">>;
read_name(master) -> <<"master_dirty_read">>.

%% Every phase of a write is a gen_server:multi_call/4 with this timeout,
%% and a write that cannot reach a quorum makes two of them, so a failed
%% write costs up to twice this. It applies to lock/4 and release/3 only,
%% see renew_lease/2.
-spec timeout_ms() -> pos_integer().
timeout_ms() ->
    list_to_integer(workbench:env("LOCKER_TIMEOUT_MS", ?DEFAULT_TIMEOUT_MS)).
