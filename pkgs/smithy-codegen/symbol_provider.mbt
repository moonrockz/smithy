///|
/// The member name of a shape: the member part of its shape ID, else its name.
fn default_member_name(shape : @smithy.Shape) -> String {
  match shape.id.member_name() {
    Some(member) => member
    None => shape.id.name()
  }
}

///|
/// Maps a shape to its symbol and to its member name in the target language.
pub struct SymbolProvider {
  symbol_fn : (@smithy.Shape) -> Symbol raise CodegenError
  member_fn : (@smithy.Shape) -> String
}

///|
pub fn SymbolProvider::new(
  to_symbol : (@smithy.Shape) -> Symbol raise CodegenError,
  to_member_name~ : (@smithy.Shape) -> String = default_member_name,
) -> SymbolProvider {
  { symbol_fn: to_symbol, member_fn: to_member_name, }
}

///|
pub fn SymbolProvider::to_symbol(
  self : SymbolProvider,
  shape : @smithy.Shape,
) -> Symbol raise CodegenError {
  (self.symbol_fn)(shape)
}

///|
pub fn SymbolProvider::to_member_name(
  self : SymbolProvider,
  shape : @smithy.Shape,
) -> String {
  (self.member_fn)(shape)
}

///|
/// A provider that calls the base provider once for each shape ID.
/// It does not keep errors: a failed call runs again.
pub fn SymbolProvider::cached(self : SymbolProvider) -> SymbolProvider {
  let cache : Map[@smithy.ShapeId, Symbol] = Map([])
  let base = self.symbol_fn
  {
    symbol_fn: shape => {
      if cache.get(shape.id) is Some(symbol) {
        return symbol
      }
      let symbol = base(shape)
      cache[shape.id] = symbol
      symbol
    },
    member_fn: self.member_fn,
  }
}

///|
/// A provider that passes each symbol of the base provider through `f`.
pub fn SymbolProvider::decorate(
  self : SymbolProvider,
  f : (@smithy.Shape, Symbol) -> Symbol,
) -> SymbolProvider {
  let base = self.symbol_fn
  { symbol_fn: shape => f(shape, base(shape)), member_fn: self.member_fn, }
}

///|
/// A provider that escapes symbol names with `symbols` and member names with
/// `members`. The two sets of words are separate.
/// A symbol whose escaped name is not a valid `SymbolName` raises `InvalidSettings`.
pub fn SymbolProvider::with_reserved_words(
  self : SymbolProvider,
  symbols~ : ReservedWords,
  members~ : ReservedWords,
) -> SymbolProvider {
  let base = self.symbol_fn
  let base_member = self.member_fn
  {
    symbol_fn: shape => {
      let symbol = base(shape)
      let text = symbols.escape(symbol.name.to_string())
      match SymbolName::parse(text) {
        Some(name) => symbol.with_name(name)
        None =>
          raise InvalidSettings(
            "I could not use `\{text}` as the escaped name of shape `\{shape.id}`: a symbol name must not be empty or have whitespace.",
          )
      }
    },
    member_fn: shape => members.escape(base_member(shape)),
  }
}
