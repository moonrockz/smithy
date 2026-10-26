package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPCallFailsWithoutFinalReply(t *testing.T) {
	for _, mode := range []string{"progress-only-sse", "callback-only-json", "accepted-without-reply"} {
		t.Run(mode, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				defer r.Body.Close()
				var fields map[string]json.RawMessage
				if err := json.NewDecoder(r.Body).Decode(&fields); err != nil {
					http.Error(w, "I expected a JSON message", 400)
					return
				}
				w.Header().Set(SessionHeader, "completion-test")
				if _, request := fields["method"]; !request {
					w.WriteHeader(http.StatusAccepted)
					return
				}
				switch mode {
				case "progress-only-sse":
					w.Header().Set("Content-Type", "text/event-stream")
					fmt.Fprintf(w, "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"progress\",\"params\":{\"requestId\":%s}}\n\n", fields["id"])
				case "callback-only-json":
					w.Header().Set("Content-Type", "application/json")
					_, _ = io.WriteString(w, `{"jsonrpc":"2.0","method":"confirm","params":{},"id":"callback-1"}`)
				case "accepted-without-reply":
					w.WriteHeader(http.StatusAccepted)
				}
			}))
			defer server.Close()
			client, err := NewPeer(fallbackContract(), "client", Options{})
			if err != nil {
				t.Fatal(err)
			}
			register(t, client, "progress", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
			register(t, client, "confirm", func(context.Context, json.RawMessage) (any, error) { return true, nil })
			transport := NewHTTPTransport(server.URL, nil)
			done := make(chan error, 1)
			go func() { done <- client.Serve(context.Background(), transport) }()
			<-client.Ready()
			defer func() {
				_ = client.Close()
				select {
				case <-done:
				case <-time.After(time.Second):
					t.Error("I expected the HTTP peer to stop")
				}
			}()
			returned := make(chan error, 1)
			go func() {
				returned <- client.CallWithID(context.Background(), StringID("original-request"), "ping", nil, nil)
			}()
			select {
			case err := <-returned:
				if err == nil {
					t.Fatal("I expected an incomplete HTTP reply error")
				}
			case <-time.After(time.Second):
				t.Fatal("I found a pending call after the HTTP response ended")
			}
		})
	}
}

func TestHTTPFinalReplyKeepsExactRequestID(t *testing.T) {
	for _, media := range []string{"application/json", "text/event-stream"} {
		for _, text := range []string{`"string-request"`, "900719925474099312345678901234567890", "1e30"} {
			t.Run(media+"/"+text, func(t *testing.T) {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					defer r.Body.Close()
					var fields map[string]json.RawMessage
					if err := json.NewDecoder(r.Body).Decode(&fields); err != nil {
						http.Error(w, "I expected a JSON message", 400)
						return
					}
					w.Header().Set(SessionHeader, "exact-id-test")
					w.Header().Set("Content-Type", media)
					if media == "application/json" {
						fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":null}`, fields["id"])
					} else {
						fmt.Fprintf(w, ": open\n\nevent: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":null}\n\n", fields["id"])
					}
				}))
				defer server.Close()
				client, err := NewPeer(fallbackContract(), "client", Options{})
				if err != nil {
					t.Fatal(err)
				}
				var id ID
				if err := json.Unmarshal([]byte(text), &id); err != nil {
					t.Fatal(err)
				}
				transport := NewHTTPTransport(server.URL, nil)
				ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				done := make(chan error, 1)
				go func() { done <- client.Serve(ctx, transport) }()
				<-client.Ready()
				defer func() {
					_ = client.Close()
					select {
					case <-done:
					case <-time.After(time.Second):
						t.Error("I expected the HTTP peer to stop")
					}
				}()
				if err := client.CallWithID(ctx, id, "ping", nil, nil); err != nil {
					t.Fatal(err)
				}
			})
		}
	}
}

type observedHTTPWrites struct {
	Transport
	headersReady chan struct{}
}

func (t *observedHTTPWrites) WriteFrame(ctx context.Context, raw []byte) error {
	err := t.Transport.WriteFrame(ctx, raw)
	var fields map[string]json.RawMessage
	if err == nil && json.Unmarshal(raw, &fields) == nil && string(fields["method"]) == `"work"` {
		close(t.headersReady)
	}
	return err
}

func TestHTTPCanceledCallKeepsSSEUntilFinalReply(t *testing.T) {
	started, canceled, release := make(chan struct{}), make(chan struct{}), make(chan struct{}, 1)
	handler := NewHTTPHandler(func() (*Peer, error) {
		p := newTestPeer(t, "server", Options{})
		register(t, p, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
		register(t, p, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
			close(started)
			<-ctx.Done()
			close(canceled)
			<-release
			return nil, ctx.Err()
		})
		return p, nil
	})
	defer handler.Close()
	server := httptest.NewServer(handler)
	defer server.Close()
	client := newTestPeer(t, "client", Options{})
	transport := &observedHTTPWrites{Transport: NewHTTPTransport(server.URL, nil), headersReady: make(chan struct{})}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- client.Serve(ctx, transport) }()
	<-client.Ready()
	defer func() {
		select {
		case release <- struct{}{}:
		default:
		}
		_ = client.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("I expected the HTTP peer to stop")
		}
	}()
	initialize(t, ctx, client)
	callCtx, cancelCall := context.WithCancel(ctx)
	returned := make(chan error, 1)
	go func() { returned <- client.CallWithID(callCtx, StringID("canceled-http-call"), "work", nil, nil) }()
	<-started
	<-transport.headersReady
	cancelCall()
	select {
	case err := <-returned:
		if err != context.Canceled {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	select {
	case <-canceled:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if err := client.Call(ctx, "ping", nil, nil); err != nil {
		t.Fatal(err)
	}
	release <- struct{}{}
	for client.State() != "ready" {
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(time.Millisecond):
		}
	}
	if err := client.Call(ctx, "ping", nil, nil); err != nil {
		t.Fatal(err)
	}
}

func TestHTTPInvalidMessagesReachDispatcherBeforeIncompleteEOF(t *testing.T) {
	fixtures := []struct {
		name, raw string
		code      int64
	}{
		{"batch", `[{"jsonrpc":"2.0","method":"confirm","params":{},"id":"batch-call"}]`, -32600},
		{"malformed-json", `{`, -32700},
		{"invalid-envelope", `{"jsonrpc":"2.0","method":true}`, -32600},
	}
	for _, media := range []string{"text/event-stream", "application/json"} {
		for _, fixture := range fixtures {
			t.Run(media+"/"+fixture.name, func(t *testing.T) {
				received := make(chan Error, 1)
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					defer r.Body.Close()
					var fields map[string]json.RawMessage
					if err := json.NewDecoder(r.Body).Decode(&fields); err != nil {
						http.Error(w, "I expected a JSON message", 400)
						return
					}
					w.Header().Set(SessionHeader, "invalid-message-test")
					if _, request := fields["method"]; request {
						w.Header().Set("Content-Type", media)
						if media == "text/event-stream" {
							fmt.Fprintf(w, "event: message\ndata: %s\n\n", fixture.raw)
						} else {
							_, _ = io.WriteString(w, fixture.raw)
						}
						return
					}
					var failure Error
					if err := json.Unmarshal(fields["error"], &failure); err != nil {
						http.Error(w, "I expected an RPC error", 400)
						return
					}
					received <- failure
					w.WriteHeader(http.StatusAccepted)
				}))
				defer server.Close()
				client, err := NewPeer(fallbackContract(), "client", Options{})
				if err != nil {
					t.Fatal(err)
				}
				transport := NewHTTPTransport(server.URL, nil)
				done := make(chan error, 1)
				go func() { done <- client.Serve(context.Background(), transport) }()
				<-client.Ready()
				defer func() {
					_ = client.Close()
					select {
					case <-done:
					case <-time.After(time.Second):
						t.Error("I expected the HTTP peer to stop")
					}
				}()
				returned := make(chan error, 1)
				go func() { returned <- client.Call(context.Background(), "ping", nil, nil) }()
				select {
				case failure := <-received:
					if failure.Code != fixture.code {
						t.Fatalf("I expected code %d, found %d", fixture.code, failure.Code)
					}
				case <-time.After(time.Second):
					t.Fatal("I expected the dispatcher to reject the received message")
				}
				select {
				case err := <-returned:
					if err == nil {
						t.Fatal("I expected an incomplete HTTP reply error")
					}
				case <-time.After(time.Second):
					t.Fatal("I found a pending call after the HTTP response ended")
				}
			})
		}
	}
}

func TestHTTPIncompleteReplyDoesNotWaitForeverForRejectionPOST(t *testing.T) {
	rejected := make(chan struct{}, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		var fields map[string]json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&fields); err != nil {
			http.Error(w, "I expected a JSON message", 400)
			return
		}
		w.Header().Set(SessionHeader, "held-rejection-test")
		if _, request := fields["method"]; request {
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = io.WriteString(w, "data: []\n\n")
			return
		}
		rejected <- struct{}{}
		<-r.Context().Done()
	}))
	defer server.Close()
	client, err := NewPeer(fallbackContract(), "client", Options{})
	if err != nil {
		t.Fatal(err)
	}
	transport := NewHTTPTransport(server.URL, nil)
	done := make(chan error, 1)
	go func() { done <- client.Serve(context.Background(), transport) }()
	<-client.Ready()
	defer func() {
		_ = client.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("I expected the HTTP peer to stop")
		}
	}()
	returned := make(chan error, 1)
	go func() { returned <- client.Call(context.Background(), "ping", nil, nil) }()
	select {
	case <-rejected:
	case <-time.After(time.Second):
		t.Fatal("I expected a batch rejection POST")
	}
	select {
	case err := <-returned:
		if err == nil {
			t.Fatal("I expected an incomplete HTTP reply error")
		}
	case <-time.After(7 * time.Second):
		t.Fatal("I found a call waiting for rejection POST headers")
	}
}
