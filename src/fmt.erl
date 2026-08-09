%% Turning terms into text.
%%
%% The workbench records whatever a registry answers, including terms it
%% has never seen before, so every conversion here has to be total.
-module(fmt).

-export([text/1, format/2, binary/1]).

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
