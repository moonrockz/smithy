///|
let hero_feature : String =
  #|namespace example.weather
  #|
  #|service Weather {
  #|    version: "2026-01-01"
  #|    operations: [GetCity]
  #|}

///|
let hero_step : String =
  #|smithy validate model.smithy
  #|smithy build

///|
let install_cli : String =
  #|# 1. Add the library
  #|moon add moonrockz/smithy
  #|# 2. Install the CLI
  #|moon install moonrockz/smithy/apps/smithy
  #|# 3. Validate a model
  #|smithy validate model.smithy

///|
let install_moonx : String =
  #|# 1. Add the library
  #|moon add moonrockz/smithy
  #|# 2. Nothing to install: moonx runs the CLI from mooncakes.io
  #|# 3. Validate a model
  #|moonx moonrockz/smithy/apps/smithy@latest validate model.smithy

///|
let tiles : Array[(String, String)] = [
  ("Smithy IDL", "Parse, format and validate Smithy models."),
  ("Build", "Assemble models and run the build plugins."),
  ("Diff", "Compare two models and report breaking changes."),
]

///|
fn tab_attrs(selected : Bool) -> @html.Attrs {
  @html.Attrs::build()
  .role("tab")
  .aria_selected(if selected { "true" } else { "false" })
}

///|
fn landing_view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let base = m.config.base
  let tab = m.install_tab
  @html.div(class="ms-landing", [
    @html.section(class="ms-hero", [
      @html.div(class="ms-hero-text", [
        @html.p(class="ms-eyebrow", "Smithy for MoonBit"),
        @html.h1([
          @html.text("Smithy models, "),
          @html.em("in MoonBit"),
          @html.text("."),
        ]),
        @html.p(
          class="ms-lead",
          "Load, validate, build and diff Smithy models with a MoonBit library and a CLI.",
        ),
        @html.div(class="ms-cta", [
          @html.a(
            class="ms-btn ms-btn-primary",
            href=@route.href(base, Doc(@route.default_doc_slug)),
            "Get started",
          ),
          @html.a(class="ms-btn", href="#why", "Why smithy?"),
        ]),
      ]),
      @html.div(class="ms-hero-code", [
        code_view("smithy", hero_feature),
        code_view("bash", hero_step),
      ]),
    ]),
    @html.section(id="why", class="ms-why", [
      @html.p(class="ms-eyebrow", "Why smithy"),
      @html.div(
        class="ms-tiles",
        tiles.map(t => @html.div(class="ms-tile", [@html.h3(t.0), @html.p(t.1)])),
      ),
    ]),
    @html.section(class="ms-start", [
      @html.p(class="ms-eyebrow", "Get started in 3 steps"),
      @html.div(class="ms-tabs", attrs=@html.Attrs::build().role("tablist"), [
        @html.button(
          class=class_if("ms-tab", "ms-tab-active", tab == Installed),
          attrs=tab_attrs(tab == Installed),
          on_click=emit(SelectTab(Installed)),
          "Installed CLI",
        ),
        @html.button(
          class=class_if("ms-tab", "ms-tab-active", tab == Moonx),
          attrs=tab_attrs(tab == Moonx),
          on_click=emit(SelectTab(Moonx)),
          "moonx (no install)",
        ),
      ]),
      code_view(
        "bash",
        if tab == Installed {
          install_cli
        } else {
          install_moonx
        },
      ),
    ]),
  ])
}
