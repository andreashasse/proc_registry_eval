%% The contract every process registry must fulfil to be evaluated.
%%
%% To add a registry: write a module implementing these callbacks and add
%% one line to adapters/0.  Nothing else in the workbench needs to change.
-module(registry).

-export([names/0, adapters/0, adapter/0]).
-export([setup/1, child_specs/0, on_cluster_ready/1, settings/0, application/0]).
-export([cleanup/0, frees_name_on_exit/0]).
-export([claim/1, discard/2, whereis_name/1, unregister_name/1, renew_lease/2]).

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

%% Does the registry give the name back by itself when the owner dies?
%% locker does not: it holds the key until the lease expires, so a process
%% registered there has to release it on the way out.
-callback frees_name_on_exit() -> boolean().

%% Forget everything this registry is holding, so the next scenario starts
%% from a clean cluster.
-callback cleanup() -> ok.

%% The OTP application the registry lives in, so the report can name the
%% version that was actually evaluated.
-callback application() -> atom().

%% How this registry is configured, for the report. Anything a reader would
%% need to know to make sense of the numbers.
-callback settings() -> [{binary(), binary()}].

%% Make a process own Key, cluster wide. The adapter starts the process
%% itself, because not every registry lets you hand it one that already
%% exists. `pending' means the claim was accepted but who ends up owning
%% the name is decided elsewhere, and later.
-callback claim(key()) -> {ok, pid()} | pending | {error, reason()}.

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
    [global, gproc, syn, horde, group, locker, highlander_pg].

-spec adapters() -> #{atom() => module()}.
adapters() ->
    #{
        global => registry_global,
        gproc => registry_gproc,
        syn => registry_syn,
        horde => registry_horde,
        group => registry_group,
        locker => registry_locker,
        highlander_pg => registry_highlander_pg
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

-spec cleanup() -> ok.
cleanup() -> (adapter()):cleanup().

-spec frees_name_on_exit() -> boolean().
frees_name_on_exit() -> (adapter()):frees_name_on_exit().

-spec claim(key()) -> {ok, pid()} | pending | {error, reason()}.
claim(Key) -> (adapter()):claim(Key).

%% Throw away the process started for a claim that was refused, so a failed
%% claim leaves nothing behind.
-spec discard(pid(), reason()) -> {error, reason()}.
discard(Pid, Reason) ->
    ok = gen_server:stop(Pid),
    {error, Reason}.

-spec whereis_name(key()) -> pid() | undefined.
whereis_name(Key) -> (adapter()):whereis_name(Key).

-spec unregister_name(key()) -> ok | {error, reason()}.
unregister_name(Key) -> (adapter()):unregister_name(Key).

-spec renew_lease(key(), pid()) -> ok | {error, reason()} | not_supported.
renew_lease(Key, Pid) -> (adapter()):renew_lease(Key, Pid).
