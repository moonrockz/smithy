///|
fn has_blank(text : String) -> Bool {
  text.is_empty() ||
  text.iter().any(c => c == ' ' || c == '\t' || c == '\n' || c == '\r')
}

///|
/// The name of a symbol. It is not empty and has no whitespace.
pub struct SymbolName(String) derive(Eq, Hash, Debug)

///|
/// Lexical order of the text.
pub impl Compare for SymbolName with fn compare(self, other) {
  lexical(self.0, other.0)
}

///|
pub fn SymbolName::parse(text : String) -> SymbolName? {
  if has_blank(text) {
    None
  } else {
    Some(SymbolName(text))
  }
}

///|
pub fn SymbolName::to_string(self : SymbolName) -> String {
  self.0
}

///|
/// A namespace of a symbol, with the separator that joins it to the name.
/// The root namespace has empty text and an empty separator.
pub struct Namespace {
  text : String
  separator : String
} derive(Eq, Hash, Debug)

///|
/// Lexical order of the text, then of the separator.
pub impl Compare for Namespace with fn compare(self, other) {
  match lexical(self.text, other.text) {
    0 => lexical(self.separator, other.separator)
    order => order
  }
}

///|
/// Parse a namespace. Empty text is not valid: use `Namespace::root`.
pub fn Namespace::parse(text : String, separator~ : String) -> Namespace? {
  if text.is_empty() {
    None
  } else {
    Some({ text, separator, })
  }
}

///|
pub fn Namespace::root() -> Namespace {
  { text: "", separator: "", }
}

///|
pub fn Namespace::is_root(self : Namespace) -> Bool {
  self.text.is_empty()
}

///|
/// A relative output path with `/` as the only separator.
pub struct OutputPath(String) derive(Eq, Hash, Debug)

///|
/// Lexical order of the text.
pub impl Compare for OutputPath with fn compare(self, other) {
  lexical(self.0, other.0)
}

///|
/// Parse an output path. I reject empty text, a leading `/`, empty segments,
/// `.` and `..` segments, `\` and a drive prefix such as `C:`.
pub fn OutputPath::parse(text : String) -> OutputPath? {
  if text.is_empty() || text.contains("\\") {
    return None
  }
  for segment in text.split("/") {
    let segment = segment.to_owned()
    if segment.is_empty() ||
      segment == "." ||
      segment == ".." ||
      segment.contains(":") {
      return None
    }
  }
  Some(OutputPath(text))
}

///|
pub fn OutputPath::to_string(self : OutputPath) -> String {
  self.0
}

///|
/// The name of a package that a generated file depends on.
pub struct PackageName(String) derive(Eq, Hash, Debug)

///|
/// Lexical order of the text.
pub impl Compare for PackageName with fn compare(self, other) {
  lexical(self.0, other.0)
}

///|
pub fn PackageName::parse(text : String) -> PackageName? {
  if has_blank(text) {
    None
  } else {
    Some(PackageName(text))
  }
}

///|
pub fn PackageName::to_string(self : PackageName) -> String {
  self.0
}

///|
pub(all) enum DependencyKind {
  Runtime
  Test
  Build
} derive(Eq, Compare, Hash, Debug)

///|
pub(all) struct SymbolDependency {
  package_name : PackageName
  version : String
  kind : DependencyKind
} derive(Eq, Hash, Debug)

///|
/// Order by package, then version in lexical order, then kind in declaration order.
pub impl Compare for SymbolDependency with fn compare(self, other) {
  match Compare::compare(self.package_name, other.package_name) {
    0 =>
      match lexical(self.version, other.version) {
        0 => Compare::compare(self.kind, other.kind)
        order => order
      }
    order => order
  }
}

///|
/// A symbol: the target-language name of a shape, where it is defined and what it needs.
pub struct Symbol {
  name : SymbolName
  ns : Namespace
  definition : OutputPath?
  references : Array[SymbolReference]
  dependencies : Array[SymbolDependency]
  properties : Map[String, Json]
} derive(Eq, Debug)

///|
/// A reference from one symbol to another, with an optional local name.
pub struct SymbolReference {
  symbol : Symbol
  local_name : SymbolName?
} derive(Eq, Debug)

///|
pub fn Symbol::new(
  name : SymbolName,
  ns~ : Namespace = Namespace::root(),
  definition~ : OutputPath? = None,
) -> Symbol {
  { name, ns, definition, references: [], dependencies: [], properties: {}, }
}

///|
/// A copy of the symbol with another name.
pub fn Symbol::with_name(self : Symbol, name : SymbolName) -> Symbol {
  { ..self, name, }
}

///|
/// A copy of the symbol with one more reference.
pub fn Symbol::with_reference(
  self : Symbol,
  reference : SymbolReference,
) -> Symbol {
  { ..self, references: [..self.references, reference], }
}

///|
/// A copy of the symbol with one more dependency.
pub fn Symbol::with_dependency(
  self : Symbol,
  dependency : SymbolDependency,
) -> Symbol {
  { ..self, dependencies: [..self.dependencies, dependency], }
}

///|
/// A copy of the symbol with a property set.
pub fn Symbol::with_property(
  self : Symbol,
  key : String,
  value : Json,
) -> Symbol {
  let properties = self.properties.copy()
  properties[key] = value
  { ..self, properties, }
}

///|
pub fn Symbol::property(self : Symbol, key : String) -> Json? {
  self.properties.get(key)
}

///|
/// The namespace, the separator and the name. Only the name when the namespace is root.
pub fn Symbol::full_name(self : Symbol) -> String {
  if self.ns.is_root() {
    self.name.0
  } else {
    "\{self.ns.text}\{self.ns.separator}\{self.name.0}"
  }
}

///|
/// The dependencies of the symbol and of its references, sorted and without duplicates.
/// A walk keeps its own stack, so deep reference chains do not overflow.
pub fn Symbol::all_dependencies(self : Symbol) -> Array[SymbolDependency] {
  let found = []
  let stack = [self]
  while stack.pop() is Some(symbol) {
    found.append(symbol.dependencies)
    for reference in symbol.references {
      stack.push(reference.symbol)
    }
  }
  found.sort()
  let result = []
  for dependency in found {
    if result.last() is Some(last) && last == dependency {
      continue
    }
    result.push(dependency)
  }
  result
}

///|
pub fn SymbolReference::new(
  symbol : Symbol,
  local_name~ : SymbolName? = None,
) -> SymbolReference {
  { symbol, local_name, }
}
