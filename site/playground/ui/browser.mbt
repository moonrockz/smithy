///|
/// The playground data in the site data of the page, or "" when the page has none.
extern "js" fn read_playground_json() -> String =
  #|() => {
  #|  try {
  #|    const text = document.querySelector('meta[name="smithy-data"]')?.getAttribute('content') ?? ''
  #|    const data = JSON.parse(text).playground
  #|    return data ? JSON.stringify(data) : ''
  #|  } catch (e) {
  #|    return ''
  #|  }
  #|}

///|
extern "js" fn set_timeout(ms : Int32, f : () -> Unit) -> Unit =
  #|(ms, f) => { setTimeout(f, ms) }

///|
extern "js" fn editor_create(
  id : String,
  text : String,
  language : String,
  read_only : Bool,
  on_change : () -> Unit,
  on_cursor : (Int32, Int32) -> Unit,
) -> Unit =
  #|(id, text, language, readOnly, onChange, onCursor) =>
  #|  globalThis.smithyEditors.create(id, text, language, readOnly, onChange, onCursor)

///|
extern "js" fn editor_text(id : String) -> String =
  #|(id) => globalThis.smithyEditors.text(id)

///|
extern "js" fn editor_load(id : String, text : String) -> Unit =
  #|(id, text) => globalThis.smithyEditors.load(id, text)

///|
extern "js" fn editor_mark(id : String, items : String) -> Unit =
  #|(id, items) => globalThis.smithyEditors.mark(id, items)

///|
extern "js" fn editor_go_to(id : String, line : Int32, column : Int32) -> Unit =
  #|(id, line, column) => globalThis.smithyEditors.goTo(id, line, column)

///|
/// A Web Worker that runs the Smithy library.
#external
type Worker

///|
/// Start the Worker script at `url`; `on_reply` gets each message it posts,
/// and `on_error` the message of an error that stops it: a script that does
/// not load, or a trap in the library.
extern "js" fn Worker::start(
  url : String,
  on_reply : (String) -> Unit,
  on_error : (String) -> Unit,
) -> Worker =
  #|(url, onReply, onError) => {
  #|  const worker = new Worker(url)
  #|  worker.onmessage = (event) => onReply(event.data)
  #|  worker.onerror = (event) => {
  #|    event.preventDefault()
  #|    onError(event.message ?? '')
  #|  }
  #|  return worker
  #|}

///|
extern "js" fn Worker::post(self : Worker, text : String) -> Unit =
  #|(worker, text) => worker.postMessage(text)

///|
extern "js" fn Worker::stop(self : Worker) -> Unit =
  #|(worker) => worker.terminate()
