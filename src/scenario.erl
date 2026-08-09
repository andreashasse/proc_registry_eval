%% A scenario is a list of steps, nothing more.
%%
%% Keeping scenarios as data rather than code means a reader can check
%% what was measured without reading the runner, and adding a scenario is
%% a new module plus one line in all/0.
%%
%% Steps:
%%   {note, Text}          free text, ends up in the report
%%   {do, Node, Action, Key}   run an action on one node
%%   {do_all, Action, Key}     run an action on every node and compare
%%   {cut, A, B}           A and B stop hearing from each other
%%   {cut_one_way, A, B}   A stops hearing from B, B still hears A
%%   {isolate, Node}       Node is cut from every other node
%%   heal                  remove all cuts and reconnect
%%   settle                wait SETTLE_MS for the registry to react
%%   {wait, Ms}            wait a specific time
%%   {lease_ms, Ms}        change the lease length used from here on
%%
%% Use a key that is unique to the scenario, so scenarios cannot affect
%% each other through a registry that kept an old entry.
-module(scenario).

-export([all/0]).

-type step() ::
    {note, binary()}
    | {do, workbench:node_id(), action:name(), workbench:key()}
    | {do_all, action:name(), workbench:key()}
    | {cut, workbench:node_id(), workbench:node_id()}
    | {cut_one_way, workbench:node_id(), workbench:node_id()}
    | {isolate, workbench:node_id()}
    | heal
    | settle
    | {wait, pos_integer()}
    | {lease_ms, pos_integer()}.

-export_type([step/0]).

-callback name() -> binary().
-callback description() -> binary().
-callback steps() -> [step()].

-spec all() -> [module()].
all() ->
    [
        scenario_baseline,
        scenario_process_death,
        scenario_lease_expiry,
        scenario_symmetric_split,
        scenario_owner_isolated,
        scenario_one_sided_split,
        scenario_full_split
    ].
