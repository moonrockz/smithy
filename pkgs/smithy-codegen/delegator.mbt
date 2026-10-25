///|
/// Gives one writer to each output path. A generator asks for the writer of a
/// file or of a shape, and the delegator makes sure that one file has one
/// writer with one namespace.
pub struct WriterDelegator {
  priv provider : SymbolProvider
  priv factory : (OutputPath, Namespace) -> CodeWriter
  priv render : (CodeWriter) -> String
  // The writers by the text of their path.
  priv writers : Map[String, CodeWriter]
  // The interceptors, in the order that they were added.
  priv interceptors : Array[Interceptor]
  // The dependencies that were added, and those of the writers that were flushed.
  priv kept : Array[SymbolDependency]
}

///|
pub fn WriterDelegator::new(
  provider : SymbolProvider,
  factory~ : (OutputPath, Namespace) -> CodeWriter = (_, ns) => {
    CodeWriter::new(namespace=ns)
  },
  render~ : (CodeWriter) -> String = w => w.to_string(),
) -> WriterDelegator {
  { provider, factory, render, writers: Map([]), interceptors: [], kept: [], }
}

///|
pub fn WriterDelegator::provider(self : WriterDelegator) -> SymbolProvider {
  self.provider
}

///|
/// Add interceptors to the writers that exist and to the writers that the
/// delegator makes later. A writer gets them in the order that they were added.
pub fn WriterDelegator::add_interceptors(
  self : WriterDelegator,
  interceptors : Array[Interceptor],
) -> Unit {
  for interceptor in interceptors {
    self.interceptors.push(interceptor)
    for _, writer in self.writers {
      writer.on_section(interceptor)
    }
  }
}

///|
/// Run `body` with the writer of the path. The first use of a path makes the
/// writer. A later use writes a blank line first. It raises `WriterConflict`
/// when the path has a writer with another namespace. An error of `body`
/// passes through, and the writer stays.
pub fn WriterDelegator::use_file_writer(
  self : WriterDelegator,
  path : OutputPath,
  namespace : Namespace,
  body : (CodeWriter) -> Unit raise CodegenError,
) -> Unit raise CodegenError {
  let key = path.to_string()
  let writer = match self.writers.get(key) {
    Some(writer) => {
      let first = writer.namespace()
      if first != namespace {
        raise WriterConflict(
          "I found two namespaces, `\{first.text}` and `\{namespace.text}`, for output file `\{key}`.",
        )
      }
      writer.blank_line()
      writer
    }
    None => {
      let writer = (self.factory)(path, namespace)
      for interceptor in self.interceptors {
        writer.on_section(interceptor)
      }
      self.writers[key] = writer
      writer
    }
  }
  body(writer)
}

///|
/// Run `body` with the writer of the file that defines the shape. The path and
/// the namespace come from the symbol of the shape. It raises
/// `MissingDefinition` when the symbol has no definition file.
pub fn WriterDelegator::use_shape_writer(
  self : WriterDelegator,
  shape : @smithy.Shape,
  body : (CodeWriter) -> Unit raise CodegenError,
) -> Unit raise CodegenError {
  let symbol = self.provider.to_symbol(shape)
  guard symbol.definition is Some(path) else {
    raise MissingDefinition(shape.id)
  }
  self.use_file_writer(path, symbol.namespace, body)
}

///|
/// Record a dependency of the generated code.
pub fn WriterDelegator::add_dependency(
  self : WriterDelegator,
  dependency : SymbolDependency,
) -> Unit {
  self.kept.push(dependency)
}

///|
/// The dependencies that were added and those of all writers, sorted and
/// without duplicates. Flushed writers keep their dependencies.
pub fn WriterDelegator::dependencies(
  self : WriterDelegator,
) -> Array[SymbolDependency] {
  let found = self.kept.copy()
  for _, writer in self.writers {
    found.append(writer.dependencies())
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
/// Render every writer, with the path text as the key and the keys in sorted
/// order. The delegator then has no writers, so a second call gives an empty map.
pub fn WriterDelegator::flush(self : WriterDelegator) -> Map[String, String] {
  let keys = self.writers.keys().collect()
  keys.sort()
  let files = Map([])
  for key in keys {
    let writer = self.writers[key]
    self.kept.append(writer.dependencies())
    files[key] = (self.render)(writer)
  }
  self.writers.clear()
  files
}
