///|
/// The Worker and the page messages. The page has one of each.
priv struct Runtime {
  data : @workbench.PlaygroundData
  mut worker : Worker?
  /// The files of each transform that the Worker answered, as (name, text), by request number.
  /// The model holds the names only, and accepts an answer or drops it. An effect names the
  /// request, so an answer that the model dropped is never shown, and `ShowFile` drops the files
  /// of every other request.
  files : Map[Int32, Array[(String, String)]]
  mut dispatch : (@workbench.Msg) -> Unit
}

///|
fn diagnostic_of(d : @core.Diagnostic) -> @workbench.Diagnostic {
  {
    severity: d.severity,
    code: d.code,
    message: d.message,
    file: d.file,
    start_line: d.start_line,
    start_column: d.start_column,
    end_line: d.end_line,
    end_column: d.end_column,
    shape: d.shape,
  }
}

///|
fn mark_json(items : Array[@workbench.Diagnostic]) -> String {
  let out : Array[Json] = items.map(d => {
    "severity": Json(d.severity),
    "code": Json(d.code),
    "message": Json(d.message),
    "start_line": Json(d.start_line),
    "start_column": Json(d.start_column),
    "end_line": Json(d.end_line),
    "end_column": Json(d.end_column),
  })
  Json::array(out).stringify()
}

///|
/// The state of a link for the editors and these settings.
fn share_state_of(
  tab : @samples.Tab,
  output : @samples.Output,
  selector : String,
  settings : @workbench.Settings,
) -> @core.ShareState {
  {
    model: editor_text(@workbench.EDITOR_ID),
    transcript: editor_text(@workbench.TRANSCRIPT_ID),
    tab,
    output,
    protocol: settings.protocol,
    format: settings.format,
    complete: settings.complete,
    selector: Some(selector),
    log_preset: Some(settings.preset),
    version: if settings.version == "" {
      None
    } else {
      Some(settings.version)
    },
  }
}

///|
/// How the page opens for the fragment of its address. A fragment that the
/// page cannot read gives the reason, and the page opens with its default
/// example.
fn opened_by(fragment : String) -> @workbench.Opened {
  if fragment == "" {
    return Default
  }
  match @core.decode_share(fragment) {
    Ok(state) => Shared(state)
    Err(reason) => Refused("I could not open this link. " + reason)
  }
}

///|
/// The file extension of a transcript format.
fn transcript_extension(format : @samples.TranscriptFormat) -> String {
  match format {
    Markdown => "md"
    Json => "json"
    Jsonl => "jsonl"
  }
}

///|
/// The language of the transcript editor. A log has one JSON value on each
/// line, and other lines, so it is plain text.
fn transcript_language(format : @samples.TranscriptFormat) -> String {
  match format {
    Markdown => "markdown"
    Json => "json"
    Jsonl => "plain"
  }
}

///|
fn entry_of(e : @core.EntryView) -> @workbench.Entry {
  {
    index: e.index,
    sender: e.sender,
    receiver: e.receiver,
    message: e.message,
    line: e.line,
    column: e.column,
  }
}

///|
fn finding_of(f : @core.FindingView) -> @workbench.Finding {
  {
    code: f.code,
    severity: f.severity,
    message: f.message,
    entry: f.entry,
    line: f.line,
    column: f.column,
    sender: f.sender,
    related: f.related,
    path: f.path,
    shape: f.shape,
    operation: f.operation,
  }
}

///|
fn summary_of(s : @core.SummaryView) -> @workbench.Summary {
  {
    valid: s.valid,
    complete: s.complete,
    entries: s.entries,
    errors: s.errors,
    outstanding: s.outstanding,
    correlation: s.correlation,
    lines: s.lines,
    not_json: s.not_json,
    skipped: s.skipped,
    expectations: s.expectations.map(e => {
      matched: e.matched,
      missing: e.missing.map(x => {
        code: x.code,
        entry: x.entry,
        related: x.related,
      }),
      unexpected: e.unexpected.map(finding_of),
    }),
  }
}

///|
/// The language of the output editor for a file.
fn language_of(name : String) -> String {
  if name.has_suffix(".json") {
    "json"
  } else if name.has_suffix(".smithy") {
    "smithy"
  } else {
    "plain"
  }
}

///|
/// The message for a reply of the Worker. A reply that does not decode gives
/// `None`. The files of a transform stay in `runtime`.
fn Runtime::reply_msg(self : Runtime, text : String) -> @workbench.Msg? {
  let response : @core.Response = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  match response {
    Diagnostics(seq~, items~, shapes~, protocols~) =>
      Some(
        Answered(
          seq~,
          answer=Validated(
            items=items.map(diagnostic_of),
            shapes~,
            protocols=protocols.map(p => {
              id: p.id,
              versions: p.versions,
              peers: p.peers,
            }),
          ),
        ),
      )
    Blocked(seq~, reason~, kind~) =>
      Some(
        Answered(
          seq~,
          answer=NotRun(
            reason,
            match kind {
              ModelErrors => ModelErrors
              Other => Other
            },
          ),
        ),
      )
    Transformed(seq~, files~, warnings~, service~) => {
      self.files[seq] = files
      Some(
        Answered(
          seq~,
          answer=Transformed(
            files=files.map(file => file.0),
            warnings~,
            service~,
          ),
        ),
      )
    }
    TranscriptProgress(seq~, entries~, findings~, checked~, done~, summary~) =>
      Some(
        Answered(
          seq~,
          answer=Progressed(
            entries=entries.map(entry_of),
            findings=findings.map(finding_of),
            checked~,
            done~,
            summary=summary.map(summary_of),
          ),
        ),
      )
  }
}

///|
fn Runtime::start_worker(self : Runtime) -> Unit {
  self.worker = Some(
    Worker::start(
      self.data.worker,
      text => if self.reply_msg(text) is Some(msg) { (self.dispatch)(msg) },
      message => (self.dispatch)(WorkerFailed(message)),
    ),
  )
}

///|
fn Runtime::file(
  self : Runtime,
  seq : Int32,
  index : Int32,
) -> (String, String)? {
  self.files.get(seq).bind(files => files.get(index))
}

///|
fn Runtime::post(self : Runtime, request : @core.Request) -> Unit {
  if self.worker is Some(worker) {
    worker.post(@json.to_json(request).stringify())
  }
}

///|
fn Runtime::run(self : Runtime, effect : @workbench.Effect) -> Unit {
  match effect {
    Wait(ms~, then~) => set_timeout(ms, () => (self.dispatch)(then))
    SendValidate(seq~) => {
      let request = @core.Validate(
        seq~,
        model=editor_text(@workbench.EDITOR_ID),
      )
      if self.worker is Some(worker) {
        worker.post(@json.to_json(request).stringify())
      }
    }
    SendTransform(seq~, output~, selector~) => {
      let request = @core.Transform(
        seq~,
        model=editor_text(@workbench.EDITOR_ID),
        output~,
        selector~,
      )
      if self.worker is Some(worker) {
        worker.post(@json.to_json(request).stringify())
      }
    }
    ShowFile(seq~, index~) => {
      for key in self.files.keys().collect() {
        if key != seq {
          self.files.remove(key)
        }
      }
      if self.file(seq, index) is Some((name, text)) {
        editor_show(@workbench.OUTPUT_ID, text, language_of(name))
      }
    }
    CopyFile(seq~, index~) =>
      if self.file(seq, index) is Some((_, text)) {
        copy_text(text, ok => (self.dispatch)(CopyDone(ok)))
      }
    DownloadFile(seq~, index~) =>
      if self.file(seq, index) is Some((name, text)) {
        download_text(name, text)
      }
    MakeShare(tab~, output~, selector~, settings~) => {
      let state = share_state_of(tab, output, selector, settings)
      if @core.share_state_problem(state) is Some(reason) {
        (self.dispatch)(ShareDone(LinkTooLong(reason)))
        return
      }
      let fragment = @core.encode_share(state)
      if @core.share_length_problem(fragment) is Some(reason) {
        (self.dispatch)(ShareDone(LinkTooLong(reason)))
        return
      }
      let url = write_hash(fragment)
      copy_text(url, ok => {
        (self.dispatch)(
          ShareDone(if ok { LinkCopied(url) } else { LinkShown(url) }),
        )
      })
    }
    SaveFiles(transcript~) => {
      download_text("model.smithy", editor_text(@workbench.EDITOR_ID))
      if transcript is Some(format) {
        download_text(
          "transcript." + transcript_extension(format),
          editor_text(@workbench.TRANSCRIPT_ID),
        )
      }
    }
    LoadText(text) => editor_load(@workbench.EDITOR_ID, text)
    Mark(items) => editor_mark(@workbench.EDITOR_ID, mark_json(items))
    MoveCursor(line~, column~) =>
      editor_go_to(@workbench.EDITOR_ID, line, column)
    SendTranscriptStart(seq~, settings~) =>
      self.post(
        TranscriptStart(
          seq~,
          model=editor_text(@workbench.EDITOR_ID),
          protocol=settings.protocol,
          format=settings.format,
          complete=settings.complete,
          log_preset=settings.request_preset(),
          version=settings.request_version(),
          text=editor_text(@workbench.TRANSCRIPT_ID),
        ),
      )
    SendTranscriptStep(seq~, count~) => self.post(TranscriptStep(seq~, count~))
    SendTranscriptReset(seq~) => self.post(TranscriptReset(seq~))
    LoadTranscript(text~, format~) =>
      editor_show(@workbench.TRANSCRIPT_ID, text, transcript_language(format))
    SetTranscriptLanguage(format) =>
      editor_language(@workbench.TRANSCRIPT_ID, transcript_language(format))
    FollowTranscript(line~) => editor_follow(@workbench.TRANSCRIPT_ID, line)
    GoToTranscript(line~, column~) =>
      editor_go_to(@workbench.TRANSCRIPT_ID, line, column)
    RestartWorker => {
      if self.worker is Some(worker) {
        worker.stop()
      }
      self.start_worker()
    }
  }
}

///|
/// A command that runs `effects` in order, with `emit` for the messages that
/// they send later.
fn Runtime::perform(
  self : Runtime,
  effects : Array[@workbench.Effect],
  emit : @rabbita.Emit[@workbench.Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    self.dispatch = msg => scheduler.add((emit.0)(msg))
    for effect in effects {
      self.run(effect)
    }
  })
}

///|
fn app(
  data : @workbench.PlaygroundData,
  opened : @workbench.Opened,
) -> @rabbita.Val[@rabbita.Html] {
  let runtime = { data, worker: None, files: {}, dispatch: _ => (), }
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let (m, effects) = @workbench.Model::start_with(data, opened)
      let start = @cmd.custom_cmd(scheduler => {
        runtime.dispatch = msg => scheduler.add((emit.0)(msg))
        editor_create(
          @workbench.EDITOR_ID,
          m.first_text(),
          "smithy",
          false,
          () => (runtime.dispatch)(Edited),
          (line, column) => (runtime.dispatch)(CursorMoved(line~, column~)),
        )
        editor_create(@workbench.OUTPUT_ID, "", "json", true, () => (), (_, _) => {
          ()
        })
        let (transcript, format) = m.first_transcript()
        editor_create(
          @workbench.TRANSCRIPT_ID,
          transcript,
          transcript_language(format),
          false,
          () => (runtime.dispatch)(TranscriptEdited),
          (_, _) => (),
        )
        runtime.start_worker()
        for effect in effects {
          runtime.run(effect)
        }
      })
      (m, start)
    },
    update=(m, msg, emit) => {
      let (next, effects) = @workbench.update(m, msg)
      if effects.is_empty() {
        (next, @rabbita.none)
      } else {
        (next, runtime.perform(effects, emit))
      }
    },
  )
  model.map(m => @workbench.view(m, emit))
}

///|
/// The playground script. The page is pre-rendered with an empty workbench
/// in the element with id `APP_ID`; this mounts the live workbench there.
fn main {
  let text = read_playground_json()
  guard text != "" else { return }
  let data : @workbench.PlaygroundData = @json.from_json(@json.parse(text)) catch {
    _ => return
  }
  reload_on_hash_change()
  @rabbita.new(() => app(data, opened_by(read_hash()))).mount(@workbench.APP_ID)
}
