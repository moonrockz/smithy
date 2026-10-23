///|
/// Answers each message with `handler(message)`. The page sends a request
/// as a JSON string, and the Worker posts the response as a JSON string.
extern "js" fn on_message(handler : (String) -> String) -> Unit =
  #|(handler) => { self.onmessage = (event) => { self.postMessage(handler(event.data)) } }

///|
/// The Worker of the playground. One session holds the transcript state
/// for the life of the Worker.
fn main {
  let session = @core.Session::new()
  on_message(text => @core.handle_json(session, text))
}
