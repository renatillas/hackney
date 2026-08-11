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

@external(erlang, "gleam_hackney_ffi", "send")
fn ffi_send(
  method: String,
  b: String,
  c: List(http.Header),
  d: BytesTree,
  options: List(ErlHttpOption),
) -> Result(Response(BitArray), Error)

// TODO: test
pub fn send_bits(
  request: Request(BytesTree),
) -> Result(Response(BitArray), Error) {
  let method = http.method_to_string(request.method)
  use response <- result.try(
    request
    |> request.to_uri
    |> uri.to_string
    |> ffi_send(method, _, request.headers, request.body, []),
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

fn normalise_header(header: http.Header) -> http.Header {
  #(string.lowercase(header.0), header.1)
}

pub opaque type Configuration {
  Builder(receive_timeout: ReceiveTimeout)
}

type ReceiveTimeout {
  Infinity
  ReceiveTimeout(Int)
}

type ErlHttpOption {
  RecvTimeout(ReceiveTimeout)
}

pub fn configure() -> Configuration {
  Builder(receive_timeout: ReceiveTimeout(5000))
}

pub fn receive_timeout(
  _builder: Configuration,
  milliseconds: Int,
) -> Configuration {
  Builder(receive_timeout: ReceiveTimeout(milliseconds))
}

pub fn receive_forever(_builder: Configuration) -> Configuration {
  Builder(receive_timeout: Infinity)
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
    |> ffi_send(method, _, request.headers, request.body, erl_http_options),
  )
  let headers = list.map(response.headers, normalise_header)
  Ok(Response(..response, headers: headers))
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

fn configuration_to_erl_options(config: Configuration) -> List(ErlHttpOption) {
  let Builder(receive_timeout:) = config

  [
    RecvTimeout(receive_timeout),
  ]
}
