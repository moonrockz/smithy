///|
/// The small model with one random edit: a code unit deleted, one
/// inserted (from the token pieces) or one replaced. For laws about
/// recovery: the parser must not crash, the CST stays lossless, and at
/// most a few diagnostics come out of a single edit.
pub(all) struct EditedModel {
  text : String
  edit_offset : @span.Offset
} derive(Debug)

///|
/// The edited text.
pub fn EditedModel::text(self : EditedModel) -> String {
  self.text
}

///|
/// One random edit to the small model: a code unit deleted, one inserted
/// (a token piece), or one replaced, at a random offset. Never deletes or
/// replaces a `"`: losing one re-pairs every quote after it in the file
/// (a quoted string may span lines), which rewrites the lexical structure
/// of everything downstream rather than testing recovery from one bad
/// spot. That cascade belongs to the scanner laws, not this one, so the
/// position is redrawn until it lands off a quote for those two edit
/// kinds (the model has plenty of non-quote positions). Inserting a piece
/// that itself contains quotes is fine, because every such piece is a
/// complete token (a whole string or text block), so it never leaves an
/// unmatched quote behind.
pub impl @quickcheck.Arbitrary for EditedModel with fn arbitrary(_size, rs) {
  let m = small_model()
  let kind = pick(rs, 3)
  let mut at = pick(rs, m.length())
  while (kind == 0 || kind == 2) &&
        m.unsafe_substring(start=at, end=at + 1) == "\"" {
    at = pick(rs, m.length())
  }
  let piece = one_of(rs, token_pieces())
  let text = match kind {
    0 =>
      m.unsafe_substring(start=0, end=at) +
      m.unsafe_substring(start=at + 1, end=m.length())
    1 =>
      m.unsafe_substring(start=0, end=at) +
      piece +
      m.unsafe_substring(start=at, end=m.length())
    _ =>
      m.unsafe_substring(start=0, end=at) +
      piece +
      m.unsafe_substring(start=at + 1, end=m.length())
  }
  { text, edit_offset: @span.Offset::new(at).unwrap_or(@span.Offset::zero()), }
}

///|
/// No shrinking: the edit is already a single code unit, as small as it
/// gets.
pub impl @quickcheck.Shrink for EditedModel with fn shrink(_) {
  Iter::empty()
}

///|
/// The offset at which the single edit was applied.
pub fn EditedModel::edit_offset(self : EditedModel) -> @span.Offset {
  self.edit_offset
}
