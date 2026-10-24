///|
/// The text of the Findings and the output tabs after an answer that the page
/// cannot read: the Worker comes from another build of the site.
let mismatch_text : String = "I could not read the answer of the checker, because the page and the checker come from different builds of the site. Reload the page."

///|
/// The text of the Findings and the output tabs after an error that stopped
/// the Worker.
fn stopped_text(message : String) -> String {
  if message == "" {
    "The checker stopped. Edit the model to try again."
  } else {
    "The checker stopped: \{message}. Edit the model to try again."
  }
}

///|
/// The Worker and the page messages. The page has one of each.
priv struct Runtime {
  page : @model.LessonPage
  /// `None` before the start and after an error that stopped the Worker. The
  /// next request starts a new one.
  mut worker : Worker?
  /// The number of the newest Worker. Each start gives a new one, so an
  /// error or a reply of a Worker that the page replaced changes nothing.
  mut number : Int32
  mut dispatch : (@lesson.Msg) -> Unit
  /// The number of the newest request that the page sent.
  mut seq : Int32
}

///|
/// The language of the output editor for the output of the lesson.
fn output_language(output : @samples.Output?) -> String {
  match output {
    Some(Idl) => "smithy"
    Some(Selector) | None => "plain"
    Some(JsonAst | JsonSchema | OpenApi30 | OpenApi31 | OpenRpc) => "json"
  }
}

///|
fn mark_json(items : Array[@core.Diagnostic]) -> String {
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
fn lines_json(lines : Array[Int32]) -> String {
  Json::array(lines.map(line => Json(line))).stringify()
}

///|
/// The message for a reply of the Worker. `newest` is the number of the newest
/// request. A reply that does not decode, and the `Blocked` with `seq` -1 that
/// the Worker gives for a request that it could not read, come from a Worker
/// of another build: they answer the newest request with `mismatch_text`.
fn reply_msg(text : String, newest : Int32) -> @lesson.Msg {
  let mismatch = @lesson.Answered(
    seq=newest,
    answer=NotConverted(mismatch_text),
  )
  let response : @core.Response = @json.from_json(@json.parse(text)) catch {
    _ => return mismatch
  }
  match response {
    Blocked(seq=-1, ..) => mismatch
    Diagnostics(seq~, items~, ..) => Answered(seq~, answer=Checked(items))
    Transformed(seq~, files~, ..) =>
      Answered(seq~, answer=Converted(@model.output_text(files)))
    Blocked(seq~, reason~, ..) => Answered(seq~, answer=NotConverted(reason))
    // The page sends no transcript, value check, message check or diff
    // request.
    TranscriptProgress(..) | DataChecked(..) | Diffed(..) => mismatch
  }
}

///|
/// A reply of the Worker with this number.
fn Runtime::worker_replied(
  self : Runtime,
  number : Int32,
  text : String,
) -> Unit {
  if number == self.number {
    (self.dispatch)(reply_msg(text, self.seq))
  }
}

///|
/// An error stopped the Worker with this number. A Worker that does not load
/// would fail again at once, so the page starts a new one at the next request
/// only.
fn Runtime::worker_failed(
  self : Runtime,
  number : Int32,
  message : String,
) -> Unit {
  guard number == self.number else { return }
  if self.worker is Some(worker) {
    worker.stop()
  }
  self.worker = None
  (self.dispatch)(
    Answered(seq=self.seq, answer=NotConverted(stopped_text(message))),
  )
}

///|
fn Runtime::start_worker(self : Runtime) -> Worker {
  self.number = self.number + 1
  let number = self.number
  let worker = Worker::start(
    self.page.worker,
    text => self.worker_replied(number, text),
    message => self.worker_failed(number, message),
  )
  self.worker = Some(worker)
  worker
}

///|
fn Runtime::post(self : Runtime, seq : Int32, request : @core.Request) -> Unit {
  self.seq = seq
  let worker = match self.worker {
    Some(worker) => worker
    None => self.start_worker()
  }
  worker.post(@json.to_json(request).stringify())
}

///|
fn Runtime::run(self : Runtime, effect : @lesson.Effect) -> Unit {
  match effect {
    SendValidate(seq~, files~) =>
      self.post(
        seq,
        @core.lesson_validate(seq~, files~, output=self.page.output),
      )
    SendTransform(seq~, files~, output~, selector~) =>
      self.post(seq, TransformFiles(seq~, files~, output~, selector~))
    Wait(ms~, msg~) => set_timeout(ms, () => (self.dispatch)(msg))
    LoadEditor(text~, file~, fresh~) => {
      editor_load_file(@lesson.EDITOR_ID, text, file, fresh)
      // The marks belong to the text before: a `Mark` follows with the
      // findings of this text.
      editor_mark(@lesson.EDITOR_ID, "[]")
    }
    ShowOutput(text~, highlight~) => {
      editor_show(@lesson.OUTPUT_ID, text, output_language(self.page.output))
      editor_highlight(@lesson.OUTPUT_ID, lines_json(highlight))
    }
    Mark(items~) => editor_mark(@lesson.EDITOR_ID, mark_json(items))
    Store(key~, value~) => storage_write(key, value)
    Clear(key~) => storage_remove(key)
    Navigate(url~) => navigate(url)
    Remeasure => editors_measure()
    RestartWorker => {
      if self.worker is Some(worker) {
        worker.stop()
      }
      self.worker = None
      ignore(self.start_worker())
    }
  }
}

///|
/// A command that runs `effects` in order, with `emit` for the messages that
/// they send later.
fn Runtime::perform(
  self : Runtime,
  effects : Array[@lesson.Effect],
  emit : @rabbita.Emit[@lesson.Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    self.dispatch = msg => scheduler.add((emit.0)(msg))
    for effect in effects {
      self.run(effect)
    }
  })
}

///|
fn app(page : @model.LessonPage) -> @rabbita.Val[@rabbita.Html] {
  let runtime = { page, worker: None, number: 0, dispatch: _ => (), seq: 0, }
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let stored = match storage_read(page.storage_key) {
        "" => None
        value => Some(value)
      }
      let (m, effects) = @lesson.Model::start(page, stored)
      let start = @cmd.custom_cmd(scheduler => {
        runtime.dispatch = msg => scheduler.add((emit.0)(msg))
        editor_create(
          @lesson.EDITOR_ID,
          m.selected_text(),
          "smithy",
          false,
          () => (runtime.dispatch)(Edited(editor_text(@lesson.EDITOR_ID))),
          (_, _) => (),
        )
        editor_create(
          @lesson.OUTPUT_ID,
          "",
          output_language(page.output),
          true,
          () => (),
          (_, _) => (),
        )
        ignore(runtime.start_worker())
        for effect in effects {
          runtime.run(effect)
        }
      })
      (m, start)
    },
    update=(m, msg, emit) => {
      let (next, effects) = @lesson.update(m, msg)
      if effects.is_empty() {
        (next, @rabbita.none)
      } else {
        (next, runtime.perform(effects, emit))
      }
    },
  )
  model.map(m => @lesson.view(m, emit))
}

///|
/// The tour script. The page is pre-rendered with the lesson text and empty
/// panes; this mounts the live lesson component in the element with id
/// `APP_ID`.
fn main {
  let text = read_tour_json()
  guard text != "" else { return }
  let tour : @model.TourPage = @json.from_json(@json.parse(text)) catch {
    _ => return
  }
  guard tour is Page(page) else { return }
  @rabbita.new(() => app(page)).mount(@lesson.APP_ID)
}
