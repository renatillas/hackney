-module(gleam_hackney_ffi).

-export([send/4, send_with_options/5]).

send(Method, Url, Headers, Body) ->
    Options = [{with_body, true}],
    send(Method, Url, Headers, Body, Options).

send_with_options(Method, Url, Headers, Body, SendOptions) ->
    Options = [{with_body, true} | send_options(SendOptions)],
    send(Method, Url, Headers, Body, Options).

send(Method, Url, Headers, Body, Options) ->
    case hackney:request(Method, Url, Headers, Body, Options) of
        {ok, Status, ResponseHeaders, ResponseBody} -> 
            {ok, {response, Status, ResponseHeaders, ResponseBody}};

        {ok, Status, ResponseHeaders} -> 
            {ok, {response, Status, ResponseHeaders, <<>>}};

        {error, Error} -> 
            {error, {other, Error}}
    end.

send_options({send_options, default_receive_timeout}) ->
    [];
send_options({send_options, {receive_timeout_ms, Timeout}}) ->
    [{recv_timeout, Timeout}].
