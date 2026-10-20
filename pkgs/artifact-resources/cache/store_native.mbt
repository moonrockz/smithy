///|
#borrow(path)
extern "C" fn read_native(path : Bytes, bound : Int32) -> Bytes = "smithy_cache_read"

///|
#borrow(path, bytes)
extern "C" fn publish_native(path : Bytes, bytes : Bytes) -> Int32 = "smithy_cache_publish"

///|
fn read(path : Bytes, bound : Int32) -> Bytes {
  read_native(path, bound)
}

///|
fn publish(path : Bytes, bytes : Bytes) -> Bool {
  publish_native(path, bytes) == 0
}
