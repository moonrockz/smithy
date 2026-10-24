///|
/// The tour data in the site data of the page, or "" when the page has none.
extern "js" fn read_tour_json() -> String =
  #|() => {
  #|  try {
  #|    const text = document.querySelector('meta[name="smithy-data"]')?.getAttribute('content') ?? ''
  #|    const data = JSON.parse(text).tour
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
/// Show the file `file` in the editor, with its own state (see `LoadEditor`).
extern "js" fn editor_load_file(
  id : String,
  text : String,
  file : String,
  fresh : Bool,
) -> Unit =
  #|(id, text, file, fresh) => globalThis.smithyEditors.load(id, text, file, fresh)

///|
extern "js" fn editor_show(
  id : String,
  text : String,
  language : String,
) -> Unit =
  #|(id, text, language) => globalThis.smithyEditors.show(id, text, language)

///|
extern "js" fn editor_mark(id : String, items : String) -> Unit =
  #|(id, items) => globalThis.smithyEditors.mark(id, items)

///|
/// Highlight the lines of `lines`, a JSON array of line numbers from 1. An
/// empty array removes the highlight.
extern "js" fn editor_highlight(id : String, lines : String) -> Unit =
  #|(id, lines) => globalThis.smithyEditors.highlight(id, lines)

///|
/// Make every editor measure its element again, after a change of layout.
extern "js" fn editors_measure() -> Unit =
  #|() => globalThis.smithyEditors.measure()

///|
/// The value of the key in localStorage, or "" when it has none. A browser
/// that refuses storage gives "".
extern "js" fn storage_read(key : String) -> String =
  #|(key) => { try { return localStorage.getItem(key) ?? '' } catch (_) { return '' } }

///|
extern "js" fn storage_write(key : String, value : String) -> Unit =
  #|(key, value) => { try { localStorage.setItem(key, value) } catch (_) {} }

///|
extern "js" fn storage_remove(key : String) -> Unit =
  #|(key) => { try { localStorage.removeItem(key) } catch (_) {} }

///|
extern "js" fn navigate(url : String) -> Unit =
  #|(url) => { location.href = url }

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
