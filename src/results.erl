%% Reading and writing the raw run data.
%%
%% One file per registry, plain Erlang terms, so a run can be re-rendered
%% into markdown without running the cluster again.
-module(results).

-export([dir/0, write/2, read_all/0]).

-type run() :: #{
    registry := atom(),
    started_at := binary(),
    environment := [{binary(), binary()}],
    scenarios := [map()]
}.

-export_type([run/0]).

-spec dir() -> file:filename().
dir() ->
    case os:getenv("RESULTS_DIR") of
        false -> "results";
        Dir -> Dir
    end.

-spec write(atom(), run()) -> ok.
write(Registry, Run) ->
    File = filename:join(dir(), atom_to_list(Registry) ++ ".result"),
    ok = filelib:ensure_dir(File),
    ok = file:write_file(File, io_lib:format("~p.~n", [Run])).

%% Every run on disk, in the order the registries are declared.
-spec read_all() -> [run()].
read_all() ->
    Runs = [read(Registry) || Registry <- registry:names()],
    [Run || {ok, Run} <- Runs].

-spec read(atom()) -> {ok, run()} | missing.
read(Registry) ->
    File = filename:join(dir(), atom_to_list(Registry) ++ ".result"),
    case file:consult(File) of
        {ok, [Run]} -> {ok, Run};
        {error, enoent} -> missing;
        %% A registry silently dropped from the report is worse than a
        %% report that refuses to render.
        {error, Reason} -> error({unreadable_result, File, Reason})
    end.
