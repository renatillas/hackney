-module(gleam_hackney_ffi).

-export([send/5]).


send(Method, Url, Headers, Body, Options) ->
    NormalizedOptions = normalize_options(Options),
    case hackney:request(Method, Url, Headers, Body, NormalizedOptions) of
        {ok, Status, ResponseHeaders, ResponseBody} -> 
            {ok, {response, Status, ResponseHeaders, ResponseBody}};

        {ok, Status, ResponseHeaders} -> 
            {ok, {response, Status, ResponseHeaders, <<>>}};

        {error, Error} -> 
            {error, {other, Error}}
    end.

normalize_options(Options) ->
    [normalize_option(Elem) || Elem <:- Options].

normalize_option({recv_timeout, {receive_timeout, Timeout}}) ->
    {recv_timeout, Timeout};
normalize_option(Option) ->
    Option.
