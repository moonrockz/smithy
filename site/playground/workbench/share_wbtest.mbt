///|
fn shared_state() -> @samples.ShareState {
  {
    model: "namespace shared\n",
    transcript: "{}\n{}\n",
    tab: TranscriptTab,
    output: Selector,
    protocol: "a#Editor",
    format: Jsonl,
    complete: true,
    selector: Some("structure"),
    log_preset: Some(
      DirMessage([{ value: "in", peer: "ide", }, { value: "out", peer: "lsp", }]),
    ),
    version: Some("2.0"),
  }
}

///|
fn opened(state : @samples.ShareState) -> Model {
  Model::start_with(tr_data(), Shared(state)).0
}

///|
test "share: the page opens with the state of a link" {
  let (m, effects) = Model::start_with(tr_data(), Shared(shared_state()))
  assert_eq(effects.length(), 2)
  assert_eq(m.tab, TranscriptTab)
  assert_eq(m.output, Selector)
  assert_eq(m.selector, "structure")
  assert_eq(m.tx_output, Selector)
  assert_eq(m.tx_selector, "structure")
  assert_eq(m.first_text(), "namespace shared\n")
  assert_eq(m.first_transcript(), ("{}\n{}\n", Jsonl))
  assert_eq(m.settings, {
    protocol: "a#Editor",
    format: Jsonl,
    complete: true,
    version: "2.0",
    preset: DirMessage([
      { value: "in", peer: "ide", },
      { value: "out", peer: "lsp", },
    ]),
  })
  assert_eq(m.share, NoShare)
  // The pickers name the link, and the examples stay.
  assert_eq(m.data.samples[m.sample].title, "Shared link")
  assert_eq(m.data.transcripts[m.transcript].title, "Shared link")
  assert_eq(m.data.samples.length(), 3)
}

///|
test "share: a link with no selector, preset or version opens with the defaults" {
  let state = {
    ..shared_state(),
    selector: None,
    log_preset: None,
    version: None,
    format: Markdown,
  }
  let m = opened(state)
  assert_eq(m.selector, DEFAULT_SELECTOR)
  assert_eq(m.settings.version, "")
  assert_eq(m.settings.preset, DirMessage([]))
}

///|
test "share: a protocol that the model lacks gives fitted settings" {
  let m = opened({ ..shared_state(), protocol: "gone#Missing", })
  // Before the first answer the settings are as the link says.
  assert_eq(m.settings.protocol, "gone#Missing")
  let m = update(
      m,
      Answered(
        seq=1,
        answer=Validated(items=[], shapes=1, protocols=[
          chat_protocol, editor_protocol,
        ]),
      ),
    ).0
  // The first protocol of the model, with its own version and peers.
  assert_eq(m.settings.protocol, "a#Chat")
  assert_eq(m.settings.version, "1.0")
  assert_eq(
    m.settings.preset,
    DirMessage([
      { value: "request", peer: "client", },
      { value: "response", peer: "server", },
    ]),
  )
  assert_true(m.protocols.iter().any(p => p.id == m.settings.protocol))
}

///|
test "share: a version and peers that the protocol lacks are fitted" {
  let m = opened({ ..shared_state(), version: Some("9.9"), })
  let m = update(
      m,
      Answered(
        seq=1,
        answer=Validated(items=[], shapes=1, protocols=[editor_protocol]),
      ),
    ).0
  assert_eq(m.settings.protocol, "a#Editor")
  assert_eq(m.settings.version, "1.0")
  // The peers of the link are the peers of the protocol: they stay.
  assert_eq(
    m.settings.preset,
    DirMessage([{ value: "in", peer: "ide", }, { value: "out", peer: "lsp", }]),
  )
}

///|
test "share: a link that was refused opens the default sample with a message" {
  let (m, _) = Model::start_with(tr_data(), Refused("I cannot read this link."))
  assert_eq(m.share, LinkRefused("I cannot read this link."))
  assert_eq(m.sample, 1)
  assert_eq(m.tab, ValidateTab)
  assert_eq(m.first_text(), "namespace b\nstructure S {")
}

///|
test "share: the button asks the page for the link with the page settings" {
  let m = opened(shared_state())
  let (_, effects) = update(m, ShareClicked)
  assert_eq(effects, [
    MakeShare(
      tab=TranscriptTab,
      output=Selector,
      selector="structure",
      settings=m.settings,
    ),
  ])
}

///|
test "share: the outcome of the link shows" {
  let m = answered()
  let (m, _) = update(m, ShareDone(LinkCopied("https://x/#v1.a")))
  assert_eq(m.share, LinkCopied("https://x/#v1.a"))
  let (m, _) = update(m, ShareDone(LinkShown("https://x/#v1.a")))
  assert_eq(m.share, LinkShown("https://x/#v1.a"))
  let (m, _) = update(m, ShareDone(LinkTooLong("The link is too long.")))
  assert_eq(m.share, LinkTooLong("The link is too long."))
}

///|
test "save: the model goes alone, and the transcript goes on its tab" {
  let m = answered()
  assert_eq(update(m, SaveClicked).1, [SaveFiles(transcript=None)])
  let (m, _) = update(m, TabChosen(TranscriptTab))
  assert_eq(update(m, SaveClicked).1, [SaveFiles(transcript=Some(Markdown))])
}
