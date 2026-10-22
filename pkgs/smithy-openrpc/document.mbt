///|
/// The boundary to `moonrockz/openrpc`. The library owns the OpenRPC object
/// model, exact JSON values and document validation; this adapter owns the
/// Smithy mapping, loss policies and shape-linked diagnostics.
///
/// Conversion never had size bounds, so library values are built without them.
fn limits() -> @exact.Limits {
  @exact.Limits::unlimited()
}

///|
fn[T] built(
  result : Result[T, @exact.Diagnostic],
  subject : @smithy.ShapeId,
) -> T raise OpenRpcError {
  match result {
    Ok(value) => value
    Err(diagnostic) =>
      raise UnsupportedMapping(
        subject,
        "I could not build an OpenRPC object: " + diagnostic.message(),
      )
  }
}

///|
fn exact(
  value : Json,
  subject : @smithy.ShapeId,
) -> @exact.Value raise OpenRpcError {
  built(@exact.from_core_json(value, limits=limits()), subject)
}

///|
fn draft07_schema(
  schema : Json,
  subject : @smithy.ShapeId,
) -> @draft07.Schema raise OpenRpcError {
  match @draft07.Schema::from_json(exact(schema, subject), limits=limits()) {
    Ok(schema) => schema
    Err(diagnostic) =>
      raise SchemaConversion(
        subject,
        "I could not represent a generated schema as draft-07: " +
        diagnostic.message(),
      )
  }
}

///|
fn extensions(
  entries : Array[(String, Json)],
  subject : @smithy.ShapeId,
) -> @rpcdoc.Extensions raise OpenRpcError {
  let out = []
  for entry in entries {
    out.push(
      (
        built(@rpcdoc.ExtensionName::parse(entry.0), subject),
        exact(entry.1, subject),
      ),
    )
  }
  built(@rpcdoc.Extensions::from_entries(out), subject)
}

///|
fn literal_example(
  name : String,
  value : Json,
  subject : @smithy.ShapeId,
) -> @rpcdoc.InlineOrReference[@rpcdoc.Example] raise OpenRpcError {
  @rpcdoc.Inline(
    built(
      @rpcdoc.Example::new(
        @rpcdoc.LiteralExample(exact(value, subject)),
        name=Some(name),
        limits=limits(),
      ),
      subject,
    ),
  )
}

///|
/// Validate the assembled document and return its JSON.
///
/// Smithy deliberately keeps optional parameters before required ones in
/// explicit positional order. OpenRPC 1.3.2 prose forbids that; the pinned
/// metaschema does not. The metaschema-compatibility profile reports exactly
/// that listed discrepancy as a warning. Every other model, schema, reference,
/// normative and official-artifact error fails conversion.
///
/// The library checks each schema graph within fixed node and edge bounds
/// that a caller cannot lift (moonrockz/moon-lander#56). A large component
/// graph exhausts them with `LimitExceeded`, which says nothing about the
/// document being invalid, so that one code does not fail conversion.
fn validated_json(
  document : @rpcdoc.Document,
  service : @smithy.ShapeId,
  operations : Array[@smithy.ShapeId],
) -> Json raise OpenRpcError {
  let report = @rpcdoc.validate(
    document,
    profile=@rpcdoc.MetaschemaCompatibility,
    limits=limits(),
  )
  let exhausted = report
    .findings()
    .any(f => f.diagnostic().code() == @exact.LimitExceeded)
  let errors = report
    .findings()
    .filter(f => {
      f.severity() == @rpcdoc.Error &&
      f.diagnostic().code() != @exact.LimitExceeded
    })
  if errors.get(0) is Some(first) {
    let shown = errors.length().min(5)
    let more = errors.length() - shown
    let message = "I produced an OpenRPC document that fails validation: " +
      errors[:shown].iter().map(finding_text).join("; ") +
      (if more > 0 { "; and \{more} more" } else { "" })
    let subject = finding_subject(first, service, operations)
    match first.phase() {
      @rpcdoc.SchemaDocument | @rpcdoc.References =>
        raise SchemaConversion(subject, message)
      _ => raise UnsupportedMapping(subject, message)
    }
  }
  let facets = [
    report.model(),
    report.schemas(),
    report.references(),
    report.normative(),
    report.artifact(),
  ]
  if !exhausted && facets.any(facet => facet != @rpcdoc.Passed) {
    raise UnsupportedMapping(
      service, "I could not complete OpenRPC document validation.",
    )
  }
  built(@exact.to_core_json(document.to_json(), limits=limits()), service)
}

///|
/// A finding under `/methods/<i>` belongs to that method's operation.
fn finding_subject(
  finding : @rpcdoc.Finding,
  service : @smithy.ShapeId,
  operations : Array[@smithy.ShapeId],
) -> @smithy.ShapeId {
  let path = finding.location().path()
  if path.length() >= 2 && path[0] == "methods" {
    for i, operation in operations {
      if path[1] == i.to_string() {
        return operation
      }
    }
  }
  service
}

///|
fn finding_text(finding : @rpcdoc.Finding) -> String {
  let path = finding.location().path()
  if path.is_empty() {
    finding.diagnostic().message()
  } else {
    finding.diagnostic().message() +
    " at /" +
    path
    .map(token => {
      token.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
    })
    .join("/")
  }
}
