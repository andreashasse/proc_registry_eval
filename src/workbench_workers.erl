%% Supervisor of the processes that get registered.
%%
%% Children are `temporary': stopping a worker means it stays stopped,
%% which is what the workbench measures.
-module(workbench_workers).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_worker/1, stop_all/0]).

-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    Flags = #{strategy => simple_one_for_one, intensity => 0, period => 1},
    Child = #{
        id => workbench_worker,
        start => {workbench_worker, start_link, []},
        restart => temporary,
        shutdown => brutal_kill
    },
    {ok, {Flags, [Child]}}.

-spec start_worker(workbench:key()) -> {ok, pid()}.
start_worker(Key) ->
    case supervisor:start_child(?MODULE, [Key]) of
        {ok, Pid} when is_pid(Pid) -> {ok, Pid}
    end.

%% Remove every worker on this node, used to reset between scenarios.
-spec stop_all() -> ok.
stop_all() ->
    _ = [
        supervisor:terminate_child(?MODULE, Pid)
     || {_Id, Pid, _Type, _Modules} <- supervisor:which_children(?MODULE), is_pid(Pid)
    ],
    ok.
