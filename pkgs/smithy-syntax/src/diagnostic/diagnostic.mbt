///|
/// How serious a diagnostic is. A file with an `Error` is rejected; a
/// `Warning` does not stop parsing.
pub(all) enum Severity {
  Error
  Warning
} derive(Eq, Debug, Hash)

///|
/// A secondary span with the text shown under it ("the structure started
/// here").
pub(all) struct Label {
  span : @span.Span
  text : String
} derive(Eq, Debug)

///|
/// A problem found while scanning or parsing, with everything a rich
/// report needs: a `title` in capitals (`UNFINISHED SHAPE`), a one-line
/// `message` under the primary `span`, secondary `labels`, `notes` in the
/// first person, an optional `hint` and an optional correct `example`.
/// Immutable: `with_context` returns a new value.
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  title : String
  message : String
  span : @span.Span
  labels : ArrayView[Label]
  notes : ArrayView[String]
  hint : String?
  example : String?
} derive(Eq, Debug)

///|
/// Build a diagnostic; the optional parts default to empty lists and `None`.
pub fn Diagnostic::new(
  code~ : String,
  severity~ : Severity,
  title~ : String,
  message~ : String,
  span~ : @span.Span,
  labels? : Array[Label],
  notes? : Array[String],
  hint? : String,
  example? : String,
) -> Diagnostic {
  {
    code,
    severity,
    title,
    message,
    span,
    labels: labels.unwrap_or([])[:],
    notes: notes.unwrap_or([])[:],
    hint,
    example,
  }
}

///|
/// Whether the severity is `Error`.
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  self.severity == Error
}

///|
/// A copy with `label` as the first label and `note` as the first note.
pub fn Diagnostic::with_context(
  self : Diagnostic,
  label : Label,
  note : String,
) -> Diagnostic {
  let labels = [label]
  labels.append(self.labels.to_owned())
  let notes = [note]
  notes.append(self.notes.to_owned())
  { ..self, labels: labels[:], notes: notes[:], }
}
