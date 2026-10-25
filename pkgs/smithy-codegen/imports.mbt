///|
/// An import that a generated file needs. The alias is the name that the
/// file uses for the symbol, when it is not the name of the symbol.
pub(all) struct ImportEntry {
  namespace : Namespace
  name : SymbolName
  alias : SymbolName?
} derive(Eq, Compare, Hash, Debug)

///|
/// The tracker of imports and dependencies. All writers of one file share it
/// by reference. `imports` maps the name that the file uses (the alias, or the
/// name of the symbol) to the first import of that name.
priv struct ImportTracker {
  imports : Map[SymbolName, ImportEntry]
  dependencies : Map[SymbolDependency, Unit]
}

///|
fn ImportTracker::new() -> ImportTracker {
  { imports: Map([]), dependencies: Map([]), }
}

///|
/// Record the use of one symbol, without its references. It gives the text to
/// write for the symbol.
fn ImportTracker::use_one(
  self : ImportTracker,
  namespace : Namespace,
  symbol : Symbol,
  alias : SymbolName?,
) -> String {
  for dependency in symbol.dependencies {
    self.dependencies[dependency] = ()
  }
  if symbol.namespace.is_root() || symbol.namespace == namespace {
    return symbol.name.to_string()
  }
  let key = match alias {
    Some(alias) => alias
    None => symbol.name
  }
  match self.imports.get(key) {
    Some(existing) =>
      if existing.namespace == symbol.namespace &&
        existing.name == symbol.name &&
        existing.alias == alias {
        key.to_string()
      } else {
        symbol.full_name()
      }
    None => {
      self.imports[key] = {
        namespace: symbol.namespace,
        name: symbol.name,
        alias,
      }
      key.to_string()
    }
  }
}

///|
/// Record the use of a symbol and of every symbol that it refers to, and give
/// the text to write for the symbol. The walk keeps its own stack and a set of
/// the symbols that it has seen (full name and alias), so a cycle or a diamond
/// of references does not loop or repeat work.
fn ImportTracker::use_symbol(
  self : ImportTracker,
  namespace : Namespace,
  symbol : Symbol,
  alias : SymbolName?,
) -> String {
  let text = self.use_one(namespace, symbol, alias)
  let seen : Map[(String, SymbolName?), Unit] = Map([])
  seen[(symbol.full_name(), alias)] = ()
  let stack : Array[SymbolReference] = []
  for index = symbol.references.length() - 1; index >= 0; index = index - 1 {
    stack.push(symbol.references[index])
  }
  while stack.pop() is Some(reference) {
    let key = (reference.symbol.full_name(), reference.alias)
    if seen.contains(key) {
      continue
    }
    seen[key] = ()
    let _ = self.use_one(namespace, reference.symbol, reference.alias)
    let references = reference.symbol.references
    for index = references.length() - 1; index >= 0; index = index - 1 {
      stack.push(references[index])
    }
  }
  text
}

///|
/// The imports that the writers of this file recorded, sorted and without
/// duplicates.
pub fn CodeWriter::imports(self : CodeWriter) -> Array[ImportEntry] {
  let result = self.tracker.imports.values().collect()
  result.sort()
  result
}

///|
/// The dependencies that the writers of this file recorded, sorted and
/// without duplicates.
pub fn CodeWriter::dependencies(self : CodeWriter) -> Array[SymbolDependency] {
  let result = self.tracker.dependencies.keys().collect()
  result.sort()
  result
}

///|
/// Record a dependency of the generated file.
pub fn CodeWriter::add_dependency(
  self : CodeWriter,
  dependency : SymbolDependency,
) -> Unit {
  self.tracker.dependencies[dependency] = ()
}

///|
/// Record the import and the dependencies of a symbol, and of its references,
/// with the rules of `$T`, and write nothing.
pub fn CodeWriter::add_import(
  self : CodeWriter,
  symbol : Symbol,
  alias~ : SymbolName? = None,
) -> Unit {
  let _ = self.tracker.use_symbol(self.namespace, symbol, alias)
}

///|
/// The text of `$T` for a symbol: it records the imports and the dependencies.
fn CodeWriter::symbol_text(
  self : CodeWriter,
  symbol : Symbol,
  alias : SymbolName?,
) -> String {
  self.tracker.use_symbol(self.namespace, symbol, alias)
}
