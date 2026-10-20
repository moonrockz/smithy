///|
/// Run from the repository root with an optional module directory or ZIP.
fn run() -> Unit raise @resources.ResourceError {
  let args = arguments()
  let path = if !args.is_empty() { args[0] } else { "pkgs/artifact-resources" }
  guard @resources.RepositoryLocation::parse(path) is Some(location) else {
    raise @resources.ResourceError(
      @resources.UnsafePath,
      @resources.Provenance::repository_reference(
        @resources.RepositoryId::parse("moonrockz/artifact-resources").unwrap(),
      ),
      "Expected a nonempty, control-free module source location",
    )
  }
  let registry = @local_resources.register(@resources.Registry::new()).add_repository({
      id: @resources.RepositoryId::parse("moonrockz/artifact-resources").unwrap(),
      provider: @resources.ProviderId::parse("local").unwrap(),
      location,
    },
  )
  let artifact = registry.resolve({
    repository: @resources.RepositoryId::parse("moonrockz/artifact-resources").unwrap(),
    key: @resources.ArtifactKey::parse(".").unwrap(),
  })
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("examples/local/data").unwrap(),
    [@resources.Matching(@resources.GlobPattern::parse("**/*.txt").unwrap())],
  ).unwrap()
  let loaded = @resources.select_resources(artifact.tree, selection)
  for resource in loaded {
    println(resource.name.to_string() + ": " + resource.text())
    println(resource.provenance)
  }
}

///|
fn main {
  run() catch {
    @resources.ResourceError(code, origin, message) => {
      eprintln(
        "[" + code.to_string() + "] " + origin.to_string() + ": " + message,
      )
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
