///|
struct WasiBuffer(Bytes)

///|
fn WasiBuffer::new() -> WasiBuffer {
  WasiBuffer(Bytes::make(8208, 0))
}

///|
#borrow(bytes)
extern "wasm" fn output_bytes_address(bytes : Bytes) -> Int32 =
  #|(func (param i32) (result i32) local.get 0)

///|
fn WasiBuffer::address(self : WasiBuffer) -> Int32 {
  output_bytes_address(self.0)
}

///|
fn WasiBuffer::put(self : WasiBuffer, offset : Int32, value : Byte) -> Unit {
  output_wasm_store(self.address() + offset, value.to_int())
}

///|
fn WasiBuffer::get_u32(self : WasiBuffer, offset : Int32) -> Int32 {
  output_wasm_load(self.address() + offset)
}

///|
extern "wasm" fn output_wasm_store(address : Int32, value : Int32) -> Unit =
  #|(func (param i32 i32) local.get 0 local.get 1 i32.store8)

///|
extern "wasm" fn output_wasm_load(address : Int32) -> Int32 =
  #|(func (param i32) (result i32) local.get 0 i32.load)
