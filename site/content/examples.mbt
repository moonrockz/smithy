///|
/// A directory under `examples/`, as found in the content tree: its name, the
/// first `#` heading of its README (empty without one) and every file in it,
/// as paths relative to the directory.
pub(all) struct ExampleDir {
  dir : String
  title : String
  files : Array[String]
} derive(Eq, Debug)

///|
pub extend ExampleDir with Eq::{equal, not_equal}

///|
pub extend ExampleDir with @debug.Debug::{to_repr}

///|
/// A published example: a directory of `examples/` that has a README.
pub(all) struct Example {
  /// The directory name, which is also the route slug.
  dir : String
  title : String
  summary : String
  /// The files of the directory other than the README, sorted.
  files : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Example with Eq::{equal, not_equal}

///|
pub extend Example with @debug.Debug::{to_repr}

///|
pub extend Example with ToJson::{to_json}

///|
pub extend Example with FromJson::{from_json}

///|
/// One line for the index card of each example, by directory. An example that
/// is not here has no line.
let summaries : Array[(String, String)] = [
  (
    "authenticated-repositories", "Build with models from a registry that needs a token.",
  ),
  ("github-release", "Use model archives attached to a release."),
  ("json-rpc", "Peers, lifecycle and batch transcripts with expectations."),
  ("maven-repository", "Build with pinned JARs from a Maven repository."),
  ("npm-archive", "Build with models from local npm archives."),
  ("npm-registry", "Build with models from public npm packages."),
  ("openrpc", "Generate an OpenRPC 1.3.2 document from a service."),
  ("protocol-tests", "Check HTTP protocol test cases in a model."),
  ("public-archive", "Build with models from a public ZIP archive."),
  ("rpc-consumer", "Check JSON-RPC messages from a MoonBit program."),
  ("validation-consumer", "Check JSON against a shape from a MoonBit program."),
]

///|
pub fn example_summary(dir : String) -> String {
  for s in summaries {
    if s.0 == dir {
      return s.1
    }
  }
  ""
}

///|
/// Dictionary order. `String::compare` is shortlex (length first).
pub fn lex_compare(a : String, b : String) -> Int32 {
  let xs = a.to_array()
  let ys = b.to_array()
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i in 0..<n {
    if xs[i] != ys[i] {
      return if xs[i] < ys[i] { -1 } else { 1 }
    }
  }
  xs.length() - ys.length()
}

///|
/// The examples among `dirs`: those with a `README.md` at their top, sorted by
/// directory name in dictionary order.
pub fn Example::build(dirs : Array[ExampleDir]) -> Array[Example] {
  let out : Array[Example] = []
  for d in dirs {
    if d.files.contains("README.md") {
      let files = d.files.filter(f => f != "README.md")
      files.sort_by(lex_compare)
      out.push({
        dir: d.dir,
        title: d.title,
        summary: example_summary(d.dir),
        files,
      })
    }
  }
  out.sort_by((a, b) => lex_compare(a.dir, b.dir))
  out
}

///|
/// The repository path of the README.
pub fn Example::source(self : Example) -> String {
  "examples/" + self.dir + "/README.md"
}

///|
pub fn Example::find(examples : Array[Example], dir : String) -> Example? {
  examples.iter().find_first(e => e.dir == dir)
}

///|
pub fn Example::find_source(
  examples : Array[Example],
  source : String,
) -> Example? {
  let wanted = normalize_path(source)
  examples.iter().find_first(e => e.source() == wanted)
}
