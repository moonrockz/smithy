///|
/// The Worker and the page messages. The page has one of each.
priv struct Runtime {
  data : @workbench.PlaygroundData
  mut worker : Worker?
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
/// The message for a reply of the Worker. A reply that is not for the
/// Validate tab, or that does not decode, gives `None`.
fn reply_msg(text : String) -> @workbench.Msg? {
  let response : @core.Response = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  match response {
    Diagnostics(seq~, items~, shapes~) =>
      Some(
        Answered(
          seq~,
          answer=Validated(items=items.map(diagnostic_of), shapes~),
        ),
      )
    Blocked(seq~, reason~) => Some(Answered(seq~, answer=NotRun(reason)))
    Transformed(..) | TranscriptProgress(..) => None
  }
}

///|
fn Runtime::start_worker(self : Runtime) -> Unit {
  self.worker = Some(
    Worker::start(
      self.data.worker,
      text => if reply_msg(text) is Some(msg) { (self.dispatch)(msg) },
      message => (self.dispatch)(WorkerFailed(message)),
    ),
  )
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
    LoadText(text) => editor_load(@workbench.EDITOR_ID, text)
    Mark(items) => editor_mark(@workbench.EDITOR_ID, mark_json(items))
    MoveCursor(line~, column~) =>
      editor_go_to(@workbench.EDITOR_ID, line, column)
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
fn app(data : @workbench.PlaygroundData) -> @rabbita.Val[@rabbita.Html] {
  let runtime = { data, worker: None, dispatch: _ => (), }
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let (m, effects) = @workbench.Model::start(data)
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
  @rabbita.new(() => app(data)).mount(@workbench.APP_ID)
}
