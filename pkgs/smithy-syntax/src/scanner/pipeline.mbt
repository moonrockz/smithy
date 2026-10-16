///|
/// Every step of the text, in order: an unfold over `scan_at`. The only
/// state is the offset local to this function.
pub fn scan_pieces(text : String) -> Array[Step] {
  let steps : Array[Step] = []
  let mut at = @span.Offset::zero()
  while scan_at(text, at) is Some(step) {
    steps.push(step)
    at = step.end
  }
  steps
}

///|
/// Group the steps into tokens with trivia and collect the diagnostics.
/// Trivia after a token up to and including the first line break is its
/// `trivia_after`; the rest goes to the next token's `trivia_before`.
/// Trailing trivia after the last token's line break stays with that token.
pub fn attach_trivia(steps : Array[Step]) -> TokenStream {
  let tokens : Array[Token] = []
  let diagnostics : Array[@diagnostic.Diagnostic] = []
  let mut before : Array[Trivia] = []
  let mut i = 0
  let n = steps.length()
  while i < n {
    diagnostics.append(steps[i].diagnostics.to_owned())
    match steps[i].piece {
      Triv(t) => {
        before.push(t)
        i += 1
      }
      Tok(kind, lexeme, span) => {
        i += 1
        let after : Array[Trivia] = []
        while i < n && steps[i].piece is Triv(t) {
          after.push(t)
          i += 1
          if t.is_newline() {
            break
          }
        }
        tokens.push({
          kind,
          lexeme,
          span,
          trivia_before: before[:],
          trivia_after: after[:],
        })
        before = []
      }
    }
  }
  let trivia : Array[Trivia] = if tokens.is_empty() {
    before
  } else {
    let last = tokens[tokens.length() - 1]
    let merged = last.trivia_after.to_owned()
    merged.append(before)
    tokens[tokens.length() - 1] = { ..last, trivia_after: merged[:], }
    []
  }
  { tokens: tokens[:], trivia: trivia[:], diagnostics: diagnostics[:], }
}

///|
/// Scan `source`: a pipeline of pure stages. The scan never fails and is
/// lossless: `TokenStream::to_source()` is the text.
pub fn tokenize(source : @span.SourceText) -> TokenStream {
  source.text() |> scan_pieces |> attach_trivia
}

///|
/// `tokenize` of a `SourceText` built from `text`.
pub fn tokenize_text(text : String) -> TokenStream {
  @span.SourceText::new(text) |> tokenize
}
