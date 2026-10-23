///|
/// The data of the playground page: the samples of the picker, read from
/// `content`, the Worker under `base` and the Smithy version of this build.
/// A missing sample is a broken build.
fn playground_data(
  content : String,
  base : String,
) -> Result[@workbench.PlaygroundData, String] {
  let paths = @samples.manifest.map(source => source.path)
  let missing = missing_sources(content, paths)
  if !missing.is_empty() {
    return Err(
      "I could not find these playground samples under \{content}: \{missing.join(", ")}",
    )
  }
  let samples = []
  for source in @samples.manifest {
    let model = @fs.read_file_to_string(content + "/" + source.path) catch {
      _ => return Err("I could not read \{source.path} under \{content}")
    }
    samples.push(@samples.Sample::{
      title: source.title,
      path: source.path,
      model,
    })
  }
  Ok({
    version: @smithy.version(),
    worker: base + "playground/worker.js",
    samples,
    selected: @samples.default_index,
  })
}

///|
/// The search entry of the playground page.
fn playground_entry(data : @workbench.PlaygroundData) -> @search.Entry {
  {
    route: Playground,
    anchor: "",
    page: "Playground",
    path: ["Playground"],
    text: "Validate a Smithy model in the browser. Nothing goes to a server. Examples: " +
    data.samples.map(s => s.title).join(", ") +
    ".",
  }
}
