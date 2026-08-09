-module(workbench_tests).

-include_lib("eunit/include/eunit.hrl").

node_ids_follow_the_peers_env_test() ->
    with_peers("node1,node2,node3", fun() ->
        ?assertEqual([n1, n2, n3], workbench:node_ids()),
        ?assertEqual('workbench@node1', workbench:node_of(n1)),
        ?assertEqual('workbench@node3', workbench:node_of(n3))
    end).

a_two_node_cluster_has_two_ids_test() ->
    with_peers("a,b", fun() ->
        ?assertEqual([n1, n2], workbench:node_ids()),
        ?assertEqual('workbench@b', workbench:node_of(n2))
    end).

%% The point of describe/1: two nodes must produce the same id for the
%% same pid, which pid_to_list/1 does not.
describe_is_stable_for_the_same_pid_test() ->
    ?assertEqual(workbench:describe(self()), workbench:describe(self())),
    ?assertNotEqual(
        workbench:describe(self()), workbench:describe(spawn(fun() -> ok end))
    ),
    ?assertMatch(#{node := _Node, id := _Id}, workbench:describe(self())),
    #{node := Node, id := Id} = workbench:describe(self()),
    ?assertEqual(node(), Node),
    ?assertEqual(6, byte_size(Id)).

lease_can_be_changed_and_reset_test() ->
    Default = workbench:lease_ms(),
    ok = workbench:set_lease_ms(1234),
    ?assertEqual(1234, workbench:lease_ms()),
    ok = workbench:reset_lease_ms(),
    ?assertEqual(Default, workbench:lease_ms()).

with_peers(Peers, Fun) ->
    Previous = os:getenv("PEERS"),
    true = os:putenv("PEERS", Peers),
    try
        Fun()
    after
        case Previous of
            false -> os:unsetenv("PEERS");
            Value -> os:putenv("PEERS", Value)
        end
    end.
