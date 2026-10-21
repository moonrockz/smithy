///|
#borrow(url, config)
extern "C" fn curl_run(
  url : Bytes,
  max_bytes : Int32,
  seconds : Int32,
  config : Bytes,
) -> Bytes = "smithy_resource_curl"

///|
fn run(
  url : String,
  max_bytes : Int32,
  seconds : Int32,
  config : String,
) -> Bytes {
  curl_run(
    @utf8.encode(url + "\u0000"),
    max_bytes,
    seconds,
    @utf8.encode(config + "\u0000"),
  )
}

///|
extern "C" fn now_ms() -> Double = "smithy_resource_monotonic_ms"
