package rpc

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"strings"
	"sync"
	"time"
)

const SessionHeader = "Smithy-Session-Id"
const HTTPPath = "/rpc"
const WebSocketPath = "/ws"
const maxMessageBytes = 1 << 20
const maxQueuedHTTPMessages = 32

// PeerFactory creates a peer and registers its handlers for one session.
type PeerFactory func() (*Peer, error)

type httpMessage struct {
	raw   []byte
	final bool
}
type httpExchange struct {
	order    uint64
	final    bool
	messages chan httpMessage
	done     chan struct{}
}
type httpSession struct {
	writeMu      sync.Mutex
	nextExchange uint64
	pending      []httpMessage
	peer         *Peer
	mu           sync.Mutex
	input        chan []byte
	done         chan struct{}
	exchanges    map[string]*httpExchange
	once         sync.Once
}

func newHTTPSession(peer *Peer) *httpSession {
	return &httpSession{peer: peer, input: make(chan []byte, 32), done: make(chan struct{}), exchanges: map[string]*httpExchange{}}
}
func (s *httpSession) ReadFrame(ctx context.Context) ([]byte, error) {
	select {
	case raw := <-s.input:
		return raw, nil
	case <-s.done:
		return nil, io.EOF
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
func (s *httpSession) WriteFrame(ctx context.Context, raw []byte) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(raw) > maxMessageBytes {
		return errors.New("I received an oversized HTTP message")
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	_, request := fields["method"]
	var id ID
	if request {
		id, _ = RequestID(ctx)
	} else {
		_ = json.Unmarshal(fields["id"], &id)
	}
	message := httpMessage{raw: append([]byte(nil), raw...), final: !request}
	s.mu.Lock()
	select {
	case <-s.done:
		s.mu.Unlock()
		return io.ErrClosedPipe
	default:
	}
	exchange := s.exchanges[id.key()]
	if request && (exchange == nil || exchange.final) {
		exchange = nil
		for _, candidate := range s.exchanges {
			if !candidate.final && (exchange == nil || candidate.order > exchange.order) {
				exchange = candidate
			}
		}
		if exchange == nil {
			if len(s.pending) >= maxQueuedHTTPMessages {
				s.mu.Unlock()
				return errors.New("I reached the queued HTTP message limit")
			}
			s.pending = append(s.pending, message)
			s.mu.Unlock()
			return nil
		}
	}
	if exchange == nil || exchange.final {
		s.mu.Unlock()
		return errors.New("I found no open HTTP request for the response")
	}
	if message.final {
		exchange.final = true
	}
	s.mu.Unlock()
	select {
	case exchange.messages <- message:
		return nil
	case <-exchange.done:
		return errors.New("I found a closed HTTP request")
	case <-s.done:
		return io.ErrClosedPipe
	case <-ctx.Done():
		return ctx.Err()
	}
}

// The new request stream receives queued messages before it enters dispatch.
func (s *httpSession) openExchange(id ID) (*httpExchange, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := id.key()
	if s.exchanges[key] != nil {
		return nil, false
	}
	s.nextExchange++
	exchange := &httpExchange{order: s.nextExchange, messages: make(chan httpMessage, maxQueuedHTTPMessages), done: make(chan struct{})}
	for _, message := range s.pending {
		exchange.messages <- message
	}
	s.pending = nil
	s.exchanges[key] = exchange
	return exchange, true
}
func (s *httpSession) Close() error {
	s.once.Do(func() { s.mu.Lock(); close(s.done); s.pending = nil; s.mu.Unlock() })
	return nil
}
func (s *httpSession) submit(ctx context.Context, raw []byte) error {
	select {
	case s.input <- raw:
		return nil
	case <-s.done:
		return io.ErrClosedPipe
	case <-ctx.Done():
		return ctx.Err()
	}
}

// HTTPServer keeps protocol state across Streamable HTTP POSTs.
// Close releases all sessions. Mount it at HTTPPath.
type HTTPServer struct {
	mu       sync.Mutex
	factory  PeerFactory
	sessions map[string]*httpSession
	closed   bool
	// MaxSessions bounds retained sessions. Zero uses 1024.
	MaxSessions int
}

func NewHTTPHandler(factory PeerFactory) *HTTPServer {
	return &HTTPServer{factory: factory, sessions: map[string]*httpSession{}}
}
func (h *HTTPServer) Close() error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.closed = true
	for id, session := range h.sessions {
		_ = session.Close()
		delete(h.sessions, id)
	}
	return nil
}
func (h *HTTPServer) session(id string) (string, *httpSession, int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return "", nil, http.StatusServiceUnavailable
	}
	if id != "" {
		session := h.sessions[id]
		if session == nil {
			return "", nil, http.StatusNotFound
		}
		return id, session, 0
	}
	limit := h.MaxSessions
	if limit == 0 {
		limit = 1024
	}
	if len(h.sessions) >= limit {
		return "", nil, http.StatusServiceUnavailable
	}
	if h.factory == nil {
		return "", nil, http.StatusInternalServerError
	}
	peer, err := h.factory()
	if err != nil || peer == nil {
		return "", nil, http.StatusInternalServerError
	}
	var token [24]byte
	if _, err := rand.Read(token[:]); err != nil {
		return "", nil, http.StatusInternalServerError
	}
	id = hex.EncodeToString(token[:])
	session := newHTTPSession(peer)
	h.sessions[id] = session
	go func() {
		_ = peer.Serve(context.Background(), session)
		_ = session.Close()
		h.mu.Lock()
		delete(h.sessions, id)
		h.mu.Unlock()
	}()
	return id, session, 0
}
func (h *HTTPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "I require POST for JSON-RPC", http.StatusMethodNotAllowed)
		return
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		http.Error(w, "I require application/json", http.StatusUnsupportedMediaType)
		return
	}
	accept := r.Header.Get("Accept")
	if accept != "" && !strings.Contains(accept, "text/event-stream") && !strings.Contains(accept, "application/json") && !strings.Contains(accept, "*/*") {
		http.Error(w, "I require a JSON or SSE response type", http.StatusNotAcceptable)
		return
	}
	id, session, status := h.session(r.Header.Get(SessionHeader))
	if status != 0 {
		http.Error(w, "I cannot find or create the session", status)
		return
	}
	w.Header().Set(SessionHeader, id)
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxMessageBytes))
	if err != nil {
		http.Error(w, "I cannot read the JSON-RPC message", http.StatusRequestEntityTooLarge)
		return
	}
	fields, problem := envelope(raw)
	if problem != nil {
		session.rejectHTTP(w, raw, ID{}, problem)
		return
	}
	_, request := fields["method"]
	idRaw, hasID := fields["id"]
	if !request || !hasID {
		if session.submit(r.Context(), raw) != nil {
			http.Error(w, "I cannot deliver the message", http.StatusGone)
			return
		}
		w.WriteHeader(http.StatusAccepted)
		return
	}
	var requestID ID
	if json.Unmarshal(idRaw, &requestID) != nil {
		session.rejectHTTP(w, raw, ID{}, NewError(-32600, "I require a string or integer request ID", nil))
		return
	}
	key := requestID.key()
	exchange, opened := session.openExchange(requestID)
	if !opened {
		session.rejectHTTP(w, raw, requestID, NewError(-32600, "I found an active RPC request with this ID", nil))
		return
	}
	defer func() { session.mu.Lock(); delete(session.exchanges, key); session.mu.Unlock(); close(exchange.done) }()
	if err := session.submit(r.Context(), raw); err != nil {
		http.Error(w, "I cannot deliver the request", http.StatusGone)
		return
	}
	flusher, canFlush := w.(http.Flusher)
	if !canFlush {
		http.Error(w, "I cannot stream the response", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if _, err := io.WriteString(w, ": open\n\n"); err != nil {
		return
	}
	flusher.Flush()
	for {
		select {
		case message := <-exchange.messages:
			if _, err := fmt.Fprintf(w, "event: message\ndata: %s\n\n", message.raw); err != nil {
				return
			}
			flusher.Flush()
			if message.final {
				return
			}
		case <-r.Context().Done():
			return
		case <-session.done:
			return
		}
	}
}

type httpInboundFrame struct {
	raw       []byte
	processed chan struct{}
}

// HTTPTransport posts each outgoing message and reads JSON or SSE responses.
type HTTPTransport struct {
	readAck   chan struct{}
	failure   error
	mu        sync.Mutex
	first     sync.Mutex
	client    *http.Client
	endpoint  string
	sessionID string
	input     chan httpInboundFrame
	done      chan struct{}
	once      sync.Once
	ctx       context.Context
	cancel    context.CancelFunc
}

func NewHTTPTransport(endpoint string, client *http.Client) *HTTPTransport {
	if client == nil {
		client = http.DefaultClient
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &HTTPTransport{client: client, endpoint: endpoint, input: make(chan httpInboundFrame, 32), done: make(chan struct{}), ctx: ctx, cancel: cancel}
}
func (t *HTTPTransport) SessionID() string { t.mu.Lock(); defer t.mu.Unlock(); return t.sessionID }
func (t *HTTPTransport) ReadFrame(ctx context.Context) ([]byte, error) {
	// Reaching the next read proves the dispatcher processed the last frame.
	// Invalid requests, including batches, are answered before this point.
	t.mu.Lock()
	if t.readAck != nil {
		close(t.readAck)
		t.readAck = nil
	}
	t.mu.Unlock()
	select {
	case frame := <-t.input:
		t.mu.Lock()
		t.readAck = frame.processed
		t.mu.Unlock()
		return frame.raw, nil
	case <-t.done:
		t.mu.Lock()
		failure := t.failure
		t.mu.Unlock()
		if failure != nil {
			return nil, failure
		}
		return nil, io.EOF
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
func (t *HTTPTransport) Close() error { t.once.Do(func() { t.cancel(); close(t.done) }); return nil }
func (t *HTTPTransport) WriteFrame(ctx context.Context, raw []byte) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	var expected ID
	if _, request := fields["method"]; request {
		if id, call := fields["id"]; call {
			if err := json.Unmarshal(id, &expected); err != nil {
				return err
			}
		}
	}
	t.first.Lock()
	t.mu.Lock()
	session := t.sessionID
	t.mu.Unlock()
	if session != "" {
		t.first.Unlock()
	}
	// The transport context keeps an SSE call alive after its caller cancels.
	requestCtx, cancelRequest := context.WithCancel(t.ctx)
	stopCancel := context.AfterFunc(ctx, cancelRequest)
	request, err := http.NewRequestWithContext(requestCtx, http.MethodPost, t.endpoint, bytes.NewReader(raw))
	if err != nil {
		stopCancel()
		cancelRequest()
		if session == "" {
			t.first.Unlock()
		}
		return err
	}
	if err := ctx.Err(); err != nil {
		stopCancel()
		cancelRequest()
		if session == "" {
			t.first.Unlock()
		}
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	if session != "" {
		request.Header.Set(SessionHeader, session)
	}
	response, err := t.client.Do(request)
	stopCancel()
	if err != nil {
		stopCancel()
		cancelRequest()
		if session == "" {
			t.first.Unlock()
		}
		return err
	}
	next := response.Header.Get(SessionHeader)
	t.mu.Lock()
	if next != "" {
		t.sessionID = next
	}
	t.mu.Unlock()
	if session == "" {
		t.first.Unlock()
	}
	if response.StatusCode == http.StatusAccepted {
		defer cancelRequest()
		_ = response.Body.Close()
		if expected.IsValid() {
			err := missingHTTPReply(expected)
			t.fail(err)
			return err
		}
		return nil
	}
	if response.StatusCode != http.StatusOK {
		defer cancelRequest()
		_ = response.Body.Close()
		return fmt.Errorf("I received HTTP status %d", response.StatusCode)
	}
	go func() {
		defer cancelRequest()
		defer response.Body.Close()
		if err := t.readResponse(response, expected); err != nil {
			t.fail(err)
		}
	}()
	return nil
}
func (t *HTTPTransport) fail(err error) {
	t.mu.Lock()
	if t.failure == nil {
		t.failure = err
	}
	t.mu.Unlock()
	_ = t.Close()
}
func (t *HTTPTransport) deliver(raw []byte) (<-chan struct{}, error) {
	frame := httpInboundFrame{raw: append([]byte(nil), raw...), processed: make(chan struct{})}
	select {
	case t.input <- frame:
		return frame.processed, nil
	case <-t.done:
		return nil, io.ErrClosedPipe
	}
}
func (t *HTTPTransport) readResponse(response *http.Response, expected ID) error {
	var processed <-chan struct{}
	deliver := func(raw []byte) error {
		var err error
		processed, err = t.deliver(raw)
		return err
	}
	incomplete := func() error {
		if processed != nil {
			// A peer can withhold headers for a rejection POST. It must not keep
			// the original call pending after its response stream has ended.
			timer := time.NewTimer(5 * time.Second)
			defer timer.Stop()
			select {
			case <-processed:
			case <-t.done:
				return io.ErrClosedPipe
			case <-timer.C:
			}
		}
		return missingHTTPReply(expected)
	}
	media, _, err := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if err != nil {
		return err
	}
	if media == "application/json" {
		raw, err := io.ReadAll(io.LimitReader(response.Body, maxMessageBytes+1))
		if err != nil {
			return err
		}
		if len(raw) > maxMessageBytes {
			return errors.New("I received an oversized JSON message")
		}
		if err := deliver(raw); err != nil {
			return err
		}
		if !finalHTTPReply(raw, expected) {
			return incomplete()
		}
		return nil
	}
	if media != "text/event-stream" {
		return errors.New("I received an unsupported response type")
	}
	scanner := bufio.NewScanner(response.Body)
	// The line limit includes the data field prefix and CRLF framing.
	scanner.Buffer(make([]byte, 4096), maxMessageBytes+len("data: ")+len("\r\n"))
	var data []byte
	hasData := false
	final := false
	flush := func() error {
		if !hasData {
			return nil
		}
		raw := data
		data = nil
		hasData = false
		final = finalHTTPReply(raw, expected)
		fields, problem := envelope(raw)
		if problem == nil {
			if _, request := fields["method"]; !request && !final {
				return missingHTTPReply(expected)
			}
		}
		return deliver(raw)
	}
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			if err := flush(); err != nil {
				return err
			}
			if final {
				return nil
			}
			continue
		}
		if strings.HasPrefix(line, "data:") {
			value := strings.TrimPrefix(line, "data:")
			value = strings.TrimPrefix(value, " ")
			additional := len(value)
			if hasData {
				additional++
			}
			if additional > maxMessageBytes-len(data) {
				return errors.New("I received an oversized SSE message")
			}
			if hasData {
				data = append(data, '\n')
			}
			data = append(data, value...)
			hasData = true
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	if err := flush(); err != nil {
		return err
	}
	if final {
		return nil
	}
	return incomplete()
}

func finalHTTPReply(raw []byte, expected ID) bool {
	if !expected.IsValid() {
		return false
	}
	fields, problem := envelope(raw)
	if problem != nil {
		return false
	}
	if _, request := fields["method"]; request {
		return false
	}
	var id ID
	return json.Unmarshal(fields["id"], &id) == nil && id.key() == expected.key()
}
func missingHTTPReply(id ID) error {
	return fmt.Errorf("I expected the final HTTP response for request %s", id.String())
}

// Adapter-level rejections keep the same JSONL record shape as dispatch.
func (s *httpSession) rejectHTTP(w http.ResponseWriter, received []byte, id ID, problem *Error) {
	raw, _ := json.Marshal(struct {
		Version string `json:"jsonrpc"`
		ID      ID     `json:"id"`
		Error   *Error `json:"error"`
	}{"2.0", id, problem})
	if err := s.peer.log("recv", received); err != nil {
		http.Error(w, "I could not write the RPC log", http.StatusInternalServerError)
		return
	}
	if err := s.peer.log("send", raw); err != nil {
		http.Error(w, "I could not write the RPC log", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write(raw)
}
