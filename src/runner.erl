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
%% A node being added connects to the members it can reach, gives up on
%% the others, and then starts its registry, so it answers well before
%% this.
-define(JOIN_TIMEOUT_MS, 60_000).
%% Leaving the cluster, and telling the members that it changed.
-define(MEMBERSHIP_TIMEOUT_MS, 30_000).

-type outcome() :: #{kind := atom(), _ => _}.
%% The nodes that are in the cluster at a given point in a scenario. It
%% starts as the nodes the run started with and grows with every `join'.
-type members() :: [workbench:node_id()].

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
    Nodes = workbench:members(),
    io:format(
        "evaluating ~p on ~p, joinable: ~p~n",
        [Registry, Nodes, workbench:joiners()]
    ),
    ok = await_cluster(Nodes),
    ok = multi(Nodes, registry, on_cluster_ready, [Nodes]),
    Scenarios = [run_scenario(Module) || Module <- scenario:all()],
    results:write(Registry, #{
        registry => Registry,
        started_at => timestamp(),
        environment => environment(Nodes),
        scenarios => Scenarios
    }).

%%%===================================================================
%%% Scenarios
%%%===================================================================

-spec run_scenario(module()) -> map().
run_scenario(Module) ->
    io:format("~n--- ~s~n", [Module:name()]),
    Base = workbench:member_ids(),
    ok = reset(Base),
    {Log, Members} = lists:mapfoldl(fun execute/2, Base, Module:steps()),
    ok = reset(Members),
    #{
        name => Module:name(),
        module => Module,
        description => Module:description(),
        log => Log
    }.

%% Back to the cluster the run started with: the nodes a scenario added
%% are removed again, cuts are lifted, and no processes or shortened
%% leases are left behind.
-spec reset(members()) -> ok.
reset(Members) ->
    Base = workbench:member_ids(),
    ok = multi(workbench:peers(), netcut, unblock_all, []),
    ok = part(Members -- Base),
    Nodes = nodes_of(Base),
    ok = reconnect(Nodes),
    ok = multi(Nodes, workbench_workers, stop_all, []),
    ok = multi(Nodes, registry, cleanup, []),
    ok = multi(Nodes, workbench, reset_lease_ms, []),
    ok = announce(Base),
    timer:sleep(?CLEANUP_SETTLE_MS),
    ok.

%% Put the nodes a scenario added back outside the cluster. Best effort:
%% a node whose registry did not survive being added still has to be
%% cleared out of the way of the next scenario.
-spec part(members()) -> ok.
part([]) ->
    ok;
part(NodeIds) ->
    _ = [
        rpc:call(
            workbench:node_of(NodeId),
            workbench_cluster,
            leave,
            [],
            ?MEMBERSHIP_TIMEOUT_MS
        )
     || NodeId <- NodeIds
    ],
    log("removed ~p from the cluster", [NodeIds]),
    ok.

%% Tell every member what the cluster looks like now.  Only registries
%% that have to be configured with the membership, locker among these,
%% care; for the rest it is a no-op. Best effort, because a scenario can
%% add a node while the cluster is partitioned, and then a node cannot
%% reach the ones it is being told about.
-spec announce(members()) -> ok.
announce(NodeIds) ->
    Nodes = nodes_of(NodeIds),
    _ = [
        rpc:call(Node, workbench, set_members, [Nodes], ?MEMBERSHIP_TIMEOUT_MS)
     || Node <- Nodes
    ],
    _ = [
        rpc:call(Node, registry, on_cluster_ready, [Nodes], ?MEMBERSHIP_TIMEOUT_MS)
     || Node <- Nodes
    ],
    ok.

-spec nodes_of(members()) -> [node()].
nodes_of(NodeIds) ->
    [workbench:node_of(NodeId) || NodeId <- NodeIds].

%%%===================================================================
%%% Steps
%%%===================================================================

%% Every step is answered with what happened and the membership the next
%% step runs against, which only `join' changes.
-spec execute(scenario:step(), members()) -> {outcome(), members()}.
execute({note, Text}, Members) ->
    {#{kind => note, text => Text}, Members};
execute({do, NodeId, Action, Key}, Members) ->
    {Result, Ms} = do_action(NodeId, Action, Key),
    log("~p ~p ~s -> ~p (~pms)", [NodeId, Action, Key, Result, Ms]),
    {
        #{
            kind => action,
            node => NodeId,
            action => Action,
            key => Key,
            result => Result,
            ms => Ms
        },
        Members
    };
execute({do_all, Action, Key}, Members) ->
    Results = [{NodeId, do_action(NodeId, Action, Key)} || NodeId <- Members],
    Agreement = agreement(Results),
    log("all ~p ~s -> ~p", [Action, Key, Agreement]),
    {
        #{
            kind => action_all,
            action => Action,
            key => Key,
            results => [{NodeId, Result, Ms} || {NodeId, {Result, Ms}} <- Results],
            agreement => Agreement
        },
        Members
    };
execute({cut, A, B}, Members) ->
    ok = block(A, B),
    ok = block(B, A),
    log("cut ~p <-> ~p", [A, B]),
    {#{kind => network, detail => {cut, A, B}}, Members};
execute({cut_one_way, A, B}, Members) ->
    ok = block(A, B),
    log("cut ~p <- ~p", [A, B]),
    {#{kind => network, detail => {cut_one_way, A, B}}, Members};
execute({isolate, NodeId}, Members) ->
    Others = Members -- [NodeId],
    [
        begin
            ok = block(NodeId, Other),
            ok = block(Other, NodeId)
        end
     || Other <- Others
    ],
    log("isolate ~p", [NodeId]),
    {#{kind => network, detail => {isolate, NodeId}}, Members};
execute({cut_db, NodeId}, Members) ->
    ok = block(NodeId, workbench:database_host()),
    log("cut ~p <- postgres", [NodeId]),
    {#{kind => network, detail => {cut_db, NodeId}}, Members};
execute({join, NodeId}, Members) ->
    Joined = Members ++ [NodeId],
    {Result, Ms} = join(NodeId, Joined),
    ok = announce(Joined),
    log("join ~p -> ~p (~pms)", [NodeId, Result, Ms]),
    {
        #{
            kind => membership,
            detail => {join, NodeId},
            node => NodeId,
            members => Joined,
            result => Result,
            ms => Ms
        },
        Joined
    };
execute(heal, Members) ->
    ok = multi(workbench:peers(), netcut, unblock_all, []),
    ok = reconnect(nodes_of(Members)),
    log("heal", []),
    {#{kind => network, detail => heal}, Members};
execute(settle, Members) ->
    Ms = workbench:settle_ms(),
    timer:sleep(Ms),
    {#{kind => wait, ms => Ms, reason => settle}, Members};
execute({wait, Ms}, Members) ->
    timer:sleep(Ms),
    {#{kind => wait, ms => Ms, reason => explicit}, Members};
execute({lease_ms, Ms}, Members) ->
    ok = multi(nodes_of(Members), workbench, set_lease_ms, [Ms]),
    {#{kind => config, setting => lease_ms, value => Ms}, Members}.

%% Add a node to the cluster.  What it answers is the ids of the members
%% it reached, which is all of them unless the cluster is partitioned.
-spec join(workbench:node_id(), members()) -> {term(), non_neg_integer()}.
join(NodeId, Members) ->
    Node = workbench:node_of(NodeId),
    Started = erlang:monotonic_time(millisecond),
    Reply = rpc:call(
        Node, workbench_cluster, join, [nodes_of(Members)], ?JOIN_TIMEOUT_MS
    ),
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    {joined(Reply), Elapsed}.

-spec joined(term()) -> term().
joined({ok, Reached}) when is_list(Reached) ->
    %% In cluster order rather than in the order they answered.
    Ids = [workbench:id_of(Node) || Node <- Reached, is_atom(Node)],
    {joined, [NodeId || NodeId <- workbench:node_ids(), lists:member(NodeId, Ids)]};
joined({badrpc, Reason}) ->
    {rpc_error, fmt:printable(Reason)};
joined(Other) ->
    %% Whatever a registry that could not be started answered with.
    fmt:printable(Other).

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
    await(Nodes, Deadline, fun(_Nodes) -> ok end).

-spec await([node()], integer(), fun(([node()]) -> ok)) -> ok.
await(Nodes, Deadline, Retry) ->
    case [Node || Node <- Nodes, not booted(Node, Nodes)] of
        [] ->
            ok;
        NotReady ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(1000),
                    ok = Retry(Nodes),
                    await(Nodes, Deadline, Retry);
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
%%
%% It keeps asking until the cluster is whole, because one round is not
%% always enough: a node that leaves drops its connections one by one, and
%% for as long as the others disagree about whether it is still there,
%% `global' takes them for an overlapping partition and disconnects them
%% from each other.
-spec reconnect([node()]) -> ok.
reconnect(Nodes) ->
    Deadline = erlang:monotonic_time(millisecond) + ?RECONNECT_TIMEOUT_MS,
    ok = connect_all(Nodes),
    await(Nodes, Deadline, fun connect_all/1).

-spec connect_all([node()]) -> ok.
connect_all(Nodes) ->
    _ = [
        rpc:call(Node, net_kernel, connect_node, [Peer], 10_000)
     || Node <- Nodes, Peer <- Nodes, Node =/= Peer
    ],
    ok.

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
