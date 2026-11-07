// Added for moonrockz/regex.

///|
/// Only immutable program data escapes compilation. A search owns its runner.
pub struct Program {
  priv table : @symbol_map.Table
  priv nodes : FixedArray[Node]
  priv entry : Int32
  priv nsym : Int32
  priv sym_ctx : FixedArray[Int32]
  priv col_cat : FixedArray[Category]
  priv ctx_start : Int32
}

///|
pub fn Regex::program(self : Regex) -> Program {
  {
    table: self.table,
    nodes: self.nodes,
    entry: self.entry,
    nsym: self.nsym,
    sym_ctx: self.sym_ctx,
    col_cat: self.col_cat,
    ctx_start: self.ctx_start,
  }
}
