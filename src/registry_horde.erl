%% Horde, https://github.com/derekkraan/horde
%%
%% A registry backed by a delta CRDT. Every node keeps a full copy and
%% merges what it hears from the others, so a lookup is a local ets read
%% and a registration never needs anyone else's agreement. Membership is
%% `auto', which tracks the visible nodes, so a netsplit shrinks the
%% cluster and a heal merges it again.
%%
%% On a merge that finds the same name registered twice, Horde picks one
%% and sends the loser `exit(Pid, {name_conflict, ...})', so the losing
%% process is killed rather than left running unregistered.
%%
%% It is an Elixir library, built by mix rather than rebar3, see
%% elixir/mix.exs.
-module(registry_horde).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([teardown/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-define(REGISTRY, workbench_horde_registry).

-spec setup([node()]) -> ok.
setup(_Peers) ->
    {ok, _Elixir} = application:ensure_all_started(elixir),
    {ok, _Logger} = application:ensure_all_started(logger),
    {ok, _Horde} = application:ensure_all_started(horde),
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    Options = [{name, ?REGISTRY}, {keys, unique}, {members, auto}],
    [
        #{
            id => ?REGISTRY,
            start => {'Elixir.Horde.Registry', start_link, [Options]},
            type => supervisor
        }
    ].

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    %% `members: auto' already tracks the visible nodes, so a node that is
    %% added to the cluster joins the registry by connecting to it.
    ok.

-spec teardown() -> ok.
teardown() ->
    %% The registry itself is a child of workbench_sup and is already gone.
    registry:stop_application(horde).

-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    %% Horde monitors the owner, and a lookup checks that it is still alive
    %% before answering.
    true.

-spec application() -> atom().
application() ->
    horde.

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    % elp:ignore W0017
    case 'Elixir.Horde.Registry':register_name({?REGISTRY, Key}, Pid) of
        yes -> {ok, Pid};
        no -> registry:discard(Pid, name_taken)
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    % elp:ignore W0017
    case 'Elixir.Horde.Registry':lookup(?REGISTRY, Key) of
        [{Pid, _Value} | _Rest] when is_pid(Pid) -> Pid;
        [] -> undefined
    end.

-spec unregister_name(workbench:key()) -> ok.
unregister_name(Key) ->
    % elp:ignore W0017
    ok = 'Elixir.Horde.Registry':unregister(?REGISTRY, Key).

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    not_supported.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [
        {<<"horde keys">>, <<"unique">>},
        {<<"horde members">>, <<"auto, the visible nodes">>}
    ].
