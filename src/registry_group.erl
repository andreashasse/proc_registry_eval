%% group, https://github.com/phoenixframework/group
%%
%% The registry underneath Chris McCord's DurableServer, usable on its own.
%% Keys are sharded across replicas and changes are replicated to the other
%% nodes asynchronously over Erlang distribution, so a lookup is local and
%% a registration does not wait for the cluster. Membership is the set of
%% connected nodes; there is nothing to configure for the default cluster.
%%
%% Two shapes worth knowing:
%%
%%   * `Group.register/4' registers the *calling* process, so the claim is
%%     made from inside the worker rather than from the action's process.
%%   * A registration that loses a merge is told so by an exit signal,
%%     `{group_registry_conflict, Key, Meta}', the same way Horde does it.
%%
%% Keys are binaries and may not end in `/', which is reserved for prefix
%% queries. It is an Elixir library, built by mix, see elixir/mix.exs.
-module(registry_group).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-define(GROUP, workbench_group).

-spec setup([node()]) -> ok.
setup(_Peers) ->
    {ok, _Elixir} = application:ensure_all_started(elixir),
    {ok, _Logger} = application:ensure_all_started(logger),
    {ok, _Group} = application:ensure_all_started(group),
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [
        #{
            id => ?GROUP,
            start => {'Elixir.Group', start_link, [[{name, ?GROUP}]]},
            type => supervisor
        }
    ].

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    %% The default cluster is whatever nodes are connected.
    ok.

-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    %% group monitors the registered process and emits an `unregistered'
    %% event when it goes away.
    true.

-spec application() -> atom().
application() ->
    group.

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    Register = fun() ->
        % elp:ignore W0017
        'Elixir.Group':register(?GROUP, Key, #{}, [])
    end,
    case workbench_worker:run(Pid, Register) of
        ok -> {ok, Pid};
        {error, Reason} -> registry:discard(Pid, Reason)
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    % elp:ignore W0017
    case 'Elixir.Group':lookup(?GROUP, Key, []) of
        {Pid, _Meta} when is_pid(Pid) -> Pid;
        nil -> undefined
    end.

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    % elp:ignore W0017
    case 'Elixir.Group':unregister(?GROUP, Key, []) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    %% group has leases, but they are for connections to named clusters,
    %% not for registrations.
    not_supported.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [{<<"group cluster">>, <<"default, the connected nodes">>}].
