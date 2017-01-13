-module(mod_aws_sns_SUITE).

-compile([export_all]).

-include("jlib.hrl").
-include_lib("exml/include/exml.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(DEFAULT_SNS_CONFIG, [
                             {access_key_id, "AKIAJAZYHOIPY6A2PESA"},
                             {secret_access_key, "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"},
                             {region, "eu-west-1"},
                             {account_id, "251423380551"},
                             {sns_host, "sns.eu-west-1.amazonaws.com"},
                             {plugin_module, mod_aws_sns_defaults},
                             {presence_updates_topic, "user_presence_updated-dev-1"},
                             {pm_messages_topic, "user_message_sent-dev-1"},
                             {muc_messages_topic, "user_messagegroup_sent-dev-1"}
                            ]).

all() ->
    [
     handles_unicode_messages,
     forwards_chat_messages_to_chat_topic,
     forwards_groupchat_messages_to_groupchat_topic,
     does_not_forward_other_messages,
     creates_proper_sns_topic_arn,
     forwards_online_presence_to_presence_topic,
     forwards_offline_presence_to_presence_topic,
     does_not_forward_messages_without_body,
     does_not_forward_messages_when_topic_is_unset,
     does_not_forward_presences_when_topic_is_unset
    ].

%% Tests

handles_unicode_messages(Config) ->
    expect_message_entry(<<"message">>, <<"❤☀☆☂☻♞☯☭☢€"/utf8>>),
    send_packet_callback(Config, <<"chat">>, <<"❤☀☆☂☻♞☯☭☢€"/utf8>>).

forwards_chat_messages_to_chat_topic(Config) ->
    expect_topic("user_message_sent-dev-1"),
    send_packet_callback(Config, <<"chat">>, <<"message">>).

forwards_groupchat_messages_to_groupchat_topic(Config) ->
    expect_topic("user_messagegroup_sent-dev-1"),
    send_packet_callback(Config, <<"groupchat">>, <<"message">>).

does_not_forward_other_messages(Config) ->
    meck:expect(erlcloud_sns, publish, fun(_, _, _, _, _, _) -> ok end),
    send_packet_callback(Config, <<"othertype">>, <<"message">>),
    ?assertNot(meck:called(erlcloud_sns, publish, '_')).

creates_proper_sns_topic_arn(Config) ->
    meck:expect(erlcloud_sns, publish, fun(_, _, _, _, _, _) -> ok end),
    ExpectedTopic = craft_arn("user_message_sent-dev-1"),
    send_packet_callback(Config, <<"chat">>, <<"message">>),
    ?assert(meck:called(erlcloud_sns, publish, [topic, ExpectedTopic, '_', '_', '_', '_'])).

forwards_online_presence_to_presence_topic(Config) ->
    expect_message_entry(<<"present">>, true),
    user_present_callback(Config),
    ExpectedTopic = craft_arn("user_presence_updated-dev-1"),
    ?assert(meck:called(erlcloud_sns, publish, [topic, ExpectedTopic, '_', '_', '_', '_'])).

forwards_offline_presence_to_presence_topic(Config) ->
    expect_message_entry(<<"present">>, false),
    user_not_present_callback(Config),
    ExpectedTopic = craft_arn("user_presence_updated-dev-1"),
    ?assert(meck:called(erlcloud_sns, publish, [topic, ExpectedTopic, '_', '_', '_', '_'])).

does_not_forward_messages_without_body(Config) ->
    meck:expect(erlcloud_sns, publish, fun(_, _, _, _, _, _) -> ok end),
    send_packet_callback(Config, <<"chat">>, undefined),
    ?assertNot(meck:called(erlcloud_sns, publish, '_')).

does_not_forward_messages_when_topic_is_unset(Config) ->
    set_sns_config(#{pm_messages_topic => undefined}),
    meck:expect(erlcloud_sns, publish, fun(_, _, _, _, _, _) -> ok end),
    send_packet_callback(Config, <<"chat">>, <<"message">>),
    ?assertNot(meck:called(erlcloud_sns, publish, '_')).

does_not_forward_presences_when_topic_is_unset(Config) ->
    set_sns_config(#{presence_updates_topic => undefined}),
    meck:expect(erlcloud_sns, publish, fun(_, _, _, _, _, _) -> ok end),
    user_not_present_callback(Config),
    ?assertNot(meck:called(erlcloud_sns, publish, '_')).

%% Fixtures

init_per_suite(Config) ->
    stringprep:start(),
    Config.

init_per_testcase(_, Config) ->
    meck:new([gen_mod, erlcloud_sns], [non_strict]),
    meck:expect(erlcloud_sns, new, fun(_, _, _) -> mod_aws_sns_SUITE_erlcloud_sns_new end),
    set_sns_config(#{}),
    [{sender, jid:from_binary(<<"sender@localhost">>)},
     {recipient, jid:from_binary(<<"recipient@localhost">>)} |
     Config].

end_per_testcase(_, Config) ->
    meck:unload(),
    Config.

%% Wrapped callbacks

send_packet_callback(Config, Type, Body) ->
    Packet = message(Config, Type, Body),
    mod_aws_sns:user_send_packet(
      ?config(sender, Config), ?config(recipient, Config), Packet).

user_present_callback(Config) ->
    mod_aws_sns:user_present(?config(sender, Config)).

user_not_present_callback(Config) ->
    #jid{luser = User, lserver = Host, lresource = Resource} = ?config(sender, Config),
    mod_aws_sns:user_not_present(User, Host, Resource, "mod_aws_sns_SUITE_status").

%% Helpers

craft_arn(Topic) ->
    "arn:aws:sns:eu-west-1:251423380551:" ++ Topic.

expect_topic(ExpectedTopic) ->
    meck:expect(erlcloud_sns, publish,
                fun(topic, Topic, _, _, _, _) -> true = lists:suffix(ExpectedTopic, Topic) end).

expect_message_entry(Key, Value) ->
    meck:expect(
      erlcloud_sns, publish,
      fun(_, _, JSON, _, _, _) ->
              MessageObject = jiffy:decode(unicode:characters_to_binary(JSON), [return_maps]),
              Value = maps:get(Key, MessageObject)
      end).

set_sns_config(Overrides) ->
    meck:expect(gen_mod, get_module_opt,
                fun(_, _, Key, _) ->
                        maps:get(Key, Overrides, proplists:get_value(Key, ?DEFAULT_SNS_CONFIG))
                end).

message(Config, Type, Body) ->
    message(?config(sender, Config), ?config(recipient, Config), Type, Body).

message(From, Recipient, Type, Body) ->
    Children =
        case Body of
            undefined -> [];
            _ -> [#xmlel{name = <<"body">>, children = [#xmlcdata{content = Body}]}]
        end,
    #xmlel{name = <<"message">>,
           attrs = [{<<"from">>, jid:to_binary(From)}, {<<"type">>, Type},
                    {<<"to">>, jid:to_binary(Recipient)}],
           children = Children}.
