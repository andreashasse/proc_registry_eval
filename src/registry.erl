%% The contract every process registry must fulfil to be evaluated.
%%
%% To add a registry: write a module implementing these callbacks and add
%% one line to adapters/0.  Nothing else in the workbench needs to change.
-module(registry).

-export([names/0, adapters/0, adapter/0]).
-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([register_name/2, whereis_name/1, unregister_name/1, renew_lease/2]).

-type key() :: workbench:key().
-type reason() :: term().

%% Start the registry on this node.  Called once at boot, with the full
%% cluster already connected.
-callback setup(Peers :: [node()]) -> ok.

%% Long lived processes the registry needs, supervised by workbench_sup.
-callback child_specs() -> [supervisor:child_spec()].

%% Called once after every node has booted, for registries that need to be
%% told the cluster membership explicitly.
-callback on_cluster_ready(Peers :: [node()]) -> ok.

%% The OTP application the registry lives in, so the report can name the
%% version that was actually evaluated.
-callback application() -> atom().

%% How this registry is configured, for the report. Anything a reader would
%% need to know to make sense of the numbers.
-callback settings() -> [{binary(), binary()}].

%% Claim Key for Pid, cluster wide.
-callback register_name(key(), pid()) -> ok | {error, reason()}.

%% This node's answer to "who owns Key?".
-callback whereis_name(key()) -> pid() | undefined.

%% Give up the claim on Key.
-callback unregister_name(key()) -> ok | {error, reason()}.

%% Extend the lease on Key, for registries that expire claims over time.
-callback renew_lease(key(), pid()) -> ok | {error, reason()} | not_supported.

%%%===================================================================
%%% Adapters
%%%===================================================================

%% The registries under evaluation, in report order.
-spec names() -> [atom()].
names() ->
    [global, gproc, syn, locker, locker_replica, locker_master].

-spec adapters() -> #{atom() => module()}.
adapters() ->
    #{
        global => registry_global,
        gproc => registry_gproc,
        syn => registry_syn,
        locker => registry_locker,
        locker_replica => registry_locker_replica,
        locker_master => registry_locker_master
    }.

-spec adapter() -> module().
adapter() ->
    maps:get(workbench:registry(), adapters()).

%%%===================================================================
%%% Dispatch
%%%===================================================================

-spec setup([node()]) -> ok.
setup(Peers) -> (adapter()):setup(Peers).

-spec child_specs() -> [supervisor:child_spec()].
child_specs() -> (adapter()):child_specs().

-spec on_cluster_ready([node()]) -> ok.
on_cluster_ready(Peers) -> (adapter()):on_cluster_ready(Peers).

-spec settings() -> [{binary(), binary()}].
settings() -> (adapter()):settings().

-spec application() -> atom().
application() -> (adapter()):application().

-spec register_name(key(), pid()) -> ok | {error, reason()}.
register_name(Key, Pid) -> (adapter()):register_name(Key, Pid).

-spec whereis_name(key()) -> pid() | undefined.
whereis_name(Key) -> (adapter()):whereis_name(Key).

-spec unregister_name(key()) -> ok | {error, reason()}.
unregister_name(Key) -> (adapter()):unregister_name(Key).

-spec renew_lease(key(), pid()) -> ok | {error, reason()} | not_supported.
renew_lease(Key, Pid) -> (adapter()):renew_lease(Key, Pid).
