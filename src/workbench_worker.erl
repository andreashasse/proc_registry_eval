%% The process that gets registered.
%%
%% It does nothing except exist, so that everything the workbench observes
%% is a property of the registry and not of the process.
-module(workbench_worker).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-spec start_link(workbench:key()) -> gen_server:start_ret().
start_link(Key) ->
    gen_server:start_link(?MODULE, Key, []).

-spec init(workbench:key()) -> {ok, workbench:key()}.
init(Key) ->
    {ok, Key}.

-spec handle_call(key, gen_server:from(), workbench:key()) ->
    {reply, workbench:key(), workbench:key()}.
handle_call(key, _From, Key) ->
    {reply, Key, Key}.

-spec handle_cast(term(), workbench:key()) -> {noreply, workbench:key()}.
handle_cast(_Msg, Key) ->
    {noreply, Key}.
