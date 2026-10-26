package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func transportServer(t *testing.T) PeerFactory {
	return func() (*Peer, error) {
		p, err := NewPeer(testContract(), "server", Options{})
		if err != nil {
			return nil, err
		}
		register(t, p, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
		register(t, p, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
			id, _ := RequestID(ctx)
			if err := p.Notify(ctx, "progress", map[string]any{"requestId": id}); err != nil {
				return nil, err
			}
			var result bool
			if err := p.Call(ctx, "confirm", struct{}{}, &result); err != nil {
				return nil, err
			}
			return result, nil
		})
		return p, nil
	}
}
func TestHTTPAndWebSocketCallbacks(t *testing.T) {
	for _, kind := range []string{"http", "websocket"} {
		t.Run(kind, func(t *testing.T) {
			handler := NewHTTPHandler(transportServer(t))
			defer handler.Close()
			mux := http.NewServeMux()
			mux.Handle(HTTPPath, handler)
			mux.Handle(WebSocketPath, NewWebSocketHandler(transportServer(t)))
			server := httptest.NewServer(mux)
			defer server.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			var transport Transport
			if kind == "http" {
				transport = NewHTTPTransport(server.URL+HTTPPath, nil)
			} else {
				var err error
				transport, err = DialWebSocket(ctx, "ws"+strings.TrimPrefix(server.URL, "http")+WebSocketPath)
				if err != nil {
					t.Fatal(err)
				}
			}
			client := newTestPeer(t, "client", Options{})
			count := make(chan struct{}, 1)
			register(t, client, "progress", func(context.Context, json.RawMessage) (any, error) { count <- struct{}{}; return nil, nil })
			register(t, client, "confirm", func(context.Context, json.RawMessage) (any, error) { return true, nil })
			done := make(chan error, 1)
			go func() { done <- client.Serve(ctx, transport) }()
			<-client.Ready()
			initialize(t, ctx, client)
			var result bool
			if err := client.Call(ctx, "work", struct{}{}, &result); err != nil || !result {
				t.Fatalf("callback %v %v", result, err)
			}
			select {
			case <-count:
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			if kind == "http" && transport.(*HTTPTransport).SessionID() == "" {
				t.Fatal("missing session")
			}
			if err := client.Call(ctx, "ping", struct{}{}, nil); err != nil {
				t.Fatal(err)
			}
			cancel()
			_ = transport.Close()
			select {
			case <-done:
			case <-time.After(time.Second):
				t.Fatal("Serve did not stop")
			}
		})
	}
}
func TestHTTPStatusAndSession(t *testing.T) {
	handler := NewHTTPHandler(transportServer(t))
	defer handler.Close()
	server := httptest.NewServer(handler)
	defer server.Close()
	post := func(body, session string) *http.Response {
		t.Helper()
		request, _ := http.NewRequest(http.MethodPost, server.URL, bytes.NewBufferString(body))
		request.Header.Set("Content-Type", "application/json")
		if session != "" {
			request.Header.Set(SessionHeader, session)
		}
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		return response
	}
	response := post(`[]`, "")
	session := response.Header.Get(SessionHeader)
	var failure struct {
		ID    any
		Error Error
	}
	if err := json.NewDecoder(response.Body).Decode(&failure); err != nil {
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != 200 || failure.Error.Code != -32600 || failure.ID != nil || session == "" {
		t.Fatalf("%d %s %+v", response.StatusCode, session, failure)
	}
	response = post(`{"jsonrpc":"2.0","method":"unknown"}`, session)
	_ = response.Body.Close()
	if response.StatusCode != 202 || response.Header.Get(SessionHeader) != session {
		t.Fatal(response.StatusCode)
	}
	response = post(`{"jsonrpc":"2.0","method":"ping","id":1}`, "missing")
	_ = response.Body.Close()
	if response.StatusCode != 404 {
		t.Fatal(response.StatusCode)
	}
}
func TestHTTPJSONAndMultilineSSE(t *testing.T) {
	for _, sse := range []bool{false, true} {
		t.Run(fmt.Sprint(sse), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set(SessionHeader, "session-1")
				if sse {
					w.Header().Set("Content-Type", "text/event-stream")
					fmt.Fprint(w, ": comment\nevent: message\ndata: {\ndata: \"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}\n\n")
				} else {
					w.Header().Set("Content-Type", "application/json")
					fmt.Fprint(w, `{"jsonrpc":"2.0","id":1,"result":null}`)
				}
			}))
			defer server.Close()
			transport := NewHTTPTransport(server.URL, nil)
			defer transport.Close()
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			if err := transport.WriteFrame(ctx, []byte(`{"jsonrpc":"2.0","id":1,"method":"ping"}`)); err != nil {
				t.Fatal(err)
			}
			raw, err := transport.ReadFrame(ctx)
			if err != nil || !json.Valid(raw) {
				t.Fatalf("%s %v", raw, err)
			}
		})
	}
}

func TestHTTPCancellationUsesNewPOST(t *testing.T) {
	started := make(chan struct{})
	stopped := make(chan struct{})
	factory := func() (*Peer, error) {
		p := newTestPeer(t, "server", Options{})
		register(t, p, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
		register(t, p, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
			close(started)
			<-ctx.Done()
			close(stopped)
			return nil, ctx.Err()
		})
		return p, nil
	}
	handler := NewHTTPHandler(factory)
	defer handler.Close()
	server := httptest.NewServer(handler)
	defer server.Close()
	client := newTestPeer(t, "client", Options{})
	transport := NewHTTPTransport(server.URL, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	defer transport.Close()
	done := make(chan error, 1)
	go func() { done <- client.Serve(ctx, transport) }()
	<-client.Ready()
	initialize(t, ctx, client)
	response := make(chan error, 1)
	go func() { response <- client.CallWithID(ctx, StringID("http-cancel"), "work", struct{}{}, nil) }()
	<-started
	if err := client.Notify(ctx, "cancel", map[string]any{"id": StringID("http-cancel")}); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-response:
		if err == nil || err.(*Error).Code != -32800 {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	<-stopped
	cancel()
	_ = transport.Close()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Serve did not stop")
	}
}

func TestHTTPBatchRejectionLog(t *testing.T) {
	var log bytes.Buffer
	handler := NewHTTPHandler(func() (*Peer, error) { return NewPeer(testContract(), "server", Options{Log: &log}) })
	defer handler.Close()
	server := httptest.NewServer(handler)
	defer server.Close()
	response, err := http.Post(server.URL, "application/json", strings.NewReader(`[]`))
	if err != nil {
		t.Fatal(err)
	}
	_ = response.Body.Close()
	lines := bytes.Split(bytes.TrimSpace(log.Bytes()), []byte("\n"))
	if len(lines) != 2 {
		t.Fatalf("expected receive and send rows: %s", log.String())
	}
	for i, direction := range []string{"recv", "send"} {
		var row struct {
			Dir     string          `json:"dir"`
			Message json.RawMessage `json:"message"`
		}
		if err := json.Unmarshal(lines[i], &row); err != nil {
			t.Fatal(err)
		}
		if row.Dir != direction || !json.Valid(row.Message) {
			t.Fatalf("%s", lines[i])
		}
	}
}
