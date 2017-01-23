%%%-------------------------------------------------------------------
%%% @doc
%%% Part of a routing chain; does only filtering - uses hooks to check
%%% if the message should be routed at all. This one should be the first
%%% module in chain.
%%% @end
%%%-------------------------------------------------------------------
-module(mongoose_router_global).
-author('bartlomiej.gorny@erlang-solutions.com').

-behaviour(xmpp_router).

-include("ejabberd.hrl").

%% xmpp_router callback
-export([filter/3, route/3]).

filter(From, To, OrigPacket) ->
    Acc = mongoose_acc:from_element(OrigPacket),
    Acc1 = mongoose_acc:put(from, From, Acc),
    Acc2 = mongoose_acc:put(to, To, Acc1),
    Acc3 = mongoose_acc:put(routing_decision, send, Acc2),
    %% Filter globally
    Res = ejabberd_hooks:run_fold(filter_packet, Acc3, []),
    case mongoose_acc:get(routing_decision, Res) of
        send ->
            {From, To, mongoose_acc:get(element, Res)};
        drop ->
            drop
    end.

route(From, To, Packet) ->
    {From, To, Packet}.
