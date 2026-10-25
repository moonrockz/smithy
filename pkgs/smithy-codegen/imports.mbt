///|
/// An import that a generated file needs. The `local_name` is the name that the
/// file uses for the symbol, when it is not the name of the symbol.
pub(all) struct ImportEntry {
  ns : Namespace
  name : SymbolName
  local_name : SymbolName?
} derive(Eq, Compare, Hash, Debug)

///|
/// The tracker of imports and dependencies. All writers of one file share it
/// by reference. `imports` maps the name that the file uses (the local name, or the
/// name of the symbol) to the first import of that name. `locals` holds the names
/// that the file itself uses for its own symbols: the symbols of the writer
/// namespace and the reserved names. A foreign symbol with one of these names is
/// written by its full name and is not imported.
priv struct ImportTracker {
  imports : Map[SymbolName, ImportEntry]
  dependencies : Map[SymbolDependency, Unit]
  locals : Map[SymbolName, Unit]
  // The keys in the order that I added them. A rollback removes the keys
  // after a mark. Nothing changes or removes an entry in another way.
  import_log : Array[SymbolName]
  dependency_log : Array[SymbolDependency]
  local_log : Array[SymbolName]
}

///|
/// A place in the history of the tracker, to which `rollback` can return.
priv struct TrackerMark {
  imports : Int32
  dependencies : Int32
  locals : Int32
}

///|
fn ImportTracker::new() -> ImportTracker {
  {
    imports: Map([]),
    dependencies: Map([]),
    locals: Map([]),
    import_log: [],
    dependency_log: [],
    local_log: [],
  }
}

///|
fn ImportTracker::mark(self : ImportTracker) -> TrackerMark {
  {
    imports: self.import_log.length(),
    dependencies: self.dependency_log.length(),
    locals: self.local_log.length(),
  }
}

///|
/// Remove the imports, the dependencies and the local names that I added after
/// the mark.
fn ImportTracker::rollback(self : ImportTracker, mark : TrackerMark) -> Unit {
  while self.import_log.length() > mark.imports {
    if self.import_log.pop() is Some(key) {
      self.imports.remove(key)
    }
  }
  while self.local_log.length() > mark.locals {
    if self.local_log.pop() is Some(name) {
      self.locals.remove(name)
    }
  }
  while self.dependency_log.length() > mark.dependencies {
    if self.dependency_log.pop() is Some(dependency) {
      self.dependencies.remove(dependency)
    }
  }
}

///|
fn ImportTracker::add_dependency(
  self : ImportTracker,
  dependency : SymbolDependency,
) -> Unit {
  if !self.dependencies.contains(dependency) {
    self.dependencies[dependency] = ()
    self.dependency_log.push(dependency)
  }
}

///|
/// Record a name that the file uses for one of its own symbols. A name that the
/// file imported before keeps its import.
fn ImportTracker::add_local(self : ImportTracker, name : SymbolName) -> Unit {
  if !self.locals.contains(name) {
    self.locals[name] = ()
    self.local_log.push(name)
  }
}

///|
/// Record the use of one symbol, without its references. It gives the text to
/// write for the symbol.
fn ImportTracker::use_one(
  self : ImportTracker,
  ns : Namespace,
  symbol : Symbol,
  local_name : SymbolName?,
) -> String {
  for dependency in symbol.dependencies {
    self.add_dependency(dependency)
  }
  if symbol.ns.is_root() {
    return symbol.name.to_string()
  }
  if symbol.ns == ns {
    self.add_local(symbol.name)
    return symbol.name.to_string()
  }
  let key = match local_name {
    Some(local_name) => local_name
    None => symbol.name
  }
  if self.locals.contains(key) {
    return symbol.full_name()
  }
  match self.imports.get(key) {
    Some(existing) =>
      if existing.ns == symbol.ns &&
        existing.name == symbol.name &&
        existing.local_name == local_name {
        key.to_string()
      } else {
        symbol.full_name()
      }
    None => {
      self.imports[key] = { ns: symbol.ns, name: symbol.name, local_name, }
      self.import_log.push(key)
      key.to_string()
    }
  }
}

///|
/// Record the use of a symbol and of every symbol that it refers to, and give
/// the text to write for the symbol. The walk keeps its own stack and a set of
/// the symbols that it has seen (full name and local name), so a cycle or a diamond
/// of references does not loop or repeat work.
fn ImportTracker::use_symbol(
  self : ImportTracker,
  ns : Namespace,
  symbol : Symbol,
  local_name : SymbolName?,
) -> String {
  let text = self.use_one(ns, symbol, local_name)
  let seen : Map[(String, SymbolName?), Unit] = Map([])
  seen[(symbol.full_name(), local_name)] = ()
  let stack : Array[SymbolReference] = []
  for index = symbol.references.length() - 1; index >= 0; index = index - 1 {
    stack.push(symbol.references[index])
  }
  while stack.pop() is Some(reference) {
    let key = (reference.symbol.full_name(), reference.local_name)
    if seen.contains(key) {
      continue
    }
    seen[key] = ()
    let _ = self.use_one(ns, reference.symbol, reference.local_name)
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
  self.tracker.add_dependency(dependency)
}

///|
/// Reserve a name for a symbol that the file defines, such as the shape that the
/// file declares. Later, `$T` writes a foreign symbol with this name by its full
/// name and does not import it. A reserved name does not change an import that
/// the file made before.
pub fn CodeWriter::reserve_name(self : CodeWriter, name : SymbolName) -> Unit {
  self.tracker.add_local(name)
}

///|
/// Record the import and the dependencies of a symbol, and of its references,
/// with the rules of `$T`, and write nothing.
pub fn CodeWriter::add_import(
  self : CodeWriter,
  symbol : Symbol,
  local_name~ : SymbolName? = None,
) -> Unit {
  let _ = self.tracker.use_symbol(self.ns, symbol, local_name)
}

///|
/// The text of `$T` for a symbol: it records the imports and the dependencies.
fn CodeWriter::symbol_text(
  self : CodeWriter,
  symbol : Symbol,
  local_name : SymbolName?,
) -> String {
  self.tracker.use_symbol(self.ns, symbol, local_name)
}
