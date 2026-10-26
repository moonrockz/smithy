// The server of the HTTP and the WebSocket transports. One port serves
// `POST /rpc` (one Peer for each HTTP session) and `GET /ws` (one Peer for
// each WebSocket).

///|
/// A server that listens on a port of 127.0.0.1.
struct RpcServer {
  server : @http.Server
  sessions : Map[String, HttpSession]
  mut next_session : Int32
}

///|
/// Starts to listen on `port` of 127.0.0.1. Port 0 picks a free port; see
/// `RpcServer::port`.
pub async fn RpcServer::listen(port~ : Int32) -> RpcServer {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ =>
      raise TransportError("I expected a port from 0 to 65535, found \{port}.")
  }
  let server = @http.Server(addr, reuse_addr=true)
  { server, sessions: Map([]), next_session: 1, }
}

///|
/// The port that the server listens on.
pub fn RpcServer::port(self : RpcServer) -> Int32 {
  self.server.addr.port()
}

///|
/// Stops the server.
pub fn RpcServer::close(self : RpcServer) -> Unit {
  for _, session in self.sessions {
    Connection::close(session)
  }
  self.sessions.clear()
  self.server.close()
}

///|
/// The path of a request target, without the query.
fn target_path(path : String) -> String {
  match path.find("?") {
    Some(i) => path[:i].to_owned()
    None => path
  }
}

///|
/// Serves the connections until the server is closed. `on_peer` runs once
/// for each HTTP session and for each WebSocket, with its connection; it
/// usually runs a Peer on it.
pub async fn RpcServer::run(
  self : RpcServer,
  on_peer : async (&Connection) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let start_peer = (conn : &Connection) => {
      group.spawn_bg(allow_failure=true, () => {
        on_peer(conn) catch {
          err =>
            if !@async.is_being_cancelled() {
              diagnose("I stopped a peer of the server: \{err}")
            }
        }
      })
    }
    self.server.run_forever(allow_failure=true, (request, body, conn) => {
      match (request.meth, target_path(request.path)) {
        (Post, "/rpc") => self.handle_post(request, body, conn, start_peer)
        (Get, "/ws") => {
          let ws = @websocket.Conn::from_http_server(request, conn)
          let connection = WsConnection::wrap(ws)
          defer Connection::close(connection)
          on_peer(connection)
          Connection::shutdown(connection)
        }
        _ => {
          conn.skip_request_body()
          conn
          ..send_response(404, "Not Found")
          ..write("I serve POST /rpc and GET /ws, not \{request.path}.")
          .end_response()
        }
      }
    })
  })
}

///|
/// Answers one POST to `/rpc`.
async fn RpcServer::handle_post(
  self : RpcServer,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  start_peer : (&Connection) -> Unit,
) -> Unit {
  let text = body.read_all().text()
  let session = match
    request.headers.get(@http.CaseInsensitiveString(session_header)) {
    Some(id) =>
      match self.sessions.get(id) {
        Some(session) => session
        None => {
          conn
          ..send_response(404, "Not Found")
          ..write("I do not know the session \{id}.")
          .end_response()
          return
        }
      }
    None => {
      let id = "session-\{@async.now()}-\{self.next_session}"
      self.next_session += 1
      let session = HttpSession::new(id)
      self.sessions[id] = session
      start_peer(session)
      session
    }
  }
  let headers : @http.Headers = Map([])
  headers[@http.CaseInsensitiveString(session_header)] = session.id
  match classify_post(text) {
    Answer(reply) => {
      headers[@http.CaseInsensitiveString("Content-Type")] = "application/json"
      conn
      ..send_response(200, "OK", extra_headers=headers)
      ..write(write_json(reply))
      .end_response()
    }
    Accepted => {
      session.inbox.put(text)
      conn..send_response(202, "Accepted", extra_headers=headers).end_response()
    }
    Call(id) => {
      let events = session.open_stream(id)
      defer (if session.streams.get(id) is Some(open) &&
        physical_equal(open, events) {
        session.streams.remove(id)
      })
      session.inbox.put(text)
      headers[@http.CaseInsensitiveString("Content-Type")] = "text/event-stream"
      headers[@http.CaseInsensitiveString("Cache-Control")] = "no-cache"
      conn.send_response(200, "OK", extra_headers=headers)
      conn.write(": open\n\n")
      conn.flush()
      while events.get() is Some(message) {
        conn.write("event: message\ndata: \{message}\n\n")
        conn.flush()
      }
      conn.end_response()
    }
  }
}

///|
/// Serves `POST /rpc` and `GET /ws` on `port` of 127.0.0.1, and writes
/// `listening N` to stderr when it is ready, where N is the port. Port 0
/// picks a free port. `on_peer` runs once for each HTTP session and for each
/// WebSocket.
pub async fn serve(
  port~ : Int32,
  on_peer : async (&Connection) -> Unit,
) -> Unit {
  let server = RpcServer::listen(port~)
  defer server.close()
  diagnose("listening \{server.port()}")
  server.run(on_peer)
}
