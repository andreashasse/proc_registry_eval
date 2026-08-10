%% Exercises the via shim against a real locker, on one node with a quorum
%% of one. No cluster and no docker needed.
-module(locker_via_tests).

-include_lib("eunit/include/eunit.hrl").

-define(KEY, <<"locker_via_tests/service">>).

via_test_() ->
    {setup, fun start_locker/0, fun stop_locker/1, [
        fun a_name_can_be_taken_and_given_back/0,
        fun a_taken_name_is_refused/0,
        fun an_unknown_name_is_not_found/0,
        fun send_reaches_the_owner/0,
        fun send_to_an_unknown_name_exits/0,
        fun gen_server_can_be_started_under_a_via_name/0,
        fun an_owner_gives_the_name_back_when_it_stops/0,
        fun a_process_does_not_release_a_name_it_does_not_own/0
    ]}.

%% locker keeps a key until the lease expires, so the owner releases it on
%% the way out. See workbench_worker:terminate/2.
an_owner_gives_the_name_back_when_it_stops() ->
    {ok, Pid} = gen_server:start(workbench_worker, ?KEY, []),
    yes = locker_via:register_name(?KEY, Pid),
    ?assertEqual(Pid, locker_via:whereis_name(?KEY)),
    ok = gen_server:stop(Pid),
    ?assertEqual(undefined, locker_via:whereis_name(?KEY)).

a_process_does_not_release_a_name_it_does_not_own() ->
    Owner = spawn_idle(),
    yes = locker_via:register_name(?KEY, Owner),
    {ok, Loser} = gen_server:start(workbench_worker, ?KEY, []),
    ok = gen_server:stop(Loser),
    ?assertEqual(Owner, locker_via:whereis_name(?KEY)),
    ok = locker_via:unregister_name(?KEY).

a_name_can_be_taken_and_given_back() ->
    Pid = spawn_idle(),
    ?assertEqual(yes, locker_via:register_name(?KEY, Pid)),
    ?assertEqual(Pid, locker_via:whereis_name(?KEY)),
    ?assertEqual(ok, locker_via:unregister_name(?KEY)),
    ?assertEqual(undefined, locker_via:whereis_name(?KEY)).

a_taken_name_is_refused() ->
    First = spawn_idle(),
    Second = spawn_idle(),
    ?assertEqual(yes, locker_via:register_name(?KEY, First)),
    ?assertEqual(no, locker_via:register_name(?KEY, Second)),
    ?assertEqual(First, locker_via:whereis_name(?KEY)),
    ok = locker_via:unregister_name(?KEY).

an_unknown_name_is_not_found() ->
    ?assertEqual(undefined, locker_via:whereis_name(<<"locker_via_tests/nobody">>)).

send_reaches_the_owner() ->
    Self = self(),
    Pid = spawn(fun() ->
        receive
            Message -> Self ! {got, Message}
        end
    end),
    yes = locker_via:register_name(?KEY, Pid),
    ?assertEqual(Pid, locker_via:send(?KEY, hello)),
    ?assertEqual(
        {got, hello},
        receive
            Got -> Got
        after 1000 -> timeout
        end
    ),
    ok = locker_via:unregister_name(?KEY).

send_to_an_unknown_name_exits() ->
    ?assertExit({badarg, _}, locker_via:send(<<"locker_via_tests/nobody">>, hello)).

%% The point of the shim: OTP behaviours can use locker as a name registry.
gen_server_can_be_started_under_a_via_name() ->
    Name = {via, locker_via, ?KEY},
    {ok, Pid} = gen_server:start(Name, workbench_worker, ?KEY, []),
    ?assertEqual(Pid, locker_via:whereis_name(?KEY)),
    ?assertEqual(?KEY, gen_server:call(Name, key)),
    ?assertMatch(
        {error, {already_started, Pid}},
        gen_server:start(Name, workbench_worker, ?KEY, [])
    ),
    ok = gen_server:stop(Pid),
    ok = locker_via:unregister_name(?KEY).

%%%===================================================================
%%% A one node locker
%%%===================================================================

start_locker() ->
    true = os:putenv("PEERS", hostname()),
    true = os:putenv("REGISTRY", "locker"),
    {ok, Pid} = locker:start_link(1),
    ok = locker:set_nodes([node()], [node()], []),
    Pid.

stop_locker(Pid) ->
    unlink(Pid),
    exit(Pid, shutdown),
    os:unsetenv("PEERS"),
    os:unsetenv("REGISTRY").

%% locker needs a real node name; eunit runs on a node called nonode@nohost
%% unless the suite is started distributed, and PEERS has to agree with it.
hostname() ->
    [_Name, Host] = string:split(atom_to_list(node()), "@"),
    Host.

spawn_idle() ->
    spawn(fun() ->
        receive
            stop -> ok
        end
    end).
