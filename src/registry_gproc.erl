%% gproc in global mode, https://github.com/uwiger/gproc
%%
%% Global names ({n, g, Key}) are kept by a gen_leader group: one elected
%% leader owns the global name table and every registration goes through
%% it.  A node that cannot see the leader cannot register a global name.
-module(registry_gproc).
-behaviour(registry).

-export([setup/1, child_specs/0, on_cluster_ready/1]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

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

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(_Peers) ->
    ok.

%% gproc signals a name that is already taken by raising `badarg', the same
%% way it signals a malformed key, so the reason is passed through as is.
-spec register_name(workbench:key(), pid()) -> ok | {error, term()}.
register_name(Key, Pid) ->
    try gproc:reg_other({n, g, Key}, Pid) of
        true -> ok
    catch
        error:Reason -> {error, Reason};
        exit:Reason -> {error, Reason}
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
