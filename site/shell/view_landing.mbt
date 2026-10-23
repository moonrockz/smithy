///|
/// The `examples/` directory on GitHub at the ref of this build.
fn examples_url(config : @data.SiteConfig) -> String {
  @data.github_repo + "/tree/" + config.git_ref + "/examples"
}

///|
/// The changelog on `main`, not at the ref of a build: `main` lists every release.
let changelog_url : String = @data.github_repo + "/blob/main/CHANGELOG.md"

///|
let install_mise : String =
  #|# Native binary for Linux, macOS or Windows
  #|mise use -g github:moonrockz/smithy
  #|smithy version

///|
let install_moonx : String =
  #|# Run the CLI from mooncakes.io without a native binary
  #|moonx moonrockz/smithy-cli@latest --help

///|
let install_library : String =
  #|# Add the library to a MoonBit project
  #|moon add moonrockz/smithy-syntax

///|
let install_download : String =
  #|# Each GitHub release has 8 assets with stable names
  #|curl -LO https://github.com/moonrockz/smithy/releases/latest/download/smithy-linux-x64.tar.gz
  #|curl -LO https://github.com/moonrockz/smithy/releases/latest/download/checksums.txt
  #|sha256sum -c --ignore-missing checksums.txt
  #|# macOS has no sha256sum. Use this command there:
  #|shasum -a 256 -c --ignore-missing checksums.txt

///|
let install_tabs : Array[(InstallTab, String, String)] = [
  (Mise, "mise", install_mise),
  (Moonx, "moonx", install_moonx),
  (Library, "library", install_library),
  (Download, "download", install_download),
]

///|
/// Title, text, bullets (bold lead, rest), link text and page.
let paths : Array[(String, String, Array[(String, String)], String, String)] = [
  (
    "Work with Smithy models in MoonBit",
    "For MoonBit developers who want Smithy without a Java toolchain.",
    [
      (
        "Parse and assemble", " IDL and JSON AST, with lossless CST and recovery",
      ),
      ("Validate", " models with the Smithy rules, selectors and contracts"),
      (
        "Build", " projections and plugins: JSON Schema, OpenAPI 3.0/3.1, OpenRPC",
      ),
      ("Diff", " two model snapshots for breaking changes"),
    ],
    "Model guide →",
    "smithy-syntax",
  ),
  (
    "Validate API requests and responses",
    "For teams who want to check real traffic against the contract.",
    [
      (
        "Values:", " application JSON or Ion against any data shape, with exact numbers",
      ),
      ("JSON-RPC 1.0 / 2.0:", " requests, notifications, replies and batches"),
      (
        "Transcripts:", " two-peer exchanges and JSONL logs, findings as they stream",
      ),
      ("Conformance suites", " for MCP, LSP and your own protocols"),
    ],
    "Validation guide →",
    "smithy-validation",
  ),
]

///|
let tiles : Array[(String, String)] = [
  (
    "No JVM", "Pure MoonBit. Ship a static native binary, a wasm module or a js bundle.",
  ),
  (
    "Reference-checked", "The parser and loader run against the vendored Java reference test corpus.",
  ),
  (
    "Findings you can act on", "First-person messages with exact paths, shape IDs and stable codes. Text or JSON.",
  ),
  (
    "Streams", "JSONL logs from stderr or files give findings line by line, before the input ends.",
  ),
  (
    "Library first", "Every CLI command is a library API you can call from your own MoonBit code.",
  ),
  (
    "Runs in the browser", "The playground runs the same packages client-side. Nothing is uploaded.",
  ),
]

///|
/// Title, text, label and the directory under `examples/`.
let example_cards : Array[(String, String, String, String)] = [
  (
    "Validate a value", "Check JSON against a shape from a MoonBit program.", "validation-consumer",
    "validation-consumer",
  ),
  (
    "JSON-RPC transcripts", "Peers, lifecycle and batch transcripts with expectations.",
    "json-rpc", "json-rpc",
  ),
  (
    "OpenRPC export", "Generate an OpenRPC 1.3.2 document from a service.", "openrpc",
    "openrpc",
  ),
  (
    "Protocol tests", "Load and run HTTP protocol test cases.", "protocol-tests",
    "protocol-tests",
  ),
  (
    "Ion values", "Validate native Ion values with the type profile.", "ion-validation-consumer",
    "ion-validation-consumer",
  ),
  (
    "Models from npm and Maven", "Build with models from public registries.", "npm-registry · maven-repository",
    "npm-registry",
  ),
  (
    "GitHub release assets", "Use model archives attached to a release.", "github-release",
    "github-release",
  ),
  ("All examples →", "", "examples/", ""),
]

///|
fn tab_attrs(selected : Bool) -> @html.Attrs {
  @html.Attrs::build()
  .role("tab")
  .aria_selected(if selected { "true" } else { "false" })
}

///|
/// A code block with a small label above its first line.
fn labeled_code(label : String, lang : String, body : Array[Html]) -> Html {
  @html.pre(
    class="ms-code",
    attrs=@html.Attrs::build().data_set("lang", lang),
    [@html.code([@html.span(class="ms-codelabel", label), ..body])],
  )
}

///|
/// `path: error[Code] rest` with the severity and code marked.
fn finding_view(line : String) -> Array[Html] {
  match (line.find("error["), line.find("] ")) {
    (Some(i), Some(j)) if j > i =>
      [
        @html.text(line[:i].to_owned()),
        @html.span(class="ms-term-error", line[i:j + 1].to_owned()),
        @html.text(line[j + 1:].to_owned()),
      ]
    _ => [@html.text(line)]
  }
}

///|
fn hero_code() -> Html {
  let sample = hero_sample()
  let command = sample.command.trim().to_owned()
  let value = sample.value.trim().to_owned()
  let prompt = @html.span(class="tk-com", "$ ")
  @html.div(class="ms-hero-code", [
    labeled_code("order.smithy", "smithy", highlighted("smithy", sample.model)),
    labeled_code(
      "terminal",
      "console",
      [
        prompt,
        @html.text("echo '\{value}' > order.json\n"),
        prompt,
        @html.text(command + "\n"),
        ..finding_view(sample.output.trim().to_owned()),
      ],
    ),
  ])
}

///|
fn section_head(eyebrow : String, title : String) -> Html {
  @html.div(class="ms-section-head", [
    @html.p(class="ms-eyebrow", eyebrow),
    @html.h2(title),
  ])
}

///|
fn hero_view(base : String) -> Html {
  @html.section(class="ms-hero", [
    @html.div(class="ms-hero-text", [
      @html.p(class="ms-eyebrow", "Smithy IDL 2.0 for MoonBit"),
      @html.h1([
        @html.text("Smithy models, "),
        @html.em("validated"),
        @html.text("."),
        @html.br(),
        @html.text("No JVM."),
      ]),
      @html.p(
        class="ms-lead",
        "Parse, validate and build Smithy models in pure MoonBit. Then check real API traffic against them: JSON values, JSON-RPC messages and whole transcripts.",
      ),
      @html.div(class="ms-cta", [
        @html.a(
          class="ms-btn ms-btn-primary",
          href=@route.href(base, DocsIndex),
          "Get started",
        ),
        @html.a(
          class="ms-btn",
          href=@route.href(base, Examples),
          "Browse examples",
        ),
      ]),
      @html.div(class="ms-facts", [
        @html.span([@html.b("native · wasm · js"), @html.text(" targets")]),
        @html.span([
          @html.text("Checked against the "),
          @html.b("Java reference corpus"),
        ]),
        @html.span([@html.b("Apache-2.0")]),
      ]),
    ]),
    hero_code(),
  ])
}

///|
fn paths_view(base : String) -> Html {
  @html.section(class="ms-section", [
    section_head("Two ways in", "Pick the job you came for"),
    @html.div(
      class="ms-paths",
      paths.map(p => {
        @html.div(class="ms-path", [
          @html.h3(p.0),
          @html.p(p.1),
          @html.ul(p.2.map(b => @html.li([@html.b(b.0), @html.text(b.1)]))),
          @html.a(class="ms-go", href=@route.href(base, Doc(p.4)), p.3),
        ])
      }),
    ),
  ])
}

///|
fn why_view() -> Html {
  @html.section(class="ms-section", [
    section_head("Why smithy.mbt", "One toolchain, every target"),
    @html.div(
      class="ms-tiles",
      tiles.map(t => @html.div(class="ms-tile", [@html.h3(t.0), @html.p(t.1)])),
    ),
  ])
}

///|
fn install_view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let tab = m.install_tab
  let current = install_tabs.iter().find_first(t => t.0 == tab)
  @html.section(class="ms-section ms-start", [
    section_head("Install", "Get the CLI or the library"),
    @html.div(
      class="ms-tabs",
      attrs=@html.Attrs::build().role("tablist"),
      install_tabs.map(t => {
        @html.button(
          class=class_if("ms-tab", "ms-tab-active", t.0 == tab),
          attrs=tab_attrs(t.0 == tab),
          on_click=emit(SelectTab(t.0)),
          t.1,
        )
      }),
    ),
    code_view(
      "bash",
      match current {
        Some(t) => t.2
        None => install_mise
      },
    ),
  ])
}

///|
/// A card links to the page of its example. An example without a README has no
/// page: its card links to the directory on GitHub.
fn example_card_href(m : Model, dir : String) -> String {
  if dir == "" {
    return @route.href(m.config.base, Examples)
  }
  match @content.Example::find(m.examples, dir) {
    Some(_) => @route.href(m.config.base, Example(dir))
    None => example_tree_url(m.config, dir)
  }
}

///|
fn examples_view(m : Model) -> Html {
  @html.section(class="ms-section", [
    section_head("Examples", "Start from a working project"),
    @html.div(
      class="ms-ex",
      example_cards.map(c => {
        let text = if c.3 == "" {
          "\{m.examples.length()} examples with a README."
        } else {
          c.1
        }
        example_card(example_card_href(m, c.3), c.0, text, c.2)
      }),
    ),
  ])
}

///|
fn landing_view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let base = m.config.base
  @html.div(class="ms-landing", [
    hero_view(base),
    paths_view(base),
    why_view(),
    install_view(m, emit),
    examples_view(m),
  ])
}
