%% The things the workbench does to a registry.
%%
%% An action always runs on one cluster node (the controller calls it over
%% rpc) and returns a small printable term that ends up in the report.
%%
%% To add an action: write a module implementing these callbacks and add
%% one line to all/0.
-module(action).

-export([all/0, module/1, run/2]).

-type name() :: start_process | lookup | stop_process | kill_process | renew_lease.
-type result() :: term().

-export_type([name/0, result/0]).

-callback name() -> name().
-callback describe() -> binary().
-callback run(workbench:key()) -> result().

-spec all() -> [module()].
all() ->
    [
        action_start_process,
        action_lookup,
        action_stop_process,
        action_kill_process,
        action_renew_lease
    ].

-spec module(name()) -> module().
module(Name) ->
    [Module] = [M || M <- all(), M:name() =:= Name],
    Module.

%% Run an action on this node.  Called over rpc by the controller.
-spec run(name(), workbench:key()) -> result().
run(Name, Key) ->
    (module(Name)):run(Key).
