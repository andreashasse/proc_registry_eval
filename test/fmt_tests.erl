-module(fmt_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEMP_DIR, "_build/test").

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

%% Results are written as Erlang source, so anything file:consult/1 cannot
%% read back has to be turned into text first.
printable_test_() ->
    [
        ?_assertEqual(<<"ok">>, fmt:printable(<<"ok">>)),
        ?_assertEqual({error, no_quorum}, fmt:printable({error, no_quorum})),
        ?_assert(is_binary(fmt:printable(self()))),
        ?_assert(is_binary(fmt:printable(make_ref()))),
        ?_assertMatch(
            {rpc_error, {'EXIT', X}} when is_binary(X),
            fmt:printable({rpc_error, {'EXIT', self()}})
        ),
        ?_assertMatch([1, X] when is_binary(X), fmt:printable([1, self()])),
        ?_assertMatch(#{a := X} when is_binary(X), fmt:printable(#{a => self()}))
    ].

a_printable_term_can_be_read_back_test() ->
    Term = #{result => {rpc_error, {'EXIT', {badarg, [{mod, fun_name, 1, self()}]}}}},
    File = filename:join(?TEMP_DIR, "printable.eterm"),
    ok = filelib:ensure_dir(File),
    ok = file:write_file(File, io_lib:format("~p.~n", [fmt:printable(Term)])),
    ?assertMatch({ok, [_Read]}, file:consult(File)),
    ok = file:delete(File).
