///|
/// The tabs whose controls are folded away, so that their code view starts on
/// the same line as the model editor. The Validate tab has no code view, so it
/// has no fold.
pub(all) struct Folded {
  transform : Bool
  transcript : Bool
} derive(Eq, Debug)

///|
pub extend Folded with Eq::{equal, not_equal}

///|
pub extend Folded with @debug.Debug::{to_repr}

///|
/// No tab folded: the playground shows every control at first.
pub let no_fold : Folded = { transform: false, transcript: false, }

///|
/// The folds that the browser keeps: the names of the folded tabs, separated
/// by commas. A name that the page does not know counts as nothing.
pub fn Folded::parse(text : String) -> Folded {
  let names = text.split(",").map(name => name.trim().to_owned()).to_array()
  {
    transform: names.contains("transform"),
    transcript: names.contains("transcript"),
  }
}

///|
/// The text that `Folded::parse` reads back.
pub fn Folded::render(self : Folded) -> String {
  let names = []
  if self.transform {
    names.push("transform")
  }
  if self.transcript {
    names.push("transcript")
  }
  names.join(",")
}

///|
/// True when the controls of `tab` are folded away.
pub fn Model::folded_on(self : Model, tab : @samples.Tab) -> Bool {
  match tab {
    ValidateTab => false
    TransformTab => self.folded.transform
    TranscriptTab => self.folded.transcript
  }
}

///|
/// True when the controls of `tab` show a notice that the reader must see: a
/// run that the Worker refused, stopped or failed, or a model that a
/// transcript check cannot use.
pub fn Model::needs_controls(self : Model, tab : @samples.Tab) -> Bool {
  match tab {
    ValidateTab => false
    TransformTab => self.tx is (TxBlocked(..) | TxStopped | TxFailed(_))
    TranscriptTab =>
      (self.protocols.is_empty() && !(self.check is Unchecked)) ||
      self.tr is (TrBlocked(..) | TrStopped | TrFailed(_))
  }
}

///|
/// The model with the controls of a tab open again when a notice that the
/// reader must see appears in them; `before` is the model before the message.
/// The reader can fold them again while the notice shows. The kept choice does
/// not change: the next visit folds the tab again.
fn Model::open_for_notices(self : Model, before : Model) -> Model {
  let opens = fn(tab) {
    self.needs_controls(tab) && !before.needs_controls(tab)
  }
  let transform = self.folded.transform && !opens(TransformTab)
  let transcript = self.folded.transcript && !opens(TranscriptTab)
  if transform == self.folded.transform && transcript == self.folded.transcript {
    self
  } else {
    { ..self, folded: { transform, transcript, }, }
  }
}

///|
/// The model with the folds that the browser kept. A tab that shows a notice
/// that the reader must see stays open.
pub fn Model::with_folded(self : Model, folded : Folded) -> Model {
  {
    ..self,
    folded: {
      transform: folded.transform && !self.needs_controls(TransformTab),
      transcript: folded.transcript && !self.needs_controls(TranscriptTab),
    },
  }
}

///|
/// The folds after the fold button of `tab`.
fn Folded::toggle(self : Folded, tab : @samples.Tab) -> Folded {
  match tab {
    ValidateTab => self
    TransformTab => { ..self, transform: !self.transform, }
    TranscriptTab => { ..self, transcript: !self.transcript, }
  }
}
