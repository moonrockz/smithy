///|
#borrow(url)
extern "C" fn curl_run(
  url : Bytes,
  max_bytes : Int32,
  seconds : Int32,
) -> Bytes = "smithy_resource_curl"

///|
fn run(url : String, max_bytes : Int32, seconds : Int32) -> Bytes {
  curl_run(@utf8.encode(url + "\u0000"), max_bytes, seconds)
}
