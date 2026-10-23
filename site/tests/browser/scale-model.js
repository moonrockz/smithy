// A generated Smithy model of a given size, for the tests of large models. `scaleModel(units, invalid)`
// gives the same text as `scale_model(units, invalid~)` in pkgs/smithy/validation_scale_test.mbt. Change
// the two together.

const header = `$version: "2.0"
metadata validators = [
  {name: "EmitEachSelector", id: "Documented", severity: "NOTE", configuration: {selector: "structure > member [trait|documentation]"}}
  {name: "EmitEachSelector", id: "Ranged", severity: "WARNING", selector: "member", configuration: {selector: "structure > member [trait|range]"}}
  {name: "EmitEachSelector", id: "ReadOnly", namespaces: ["example.bench"], configuration: {selector: "operation [trait|readonly]"}}
]
namespace example.bench

blob Payload

@trait(selector: "operation -[input]-> structure")
structure inputMarker {}

@trait(selector: "structure")
@traitValidators("Marked.NoBlob": {selector: "~> blob", message: "no blobs", severity: "WARNING"})
structure marked {}

@trait(selector: "structure")
@idRef(selector: "operation", failWhenMissing: true)
string opRef

service Bench {
  version: "1"
  operations: [`;

// A model of `units` operations, each with an input, an output and a nested structure. With `invalid`,
// every tenth unit has wrong trait targets.
export function scaleModel(units, invalid = false) {
  const out = [header];
  for (let i = 0; i < units; i++) {
    out.push(`\n    Op${i}`);
  }
  out.push("\n  ]\n}\n");
  for (let i = 0; i < units; i++) {
    const tenth = i % 10 === 0;
    const wrongTarget = invalid && tenth ? "@inputMarker\n" : "";
    const wrongRange = invalid && tenth ? "@range(min: 0)\n  " : "";
    const blob = tenth ? "  c: Payload\n" : "";
    out.push(`
@readonly
@http(method: "GET", uri: "/op${i}")
operation Op${i} {
  input: Op${i}Input
  output: Op${i}Output
}

@input
@inputMarker
structure Op${i}Input {
  @required
  @httpQuery("q")
  @length(min: 1)
  q: String
}

@output
@marked
${wrongTarget}structure Op${i}Output {
  @documentation("Value ${i}")
  v: Rec${i}
}

@opRef("example.bench#Op${i}")
structure Rec${i} {
  @range(min: 0)
  a: Integer
  ${wrongRange}b: String
${blob}}
`);
  }
  return out.join("");
}

// The validation events of `scaleModel(units)`, by severity and id, as the 40-unit snapshot
// pkgs/smithy/__snapshot__/scale_valid_events.txt shows them: one Documented NOTE for each
// `@documentation` member, one Ranged WARNING for each `@range` member, one ReadOnly DANGER for each
// `@readonly` operation (the validator gives no severity), and one Marked.NoBlob WARNING for each tenth
// unit, whose output reaches the blob.
export function scaleEvents(units) {
  return {
    documented: units,
    ranged: units,
    readOnly: units,
    noBlob: Math.ceil(units / 10),
  };
}

// `scaleModel(units)` with no error events: the ReadOnly validator gets severity NOTE. The playground
// counts DANGER as an error, and a Transform stops on an error, so the Transform tests use this model.
export function transformableScaleModel(units) {
  return scaleModel(units).replace(
    '{name: "EmitEachSelector", id: "ReadOnly", namespaces',
    '{name: "EmitEachSelector", id: "ReadOnly", severity: "NOTE", namespaces',
  );
}
