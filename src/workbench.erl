%% Configuration and boot for one workbench node.
%%
%% Everything configurable comes from OS environment variables so that a
%% reader only has to look at docker-compose.yml to know how a node was
%% started.
-module(workbench).

-export([boot/0]).
-export([registry/0, peers/0, settle_ms/0, action_timeout_ms/0]).
-export([lease_ms/0, set_lease_ms/1, reset_lease_ms/0]).
-export([node_of/1, node_ids/0]).
-export([describe/1]).

% n1 | n2 | n3 ...
-type node_id() :: atom().
-type key() :: binary().
-type pid_ref() :: #{node := node(), id := binary()}.

-export_type([node_id/0, key/0, pid_ref/0]).

-define(CONNECT_TIMEOUT_MS, 60_000).
-define(LEASE_KEY, {?MODULE, lease_ms}).
%% Scenarios name nodes n1, n2, n3. Written out rather than built at run
%% time, so these are the only node ids that exist.
-define(NODE_IDS, [n1, n2, n3, n4, n5, n6, n7, n8, n9]).

%%%===================================================================
%%% Boot
%%%===================================================================

%% Entry point for a cluster node (see docker/entrypoint.sh).
%%
%% The peers are connected *before* the registry starts, because gproc and
%% locker need to know the cluster membership at startup.
-spec boot() -> ok.
boot() ->
    Peers = peers(),
    ok = await_peers(Peers),
    ok = registry:setup(Peers),
    {ok, _} = application:ensure_all_started(workbench),
    io:format(
        "workbench up on ~p with registry ~p, peers ~p~n",
        [node(), registry(), nodes()]
    ),
    ok.

await_peers(Peers) ->
    Deadline = erlang:monotonic_time(millisecond) + ?CONNECT_TIMEOUT_MS,
    await_peers(Peers -- [node()], Deadline).

await_peers([], _Deadline) ->
    ok;
await_peers(Missing, Deadline) ->
    case [P || P <- Missing, net_kernel:connect_node(P) =/= true] of
        [] ->
            ok;
        Still ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(500),
                    await_peers(Still, Deadline);
                false ->
                    error({peers_unreachable, Still})
            end
    end.

%%%===================================================================
%%% Configuration
%%%===================================================================

%% Which registry this run evaluates, e.g. `global'.
-spec registry() -> atom().
registry() ->
    Name = env("REGISTRY", "global"),
    case [Registry || Registry <- registry:names(), atom_to_list(Registry) =:= Name] of
        [Registry] -> Registry;
        [] -> error({unknown_registry, Name, registry:names()})
    end.

%% All cluster nodes, in the order that defines n1, n2, n3.
-spec peers() -> [node()].
peers() ->
    %% A node name has to be an atom, and PEERS is fixed by docker-compose.yml.
    % elp:ignore W0023
    [list_to_atom("workbench@" ++ Host) || Host <- string:lexemes(env("PEERS", ""), ",")].

%% How long to wait for a registry to react to a network change.
-spec settle_ms() -> pos_integer().
settle_ms() ->
    list_to_integer(env("SETTLE_MS", "15000")).

%% Lease length handed to registries that support leases.
%%
%% A scenario can shorten it with the `{lease_ms, Ms}' step; reset/0 puts
%% it back so scenarios stay independent.
-spec lease_ms() -> pos_integer().
lease_ms() ->
    persistent_term:get(?LEASE_KEY, default_lease_ms()).

-spec set_lease_ms(pos_integer()) -> ok.
set_lease_ms(Ms) ->
    persistent_term:put(?LEASE_KEY, Ms).

-spec reset_lease_ms() -> ok.
reset_lease_ms() ->
    _ = persistent_term:erase(?LEASE_KEY),
    ok.

-spec default_lease_ms() -> pos_integer().
default_lease_ms() ->
    list_to_integer(env("LEASE_MS", "60000")).

%% Give up on an action after this long and record a timeout.
-spec action_timeout_ms() -> pos_integer().
action_timeout_ms() ->
    list_to_integer(env("ACTION_TIMEOUT_MS", "20000")).

env(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        "" -> Default;
        Value -> Value
    end.

%%%===================================================================
%%% Node ids
%%%===================================================================

%% `n1' is the first node in PEERS, `n2' the second, and so on.
-spec node_of(node_id()) -> node().
node_of(NodeId) ->
    lists:nth(index(NodeId), peers()).

-spec node_ids() -> [node_id()].
node_ids() ->
    lists:sublist(?NODE_IDS, length(peers())).

-spec index(node_id()) -> pos_integer().
index(NodeId) ->
    {Index, NodeId} = lists:keyfind(NodeId, 2, lists:enumerate(?NODE_IDS)),
    Index.

%%%===================================================================
%%% Pids
%%%===================================================================

%% A node independent description of a pid.
%%
%% `pid_to_list/1' renders the same remote pid differently on different
%% nodes, so it cannot be used to compare what two nodes see.  `phash2/1'
%% hashes the node independent external representation, which can.
-spec describe(pid()) -> pid_ref().
describe(Pid) when is_pid(Pid) ->
    Hash = erlang:phash2(Pid),
    #{
        node => node(Pid),
        id => list_to_binary(io_lib:format("~6.16.0b", [Hash rem 16#1000000]))
    }.
