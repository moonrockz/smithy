///|
/// The playground page: the workbench with no result. The playground script
/// mounts the workbench again in the same element and starts the editor and
/// the Worker.
fn playground_view(m : Model) -> Html {
  match m.playground {
    Some(data) =>
      @html.div(id=@workbench.APP_ID, class="pg-app", [
        @workbench.view(
          @workbench.Model::start(data).0,
          @cmd.Emit(_ => @rabbita.none),
        ),
      ])
    None =>
      @html.section(class="ms-notfound", [
        @html.h1("Playground"),
        @html.p(
          "The playground could not start, because this build has no playground data.",
        ),
      ])
  }
}
