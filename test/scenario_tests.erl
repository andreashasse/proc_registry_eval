%% Checks that scenarios and adapters are wired up correctly.
%%
%% These are the mistakes that are easy to make when extending the
%% workbench, and they would otherwise only show up after a docker run.
-module(scenario_tests).

-include_lib("eunit/include/eunit.hrl").

-define(NODE_IDS, [n1, n2, n3]).

every_scenario_is_described_test_() ->
    [
        {binary_to_list(Module:name()), fun() ->
            ?assert(byte_size(Module:name()) > 0),
            ?assert(byte_size(Module:description()) > 20),
            ?assertNotEqual([], Module:steps())
        end}
     || Module <- scenario:all()
    ].

every_step_is_valid_test_() ->
    [
        {
            binary_to_list(Module:name()) ++ ": " ++
                lists:flatten(io_lib:format("~p", [Step])),
            fun() -> check_step(Step) end
        }
     || Module <- scenario:all(), Step <- Module:steps()
    ].

%% A scenario that reuses another scenario's key could be affected by an
%% entry the previous scenario left behind.
scenario_keys_are_unique_test() ->
    Keys = [Key || Module <- scenario:all(), Key <- keys(Module:steps())],
    ?assertEqual(lists:usort(Keys), lists:sort(Keys)).

every_scenario_ends_by_asking_all_nodes_test_() ->
    [
        {binary_to_list(Module:name()), fun() ->
            ?assertMatch({do_all, _Action, _Key}, lists:last(Module:steps()))
        end}
     || Module <- scenario:all()
    ].

%% A cut that is never healed would leak into the next scenario. The
%% runner heals anyway, but a scenario that forgets it is probably a bug.
every_cut_is_healed_test_() ->
    [
        {binary_to_list(Module:name()), fun() ->
            Steps = Module:steps(),
            ?assertEqual(lists:member(heal, Steps), cuts_something(Steps))
        end}
     || Module <- scenario:all()
    ].

%%%===================================================================
%%% Helpers
%%%===================================================================

check_step({note, Text}) ->
    ?assert(is_binary(Text));
check_step({do, NodeId, Action, Key}) ->
    ?assert(lists:member(NodeId, ?NODE_IDS)),
    ?assert(is_binary(Key)),
    ?assertEqual(Action, (action:module(Action)):name());
check_step({do_all, Action, Key}) ->
    ?assert(is_binary(Key)),
    ?assertEqual(Action, (action:module(Action)):name());
check_step({cut, A, B}) ->
    ?assert(lists:member(A, ?NODE_IDS) andalso lists:member(B, ?NODE_IDS)),
    ?assertNotEqual(A, B);
check_step({cut_one_way, A, B}) ->
    ?assert(lists:member(A, ?NODE_IDS) andalso lists:member(B, ?NODE_IDS)),
    ?assertNotEqual(A, B);
check_step({isolate, NodeId}) ->
    ?assert(lists:member(NodeId, ?NODE_IDS));
check_step({cut_db, NodeId}) ->
    ?assert(lists:member(NodeId, ?NODE_IDS));
check_step(heal) ->
    ok;
check_step(settle) ->
    ok;
check_step({wait, Ms}) ->
    ?assert(is_integer(Ms) andalso Ms > 0);
check_step({lease_ms, Ms}) ->
    ?assert(is_integer(Ms) andalso Ms > 0).

keys(Steps) ->
    lists:usort([
        Key
     || Step <- Steps,
        Key <-
            case Step of
                {do, _NodeId, _Action, K} -> [K];
                {do_all, _Action, K} -> [K];
                _Other -> []
            end
    ]).

cuts_something(Steps) ->
    lists:any(
        fun
            ({cut, _A, _B}) -> true;
            ({cut_one_way, _A, _B}) -> true;
            ({isolate, _NodeId}) -> true;
            ({cut_db, _NodeId}) -> true;
            (_Other) -> false
        end,
        Steps
    ).
