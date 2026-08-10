%% Runs every scenario against one registry and stores the raw data.
%%
%% This is the only module that talks to the cluster.  It runs on the
%% controller, a hidden node on the same docker network: hidden so that it
%% takes no part in the registries under test, and on the same network so
%% that it can still reach a node that has been cut off from its peers.
-module(runner).

-export([main/0]).

-define(RECONNECT_TIMEOUT_MS, 60_000).
-define(CLEANUP_SETTLE_MS, 2000).

-type outcome() :: #{kind := atom(), _ => _}.

%%%===================================================================
%%% Entry point
%%%===================================================================

-spec main() -> no_return().
main() ->
    try
        ok = run(),
        halt(0)
    catch
        Class:Reason:Stack ->
            io:format("runner failed: ~p~n", [{Class, Reason, Stack}]),
            halt(1)
    end.

-spec run() -> ok.
run() ->
    Registry = workbench:registry(),
    Nodes = workbench:peers(),
    io:format("evaluating ~p on ~p~n", [Registry, Nodes]),
    ok = await_cluster(Nodes),
    ok = multi(Nodes, registry, on_cluster_ready, [Nodes]),
    Scenarios = [run_scenario(Module, Nodes) || Module <- scenario:all()],
    results:write(Registry, #{
        registry => Registry,
        started_at => timestamp(),
        environment => environment(Nodes),
        scenarios => Scenarios
    }).

%%%===================================================================
%%% Scenarios
%%%===================================================================

-spec run_scenario(module(), [node()]) -> map().
run_scenario(Module, Nodes) ->
    io:format("~n--- ~s~n", [Module:name()]),
    ok = reset(Nodes),
    Log = [execute(Step, Nodes) || Step <- Module:steps()],
    ok = reset(Nodes),
    #{
        name => Module:name(),
        module => Module,
        description => Module:description(),
        log => Log
    }.

%% Back to a healthy cluster with no processes and default leases.
-spec reset([node()]) -> ok.
reset(Nodes) ->
    ok = multi(Nodes, netcut, unblock_all, []),
    ok = reconnect(Nodes),
    ok = multi(Nodes, workbench_workers, stop_all, []),
    ok = multi(Nodes, registry, cleanup, []),
    ok = multi(Nodes, workbench, reset_lease_ms, []),
    timer:sleep(?CLEANUP_SETTLE_MS),
    ok.

%%%===================================================================
%%% Steps
%%%===================================================================

-spec execute(scenario:step(), [node()]) -> outcome().
execute({note, Text}, _Nodes) ->
    #{kind => note, text => Text};
execute({do, NodeId, Action, Key}, _Nodes) ->
    {Result, Ms} = do_action(NodeId, Action, Key),
    log("~p ~p ~s -> ~p (~pms)", [NodeId, Action, Key, Result, Ms]),
    #{
        kind => action,
        node => NodeId,
        action => Action,
        key => Key,
        result => Result,
        ms => Ms
    };
execute({do_all, Action, Key}, _Nodes) ->
    Results = [
        {NodeId, do_action(NodeId, Action, Key)}
     || NodeId <- workbench:node_ids()
    ],
    Agreement = agreement(Results),
    log("all ~p ~s -> ~p", [Action, Key, Agreement]),
    #{
        kind => action_all,
        action => Action,
        key => Key,
        results => [{NodeId, Result, Ms} || {NodeId, {Result, Ms}} <- Results],
        agreement => Agreement
    };
execute({cut, A, B}, _Nodes) ->
    ok = block(A, B),
    ok = block(B, A),
    log("cut ~p <-> ~p", [A, B]),
    #{kind => network, detail => {cut, A, B}};
execute({cut_one_way, A, B}, _Nodes) ->
    ok = block(A, B),
    log("cut ~p <- ~p", [A, B]),
    #{kind => network, detail => {cut_one_way, A, B}};
execute({isolate, NodeId}, _Nodes) ->
    Others = workbench:node_ids() -- [NodeId],
    [
        begin
            ok = block(NodeId, Other),
            ok = block(Other, NodeId)
        end
     || Other <- Others
    ],
    log("isolate ~p", [NodeId]),
    #{kind => network, detail => {isolate, NodeId}};
execute({cut_db, NodeId}, _Nodes) ->
    ok = block(NodeId, workbench:database_host()),
    log("cut ~p <- postgres", [NodeId]),
    #{kind => network, detail => {cut_db, NodeId}};
execute(heal, Nodes) ->
    ok = multi(Nodes, netcut, unblock_all, []),
    ok = reconnect(Nodes),
    log("heal", []),
    #{kind => network, detail => heal};
execute(settle, _Nodes) ->
    Ms = workbench:settle_ms(),
    timer:sleep(Ms),
    #{kind => wait, ms => Ms, reason => settle};
execute({wait, Ms}, _Nodes) ->
    timer:sleep(Ms),
    #{kind => wait, ms => Ms, reason => explicit};
execute({lease_ms, Ms}, Nodes) ->
    ok = multi(Nodes, workbench, set_lease_ms, [Ms]),
    #{kind => config, setting => lease_ms, value => Ms}.

-spec do_action(workbench:node_id(), action:name(), workbench:key()) ->
    {action:result(), non_neg_integer()}.
do_action(NodeId, Action, Key) ->
    Node = workbench:node_of(NodeId),
    Timeout = workbench:action_timeout_ms(),
    Started = erlang:monotonic_time(millisecond),
    Reply = rpc:call(Node, action, run, [Action, Key], Timeout),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    {result(Reply), Elapsed}.

%% An action that does not answer in time is a result in itself.
-spec result(term()) -> action:result().
result({badrpc, timeout}) -> timeout;
result({badrpc, Reason}) -> {rpc_error, fmt:printable(Reason)};
result(Reply) -> fmt:printable(Reply).

%% Do all nodes give the same answer?
-spec agreement([{workbench:node_id(), {action:result(), non_neg_integer()}}]) ->
    agree | disagree.
agreement(Results) ->
    case lists:usort([Result || {_NodeId, {Result, _Ms}} <- Results]) of
        [_Single] -> agree;
        _Several -> disagree
    end.

-spec block(workbench:node_id(), workbench:node_id() | string()) -> ok.
block(NodeId, Target) ->
    Node = workbench:node_of(NodeId),
    ok = rpc:call(Node, netcut, block, [resolve(Target)], 10_000).

-spec resolve(workbench:node_id() | string()) -> node() | string().
resolve(Host) when is_list(Host) -> Host;
resolve(NodeId) -> workbench:node_of(NodeId).

%%%===================================================================
%%% Cluster
%%%===================================================================

%% Wait until every node runs the workbench and sees all its peers.
-spec await_cluster([node()]) -> ok.
await_cluster(Nodes) ->
    Deadline = erlang:monotonic_time(millisecond) + ?RECONNECT_TIMEOUT_MS,
    await_cluster(Nodes, Deadline).

await_cluster(Nodes, Deadline) ->
    case [Node || Node <- Nodes, not booted(Node, Nodes)] of
        [] ->
            ok;
        NotReady ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(1000),
                    await_cluster(Nodes, Deadline);
                false ->
                    error({cluster_not_ready, NotReady})
            end
    end.

-spec booted(node(), [node()]) -> boolean().
booted(Node, Nodes) ->
    is_pid(rpc:call(Node, erlang, whereis, [workbench_sup], 5000)) andalso
        sees_peers(Node, Nodes).

-spec sees_peers(node(), [node()]) -> boolean().
sees_peers(Node, Nodes) ->
    case rpc:call(Node, erlang, nodes, [], 5000) of
        Visible when is_list(Visible) -> (Nodes -- [Node]) -- Visible =:= [];
        _Error -> false
    end.

%% Distributed Erlang only reconnects when something sends a message,
%% so the workbench asks every node to reconnect after a heal. Otherwise
%% the measurement would depend on which registry happens to poll.
-spec reconnect([node()]) -> ok.
reconnect(Nodes) ->
    [
        rpc:call(Node, net_kernel, connect_node, [Peer], 10_000)
     || Node <- Nodes, Peer <- Nodes, Node =/= Peer
    ],
    await_cluster(Nodes).

-spec multi([node()], module(), atom(), [term()]) -> ok.
multi(Nodes, Module, Function, Args) ->
    Bad = [
        {Node, Result}
     || Node <- Nodes,
        Result <- [rpc:call(Node, Module, Function, Args, 20_000)],
        Result =/= ok
    ],
    case Bad of
        [] -> ok;
        Errors -> error({rpc_failed, Module, Function, Errors})
    end.

%%%===================================================================
%%% Run metadata
%%%===================================================================

-spec environment([node()]) -> [{binary(), binary()}].
environment([Node | _]) ->
    [
        {<<"OTP release">>, fmt:text(rpc:call(Node, erlang, system_info, [otp_release]))},
        {<<"net_ticktime">>, fmt:text(rpc:call(Node, net_kernel, get_net_ticktime, []))},
        {<<"kernel prevent_overlapping_partitions">>,
            fmt:text(
                rpc:call(
                    Node,
                    application,
                    get_env,
                    [kernel, prevent_overlapping_partitions, true]
                )
            )},
        {<<"registry version">>, registry_version(Node)},
        {<<"settle after network change">>, fmt:text(workbench:settle_ms())},
        {<<"default lease">>, fmt:text(workbench:lease_ms())},
        {<<"action timeout">>, fmt:text(workbench:action_timeout_ms())},
        {<<"wait for a pending claim">>, fmt:text(workbench:claim_settle_ms())}
    ] ++ registry_settings(Node).

%% Whatever the registry itself thinks is worth knowing, asked on a node so
%% that it reflects the cluster and not the controller.
-spec registry_settings(node()) -> [{binary(), binary()}].
registry_settings(Node) ->
    case rpc:call(Node, registry, settings, []) of
        Settings when is_list(Settings) ->
            [
                {Name, Value}
             || {Name, Value} <- Settings, is_binary(Name), is_binary(Value)
            ];
        _Unavailable ->
            []
    end.

-spec registry_version(node()) -> binary().
registry_version(Node) ->
    Application = rpc:call(Node, registry, application, []),
    %% locker is used as a library and never started, so its application
    %% has to be loaded before it can be asked for a version.
    _ = rpc:call(Node, application, load, [Application]),
    case rpc:call(Node, application, get_key, [Application, vsn]) of
        {ok, Vsn} -> fmt:format("~s ~s", [Application, Vsn]);
        _Missing -> fmt:text(Application)
    end.

-spec timestamp() -> binary().
timestamp() ->
    list_to_binary(
        calendar:system_time_to_rfc3339(
            erlang:system_time(second),
            [{offset, "Z"}]
        )
    ).

-spec log(string(), [term()]) -> ok.
log(Format, Args) ->
    io:format("  " ++ Format ++ "~n", Args).
