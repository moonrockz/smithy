///|
fn rank(severity : String) -> Int32 {
  match severity {
    "ERROR" => 4
    "DANGER" => 3
    "WARNING" => 2
    "NOTE" => 1
    _ => 0
  }
}

///|
fn member_target_changes(
  d : Differences,
  events : Array[ValidationEvent],
  context : ComparisonContext,
) -> Unit {
  for change in d.changed {
    if change.old_shape.body is Member(target=old_id) &&
      change.new_shape.body is Member(target=new_id) &&
      old_id != new_id {
      events.push(member_target_event(d, change, Set([]), context))
    }
  }
}

///|
fn member_target_event(
  d : Differences,
  change : ShapeChange,
  active : Set[(@smithy.ShapeId, @smithy.ShapeId)],
  context : ComparisonContext,
) -> ValidationEvent {
  let a = change.old_shape
  let b = change.new_shape
  let old_target = target(d.old_model, a)
  let new_target = target(d.new_model, b)
  let old_id = match a.body {
    Member(target~) => target
    _ => a.id
  }
  let new_id = match b.body {
    Member(target~) => target
    _ => b.id
  }
  let (severity, explanation) = target_evaluation(
    d, old_target, new_target, active, context,
  )
  {
    id: "ChangedMemberTarget",
    severity,
    shape: Some(b.id),
    source: Some(b.source),
    suppression_reason: None,
    message: "The shape targeted by the member " +
    tick(a.id.to_string()) +
    " changed from " +
    tick(old_id.to_string()) +
    " (" +
    old_target.map(kind).unwrap_or("unknown") +
    ") to " +
    tick(new_id.to_string()) +
    " (" +
    new_target.map(kind).unwrap_or("unknown") +
    "). " +
    explanation,
  }
}

///|
fn target_evaluation(
  d : Differences,
  old_shape : @smithy.Shape?,
  new_shape : @smithy.Shape?,
  active : Set[(@smithy.ShapeId, @smithy.ShapeId)],
  context : ComparisonContext,
) -> (String, String) {
  guard old_shape is Some(a) && new_shape is Some(b) else {
    return ("WARNING", "This was determined backward compatible.")
  }
  if kind(a) != kind(b) {
    return (
      "ERROR",
      "The type of the targeted shape changed from " +
      kind(a) +
      " to " +
      kind(b) +
      ".",
    )
  }
  match a.body {
    Simple(_) | List(_) | Map(..) => ()
    _ => return ("ERROR", "The name of a " + kind(a) + " is significant.")
  }
  if has(a, "enum") {
    return (
      "ERROR", "The `smithy.api#enum` trait was found on the target, so the name of the targeted shape matters for codegen.",
    )
  }
  // Assembled Smithy models cannot have a cycle made solely from collections.
  // Keep a pair guard for callers that construct models directly.
  let pair = (a.id, b.id)
  if active.contains(pair) {
    return ("WARNING", "This was determined backward compatible.")
  }
  active.add(pair)
  let changes = [shape_change(a, b)]
  let old_members = members(a)
  let new_members = members(b)
  for i = 0; i < old_members.length() && i < new_members.length(); i = i + 1 {
    if d.old_model.shapes.get(old_members[i]) is Some(old_member) &&
      d.new_model.shapes.get(new_members[i]) is Some(new_member) {
      changes.push(shape_change(old_member, new_member))
    }
  }
  let synthetic = {
    old_model: d.old_model,
    new_model: d.new_model,
    added: [],
    removed: [],
    changed: changes,
    metadata: [],
  }
  let nested = evaluate(synthetic, context, include_targets=false)
  for change in changes {
    if change.old_shape.body is Member(target=old_id) &&
      change.new_shape.body is Member(target=new_id) &&
      old_id != new_id {
      nested.push(member_target_event(d, change, active, context))
    }
  }
  active.remove(pair)
  let decorated = decorate(synthetic, nested, context)
  if decorated.is_empty() {
    return ("WARNING", "This was determined backward compatible.")
  }
  let mut severity = "WARNING"
  for event in decorated {
    if rank(event.severity) > rank(severity) {
      severity = event.severity
    }
  }
  let details = decorated
    .map(event => {
      "- [" +
      event.severity +
      "] " +
      event.message.replace_all(old="\n", new="\n  ")
    })
    .join("\n")
    .trim_end()
    .to_owned()
  (
    severity,
    (if rank(severity) <= 2 {
      "This was determined backward compatible. "
    } else {
      ""
    }) +
    "This will result in the following effective differences:\n\n" +
    details,
  )
}
