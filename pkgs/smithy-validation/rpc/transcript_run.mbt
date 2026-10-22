///|
/// The outcome of checking a transcript document.
pub struct TranscriptRun {
  /// Reader findings first, then checker findings, then the end-of-input ones.
  findings : Array[TranscriptFinding]
  summary : TranscriptSummary
  /// The match against the document's expect list; None without one.
  expectations : ExpectationResult?
} derive(Eq, Debug)

///|
/// Checks the entries of a document that a reader produced and matches its
/// expect list. `completeness` overrides the document's; without either, the
/// transcript is Partial. It does no I/O and never raises.
pub fn run_transcript(
  protocol : ProtocolDescription,
  document : TranscriptDocument,
  read_findings : Array[TranscriptFinding],
  completeness? : Completeness,
  limits~ : TranscriptLimits = TranscriptLimits::default(),
) -> TranscriptRun {
  let completeness = match completeness {
    Some(chosen) => chosen
    None => document.completeness.unwrap_or(Partial)
  }
  let checker = TranscriptChecker::new(protocol, completeness~, limits~)
  let findings = read_findings + checker.feed_all(document.entries)
  let summary = checker.finish()
  findings.append(summary.findings)
  let expectations = document.expect.map(expect => {
    match_expected(expect, findings)
  })
  { findings, summary, expectations, }
}
