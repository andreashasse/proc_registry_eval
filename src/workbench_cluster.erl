%% Joining and leaving the cluster, from inside a node.
%%
%% A node is either a member, which connects to the other members and
%% starts the registry as it boots, or a joiner, which boots idle and
%% waits to be added by the `{join, Node}' step.  Adding a node is exactly
%% what booting one does, only later: connect, start the registry with the
%% new membership, start the workbench.  That is the point of doing it
%% this way, because it is what a registry sees when a cluster grows.
%%
%% The controller drives it over rpc and tells the other members about the
%% new membership afterwards; see runner.
-module(workbench_cluster).

-export([boot/0, join/1, leave/0]).

-define(CONNECT_TIMEOUT_MS, 60_000).
%% A node being added may not be able to reach every member, so joining
%% gives up on the ones it cannot reach rather than on the join. Longer
%% than `net_setuptime', so that a member which is merely unreachable gets
%% to say so rather than be timed out here.
-define(JOIN_CONNECT_TIMEOUT_MS, 10_000).

%%%===================================================================
%%% Boot
%%%===================================================================

%% Entry point for a cluster node (see docker/entrypoint.sh).
-spec boot() -> ok.
boot() ->
    case lists:member(node(), workbench:joiners()) of
        true ->
            io:format(
                "~p is up and outside the cluster, waiting to be added~n",
                [node()]
            );
        false ->
            Members = workbench:members(),
            ok = await(Members),
            ok = start(Members),
            io:format(
                "workbench up on ~p with registry ~p, peers ~p~n",
                [node(), workbench:registry(), nodes()]
            )
    end.

%%%===================================================================
%%% Membership
%%%===================================================================

%% Join a cluster that is already running.  Members is the membership this
%% node is joining, itself included.
%%
%% The reply says which members it managed to connect to, because a node
%% can be added to a cluster that is partitioned and then it only reaches
%% one side of it.
-spec join([node()]) -> {ok, [node()]} | {error, term()}.
join(Members) ->
    Reached = connect(Members -- [node()], ?JOIN_CONNECT_TIMEOUT_MS),
    try start(Members) of
        ok -> {ok, Reached}
    catch
        Class:Reason -> {error, {Class, Reason}}
    end.

%% Leave the cluster: stop the registry and drop the connections, so that
%% nothing this node knew survives.  Used to put a joined node back where
%% it started before the next scenario runs.
-spec leave() -> ok.
leave() ->
    _ = application:stop(workbench),
    _ = registry:teardown(),
    _ = [
        erlang:disconnect_node(Node)
     || Node <- workbench:peers(), Node =/= node()
    ],
    workbench:reset_members().

%% The peers are connected *before* the registry starts, because gproc and
%% locker need to know the cluster membership at startup.
-spec start([node()]) -> ok.
start(Members) ->
    ok = workbench:set_members(Members),
    ok = registry:setup(Members),
    {ok, _Started} = application:ensure_all_started(workbench),
    ok.

%%%===================================================================
%%% Connecting
%%%===================================================================

%% Every member has to be up before the first one starts its registry, so
%% booting waits for all of them.
-spec await([node()]) -> ok.
await(Members) ->
    Deadline = erlang:monotonic_time(millisecond) + ?CONNECT_TIMEOUT_MS,
    await(Members -- [node()], Deadline).

await([], _Deadline) ->
    ok;
await(Missing, Deadline) ->
    case [P || P <- Missing, net_kernel:connect_node(P) =/= true] of
        [] ->
            ok;
        Still ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(500),
                    await(Still, Deadline);
                false ->
                    error({peers_unreachable, Still})
            end
    end.

%% Connect to as many of Nodes as answer within the timeout.
%%
%% `net_kernel:connect_node/1' takes no timeout of its own and gives up
%% after `net_setuptime', 7 seconds by default, so a node added to a
%% partitioned cluster waits that long for every member it cannot reach.
%% Running the attempts in their own processes makes that one wait rather
%% than one per unreachable member, and puts a bound on it either way.
-spec connect([node()], pos_integer()) -> [node()].
connect(Nodes, TimeoutMs) ->
    Self = self(),
    Ref = make_ref(),
    _ = [
        spawn(fun() -> Self ! {Ref, Node, net_kernel:connect_node(Node)} end)
     || Node <- Nodes
    ],
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    collect(Ref, length(Nodes), Deadline, []).

-spec collect(reference(), non_neg_integer(), integer(), [node()]) -> [node()].
collect(_Ref, 0, _Deadline, Reached) ->
    lists:reverse(Reached);
collect(Ref, Pending, Deadline, Reached) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Ref, Node, true} -> collect(Ref, Pending - 1, Deadline, [Node | Reached]);
        {Ref, _Node, _Failed} -> collect(Ref, Pending - 1, Deadline, Reached)
    after Left ->
        lists:reverse(Reached)
    end.
