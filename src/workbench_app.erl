-module(workbench_app).
-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_Type, _Args) ->
    {ok, Pid} = workbench_sup:start_link(),
    {ok, Pid}.

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
