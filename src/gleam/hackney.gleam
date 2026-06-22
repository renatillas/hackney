import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response, Response}
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

pub type Error {
  InvalidUtf8Response
  // TODO: refine error type
  Other(dynamic.Dynamic)
}

pub type Http2Stream

pub type Http2Message {
  Http2Response(status: Int, headers: List(http.Header))
  Http2Data(data: BitArray)
  Http2Trailers(headers: List(http.Header))
  Http2Done
}

pub opaque type Http2Options {
  Http2Options(tls: TlsOptions)
}

pub type TlsOptions {
  VerifyPeer
  VerifyPeerWithCertificateAuthorityFile(certificate_authority_file: String)
  VerifyNone
}

@external(erlang, "gleam_hackney_ffi", "send")
fn ffi_send(
  method: String,
  b: String,
  c: List(http.Header),
  d: BytesTree,
) -> Result(Response(BitArray), Error)

@external(erlang, "gleam_hackney_ffi", "h2_open")
fn ffi_h2_open(
  url: String,
  headers: List(http.Header),
  options: Http2Options,
) -> Result(Http2Stream, Error)

@external(erlang, "gleam_hackney_ffi", "h2_send")
fn ffi_h2_send(stream: Http2Stream, data: BitArray) -> Result(Nil, Error)

@external(erlang, "gleam_hackney_ffi", "h2_send_fin")
fn ffi_h2_send_fin(stream: Http2Stream, data: BitArray) -> Result(Nil, Error)

@external(erlang, "gleam_hackney_ffi", "h2_recv")
fn ffi_h2_recv(stream: Http2Stream, timeout: Int) -> Result(Http2Message, Error)

@external(erlang, "gleam_hackney_ffi", "h2_close")
fn ffi_h2_close(stream: Http2Stream) -> Nil

// TODO: test
pub fn send_bits(
  request: Request(BytesTree),
) -> Result(Response(BitArray), Error) {
  let method = http.method_to_string(request.method)
  use response <- result.try(
    request
    |> request.to_uri
    |> uri.to_string
    |> ffi_send(method, _, request.headers, request.body),
  )
  let headers = list.map(response.headers, normalise_header)
  Ok(Response(..response, headers: headers))
}

pub fn send(req: Request(String)) -> Result(Response(String), Error) {
  use resp <- result.try(
    req
    |> request.map(bytes_tree.from_string)
    |> send_bits,
  )

  case bit_array.to_string(resp.body) {
    Ok(body) -> Ok(response.set_body(resp, body))
    Error(_) -> Error(InvalidUtf8Response)
  }
}

pub fn open_http2_stream(
  request: Request(BytesTree),
  options: Http2Options,
) -> Result(Http2Stream, Error) {
  request
  |> request.to_uri
  |> uri.to_string
  |> ffi_h2_open(request.headers, options)
}

pub fn default_http2_options() -> Http2Options {
  Http2Options(tls: VerifyPeer)
}

pub fn verify_peer(_options: Http2Options) -> Http2Options {
  Http2Options(tls: VerifyPeer)
}

pub fn verify_peer_with_certificate_authority_file(
  _options: Http2Options,
  certificate_authority_file: String,
) -> Http2Options {
  Http2Options(tls: VerifyPeerWithCertificateAuthorityFile(
    certificate_authority_file:,
  ))
}

pub fn verify_none(_options: Http2Options) -> Http2Options {
  Http2Options(tls: VerifyNone)
}

pub fn send_http2(stream: Http2Stream, data: BitArray) -> Result(Nil, Error) {
  ffi_h2_send(stream, data)
}

pub fn send_http2_fin(
  stream: Http2Stream,
  data: BitArray,
) -> Result(Nil, Error) {
  ffi_h2_send_fin(stream, data)
}

pub fn receive_http2(
  stream: Http2Stream,
  timeout: Int,
) -> Result(Http2Message, Error) {
  use message <- result.try(ffi_h2_recv(stream, timeout))
  case message {
    Http2Response(status, headers) ->
      Ok(Http2Response(status, list.map(headers, normalise_header)))
    Http2Data(data) -> Ok(Http2Data(data))
    Http2Trailers(headers) ->
      Ok(Http2Trailers(list.map(headers, normalise_header)))
    Http2Done -> Ok(Http2Done)
  }
}

pub fn close_http2(stream: Http2Stream) -> Nil {
  ffi_h2_close(stream)
}

fn normalise_header(header: http.Header) -> http.Header {
  #(string.lowercase(header.0), header.1)
}
