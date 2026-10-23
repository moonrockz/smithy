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

///|
test "link: a pasted link opens in place when the editors have no changes" {
  let m = answered()
  let (m, effects) = update(
    m,
    LinkOpened(opened=Shared(shared_state()), dirty=false),
  )
  assert_eq(m.incoming, None)
  assert_eq(m.tab, TranscriptTab)
  assert_eq(m.output, Selector)
  assert_eq(m.selector, "structure")
  assert_eq(m.settings.protocol, "a#Editor")
  assert_true(m.settings.complete)
  assert_eq(m.tx, TxIdle)
  assert_eq(m.data.samples[m.sample].title, "Shared link")
  assert_eq(effects, [
    ApplyShared(model="namespace shared\n", transcript="{}\n{}\n", format=Jsonl),
    Wait(ms=DEBOUNCE_MS, then=Debounced(edits=m.edits)),
  ])
  // A second link replaces the first "Shared link" in the pickers.
  let (m, _) = update(
    m,
    LinkOpened(
      opened=Shared({ ..shared_state(), model: "namespace two\n", }),
      dirty=false,
    ),
  )
  assert_eq(m.data.samples.filter(s => s.title == "Shared link").length(), 1)
  assert_eq(m.data.samples[m.sample].model, "namespace two\n")
}

///|
test "link: the check after a pasted link fits the settings to the model" {
  let m = answered()
  let (m, _) = update(
    m,
    LinkOpened(
      opened=Shared({ ..shared_state(), protocol: "gone#Missing", }),
      dirty=false,
    ),
  )
  assert_eq(m.settings.protocol, "gone#Missing")
  let (m, effects) = update(m, Debounced(edits=m.edits))
  // One request runs at a time: the check goes out with the next number.
  assert_eq(effects[0], SendValidate(seq=m.seq))
  let m = update(
      m,
      Answered(
        seq=m.seq,
        answer=Validated(items=[], shapes=1, protocols=[
          chat_protocol, editor_protocol,
        ]),
      ),
    ).0
  assert_eq(m.settings.protocol, "a#Chat")
}

///|
test "link: a pasted link waits for the answer when the editors have changes" {
  let m = answered()
  let (asked, effects) = update(
    m,
    LinkOpened(opened=Shared(shared_state()), dirty=true),
  )
  assert_eq(effects, [])
  assert_eq(asked.incoming, Some(shared_state()))
  assert_eq(asked.tab, m.tab)
  assert_eq(asked.sample, m.sample)
  let (kept, effects) = update(asked, KeepMine)
  assert_eq(effects, [])
  assert_eq(kept.incoming, None)
  assert_eq(kept.tab, m.tab)
  let (opened, effects) = update(asked, OpenIncoming)
  assert_eq(opened.incoming, None)
  assert_eq(opened.tab, TranscriptTab)
  assert_eq(effects.length(), 2)
  // With no question open, the buttons do nothing.
  assert_eq(update(m, OpenIncoming), (m, []))
}

///|
test "link: a link that cannot be read keeps the state of the page" {
  let m = answered()
  let (m, effects) = update(
    m,
    LinkOpened(opened=Refused("I could not open this link."), dirty=true),
  )
  assert_eq(effects, [])
  assert_eq(m.share, LinkIgnored("I could not open this link."))
  assert_eq(m.incoming, None)
  assert_eq(m.sample, 1)
  assert_eq(m.tab, ValidateTab)
  // An empty fragment changes nothing.
  assert_eq(update(m, LinkOpened(opened=Default, dirty=true)), (m, []))
}

///|
test "link: a transform that runs keeps the labels of its own run" {
  let m = answered()
  let (m, _) = update(m, RunClicked)
  assert_eq(m.tx, TxRunning)
  let running_output = m.tx_output
  let (m, _) = update(
    m,
    LinkOpened(opened=Shared({ ..shared_state(), output: Idl, }), dirty=false),
  )
  // The tab still shows the run, and the picker shows the output of the link.
  assert_eq(m.tx, TxRunning)
  assert_eq(m.tx_output, running_output)
  assert_eq(m.output, Idl)
  let (m, _) = update(
    m,
    Answered(
      seq=m.seq,
      answer=Transformed(files=["model.json"], warnings=[], service=None),
    ),
  )
  match m.tx {
    TxDone(output~, edits~, ..) => {
      // The old answer is labeled with its own output and marked old.
      assert_eq(output, running_output)
      assert_true(edits < m.edits)
    }
    _ => fail("I expected the answer of the run")
  }
}

///|
test "link: an Open clears a Run and a Step that waited for a request" {
  let m = answered()
  let (m, _) = update(m, Edited)
  let (m, _) = update(m, Debounced(edits=m.edits))
  assert_true(m.waiting)
  let (m, _) = update(m, RunClicked)
  assert_true(m.run_pending)
  assert_eq(m.tx, TxRunning)
  let m = { ..m, tr_pending: Some(StepAction), goal: ToEnd, }
  let (m, _) = update(m, LinkOpened(opened=Shared(shared_state()), dirty=false))
  assert_false(m.run_pending)
  assert_eq(m.tr_pending, None)
  assert_eq(m.goal, NoGoal)
  // No transform runs, so the tab is not left in the running state.
  assert_eq(m.tx, TxIdle)
}

///|
test "link: the first page and a later link make the same shared sample" {
  let (first, _) = Model::start_with(tr_data(), Shared(shared_state()))
  let (later, _) = update(
    answered(),
    LinkOpened(opened=Shared(shared_state()), dirty=false),
  )
  assert_eq(first.data.samples.last(), later.data.samples.last())
  assert_eq(first.data.transcripts.last(), later.data.transcripts.last())
  assert_eq(first.settings, later.settings)
}

///|
test "link: picking an example loads its text, which the page takes as unchanged" {
  // The page script keeps the loaded text as the text without changes.
  let m = answered()
  let (_, effects) = update(m, SampleChosen(0))
  assert_eq(effects, [LoadText("namespace a\n")])
}
