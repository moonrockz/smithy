///|
/// The URL of the Worker script of the build, with its git ref as the query,
/// as `ui.js` has. A page of one build then never runs the Worker of another.
fn worker_url(config : @data.SiteConfig) -> String {
  config.versioned(config.base + "playground/worker.js")
}

///|
/// The data of the playground page: the samples of the picker, read from
/// `content`, the Worker at `worker` and the Smithy version of this build.
/// A missing sample is a broken build.
fn playground_data(
  content : String,
  worker : String,
) -> Result[@workbench.PlaygroundData, String] {
  let paths = @samples.manifest.map(source => source.path) +
    @samples.transcript_manifest.map(source => source.path)
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
  let transcripts = []
  for source in @samples.transcript_manifest {
    let text = @fs.read_file_to_string(content + "/" + source.path) catch {
      _ => return Err("I could not read \{source.path} under \{content}")
    }
    transcripts.push(@samples.TranscriptSample::{
      title: source.title,
      path: source.path,
      protocol: source.protocol,
      format: source.format,
      version: source.version,
      preset: source.preset,
      text,
    })
  }
  Ok({
    version: @smithy.version(),
    worker,
    samples,
    selected: @samples.default_index,
    transcripts,
    transcript: @samples.default_transcript,
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
    text: "Validate a Smithy model, convert it, and check JSON-RPC transcripts in the browser. Nothing goes to a server. Examples: " +
    data.samples.map(s => s.title).join(", ") +
    ". Transcripts: " +
    data.transcripts.map(s => s.title).join(", ") +
    ".",
  }
}

///|
/// The share fragment that "Open in playground" uses for the example `dir`:
/// `None` when the picker has no model of that directory. A fragment that is
/// too long is a broken build, because the button would open nothing.
fn example_fragment(
  dir : String,
  data : @workbench.PlaygroundData,
) -> Result[String?, String] {
  match
    @samples.example_state(dir, data.samples, data.transcripts, data.transcript) {
    None => Ok(None)
    Some(state) => {
      let fragment = @core.encode_share(state)
      match
        (@core.share_state_problem(state), @core.share_length_problem(fragment)) {
        (Some(problem), _) | (_, Some(problem)) =>
          Err("The playground link of examples/\{dir} does not fit: \{problem}")
        _ => Ok(Some(fragment))
      }
    }
  }
}

///|
/// The examples, each with the fragment of "Open in playground". Every page
/// carries them: the site moves between example pages with no page load, so
/// the page that opens first must already know the fragment of each example.
fn with_playground_links(
  examples : Array[@content.Example],
  data : @workbench.PlaygroundData,
) -> Result[Array[@content.Example], String] {
  let out = []
  for e in examples {
    match example_fragment(e.dir, data) {
      Ok(playground) => out.push({ ..e, playground, })
      Err(message) => return Err(message)
    }
  }
  Ok(out)
}
