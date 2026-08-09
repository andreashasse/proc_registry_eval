%% Checks that every registry is fully wired up.
-module(registry_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CALLBACKS, [
    {setup, 1},
    {child_specs, 0},
    {on_cluster_ready, 1},
    {register_name, 2},
    {whereis_name, 1},
    {unregister_name, 1},
    {renew_lease, 2}
]).

every_name_has_an_adapter_test_() ->
    [
        {atom_to_list(Name), fun() ->
            ?assert(is_atom(maps:get(Name, registry:adapters())))
        end}
     || Name <- registry:names()
    ].

no_adapter_is_left_out_of_the_report_test() ->
    ?assertEqual(
        lists:sort(registry:names()), lists:sort(maps:keys(registry:adapters()))
    ).

every_adapter_implements_the_behaviour_test_() ->
    [
        {atom_to_list(Module) ++ ":" ++ atom_to_list(Function), fun() ->
            _ = code:ensure_loaded(Module),
            ?assert(erlang:function_exported(Module, Function, Arity))
        end}
     || Module <- maps:values(registry:adapters()), {Function, Arity} <- ?CALLBACKS
    ].

every_action_is_reachable_by_name_test_() ->
    [
        {atom_to_list(Module:name()), fun() ->
            ?assertEqual(Module, action:module(Module:name())),
            ?assert(byte_size(Module:describe()) > 0)
        end}
     || Module <- action:all()
    ].

action_names_are_unique_test() ->
    Names = [Module:name() || Module <- action:all()],
    ?assertEqual(lists:usort(Names), lists:sort(Names)).
