%% locker, https://github.com/wooga/locker
%%
%% A quorum based key-value store with leases.  A write needs W of the N
%% nodes to agree, a read is a local ETS lookup.  Unlike the other three
%% registries locker knows nothing about processes: it stores the pid as
%% an opaque value, does not monitor it, and drops the key when the lease
%% expires rather than when the process dies.
-module(registry_locker).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

-spec setup([node()]) -> ok.
setup(_Peers) ->
    % locker is a plain gen_server, started from child_specs/0
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [
        #{
            id => locker,
            start => {locker, start_link, [write_quorum()]}
        }
    ].

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(Peers) ->
    %% Every node is a master, no replicas.  Idempotent, so it does not
    %% matter that every node runs it.
    ok = locker:set_nodes(Peers, Peers, []).

-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    case locker:lock(Key, Pid, workbench:lease_ms()) of
        {ok, _W, _Votes, _Commits} -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    case locker:dirty_read(Key) of
        {ok, Pid} when is_pid(Pid) -> Pid;
        {error, not_found} -> undefined
    end.

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    case whereis_name(Key) of
        undefined ->
            {error, not_registered};
        Pid ->
            case locker:release(Key, Pid) of
                {ok, _W, _Votes, _Commits} -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.

-spec renew_lease(workbench:key(), pid()) -> ok | {error, term()}.
renew_lease(Key, Pid) ->
    case locker:extend_lease(Key, Pid, workbench:lease_ms()) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% A strict majority, so two sides of a partition can never both write.
-spec write_quorum() -> pos_integer().
write_quorum() ->
    length(workbench:peers()) div 2 + 1.
