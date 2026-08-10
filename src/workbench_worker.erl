%% The process that gets registered.
%%
%% It does nothing except exist, so that everything the workbench observes
%% is a property of the registry and not of the process. The one exception
%% is terminate/2: a registry that does not free the name when its owner
%% dies needs the owner to give it back, and that is the best a process can
%% do about it.
-module(workbench_worker).
-behaviour(gen_server).

-export([start_link/1, run/2]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

-spec start_link(workbench:key()) -> gen_server:start_ret().
start_link(Key) ->
    gen_server:start_link(?MODULE, Key, []).

%% Some registries register the calling process rather than a pid you hand
%% them, so the claim has to be made from in here.
-spec run(pid(), fun(() -> Result)) -> Result.
run(Pid, Fun) ->
    gen_server:call(Pid, {run, Fun}).

-spec init(workbench:key()) -> {ok, workbench:key()}.
init(Key) ->
    %% Without this a supervisor shutdown kills the process outright and
    %% terminate/2 never runs.
    process_flag(trap_exit, true),
    {ok, Key}.

-spec handle_call(key | {run, fun(() -> term())}, gen_server:from(), workbench:key()) ->
    {reply, term(), workbench:key()}.
handle_call(key, _From, Key) ->
    {reply, Key, Key};
handle_call({run, Fun}, _From, Key) ->
    {reply, Fun(), Key}.

-spec handle_cast(term(), workbench:key()) -> {noreply, workbench:key()}.
handle_cast(_Msg, Key) ->
    {noreply, Key}.

%% Only reached on an orderly stop. `exit(Pid, kill)' skips it, which is
%% exactly what the process death scenario shows: a process can tidy up
%% after a shutdown, but nothing can tidy up after a crash.
-spec terminate(term(), workbench:key()) -> ok.
terminate(_Reason, Key) ->
    case registry:frees_name_on_exit() of
        true -> ok;
        false -> release_if_owner(Key)
    end.

%% Only the owner may give a name back. A process that lost the race, or
%% that is looking at a stale local copy on the wrong side of a partition,
%% would otherwise release somebody else's name, and pay for a quorum write
%% to do it.
-spec release_if_owner(workbench:key()) -> ok.
release_if_owner(Key) ->
    Self = self(),
    case registry:whereis_name(Key) of
        Self ->
            _ = registry:unregister_name(Key),
            ok;
        _SomebodyElseOrNobody ->
            ok
    end.
