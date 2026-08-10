%% Supervisor for processes that compete for a name rather than hold it.
%%
%% HighlanderPG works this way: you start a contender, and Postgres decides
%% later whether it becomes the owner. Unlike workbench_workers this is a
%% plain one_for_one, because each contender needs its own child spec.
-module(workbench_contenders).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_contender/1, stop_contender/1, stop_all/0]).

-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), []}}.
init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 0, period => 1}, []}}.

-spec start_contender(supervisor:child_spec()) -> {ok, pid()} | {error, term()}.
start_contender(ChildSpec) ->
    case supervisor:start_child(?MODULE, ChildSpec) of
        {ok, Pid} when is_pid(Pid) -> {ok, Pid};
        {error, Reason} -> {error, Reason}
    end.

-spec stop_contender(term()) -> ok | {error, not_found}.
stop_contender(Id) ->
    case supervisor:terminate_child(?MODULE, Id) of
        ok ->
            %% Temporary children are dropped from the child list as soon
            %% as they terminate, so this is expected to say not_found.
            _ = supervisor:delete_child(?MODULE, Id),
            ok;
        {error, not_found} ->
            {error, not_found}
    end.

-spec stop_all() -> ok.
stop_all() ->
    _ = [
        stop_contender(Id)
     || {Id, _Pid, _Type, _Modules} <- supervisor:which_children(?MODULE)
    ],
    ok.
