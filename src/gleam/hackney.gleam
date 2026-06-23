import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic.{type Dynamic}
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
  Other(Dynamic)
}

pub type HttpStream

pub type HttpStreamMessage {
  HttpStreamData(data: BitArray)
  HttpStreamDone
}

pub opaque type Configuration {
  Builder(
    // Time in milliseconds for opening a http stream
    connect_timeout: Int,
    // Time in milliseconds for a request to be received
    receive_timeout: Int,
    // Wheter to verify the TLS certificate of the server.
    verify_tls: VerifyTls,
  )
}

pub opaque type VerifyTls {
  TlsVerifyPeer
  TlsVerifyNone
  TlsCaCertificate(file: String)
}

type ErlHttpOption {
  SslOptions(List(ErlSslOption))
  RecvTimeout(Int)
  ConnectTimeout(Int)
}

type ErlSslOption {
  Verify(ErlVerifyOption)
  Cacertfile(String)
}

type ErlVerifyOption {
  VerifyNone
}

@external(erlang, "gleam_hackney_ffi", "send")
fn ffi_send(
  method: String,
  url: String,
  headers: List(http.Header),
  body: BytesTree,
) -> Result(Response(BitArray), Error)

@external(erlang, "gleam_hackney_ffi", "send_with_options")
fn ffi_send_with_options(
  method: String,
  url: String,
  headers: List(http.Header),
  body: BytesTree,
  options: List(ErlHttpOption),
) -> Result(Response(BitArray), Error)

@external(erlang, "gleam_hackney_ffi", "open_stream")
fn ffi_open_stream(
  method: String,
  url: String,
  headers: List(http.Header),
  body: BytesTree,
  options: List(ErlHttpOption),
) -> Result(Response(HttpStream), Error)

@external(erlang, "gleam_hackney_ffi", "stream_receive")
fn ffi_stream_receive(
  stream: HttpStream,
  timeout: Int,
) -> Result(HttpStreamMessage, Error)

@external(erlang, "gleam_hackney_ffi", "stream_close")
fn ffi_stream_close(stream: HttpStream) -> Nil

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

pub fn configure() -> Configuration {
  Builder(
    connect_timeout: 30_000,
    verify_tls: TlsVerifyPeer,
    receive_timeout: 30_000,
  )
}

pub fn connect_timeout(
  config: Configuration,
  connect_timeout: Int,
) -> Configuration {
  Builder(..config, connect_timeout:)
}

pub fn verify_none(config: Configuration) {
  Builder(..config, verify_tls: TlsVerifyNone)
}

pub fn verify_ca_certificate_file(config: Configuration, file: String) {
  Builder(..config, verify_tls: TlsCaCertificate(file:))
}

pub fn dispatch_bits(
  config: Configuration,
  request: Request(BytesTree),
) -> Result(Response(BitArray), Error) {
  let method = http.method_to_string(request.method)
  let erl_http_options = configuration_to_erl_options(config)

  use response <- result.try(
    request
    |> request.to_uri
    |> uri.to_string
    |> ffi_send_with_options(
      method,
      _,
      request.headers,
      request.body,
      erl_http_options,
    ),
  )
  let headers = list.map(response.headers, normalise_header)
  Ok(Response(..response, headers: headers))
}

fn configuration_to_erl_options(config: Configuration) -> List(ErlHttpOption) {
  let Builder(verify_tls:, connect_timeout:, receive_timeout:) = config

  let erl_http_options = [ConnectTimeout(connect_timeout)]

  let erl_http_options = [RecvTimeout(receive_timeout), ..erl_http_options]

  case verify_tls {
    // Default behaviour for hackney is to perform tls verify peer.
    TlsVerifyPeer -> erl_http_options
    TlsVerifyNone -> [SslOptions([Verify(VerifyNone)]), ..erl_http_options]
    TlsCaCertificate(cacertfile) -> [
      SslOptions([Cacertfile(cacertfile)]),
      ..erl_http_options
    ]
  }
}

pub fn dispatch(
  config: Configuration,
  request: Request(String),
) -> Result(Response(String), Error) {
  let request = request.map(request, bytes_tree.from_string)

  use received_response <- result.try(dispatch_bits(config, request))

  case bit_array.to_string(received_response.body) {
    Ok(body) -> Ok(response.set_body(received_response, body))
    Error(_) -> Error(InvalidUtf8Response)
  }
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

pub fn open_stream(
  config: Configuration,
  request: Request(BytesTree),
) -> Result(Response(HttpStream), Error) {
  let method = http.method_to_string(request.method)
  let erl_http_options = configuration_to_erl_options(config)
  use response <- result.map(
    request
    |> request.to_uri
    |> uri.to_string
    |> ffi_open_stream(
      method,
      _,
      request.headers,
      request.body,
      erl_http_options,
    ),
  )
  let headers = list.map(response.headers, normalise_header)
  Response(..response, headers: headers)
}

pub fn receive_stream(
  stream: HttpStream,
  timeout: Int,
) -> Result(HttpStreamMessage, Error) {
  ffi_stream_receive(stream, timeout)
}

pub fn close_stream(stream: HttpStream) -> Nil {
  ffi_stream_close(stream)
}

fn normalise_header(header: http.Header) -> http.Header {
  #(string.lowercase(header.0), header.1)
}
