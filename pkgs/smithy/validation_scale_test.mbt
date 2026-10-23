///|
/// A generated model of `units` operations, each with an input, an output and
/// a nested structure. Its traits exercise the selector paths whose cost grows
/// with the model: trait targets, a neighbor selector, trait validators, idRef
/// and configured validators. `scripts/bench-validate.mbtx` generates the same
/// shapes. With `invalid`, every tenth unit has wrong trait targets.
fn scale_model(units : Int32, invalid~ : Bool = false) -> String {
  let out = StringBuilder()
  out.write_string(
    (
      #|$version: "2.0"
      #|metadata validators = [
      #|  {name: "EmitEachSelector", id: "Documented", severity: "NOTE", configuration: {selector: "structure > member [trait|documentation]"}}
      #|  {name: "EmitEachSelector", id: "Ranged", severity: "WARNING", selector: "member", configuration: {selector: "structure > member [trait|range]"}}
      #|  {name: "EmitEachSelector", id: "ReadOnly", namespaces: ["example.bench"], configuration: {selector: "operation [trait|readonly]"}}
      #|]
      #|namespace example.bench
      #|
      #|blob Payload
      #|
      #|@trait(selector: "operation -[input]-> structure")
      #|structure inputMarker {}
      #|
      #|@trait(selector: "structure")
      #|@traitValidators("Marked.NoBlob": {selector: "~> blob", message: "no blobs", severity: "WARNING"})
      #|structure marked {}
      #|
      #|@trait(selector: "structure")
      #|@idRef(selector: "operation", failWhenMissing: true)
      #|string opRef
      #|
      #|service Bench {
      #|  version: "1"
      #|  operations: [
    ),
  )
  for i in 0..<units {
    out.write_string("\n    Op\{i}")
  }
  out.write_string("\n  ]\n}\n")
  for i in 0..<units {
    let tenth = i % 10 == 0
    let wrong_target = if invalid && tenth { "@inputMarker\n" } else { "" }
    let wrong_range = if invalid && tenth { "@range(min: 0)\n  " } else { "" }
    let blob = if tenth { "  c: Payload\n" } else { "" }
    out.write_string(
      (
        $|
        $|@readonly
        $|@http(method: "GET", uri: "/op\{i}")
        $|operation Op\{i} {
        $|  input: Op\{i}Input
        $|  output: Op\{i}Output
        $|}
        $|
        $|@input
        $|@inputMarker
        $|structure Op\{i}Input {
        $|  @required
        $|  @httpQuery("q")
        $|  @length(min: 1)
        $|  q: String
        $|}
        $|
        $|@output
        $|@marked
        $|\{wrong_target}structure Op\{i}Output {
        $|  @documentation("Value \{i}")
        $|  v: Rec\{i}
        $|}
        $|
        $|@opRef("example.bench#Op\{i}")
        $|structure Rec\{i} {
        $|  @range(min: 0)
        $|  a: Integer
        $|  \{wrong_range}b: String
        $|\{blob}}
        $|
      ),
    )
  }
  out.to_string()
}

///|
fn scale_events(source : String) -> String raise {
  let result = @smithy.Loader::new().add_idl("bench.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let out = StringBuilder()
  for event in model.validation_events() {
    let shape = event.shape.map(id => id.to_string()).unwrap_or("-")
    out.write_string(
      "[\{event.severity}] \{event.id} \{shape}: \{event.message}\n",
    )
  }
  out.to_string()
}

///|
/// The validation events of the generated models must not change when the
/// selector and validator code gets faster.
test "validation events of a generated valid model" (t : @test.Test) {
  t.write(scale_events(scale_model(40)))
  t.snapshot(filename="scale_valid_events.txt")
}

///|
test "validation events of a generated model with wrong trait targets" (
  t : @test.Test,
) {
  t.write(scale_events(scale_model(40, invalid=true)))
  t.snapshot(filename="scale_invalid_events.txt")
}
