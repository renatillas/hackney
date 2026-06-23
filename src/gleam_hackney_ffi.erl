-module(gleam_hackney_ffi).

-export([
    send/4,
    send_with_options/5,
    open_stream/5,
    stream_receive/2,
    stream_close/1
]).

send(Method, Url, Headers, Body) ->
    Options = [],
    send_with_options(Method, Url, Headers, Body, Options).

send_with_options(Method, Url, Headers, Body, Options) ->
    case hackney:request(Method, Url, Headers, Body, Options) of
        {ok, Status, ResponseHeaders, ResponseBody} -> 
            response(Status, ResponseHeaders, ResponseBody);

        {ok, Status, ResponseHeaders} -> 
            response(Status, ResponseHeaders, <<>>);

        {error, Error} -> 
            hackney_error(Error)
    end.

open_stream(Method, Url, Headers, Body, Options) ->
    case hackney:request(Method, Url, Headers, stream, Options) of
        {ok, Status, ResponseHeaders, Stream} ->
            response(Status, ResponseHeaders, Stream);
        {ok, Stream} ->
            send_stream_body(Stream, Body);
        {error, Error} -> hackney_error(Error)
    end.

send_stream_body(Stream, Body) ->
    case hackney:send_body(Stream, Body) of
        ok -> finish_stream_body(Stream);
        {error, Error} -> hackney_error(Error)
    end.

finish_stream_body(Stream) ->
    case hackney:finish_send_body(Stream) of
        ok -> start_stream_response(Stream);
        {error, Error} -> hackney_error(Error)
    end.

start_stream_response(Stream) ->
    case hackney:start_response(Stream) of
        {ok, Status, ResponseHeaders, ResponseStream} ->
            response(Status, ResponseHeaders, ResponseStream);
        {error, Error} -> hackney_error(Error)
    end.

stream_receive(Stream, Timeout) ->
    _ = Timeout,
    case hackney:stream_body(Stream) of
        {ok, Data} -> {ok, {http_stream_data, Data}};
        done -> {ok, http_stream_done};
        {error, Error} -> hackney_error(Error)
    end.

response(Status, Headers, Body) ->
    {ok, {response, Status, Headers, Body}}.

hackney_error(Error) ->
    {error, {other, Error}}.

stream_close(Stream) ->
    ok = hackney:close(Stream),
    nil.
