%% The report is the deliverable, so it is worth testing on its own.
%%
%% These tests feed the renderer the same shape the runner writes and
%% check what a reader would look for.
-module(report_tests).

-include_lib("eunit/include/eunit.hrl").

render_test_() ->
    Markdown = render([run()]),
    [
        {"has a title",
            ?_assert(contains(Markdown, <<"# Distributed process registry">>))},
        {"names the registry", ?_assert(contains(Markdown, <<"syn">>))},
        {"says when it ran", ?_assert(contains(Markdown, <<"2026-08-09T12:00:00Z">>))},
        {"has a column per node",
            ?_assert(contains(Markdown, <<"| n1 | n2 | n3 | n4 |">>))},
        {"shows who owns the name", ?_assert(contains(Markdown, <<"`node1/aaaaaa`">>))},
        {"flags disagreement", ?_assert(contains(Markdown, <<"**disagree**">>))},
        {"describes the partition", ?_assert(contains(Markdown, <<"**isolate n3**">>))},
        {"describes a node being added",
            ?_assert(
                contains(Markdown, <<"**n4 joins the cluster** (now n1, n2, n3, n4)">>)
            )},
        {"says who the new node reached",
            ?_assert(contains(Markdown, <<"connected to n1, n2, n3">>))},
        {"keeps the note", ?_assert(contains(Markdown, <<"_something happened_">>))},
        {"counts the checks", ?_assert(contains(Markdown, <<"agree 0/1">>))},
        {"counts the owners", ?_assert(contains(Markdown, <<"2 owners">>))},
        {"counts timeouts", ?_assert(contains(Markdown, <<"1 timed out">>))},
        {"explains the actions", ?_assert(contains(Markdown, <<"start a process">>))}
    ].

%% A registry saying no is a normal answer; a registry not answering at
%% all is not. The report has to keep them apart.
refusals_and_timeouts_are_counted_separately_test() ->
    Refused = render([run_with_result({error, name_taken})]),
    ?assert(contains(Refused, <<"1 refused">>)),
    ?assertNot(contains(Refused, <<"1 timed out">>)),
    TimedOut = render([run_with_result(timeout)]),
    ?assert(contains(TimedOut, <<"1 timed out">>)),
    ?assertNot(contains(TimedOut, <<"1 refused">>)).

%% Slow answers are what a partition looks like from the outside, so the
%% duration is shown, but only when it is worth noticing.
slow_actions_are_timed_test() ->
    Markdown = render([run()]),
    ?assert(contains(Markdown, <<"_(300ms)_">>)),
    ?assertNot(contains(Markdown, <<"_(1ms)_">>)).

%% `~p' wraps a long term over several lines, and a stack trace is long.
%% A newline in a cell would split the row it sits in.
wrapped_terms_stay_on_one_line_test() ->
    Long = list_to_tuple([
        {a_long_enough_atom_to_force_wrapping, N}
     || N <- lists:seq(1, 20)
    ]),
    Markdown = render([run_with_result({rpc_error, Long})]),
    ?assertEqual(equal_columns, columns_are_consistent(Markdown)),
    ?assertNot(contains(Markdown, <<"\n ">>)).

%% A pipe in a result would otherwise break the table it sits in.
pipes_are_escaped_test() ->
    Markdown = render([run_with_result({error, <<"a|b">>})]),
    ?assert(contains(Markdown, <<"a\\|b">>)),
    ?assertEqual(equal_columns, columns_are_consistent(Markdown)).

registries_become_columns_test() ->
    Markdown = render([run(), maps:put(registry, locker, run())]),
    ?assert(contains(Markdown, <<"| Setting | syn | locker |">>)),
    ?assert(contains(Markdown, <<"| Question | syn | locker |">>)).

%% A node that could not start its registry is not a bigger cluster, and
%% the report has to say so rather than list it as a member.
a_failed_join_did_not_grow_the_cluster_test() ->
    Markdown = render([run_with_failed_join()]),
    ?assert(
        contains(Markdown, <<"**n4 does not join the cluster** (still n1, n2, n3)">>)
    ),
    ?assertNot(contains(Markdown, <<"joins the cluster">>)),
    ?assert(contains(Markdown, <<"error: `setup failed`">>)).

%%%===================================================================
%%% Fixtures
%%%===================================================================

render(Runs) ->
    fmt:binary(report:render(Runs)).

run() ->
    run_with_result(timeout).

run_with_result(Result) ->
    #{
        registry => syn,
        started_at => <<"2026-08-09T12:00:00Z">>,
        environment => [{<<"OTP release">>, <<"27">>}, {<<"net_ticktime">>, <<"5">>}],
        scenarios => [scenario(Result)]
    }.

scenario(Result) ->
    #{
        name => <<"baseline">>,
        module => scenario_baseline,
        description => <<"A description long enough to be useful.">>,
        log =>
            [
                #{kind => note, text => <<"something happened">>},
                #{
                    kind => action,
                    node => n1,
                    action => start_process,
                    key => <<"baseline/service">>,
                    result => {started, owner(node1)},
                    ms => 5
                },
                #{
                    kind => action,
                    node => n2,
                    action => renew_lease,
                    key => <<"baseline/service">>,
                    result => Result,
                    ms => 20
                },
                #{
                    kind => action_all,
                    action => lookup,
                    key => <<"baseline/service">>,
                    results => [
                        {n1, {found, owner(node1)}, 1},
                        {n2, {found, owner(node1)}, 300},
                        {n3, {found, owner(node3)}, 2}
                    ],
                    agreement => disagree
                },
                #{kind => network, detail => {isolate, n3}},
                #{
                    kind => membership,
                    detail => {join, n4},
                    node => n4,
                    members => [n1, n2, n3, n4],
                    result => {joined, [n1, n2, n3]},
                    ms => 120
                },
                #{kind => network, detail => heal},
                #{kind => wait, ms => 15000, reason => settle},
                #{kind => config, setting => lease_ms, value => 3000}
            ]
    }.

run_with_failed_join() ->
    maps:put(
        scenarios,
        [
            #{
                name => <<"node added">>,
                module => scenario_node_added,
                description => <<"A description long enough to be useful.">>,
                log => [
                    #{
                        kind => membership,
                        detail => {join, n4},
                        node => n4,
                        members => [n1, n2, n3],
                        result => {error, <<"setup failed">>},
                        ms => 40
                    }
                ]
            }
        ],
        run()
    ).

owner(node1) -> #{node => 'workbench@node1', id => <<"aaaaaa">>};
owner(node3) -> #{node => 'workbench@node3', id => <<"bbbbbb">>}.

%%%===================================================================
%%% Helpers
%%%===================================================================

contains(Haystack, Needle) ->
    binary:match(Haystack, Needle) =/= nomatch.

%% Within one table every row must have the same number of cells. Tables
%% are the blocks of consecutive rows; the report has several, of
%% different widths.
columns_are_consistent(Markdown) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    Tables = [Table || Table <- blocks(Lines, [], []), Table =/= []],
    case
        [Widths || Table <- Tables, Widths <- [lists:usort(Table)], length(Widths) > 1]
    of
        [] -> equal_columns;
        Uneven -> {different_column_counts, Uneven}
    end.

blocks([], Current, Done) ->
    lists:reverse([lists:reverse(Current) | Done]);
blocks([Line | Rest], Current, Done) ->
    case is_row(Line) of
        true -> blocks(Rest, [columns(Line) | Current], Done);
        false -> blocks(Rest, [], [lists:reverse(Current) | Done])
    end.

is_row(<<"| ", _Rest/binary>>) -> true;
is_row(_Line) -> false.

columns(Row) ->
    length(binary:split(Row, <<" | ">>, [global])).
