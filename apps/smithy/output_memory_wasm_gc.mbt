///|
/// GC arrays are not linear-memory pointers. Reserve one page exclusively for
/// synchronous WASI calls, copying at most 8192 bytes per call. No GC allocation
/// can move this scratch page; the CLI never makes overlapping output calls.
struct WasiBuffer(Int32)

///|
extern "wasm" fn output_grow_memory() -> Int32 =
  #|(func (result i32) i32.const 1 memory.grow)

///|
extern "wasm" fn output_store_byte(address : Int32, value : Int32) -> Unit =
  #|(func (param i32 i32) local.get 0 local.get 1 i32.store8)

///|
extern "wasm" fn output_load_int(address : Int32) -> Int32 =
  #|(func (param i32) (result i32) local.get 0 i32.load)

///|
let output_scratch_page : Int32 = output_grow_memory()

///|
fn WasiBuffer::new() -> WasiBuffer raise {
  guard output_scratch_page >= 0 else {
    raise CliError("could not allocate output buffer", 1)
  }
  WasiBuffer(output_scratch_page * 65536)
}

///|
fn WasiBuffer::address(self : WasiBuffer) -> Int32 {
  self.0
}

///|
fn WasiBuffer::put(self : WasiBuffer, offset : Int32, value : Byte) -> Unit {
  output_store_byte(self.0 + offset, value.to_int())
}

///|
fn WasiBuffer::get_u32(self : WasiBuffer, offset : Int32) -> Int32 {
  output_load_int(self.0 + offset)
}
