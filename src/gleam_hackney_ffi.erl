-module(gleam_hackney_ffi).

-export([send/4, h2_open/3, h2_send/2, h2_send_fin/2, h2_recv/2, h2_close/1]).

send(Method, Url, Headers, Body) ->
    Options = [{with_body, true}],
    case hackney:request(Method, Url, Headers, Body, Options) of
        {ok, Status, ResponseHeaders, ResponseBody} -> 
            {ok, {response, Status, ResponseHeaders, ResponseBody}};

        {ok, Status, ResponseHeaders} -> 
            {ok, {response, Status, ResponseHeaders, <<>>}};

        {error, Error} -> 
            {error, {other, Error}}
    end.

h2_open(Url, Headers, Http2Options) ->
    Options = [{protocols, [http2]} | tls_options(Http2Options)],
    case hackney:h2_open(Url, Headers, Options) of
        {ok, Stream} -> {ok, Stream};
        {error, Error} -> {error, {other, Error}}
    end.

tls_options({http2_options, verify_peer}) ->
    [];
tls_options({http2_options, {verify_peer_with_certificate_authority_file, CertificateAuthorityFile}}) ->
    [{ssl_options, [
        {cacertfile, unicode:characters_to_list(CertificateAuthorityFile)},
        {verify, verify_peer}
    ]}];
tls_options({http2_options, verify_none}) ->
    [{ssl_options, [{verify, verify_none}]}].

h2_send(Stream, Data) ->
    case hackney:h2_send(Stream, Data) of
        ok -> {ok, nil};
        {error, Error} -> {error, {other, Error}}
    end.

h2_send_fin(Stream, Data) ->
    case hackney:h2_send(Stream, Data, fin) of
        ok -> {ok, nil};
        {error, Error} -> {error, {other, Error}}
    end.

h2_recv(Stream, Timeout) ->
    case hackney:h2_recv(Stream, Timeout) of
        {ok, {response, Status, Headers}} ->
            {ok, {http2_response, Status, Headers}};
        {ok, {data, Data}} ->
            {ok, {http2_data, Data}};
        {ok, {trailers, Headers}} ->
            {ok, {http2_trailers, Headers}};
        {ok, done} ->
            {ok, http2_done};
        {error, Error} ->
            {error, {other, Error}}
    end.

h2_close(Stream) ->
    ok = hackney:h2_close(Stream),
    nil.

