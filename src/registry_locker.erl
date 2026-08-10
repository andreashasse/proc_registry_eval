%% locker, https://github.com/wooga/locker
%%
%% A quorum based key-value store with leases. Every node is a master and a
%% write needs a strict majority of them, so the master count is kept odd:
%% with an even number a write needs more than half of an even set, which
%% costs availability without buying any more safety.
%%
%% Unlike the other registries locker knows nothing about processes: it
%% stores the pid as an opaque value, does not monitor it, and drops the
%% key when the lease expires rather than when the process dies.
%%
%% Reads are `locker:dirty_read/1', an ets lookup on the local node.
%% locker's other read, `master_dirty_read/1', checks whether the caller is
%% a master and falls straight through to `dirty_read/1' when it is, so on
%% an all-master cluster the two are the same code path.
-module(registry_locker).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([teardown/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-define(DEFAULT_TIMEOUT_MS, "5000").

-spec setup([node()]) -> ok.
setup(_Peers) ->
    % locker is a plain gen_server, started from child_specs/0
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [
        #{
            id => locker,
            start => {locker, start_link, [quorum(workbench:members())]}
        }
    ].

%% Tell every node who the masters are and how many have to agree.
%% Idempotent, so it does not matter that every node runs it.
%%
%% This is also what growing the cluster means for locker: a node added to
%% it is a master nobody was counting, so the quorum has to be raised
%% before the new node can take part in one.
-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(Peers) ->
    ok = locker:set_w(Peers, quorum(Peers)),
    ok = locker:set_nodes(Peers, Peers, []).

-spec teardown() -> ok.
teardown() ->
    % locker is a child of workbench_sup, and its tables die with it
    ok.

%% Names disappear with the processes that hold them, which
%% workbench_workers already stops.
-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    % the key outlives the process, until the lease expires
    false.

-spec application() -> atom().
application() ->
    locker.

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    case locker:lock(Key, Pid, workbench:lease_ms(), timeout_ms()) of
        {ok, _W, _Votes, _Commits} -> {ok, Pid};
        {error, Reason} -> registry:discard(Pid, Reason)
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
            case locker:release(Key, Pid, timeout_ms()) of
                {ok, _W, _Votes, _Commits} -> ok;
                {error, Reason} -> {error, Reason}
            end
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

-spec settings() -> [{binary(), binary()}].
settings() ->
    Masters = workbench:members(),
    [
        {<<"locker write quorum">>,
            fmt:format("~p of ~p masters", [quorum(Masters), length(Masters)])},
        {<<"locker call timeout">>, fmt:format("~pms", [timeout_ms()])}
    ].

%% A strict majority, so two sides of a partition can never both write.
-spec quorum([node()]) -> pos_integer().
quorum(Masters) ->
    length(Masters) div 2 + 1.

%% Every phase of a write is a gen_server:multi_call/4 with this timeout,
%% and a write that cannot reach a quorum makes two of them, so a failed
%% write costs up to twice this. It applies to lock/4 and release/3 only,
%% see renew_lease/2.
-spec timeout_ms() -> pos_integer().
timeout_ms() ->
    list_to_integer(workbench:env("LOCKER_TIMEOUT_MS", ?DEFAULT_TIMEOUT_MS)).
