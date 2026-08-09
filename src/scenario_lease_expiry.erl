-module(scenario_lease_expiry).
-behaviour(scenario).

-export([name/0, description/0, steps/0]).

-define(KEY, <<"lease_expiry/service">>).
-define(LEASE_MS, 3000).

-spec name() -> binary().
name() -> <<"lease expiry">>.

-spec description() -> binary().
description() ->
    <<
        "The lease is shortened to 3s and then nobody renews it. Registries "
        "without leases keep the name forever; a lease based registry drops "
        "it and lets another node take over."
    >>.

-spec steps() -> [scenario:step()].
steps() ->
    [
        {lease_ms, ?LEASE_MS},
        {do, n1, start_process, ?KEY},
        {do_all, lookup, ?KEY},
        {do, n1, renew_lease, ?KEY},
        {note, <<"Wait past the lease without renewing.">>},
        {wait, 6000},
        {do_all, lookup, ?KEY},
        {note, <<"Another node tries to take the name over.">>},
        {do, n2, start_process, ?KEY},
        {do_all, lookup, ?KEY}
    ].
