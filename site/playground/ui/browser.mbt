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
/// The fragment of the address, without the `#`; "" when there is none.
extern "js" fn read_hash() -> String =
  #|() => location.hash.startsWith('#') ? location.hash.slice(1) : location.hash

///|
/// Put the fragment in the address bar with no new history entry, and give the
/// full URL of the page with it.
extern "js" fn write_hash(fragment : String) -> String =
  #|(fragment) => {
  #|  try { history.replaceState(null, '', '#' + fragment) } catch (e) {}
  #|  return location.origin + location.pathname + location.search + '#' + fragment
  #|}

///|
/// Call `f` when the fragment of the address changes with no page load: the
/// user opened another link in this tab, or used Back or Forward. A change
/// that the page makes with `history.replaceState` fires no event.
extern "js" fn on_hash_change(f : () -> Unit) -> Unit =
  #|(f) => { addEventListener('hashchange', () => f()) }

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
extern "js" fn editor_show(
  id : String,
  text : String,
  language : String,
) -> Unit =
  #|(id, text, language) => globalThis.smithyEditors.show(id, text, language)

///|
/// Put the text on the clipboard. `done` gets true when the clipboard took it.
/// A browser with no clipboard API gets false.
extern "js" fn copy_text(text : String, done : (Bool) -> Unit) -> Unit =
  #|(text, done) => {
  #|  if (!navigator.clipboard || !navigator.clipboard.writeText) { done(false); return }
  #|  navigator.clipboard.writeText(text).then(() => done(true), () => done(false))
  #|}

///|
/// Save the text as a file on the computer of the user. The text goes nowhere else.
extern "js" fn download_text(name : String, text : String) -> Unit =
  #|(name, text) => {
  #|  const type = name.endsWith('.json') ? 'application/json' : 'text/plain'
  #|  const url = URL.createObjectURL(new Blob([text], { type: type + ';charset=utf-8' }))
  #|  const link = document.createElement('a')
  #|  link.href = url
  #|  link.download = name
  #|  document.body.appendChild(link)
  #|  link.click()
  #|  link.remove()
  #|  setTimeout(() => URL.revokeObjectURL(url), 0)
  #|}

///|
extern "js" fn editor_language(id : String, language : String) -> Unit =
  #|(id, language) => globalThis.smithyEditors.language(id, language)

///|
extern "js" fn editor_follow(id : String, line : Int32) -> Unit =
  #|(id, line) => globalThis.smithyEditors.follow(id, line)

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

///|
/// The choice of "Group repeats" that the browser kept: on, unless it kept
/// "off". A browser that refuses storage gives the default.
extern "js" fn read_grouped() -> Bool =
  #|() => { try { return localStorage.getItem('smithy-playground-group-repeats') !== 'off' } catch (_) { return true } }

///|
extern "js" fn store_grouped(on : Bool) -> Unit =
  #|(on) => { try { localStorage.setItem('smithy-playground-group-repeats', on ? 'on' : 'off') } catch (_) {} }

///|
/// True when the reader has selected text on the page, for example by a drag
/// over a row of the Validate list. The click at the end of the drag then
/// does not move the cursor.
extern "js" fn has_selection() -> Bool =
  #|() => { const s = window.getSelection(); return !!s && !s.isCollapsed && s.toString() !== '' }

///|
/// The folds of the tabs that the browser kept, as `Folded::render` gives
/// them; empty when it kept none or refuses storage.
extern "js" fn read_folded() -> String =
  #|() => { try { return localStorage.getItem('smithy-playground-folded') ?? '' } catch (_) { return '' } }

///|
extern "js" fn store_folded(text : String) -> Unit =
  #|(text) => { try { localStorage.setItem('smithy-playground-folded', text) } catch (_) {} }
