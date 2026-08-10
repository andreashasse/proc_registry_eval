%% syn, https://github.com/ostinelli/syn
%%
%% Names live in a scope; every node in the scope keeps a full copy and
%% gossips changes, so a lookup is a local ETS read and never blocks.
%% Conflicts after a partition are resolved by keeping the most recently
%% registered process and killing the other one.
-module(registry_syn).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([teardown/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

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
    % a scope spans whatever nodes have joined it
    ok.

-spec teardown() -> ok.
teardown() ->
    registry:stop_application(syn).

%% Names disappear with the processes that hold them, which
%% workbench_workers already stops.
-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    % syn monitors the process
    true.

-spec application() -> atom().
application() ->
    syn.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [].

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    case syn:register(?SCOPE, Key, Pid) of
        ok -> {ok, Pid};
        {error, Reason} -> registry:discard(Pid, Reason)
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
