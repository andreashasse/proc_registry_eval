-module(fmt_tests).

-include_lib("eunit/include/eunit.hrl").

text_test_() ->
    [
        ?_assertEqual(<<"hello">>, fmt:text(<<"hello">>)),
        ?_assertEqual(<<"hello">>, fmt:text(hello)),
        ?_assertEqual(<<"42">>, fmt:text(42)),
        ?_assertEqual(<<"{error,no_quorum}">>, fmt:text({error, no_quorum})),
        ?_assertEqual(<<"#{a => 1}">>, fmt:text(#{a => 1}))
    ].

format_test() ->
    ?assertEqual(<<"2 of 3">>, fmt:format("~p of ~p", [2, 3])).

binary_test_() ->
    [
        ?_assertEqual(<<"ab">>, fmt:binary([<<"a">>, [<<"b">>]])),
        ?_assertEqual(<<"">>, fmt:binary([]))
    ].

%% Whatever a registry answers has to be printable, including terms with
%% pids and references in them.
any_term_is_printable_test() ->
    Terms = [self(), make_ref(), fun() -> ok end, {'EXIT', {badarg, []}}, <<1:1>>],
    [?assert(is_binary(fmt:text(Term))) || Term <- Terms],
    ok.
