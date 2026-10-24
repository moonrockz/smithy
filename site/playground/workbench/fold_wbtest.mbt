///|
test "fold: the kept text reads back as the same folds, and unknown names count as nothing" {
  let both = { transform: true, transcript: true, }
  assert_eq(both.render(), "transform,transcript")
  assert_eq(Folded::parse(both.render()), both)
  assert_eq(Folded::parse(""), no_fold)
  assert_eq(Folded::parse("transcript, other"), {
    transform: false,
    transcript: true,
  })
  assert_eq(no_fold.render(), "")
}

///|
test "fold: the button folds the controls of a tab, keeps the choice, and Validate has no fold" {
  let m = answered()
  assert_eq(m.folded, no_fold)
  let (m, effects) = update(m, FoldToggled(TransformTab))
  assert_true(m.folded_on(TransformTab))
  assert_false(m.folded_on(TranscriptTab))
  assert_eq(effects, [StoreFolded({ transform: true, transcript: false, })])
  let (m, _) = update(m, FoldToggled(TransformTab))
  assert_false(m.folded_on(TransformTab))
  let (m, effects) = update(m, FoldToggled(ValidateTab))
  assert_false(m.folded_on(ValidateTab))
  assert_eq(effects, [StoreFolded(no_fold)])
}

///|
test "fold: a stopped transform opens the folded controls, so its notice shows" {
  let m = answered().with_folded({ transform: true, transcript: false, })
  assert_true(m.folded_on(TransformTab))
  let (m, _) = update(m, RunClicked)
  // Folded controls stay folded while the transform runs.
  assert_true(m.folded_on(TransformTab))
  let (m, _) = update(m, TimedOut(seq=m.seq))
  assert_eq(m.tx, TxStopped)
  assert_true(m.needs_controls(TransformTab))
  assert_false(m.folded_on(TransformTab))
}

///|
test "fold: a refused transform opens the folded controls" {
  let m = answered().with_folded({ transform: true, transcript: false, })
  let (m, _) = update(m, RunClicked)
  let (m, _) = update(
    m,
    Answered(seq=m.seq, answer=NotRun("The model has errors.", ModelErrors)),
  )
  assert_true(m.tx is TxBlocked(..))
  assert_false(m.folded_on(TransformTab))
}

///|
test "fold: a model without a JSON-RPC protocol opens the folded Transcript controls" {
  // The test data has no protocol, so after its check the Transcript tab has a notice.
  let m = answered().with_folded({ transform: false, transcript: true, })
  assert_true(m.needs_controls(TranscriptTab))
  assert_false(m.folded_on(TranscriptTab))
}

///|
test "fold: the reader can fold the controls again while the notice shows" {
  let m = answered().with_folded({ transform: true, transcript: false, })
  let (m, _) = update(m, RunClicked)
  let (m, _) = update(m, TimedOut(seq=m.seq))
  assert_false(m.folded_on(TransformTab))
  let (m, effects) = update(m, FoldToggled(TransformTab))
  assert_true(m.folded_on(TransformTab))
  assert_eq(effects, [StoreFolded({ transform: true, transcript: false, })])
  // Another message with the same notice keeps the fold.
  let (m, _) = update(m, CursorMoved(line=2, column=1))
  assert_true(m.folded_on(TransformTab))
}
