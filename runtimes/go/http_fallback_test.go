package rpc

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type openHTTPCall struct {
	ctx     context.Context
	id      ID
	release chan struct{}
}

func fallbackContract() Contract {
	contract := testContract()
	contract.Session = nil
	contract.Peers[0].Methods = append(contract.Peers[0].Methods, MethodContract{Name: "notice", Kind: "notification", Params: "named"})
	return contract
}

func fallbackServer(t *testing.T) (*httptest.Server, *HTTPServer, <-chan *Peer, <-chan openHTTPCall) {
	t.Helper()
	peers := make(chan *Peer, 1)
	calls := make(chan openHTTPCall, 2)
	handler := NewHTTPHandler(func() (*Peer, error) {
		p, err := NewPeer(fallbackContract(), "server", Options{})
		if err != nil {
			return nil, err
		}
		register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
		register(t, p, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
			id, _ := RequestID(ctx)
			release := make(chan struct{})
			calls <- openHTTPCall{ctx: ctx, id: id, release: release}
			select {
			case <-release:
				return true, nil
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		})
		peers <- p
		return p, nil
	})
	server := httptest.NewServer(handler)
	t.Cleanup(func() { _ = handler.Close(); server.Close() })
	return server, handler, peers, calls
}

func postHTTP(t *testing.T, ctx context.Context, url, session, raw string) *http.Response {
	t.Helper()
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	if session != "" {
		request.Header.Set(SessionHeader, session)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func readHTTPEvent(t *testing.T, reader *bufio.Reader) json.RawMessage {
	t.Helper()
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatal(err)
		}
		if strings.HasPrefix(line, "data: ") {
			raw := json.RawMessage(strings.TrimSpace(strings.TrimPrefix(line, "data: ")))
			if !json.Valid(raw) {
				t.Fatal(string(raw))
			}
			return raw
		}
	}
}

func TestHTTPQueuedNotificationAndOpenComment(t *testing.T) {
	server, _, peers, _ := fallbackServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	response := postHTTP(t, ctx, server.URL, "", `{"jsonrpc":"2.0","method":"unknown"}`)
	session := response.Header.Get(SessionHeader)
	_ = response.Body.Close()
	p := <-peers
	<-p.Ready()
	if err := p.Notify(ctx, "notice", map[string]any{"message": "queued"}); err != nil {
		t.Fatal(err)
	}
	// Queueing must not bypass an active-call reference check.
	if err := p.Notify(ctx, "progress", map[string]any{"requestId": StringID("missing")}); err == nil || err.(*Error).Code != -32602 {
		t.Fatalf("inactive reference %v", err)
	}
	response = postHTTP(t, ctx, server.URL, session, `{"jsonrpc":"2.0","method":"ping","id":1}`)
	defer response.Body.Close()
	reader := bufio.NewReader(response.Body)
	first, err := reader.ReadString('\n')
	if err != nil || first != ": open\n" {
		t.Fatalf("opening comment %q %v", first, err)
	}
	queued := readHTTPEvent(t, reader)
	if !strings.Contains(string(queued), `"method":"notice"`) {
		t.Fatal(string(queued))
	}
	reply := readHTTPEvent(t, reader)
	if !strings.Contains(string(reply), `"result":null`) {
		t.Fatal(string(reply))
	}
}

func TestHTTPUnboundMessagesUseLatestOpenStream(t *testing.T) {
	server, _, peers, calls := fallbackServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	response := postHTTP(t, ctx, server.URL, "", `{"jsonrpc":"2.0","method":"unknown"}`)
	session := response.Header.Get(SessionHeader)
	_ = response.Body.Close()
	p := <-peers
	<-p.Ready()
	first := postHTTP(t, ctx, server.URL, session, `{"jsonrpc":"2.0","method":"work","id":1}`)
	defer first.Body.Close()
	firstCall := <-calls
	second := postHTTP(t, ctx, server.URL, session, `{"jsonrpc":"2.0","method":"work","id":2}`)
	defer second.Body.Close()
	secondCall := <-calls
	firstReader, secondReader := bufio.NewReader(first.Body), bufio.NewReader(second.Body)
	if err := p.Notify(ctx, "notice", map[string]any{"message": "latest"}); err != nil {
		t.Fatal(err)
	}
	if raw := readHTTPEvent(t, secondReader); !strings.Contains(string(raw), `"latest"`) {
		t.Fatal(string(raw))
	}
	if err := p.Notify(firstCall.ctx, "notice", map[string]any{"message": "parent"}); err != nil {
		t.Fatal(err)
	}
	if raw := readHTTPEvent(t, firstReader); !strings.Contains(string(raw), `"parent"`) {
		t.Fatal(string(raw))
	}
	close(secondCall.release)
	if raw := readHTTPEvent(t, secondReader); !strings.Contains(string(raw), `"result":true`) {
		t.Fatal(string(raw))
	}
	if _, err := io.ReadAll(secondReader); err != nil {
		t.Fatal(err)
	}
	if err := p.Notify(ctx, "notice", map[string]any{"message": "remaining"}); err != nil {
		t.Fatal(err)
	}
	if raw := readHTTPEvent(t, firstReader); !strings.Contains(string(raw), `"remaining"`) {
		t.Fatal(string(raw))
	}
	close(firstCall.release)
	if raw := readHTTPEvent(t, firstReader); !strings.Contains(string(raw), `"result":true`) {
		t.Fatal(string(raw))
	}
}

func TestHTTPNotificationQueueIsBounded(t *testing.T) {
	session := newHTTPSession(nil)
	ctx := context.Background()
	raw := []byte(`{"jsonrpc":"2.0","method":"notice","params":{}}`)
	for range 32 {
		if err := session.WriteFrame(ctx, raw); err != nil {
			t.Fatal(err)
		}
	}
	if err := session.WriteFrame(ctx, raw); err == nil {
		t.Fatal("I expected a full HTTP message queue error")
	}
	_ = session.Close()
	if err := session.WriteFrame(ctx, raw); err == nil {
		t.Fatal("I expected a closed HTTP session error")
	}
}

func TestHTTPQueuedCallbackKeepsActiveCallAndUsesNewPOST(t *testing.T) {
	server, _, peers, _ := fallbackServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	client, err := NewPeer(fallbackContract(), "client", Options{})
	if err != nil {
		t.Fatal(err)
	}
	register(t, client, "confirm", func(context.Context, json.RawMessage) (any, error) { return true, nil })
	transport := NewHTTPTransport(server.URL, nil)
	done := make(chan error, 1)
	go func() { done <- client.Serve(ctx, transport) }()
	<-client.Ready()
	defer func() {
		cancel()
		_ = transport.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("I expected the HTTP client to stop")
		}
	}()
	if err := client.Notify(ctx, "ready", nil); err != nil {
		t.Fatal(err)
	}
	p := <-peers
	<-p.Ready()
	returned := make(chan error, 1)
	go func() {
		var confirmed bool
		err := p.Call(ctx, "confirm", nil, &confirmed)
		if err == nil && !confirmed {
			err = NewError(-32603, "I expected a confirmed callback", nil)
		}
		returned <- err
	}()
	// Wait for the transport queue so this call cannot use an existing stream.
	for {
		p.mu.Lock()
		session, _ := p.transport.(*httpSession)
		p.mu.Unlock()
		session.mu.Lock()
		queued := len(session.pending)
		session.mu.Unlock()
		if queued == 1 {
			break
		}
		select {
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		case <-time.After(time.Millisecond):
		}
	}
	if err := client.Call(ctx, "ping", nil, nil); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-returned:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}
