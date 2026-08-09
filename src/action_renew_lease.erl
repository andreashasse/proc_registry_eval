%% Extend the claim on a name.
%%
%% Only meaningful for registries that expire claims; the others answer
%% `not_supported', which is itself a result worth recording.
-module(action_renew_lease).
-behaviour(action).

-export([name/0, describe/0, run/1]).

-spec name() -> action:name().
name() -> renew_lease.

-spec describe() -> binary().
describe() -> <<"renew the lease on the name">>.

-spec run(workbench:key()) -> renewed | not_found | not_supported | {error, term()}.
run(Key) ->
    case registry:whereis_name(Key) of
        undefined ->
            not_found;
        Pid ->
            case registry:renew_lease(Key, Pid) of
                ok -> renewed;
                not_supported -> not_supported;
                {error, Error} -> {error, Error}
            end
    end.
