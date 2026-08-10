%% Cuts the network between cluster nodes with iptables.
%%
%% This runs inside the node's own container, so a cut only ever affects
%% the two nodes involved.  The controller is a hidden node on the same
%% docker network with a different address and is never blocked, which is
%% what makes it possible to ask an isolated node what it thinks.
%%
%% Blocking is done on INPUT only: `netcut:block(N, Peer)' means "N stops
%% hearing from Peer".  Calling it on both sides gives a symmetric split,
%% calling it on one side gives a one sided split.
-module(netcut).

-export([block/1, unblock_all/0]).

%% A target is either another cluster node or a plain hostname, which is
%% how a node is cut off from Postgres.
-spec block(node() | string()) -> ok | {error, term()}.
block(Target) ->
    case address_of(Target) of
        {ok, Address} ->
            sh("iptables -I INPUT 1 -s " ++ Address ++ " -j DROP");
        {error, Reason} ->
            {error, Reason}
    end.

-spec unblock_all() -> ok | {error, term()}.
unblock_all() ->
    sh("iptables -F INPUT").

%% The IP address of the container running Peer, via docker's DNS.
-spec address_of(node() | string()) -> {ok, string()} | {error, term()}.
address_of(Target) ->
    Host = hostname_of(Target),
    case inet:getaddr(Host, inet) of
        {ok, Address} ->
            case inet:ntoa(Address) of
                Text when is_list(Text) -> {ok, Text};
                {error, Reason} -> {error, {cannot_print, Address, Reason}}
            end;
        {error, Reason} ->
            {error, {cannot_resolve, Host, Reason}}
    end.

-spec hostname_of(node() | string()) -> string().
hostname_of(Node) when is_atom(Node) ->
    [_Name, Host] = string:split(atom_to_list(Node), "@"),
    Host;
hostname_of(Host) when is_list(Host) ->
    Host.

-spec sh(string()) -> ok | {error, term()}.
sh(Command) ->
    case os:cmd(Command ++ " 2>&1; printf 'rc=%d' $?") of
        "rc=0" -> ok;
        Output -> {error, {Command, Output}}
    end.
