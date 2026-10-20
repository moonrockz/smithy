///|
/// Run from the repository root with the data directory as the first argument.
fn run() -> Unit raise @resources.ResourceError {
  let args = arguments()
  let path = if !args.is_empty() {
    args[0]
  } else {
    "pkgs/artifact-resources/examples/local/data"
  }
  let registry = @local_resources.register(@resources.Registry::new()).add_repository({
      id: "example",
      provider: "local",
      location: path,
    },
  )
  let artifact = registry.resolve({ repository: "example", key: ".", })
  let loaded = @resources.load_resources(artifact.tree, [
    { name: "greeting", path: "greeting.txt", },
  ])
  for resource in loaded {
    println(resource.name + ": " + resource.text())
    println(resource.provenance)
  }
}

///|
fn main {
  run() catch {
    @resources.ResourceError(code, origin, message) => {
      eprintln("[" + code + "] " + origin + ": " + message)
      @sys.exit(1)
    }
  }
}

///|
#cfg(target="js")
fn arguments() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn arguments() -> Array[String] {
  @env.args()[1:].to_owned()
}
