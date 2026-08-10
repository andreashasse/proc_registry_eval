%% HighlanderPG, https://hex.pm/packages/highlander_pg
%%
%% The odd one out: the registry is not on the BEAM at all, it is a
%% Postgres advisory lock. Every node opens its own Postgres connection and
%% polls `select pg_try_advisory_lock(1, phash2(Name))'. Whoever gets the
%% lock starts the process; the others keep polling. The lock is held by
%% the database session, so when a holder's connection drops Postgres frees
%% it and the next poller takes over.
%%
%% Two consequences the other registries do not have:
%%
%%   * A claim is not a decision. `claim/1' starts a contender and returns
%%     `pending'; who wins is settled in Postgres a poll interval later.
%%   * There is no cluster wide lookup. `whereis_name/1' can only answer
%%     for the node it runs on, so a healthy cluster has exactly one node
%%     answering with a pid and the rest answering `undefined'. In the
%%     report that reads as disagreement, which is why the owner count
%%     matters more than the agreement column here.
%%
%% It is an Elixir library, built by mix rather than rebar3 (see
%% elixir/mix.exs) and reached through its `Elixir.'-prefixed modules.
-module(registry_highlander_pg).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([teardown/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-define(POLLING_INTERVAL_MS, "300").

-spec setup([node()]) -> ok.
setup(_Peers) ->
    %% The Elixir standard library has to be running before any Elixir
    %% module can be called.
    {ok, _Started} = application:ensure_all_started(elixir),
    {ok, _Logger} = application:ensure_all_started(logger),
    {ok, _Postgrex} = application:ensure_all_started(postgrex),
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [
        #{
            id => workbench_contenders,
            start => {workbench_contenders, start_link, []},
            type => supervisor
        }
    ].

%% Stopping a contender closes its Postgres connection, which frees the
%% advisory lock for the next scenario.
-spec cleanup() -> ok.
cleanup() ->
    workbench_contenders:stop_all().

%% Nothing to tell it: the cluster it cares about is the set of sessions
%% polling Postgres, so a node is added to it by starting a contender.
-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    ok.

-spec teardown() -> ok.
teardown() ->
    %% The contenders are children of workbench_sup and are already gone,
    %% which closed their Postgres sessions and freed their locks.
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    % the lock goes with the database session
    true.

-spec application() -> atom().
application() ->
    highlander_pg.

%% Start a contender for Key. Returns as soon as it is running, which is
%% before Postgres has been asked whether this node gets the lock.
-spec claim(workbench:key()) -> pending | {error, term()}.
claim(Key) ->
    Options = [
        {child, #{id => workbench_worker, start => {workbench_worker, start_link, [Key]}}},
        {connect_opts, connect_opts()},
        {name, Key},
        {sup_name, sup_name(Key)},
        {polling_interval, polling_interval_ms()}
    ],
    case workbench_contenders:start_contender(contender(Key, Options)) of
        {ok, _Pid} -> pending;
        {error, {already_started, _Pid}} -> {error, already_contending};
        {error, Reason} -> {error, Reason}
    end.

%% What this node runs, which is the singleton only if this node holds the
%% lock. Every other node answers undefined.
-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    %% Built by mix, so no Erlang tool can see it from here.
    % elp:ignore W0017
    try 'Elixir.HighlanderPG':which_children(sup_name(Key)) of
        [{_Id, Pid, _Type, _Modules} | _Rest] when is_pid(Pid) -> Pid;
        _NoneRunning -> undefined
    catch
        %% No contender on this node at all.
        exit:{noproc, _Call} -> undefined
    end.

%% Stopping the contender closes its Postgres connection, which is what
%% releases the advisory lock.
-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    case workbench_contenders:stop_contender({highlander_pg, Key}) of
        ok -> ok;
        {error, not_found} -> {error, not_registered}
    end.

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    %% The advisory lock lives as long as the database session, so there is
    %% nothing to renew.
    not_supported.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [
        {<<"highlander_pg database">>, fmt:format("~s@~s", [database(), hostname()])},
        {<<"highlander_pg polling interval">>,
            fmt:format("~pms", [polling_interval_ms()])}
    ].

contender(Key, Options) ->
    #{
        id => {highlander_pg, Key},
        start => {'Elixir.HighlanderPG', start_link, [Options]},
        restart => temporary,
        shutdown => 5000
    }.

sup_name(Key) ->
    %% The scenarios use a fixed set of keys, so this cannot run away.
    % elp:ignore W0023
    binary_to_atom(<<"highlander_", Key/binary>>).

connect_opts() ->
    [
        {hostname, hostname()},
        {port, list_to_integer(workbench:env("POSTGRES_PORT", "5432"))},
        {username, list_to_binary(workbench:env("POSTGRES_USER", "workbench"))},
        {password, list_to_binary(workbench:env("POSTGRES_PASSWORD", "workbench"))},
        {database, database()}
    ].

hostname() ->
    list_to_binary(workbench:env("POSTGRES_HOST", "postgres")).

database() ->
    list_to_binary(workbench:env("POSTGRES_DB", "workbench")).

polling_interval_ms() ->
    list_to_integer(workbench:env("HIGHLANDER_POLLING_MS", ?POLLING_INTERVAL_MS)).
