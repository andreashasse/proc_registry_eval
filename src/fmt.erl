%% Turning terms into text.
%%
%% The workbench records whatever a registry answers, including terms it
%% has never seen before, so every conversion here has to be total.
-module(fmt).

-export([text/1, format/2, binary/1, printable/1]).

%% A short, printable rendering of any term.
-spec text(term()) -> binary().
text(Term) when is_binary(Term) -> Term;
text(Term) when is_atom(Term) -> atom_to_binary(Term);
text(Term) when is_integer(Term) -> integer_to_binary(Term);
text(Term) when is_list(Term) ->
    case io_lib:printable_unicode_list(Term) of
        true -> format("~ts", [Term]);
        false -> format("~p", [Term])
    end;
text(Term) ->
    format("~p", [Term]).

%% Results are stored as Erlang source and read back with file:consult/1,
%% which cannot parse pids, references, ports or funs. Anything of that
%% kind becomes text before it is written down.
-spec printable(term()) -> term().
printable(Term) when is_pid(Term); is_reference(Term); is_port(Term); is_function(Term) ->
    text(Term);
printable(Term) when is_list(Term) ->
    printable_list(Term);
printable(Term) when is_tuple(Term) ->
    list_to_tuple(printable_list(tuple_to_list(Term)));
printable(Term) when is_map(Term) ->
    maps:from_list([{printable(Key), printable(Value)} || Key := Value <- Term]);
printable(Term) ->
    Term.

%% Improper lists show up in crash reasons, so this cannot use a
%% comprehension.
printable_list([]) -> [];
printable_list([Head | Tail]) -> [printable(Head) | printable_list(Tail)];
printable_list(Improper) -> printable(Improper).

-spec format(io:format(), [term()]) -> binary().
format(Format, Args) ->
    binary(io_lib:format(Format, Args)).

%% Flatten iodata that was built for output into a single binary.
-spec binary(unicode:chardata()) -> binary().
binary(Chardata) ->
    case unicode:characters_to_binary(Chardata) of
        Binary when is_binary(Binary) -> Binary;
        Error -> error({not_text, Error})
    end.
