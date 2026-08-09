%% Top supervisor of a workbench node.
%%
%% Holds the processes the workbench registers (`workbench_workers') plus
%% whatever long lived processes the registry under test needs.
-module(workbench_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    Flags = #{strategy => one_for_one, intensity => 5, period => 10},
    Children = [workers_spec() | registry:child_specs()],
    {ok, {Flags, Children}}.

-spec workers_spec() -> supervisor:child_spec().
workers_spec() ->
    #{
        id => workbench_workers,
        start => {workbench_workers, start_link, []},
        type => supervisor
    }.
