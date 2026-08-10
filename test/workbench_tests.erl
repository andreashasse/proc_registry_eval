-module(workbench_tests).

-include_lib("eunit/include/eunit.hrl").

node_ids_follow_the_peers_env_test() ->
    with_peers("node1,node2,node3", fun() ->
        ?assertEqual([n1, n2, n3], workbench:node_ids()),
        ?assertEqual('workbench@node1', workbench:node_of(n1)),
        ?assertEqual('workbench@node3', workbench:node_of(n3)),
        ?assertEqual(n3, workbench:id_of('workbench@node3'))
    end).

a_two_node_cluster_has_two_ids_test() ->
    with_peers("a,b", fun() ->
        ?assertEqual([n1, n2], workbench:node_ids()),
        ?assertEqual('workbench@b', workbench:node_of(n2))
    end).

%% A joiner is a peer like any other, but it is not in the cluster until a
%% scenario adds it, so it has an id and is not a member.
the_cluster_starts_without_the_joiners_test() ->
    with_peers("node1,node2,node3,node4", fun() ->
        with_joiners("node4", fun() ->
            ?assertEqual([n1, n2, n3, n4], workbench:node_ids()),
            ?assertEqual(['workbench@node4'], workbench:joiners()),
            ?assertEqual([n1, n2, n3], workbench:member_ids())
        end)
    end).

a_joiner_has_to_be_a_peer_test() ->
    with_peers("node1,node2", fun() ->
        with_joiners("node9", fun() ->
            ?assertError({joiners_not_in_peers, _Unknown}, workbench:joiners())
        end)
    end).

membership_can_be_changed_and_reset_test() ->
    with_peers("node1,node2,node3,node4", fun() ->
        with_joiners("node4", fun() ->
            ok = workbench:set_members(['workbench@node1', 'workbench@node4']),
            ?assertEqual([n1, n4], workbench:member_ids()),
            ok = workbench:reset_members(),
            ?assertEqual([n1, n2, n3], workbench:member_ids())
        end)
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
    with_env("PEERS", Peers, Fun).

with_joiners(Joiners, Fun) ->
    with_env("JOINERS", Joiners, Fun).

with_env(Name, Value, Fun) ->
    Previous = os:getenv(Name),
    true = os:putenv(Name, Value),
    try
        Fun()
    after
        case Previous of
            false -> os:unsetenv(Name);
            Restore -> os:putenv(Name, Restore)
        end
    end.
