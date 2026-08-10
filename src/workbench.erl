%% Configuration for one workbench node.
%%
%% Everything configurable comes from OS environment variables so that a
%% reader only has to look at docker-compose.yml to know how a node was
%% started.  Joining and leaving the cluster is workbench_cluster.
-module(workbench).

-export([registry/0, peers/0, joiners/0, settle_ms/0, action_timeout_ms/0, env/2]).
-export([database_host/0, claim_settle_ms/0]).
-export([members/0, set_members/1, reset_members/0]).
-export([lease_ms/0, set_lease_ms/1, reset_lease_ms/0]).
-export([node_of/1, id_of/1, node_ids/0, member_ids/0]).
-export([describe/1]).

% n1 | n2 | n3 ...
-type node_id() :: atom().
-type key() :: binary().
-type pid_ref() :: #{node := node(), id := binary()}.

-export_type([node_id/0, key/0, pid_ref/0]).

-define(LEASE_KEY, {?MODULE, lease_ms}).
-define(MEMBERS_KEY, {?MODULE, members}).
%% Scenarios name nodes n1, n2, n3. Written out rather than built at run
%% time, so these are the only node ids that exist.
-define(NODE_IDS, [n1, n2, n3, n4, n5, n6, n7, n8, n9]).

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

%% Every node in docker-compose.yml, in the order that defines n1, n2, n3.
%% Not the same as members/0: the joiners are listed here but start
%% outside the cluster.
-spec peers() -> [node()].
peers() ->
    nodes_named(env("PEERS", "")).

%% The nodes that boot idle, outside the cluster, until a scenario adds
%% them with the `{join, Node}' step. They exist so that a run can measure
%% what a registry does when the cluster grows: a node that was a member
%% all along and one that has just been added are not the same thing.
-spec joiners() -> [node()].
joiners() ->
    Joiners = nodes_named(env("JOINERS", "")),
    case Joiners -- peers() of
        [] -> Joiners;
        Unknown -> error({joiners_not_in_peers, Unknown})
    end.

%% The cluster this node belongs to right now.
%%
%% Every node but the joiners starts as a member; a joiner is told the
%% membership it is joining, and every member is told when it changes, so
%% a registry that has to be configured with the cluster can be.
-spec members() -> [node()].
members() ->
    persistent_term:get(?MEMBERS_KEY, peers() -- joiners()).

-spec set_members([node()]) -> ok.
set_members(Members) ->
    persistent_term:put(?MEMBERS_KEY, Members).

-spec reset_members() -> ok.
reset_members() ->
    _ = persistent_term:erase(?MEMBERS_KEY),
    ok.

-spec nodes_named(string()) -> [node()].
nodes_named(Hosts) ->
    %% A node name has to be an atom, and PEERS is fixed by docker-compose.yml.
    % elp:ignore W0023
    [list_to_atom("workbench@" ++ Host) || Host <- string:lexemes(Hosts, ",")].

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
%% The hostname of the database, for registries that keep their state
%% there and for cutting a node off from it.
-spec database_host() -> string().
database_host() ->
    env("POSTGRES_HOST", "postgres").

%% How long to wait for a registry that answers a claim with `pending' to
%% decide who owns the name. Only registries that settle asynchronously,
%% such as highlander_pg, ever use it.
-spec claim_settle_ms() -> pos_integer().
claim_settle_ms() ->
    list_to_integer(env("CLAIM_SETTLE_MS", "3000")).

-spec action_timeout_ms() -> pos_integer().
action_timeout_ms() ->
    list_to_integer(env("ACTION_TIMEOUT_MS", "20000")).

%% Configuration is read straight from the environment, so docker-compose.yml
%% is the only place to look.
-spec env(string(), string()) -> string().
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

-spec id_of(node()) -> node_id().
id_of(Node) ->
    {Index, Node} = lists:keyfind(Node, 2, lists:enumerate(peers())),
    lists:nth(Index, ?NODE_IDS).

%% Every node id, joiners included.
-spec node_ids() -> [node_id()].
node_ids() ->
    lists:sublist(?NODE_IDS, length(peers())).

%% The ids of the nodes that are in the cluster right now.
-spec member_ids() -> [node_id()].
member_ids() ->
    [id_of(Node) || Node <- members()].

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
