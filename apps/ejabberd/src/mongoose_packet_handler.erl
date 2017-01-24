%%%----------------------------------------------------------------------
%%% File    : mongoose_packet_handler.erl
%%% Author  : Piotr Nosek <piotr.nosek@erlang-solutions.com>
%%% Purpose : Packet handler behaviour
%%% Created : 24 Jan 2017
%%%----------------------------------------------------------------------

-module(mongoose_packet_handler).
-author('piotr.nosek@erlang-solutions.com').

-include("jlib.hrl").

%%----------------------------------------------------------------------
%% Types
%%----------------------------------------------------------------------

-record(packet_handler, { module, function }).

-type handler_fun() :: fun((From :: jid(), To :: jid(), Packet :: exml:element()) -> any()).
-type t() :: #packet_handler{
                module :: module(),
                function :: atom() | handler_fun()
               }.

-export_type([t/0]).

%%----------------------------------------------------------------------
%% Callback declarations
%%----------------------------------------------------------------------

-callback process(From :: jid(), To :: jid(), Packet :: exml:element()) -> any().

%%----------------------------------------------------------------------
%% API
%%----------------------------------------------------------------------

-export([new/0, new/1, new/2, process/4]).

-spec new() -> t().
new() ->
    Pid = self(),
    Fun = fun(From, To, Packet) ->
                  Pid ! {route, From, To, Packet}
          end,
    new(Fun).

-spec new(Function :: handler_fun()) -> t().
new(Fun) when is_function(Fun, 3) ->
    #packet_handler{ module = undefined, function = Fun }.

-spec new(Module :: module(), Function :: atom()) -> t().
new(Module, Function) when is_atom(Module), is_atom(Function) ->
    #packet_handler{ module = Module, function = Function }.

-spec process(Handler :: t(), From :: jid(), To :: jid(), Packet :: exml:element()) -> any().
process(#packet_handler{ module = undefined, function = Fun }, From, To, Packet) ->
    Fun(From, To, Packet);
process(#packet_handler{ module = Module, function = Function }, From, To, Packet) ->
    Module:Function(From, To, Packet).

