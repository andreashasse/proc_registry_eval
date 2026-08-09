%% Renders the raw run data into results/RESULTS.md.
%%
%% Pure formatting: it reads the files written by the runner and writes
%% markdown, so a report can be regenerated without touching the cluster.
-module(report).

-export([main/0, render/1]).

-type run() :: results:run().
-type scenario_result() :: map().
-type outcome() :: map().
-type cell() :: unicode:chardata().

%%%===================================================================
%%% Entry point
%%%===================================================================

-spec main() -> no_return().
main() ->
    try
        Runs = results:read_all(),
        [] =:= Runs andalso error(no_results),
        File = filename:join(results:dir(), "RESULTS.md"),
        ok = file:write_file(File, render(Runs)),
        io:format("wrote ~s (~p registries)~n", [File, length(Runs)]),
        halt(0)
    catch
        Class:Reason:Stack ->
            io:format("report failed: ~p~n", [{Class, Reason, Stack}]),
            halt(1)
    end.

-spec render([run()]) -> unicode:chardata().
render(Runs) ->
    [
        heading(1, <<"Distributed process registry evaluation">>),
        intro(Runs),
        environment_section(Runs),
        summary_section(Runs),
        observations_section(Runs),
        actions_section(),
        details_section(Runs)
    ].

%%%===================================================================
%%% Sections
%%%===================================================================

-spec intro([run()]) -> unicode:chardata().
intro(Runs) ->
    [
        para([
            <<"A three node Erlang cluster in docker. The network between the ">>,
            <<"nodes is cut and healed with iptables while a fixed list of ">>,
            <<"actions is run against each registry, and every answer every ">>,
            <<"node gives is written down.">>
        ]),
        para([
            <<"Registries in this run: ">>,
            join([registry_name(Run) || Run <- Runs], <<", ">>),
            <<". Produced by `./run.sh`; nothing in this file is written by hand.">>
        ])
    ].

-spec environment_section([run()]) -> unicode:chardata().
environment_section(Runs) ->
    [
        heading(2, <<"Environment">>),
        table(header(<<"Setting">>, Runs), environment_rows(Runs))
    ].

-spec environment_rows([run()]) -> [[cell()]].
environment_rows(Runs) ->
    Settings = unique([Setting || Run <- Runs, {Setting, _Value} <- environment(Run)]),
    Started = [<<"run started">> | [fmt:text(maps:get(started_at, Run)) || Run <- Runs]],
    [
        Started
        | [
            [Setting | [environment_value(Run, Setting) || Run <- Runs]]
         || Setting <- Settings
        ]
    ].

-spec environment_value(run(), binary()) -> cell().
environment_value(Run, Setting) ->
    case lists:keyfind(Setting, 1, environment(Run)) of
        {_Setting, Value} -> fmt:text(Value);
        false -> <<"-">>
    end.

-spec summary_section([run()]) -> unicode:chardata().
summary_section(Runs) ->
    [
        heading(2, <<"Summary">>),
        para([
            <<"Every `lookup on all nodes` step asks all three nodes who owns ">>,
            <<"the name and compares the answers. `agree n/m` counts how many ">>,
            <<"of those checks got the same answer from every node. `owners` is ">>,
            <<"the highest number of different owners seen at the same time, so ">>,
            <<"more than one means the cluster had a split brain. `refused` ">>,
            <<"counts the actions the registry answered `{error, Reason}` to, ">>,
            <<"such as a second claim on a name that is already owned; ">>,
            <<"`timed out` counts the ones it did not answer at all.">>
        ]),
        table(header(<<"Scenario">>, Runs), summary_rows(Runs))
    ].

-spec summary_rows([run()]) -> [[cell()]].
summary_rows(Runs) ->
    [
        [scenario_name(Module) | [summary_cell(Run, Module) || Run <- Runs]]
     || Module <- scenario:all()
    ].

-spec summary_cell(run(), module()) -> cell().
summary_cell(Run, Module) ->
    case find_scenario(Run, Module) of
        false ->
            <<"-">>;
        Scenario ->
            Checks = [Outcome || Outcome <- log(Scenario), kind(Outcome) =:= action_all],
            Agreed = length([O || O <- Checks, maps:get(agreement, O) =:= agree]),
            Owners = lists:max([1 | [owner_count(O) || O <- Checks]]),
            Results = results_of(Scenario),
            Refused = count(Results, fun is_refusal/1),
            Timeouts = count(Results, fun is_timeout/1),
            join(
                [
                    fmt:format("agree ~p/~p", [Agreed, length(Checks)]),
                    fmt:format("~p owner~s", [Owners, plural(Owners)])
                ] ++
                    [fmt:format("~p refused", [Refused]) || Refused > 0] ++
                    [fmt:format("~p timed out", [Timeouts]) || Timeouts > 0],
                <<", ">>
            )
    end.

-spec observations_section([run()]) -> unicode:chardata().
observations_section(Runs) ->
    [
        heading(2, <<"Observations">>),
        table(
            header(<<"Question">>, Runs),
            [
                [
                    <<"Are leases supported?">>
                    | [yes_no(supports_leases(Run)) || Run <- Runs]
                ],
                [
                    <<"Slowest single action">>
                    | [fmt:format("~pms", [slowest_action(Run)]) || Run <- Runs]
                ],
                [
                    <<"Claims the registry refused">>
                    | [fmt:text(count(all_results(Run), fun is_refusal/1)) || Run <- Runs]
                ],
                [
                    <<"Actions that timed out or crashed">>
                    | [fmt:text(count(all_results(Run), fun is_timeout/1)) || Run <- Runs]
                ],
                [
                    <<"Checks where the nodes disagreed">>
                    | [fmt:text(total_disagreements(Run)) || Run <- Runs]
                ],
                [
                    <<"Highest number of owners at the same time">>
                    | [fmt:text(most_owners(Run)) || Run <- Runs]
                ]
            ]
        )
    ].

-spec actions_section() -> unicode:chardata().
actions_section() ->
    [
        heading(2, <<"Actions">>),
        table(
            [<<"Action">>, <<"What it does">>],
            [
                [[<<"`">>, fmt:text(Module:name()), <<"`">>], Module:describe()]
             || Module <- action:all()
            ]
        )
    ].

-spec details_section([run()]) -> unicode:chardata().
details_section(Runs) ->
    [heading(2, <<"Details">>), [registry_details(Run) || Run <- Runs]].

-spec registry_details(run()) -> unicode:chardata().
registry_details(Run) ->
    NodeIds = node_ids(Run),
    [
        heading(3, registry_name(Run)),
        [scenario_details(Scenario, NodeIds) || Scenario <- scenarios(Run)]
    ].

-spec scenario_details(scenario_result(), [workbench:node_id()]) -> unicode:chardata().
scenario_details(Scenario, NodeIds) ->
    [
        heading(4, fmt:text(maps:get(name, Scenario))),
        para([fmt:text(maps:get(description, Scenario))]),
        table(
            [<<"#">>, <<"Step">> | [fmt:text(NodeId) || NodeId <- NodeIds]],
            [
                [
                    integer_to_binary(Number),
                    step_label(Outcome)
                    | node_cells(Outcome, NodeIds)
                ]
             || {Number, Outcome} <- lists:enumerate(log(Scenario))
            ]
        )
    ].

%%%===================================================================
%%% Step rendering
%%%===================================================================

-spec step_label(outcome()) -> cell().
step_label(#{kind := note, text := Text}) ->
    [<<"_">>, fmt:text(Text), <<"_">>];
step_label(#{kind := action, node := NodeId, action := Action, key := Key}) ->
    [
        <<"`">>,
        fmt:text(Action),
        <<"` on ">>,
        fmt:text(NodeId),
        <<" (">>,
        fmt:text(Key),
        <<")">>
    ];
step_label(#{kind := action_all, action := Action, key := Key, agreement := Agreement}) ->
    [
        <<"`">>,
        fmt:text(Action),
        <<"` on all nodes (">>,
        fmt:text(Key),
        <<") - **">>,
        fmt:text(Agreement),
        <<"**">>
    ];
step_label(#{kind := network, detail := Detail}) ->
    network_label(Detail);
step_label(#{kind := wait, ms := Ms, reason := settle}) ->
    [<<"wait ">>, fmt:text(Ms), <<"ms for the registry to react">>];
step_label(#{kind := wait, ms := Ms}) ->
    [<<"wait ">>, fmt:text(Ms), <<"ms">>];
step_label(#{kind := config, setting := Setting, value := Value}) ->
    [<<"set ">>, fmt:text(Setting), <<" to ">>, fmt:text(Value)].

-spec network_label(term()) -> cell().
network_label({cut, A, B}) ->
    [<<"**cut ">>, fmt:text(A), <<" <-> ">>, fmt:text(B), <<"**">>];
network_label({cut_one_way, A, B}) ->
    [
        <<"**cut ">>,
        fmt:text(A),
        <<" <- ">>,
        fmt:text(B),
        <<"** (one sided: ">>,
        fmt:text(B),
        <<" still hears ">>,
        fmt:text(A),
        <<")">>
    ];
network_label({isolate, NodeId}) ->
    [<<"**isolate ">>, fmt:text(NodeId), <<"**">>];
network_label(heal) ->
    <<"**heal the network**">>.

-spec node_cells(outcome(), [workbench:node_id()]) -> [cell()].
node_cells(#{kind := action, node := NodeId, result := Result, ms := Ms}, NodeIds) ->
    [
        case Id of
            NodeId -> format_result(Result, Ms);
            _Other -> <<>>
        end
     || Id <- NodeIds
    ];
node_cells(#{kind := action_all, results := Results}, NodeIds) ->
    [
        case lists:keyfind(Id, 1, Results) of
            {_NodeId, Result, Ms} -> format_result(Result, Ms);
            false -> <<>>
        end
     || Id <- NodeIds
    ];
node_cells(_Outcome, NodeIds) ->
    [<<>> || _NodeId <- NodeIds].

-spec format_result(term(), non_neg_integer()) -> cell().
format_result(Result, Ms) when Ms >= 100 ->
    [format_result(Result), <<" _(">>, fmt:text(Ms), <<"ms)_">>];
format_result(Result, _Ms) ->
    format_result(Result).

-spec format_result(term()) -> cell().
format_result({started, Ref}) -> [<<"started ">>, owner(Ref)];
format_result({found, Ref}) -> owner(Ref);
format_result({error, Reason}) -> [<<"error: `">>, fmt:text(Reason), <<"`">>];
format_result({rpc_error, Reason}) -> [<<"rpc error: `">>, fmt:text(Reason), <<"`">>];
format_result(Other) -> [<<"`">>, fmt:text(Other), <<"`">>].

-spec owner(term()) -> cell().
owner(#{node := Node, id := Id}) ->
    [<<"`">>, short_node(Node), <<"/">>, fmt:text(Id), <<"`">>];
owner(Other) ->
    fmt:text(Other).

-spec short_node(term()) -> binary().
short_node(Node) ->
    case string:split(fmt:text(Node), <<"@">>) of
        [_Name, Host] -> fmt:binary(Host);
        [Whole] -> fmt:binary(Whole)
    end.

%%%===================================================================
%%% Derived numbers
%%%===================================================================

-spec registry_name(run()) -> binary().
registry_name(Run) -> fmt:text(maps:get(registry, Run)).

-spec scenarios(run()) -> [scenario_result()].
scenarios(Run) -> maps:get(scenarios, Run).

-spec environment(run()) -> [{binary(), binary()}].
environment(Run) -> maps:get(environment, Run).

-spec log(scenario_result()) -> [outcome()].
log(Scenario) -> maps:get(log, Scenario).

-spec kind(outcome()) -> atom().
kind(Outcome) -> maps:get(kind, Outcome).

-spec find_scenario(run(), module()) -> scenario_result() | false.
find_scenario(Run, Module) ->
    case [S || S <- scenarios(Run), maps:get(module, S) =:= Module] of
        [Scenario | _Rest] -> Scenario;
        [] -> false
    end.

-spec scenario_name(module()) -> binary().
scenario_name(Module) -> fmt:text(Module:name()).

%% The columns the detail tables need, taken from the data itself.
-spec node_ids(run()) -> [workbench:node_id()].
node_ids(Run) ->
    unique([
        NodeId
     || Scenario <- scenarios(Run),
        #{kind := action_all, results := Results} <- log(Scenario),
        {NodeId, _Result, _Ms} <- Results
    ]).

%% How many different owners the cluster reported at the same time.
-spec owner_count(outcome()) -> non_neg_integer().
owner_count(#{results := Results}) ->
    length(lists:usort([Ref || {_NodeId, {found, Ref}, _Ms} <- Results])).

-spec results_of(scenario_result()) -> [term()].
results_of(Scenario) ->
    [Result || {Result, _Ms} <- timed_results(Scenario)].

-spec timed_results(scenario_result()) -> [{term(), non_neg_integer()}].
timed_results(Scenario) ->
    lists:append([outcome_results(Outcome) || Outcome <- log(Scenario)]).

-spec outcome_results(outcome()) -> [{term(), non_neg_integer()}].
outcome_results(#{kind := action, result := Result, ms := Ms}) ->
    [{Result, Ms}];
outcome_results(#{kind := action_all, results := Results}) ->
    [{Result, Ms} || {_NodeId, Result, Ms} <- Results];
outcome_results(_Outcome) ->
    [].

%% The registry said no: a legitimate answer, not a malfunction.
-spec is_refusal(term()) -> boolean().
is_refusal({error, _Reason}) -> true;
is_refusal(_Other) -> false.

%% The registry did not answer within the action timeout, or blew up.
-spec is_timeout(term()) -> boolean().
is_timeout(timeout) -> true;
is_timeout({rpc_error, _Reason}) -> true;
is_timeout(_Other) -> false.

-spec count([term()], fun((term()) -> boolean())) -> non_neg_integer().
count(Results, Predicate) ->
    length(lists:filter(Predicate, Results)).

-spec supports_leases(run()) -> boolean().
supports_leases(Run) ->
    lists:member(renewed, all_results(Run)).

-spec slowest_action(run()) -> non_neg_integer().
slowest_action(Run) ->
    lists:max([0 | [Ms || {_Result, Ms} <- all_timed_results(Run)]]).

-spec total_disagreements(run()) -> non_neg_integer().
total_disagreements(Run) ->
    length([
        Outcome
     || Scenario <- scenarios(Run),
        Outcome <- log(Scenario),
        kind(Outcome) =:= action_all,
        maps:get(agreement, Outcome) =:= disagree
    ]).

-spec most_owners(run()) -> non_neg_integer().
most_owners(Run) ->
    lists:max([
        0
        | [
            owner_count(Outcome)
         || Scenario <- scenarios(Run),
            Outcome <- log(Scenario),
            kind(Outcome) =:= action_all
        ]
    ]).

-spec all_results(run()) -> [term()].
all_results(Run) ->
    [Result || {Result, _Ms} <- all_timed_results(Run)].

-spec all_timed_results(run()) -> [{term(), non_neg_integer()}].
all_timed_results(Run) ->
    lists:append([timed_results(Scenario) || Scenario <- scenarios(Run)]).

%%%===================================================================
%%% Markdown
%%%===================================================================

-spec heading(pos_integer(), binary()) -> unicode:chardata().
heading(Level, Text) ->
    [lists:duplicate(Level, $#), <<" ">>, Text, <<"\n\n">>].

-spec para([unicode:chardata()]) -> unicode:chardata().
para(Parts) ->
    [Parts, <<"\n\n">>].

-spec header(binary(), [run()]) -> [cell()].
header(First, Runs) ->
    [First | [registry_name(Run) || Run <- Runs]].

-spec table([cell()], [[cell()]]) -> unicode:chardata().
table(Header, Rows) ->
    [
        row(Header),
        row([<<"---">> || _Cell <- Header]),
        [row(Cells) || Cells <- Rows],
        <<"\n">>
    ].

-spec row([cell()]) -> unicode:chardata().
row(Cells) ->
    [<<"| ">>, join([escape(Cell) || Cell <- Cells], <<" | ">>), <<" |\n">>].

-spec escape(cell()) -> binary().
escape(Cell) ->
    binary:replace(fmt:binary(Cell), <<"|">>, <<"\\|">>, [global]).

-spec join([unicode:chardata()], binary()) -> [unicode:chardata()].
join([], _Separator) -> [];
join([Last], _Separator) -> [Last];
join([Head | Tail], Separator) -> [Head, Separator | join(Tail, Separator)].

-spec unique([T]) -> [T].
unique(List) ->
    lists:foldr(fun(Item, Acc) -> [Item | lists:delete(Item, Acc)] end, [], List).

-spec yes_no(boolean()) -> binary().
yes_no(true) -> <<"yes">>;
yes_no(false) -> <<"no">>.

-spec plural(non_neg_integer()) -> binary().
plural(1) -> <<"">>;
plural(_Other) -> <<"s">>.
