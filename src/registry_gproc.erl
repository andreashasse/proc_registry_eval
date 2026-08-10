%% gproc in global mode, https://github.com/uwiger/gproc
%%
%% Global names ({n, g, Key}) are kept by a gen_leader group: one elected
%% leader owns the global name table and every registration goes through
%% it.  A node that cannot see the leader cannot register a global name.
-module(registry_gproc).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([teardown/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, whereis_name/1, unregister_name/1, renew_lease/2]).

-spec setup([node()]) -> ok.
setup(Peers) ->
    %% The candidate list must be set before gproc starts, otherwise
    %% gproc_dist forms a leader group of one.
    ok = application:set_env(gproc, gproc_dist, {Peers, []}),
    {ok, _} = application:ensure_all_started(gproc),
    ok.

-spec child_specs() -> [supervisor:child_spec()].
child_specs() ->
    [].

%% There is nothing to tell gproc: the candidate list is read when
%% gproc_dist starts and cannot be changed afterwards, which is why a node
%% added to a running cluster is a leader group of its own.
-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    ok.

-spec teardown() -> ok.
teardown() ->
    registry:stop_application(gproc).

%% gproc signals a name that is already taken by raising `badarg', the same
%% way it signals a malformed key, so the reason is passed through as is.
%% Names disappear with the processes that hold them, which
%% workbench_workers already stops.
-spec cleanup() -> ok.
cleanup() ->
    ok.

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() ->
    % gproc monitors the process
    true.

-spec application() -> atom().
application() ->
    gproc.

-spec settings() -> [{binary(), binary()}].
settings() ->
    [].

-spec claim(workbench:key()) -> {ok, pid()} | {error, term()}.
claim(Key) ->
    {ok, Pid} = workbench_workers:start_worker(Key),
    try gproc:reg_other({n, g, Key}, Pid) of
        true -> {ok, Pid}
    catch
        error:Reason -> registry:discard(Pid, Reason);
        exit:Reason -> registry:discard(Pid, Reason)
    end.

-spec whereis_name(workbench:key()) -> pid() | undefined.
whereis_name(Key) ->
    try
        gproc:where({n, g, Key})
    catch
        error:Reason -> error({gproc_where_failed, Reason});
        exit:Reason -> error({gproc_where_failed, Reason})
    end.

-spec unregister_name(workbench:key()) -> ok | {error, term()}.
unregister_name(Key) ->
    case whereis_name(Key) of
        undefined ->
            {error, not_registered};
        Pid ->
            try gproc:unreg_other({n, g, Key}, Pid) of
                true -> ok
            catch
                error:Reason -> {error, Reason};
                exit:Reason -> {error, Reason}
            end
    end.

-spec renew_lease(workbench:key(), pid()) -> not_supported.
renew_lease(_Key, _Pid) ->
    % gproc holds a name until the process dies
    not_supported.
