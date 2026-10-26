package rpc

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

func ptr[T any](value T) *T { return &value }
func testContract() Contract {
	return Contract{Peers: []PeerContract{
		{Name: "client", Methods: []MethodContract{
			{Name: "confirm", Kind: "request", Params: "named"},
			{Name: "progress", Kind: "notification", Params: "named", RefersToCall: &CallReference{WireName: "requestId"}},
		}},
		{Name: "server", Methods: []MethodContract{
			{Name: "init", Kind: "request", Params: "named"},
			{Name: "ready", Kind: "notification", Params: "named"},
			{Name: "work", Kind: "request", Params: "named"},
			{Name: "cancel", Kind: "notification", Params: "named"},
			{Name: "ping", Kind: "request", Params: "named", NullResult: true},
			{Name: "add", Kind: "request", Params: "positional", Positional: []string{"a", "b"}},
		}},
	}, Session: &SessionContract{
		States:       []string{"starting", "initializing", "ready", "working"},
		Capabilities: []CapabilityContract{{Name: "work", Method: "init", Pointer: "/enabled"}},
		Refusals:     []StateRefusal{{State: "starting", Code: 1007}}, CapabilityRefusal: ptr(int64(1008)),
		Methods: []MethodRule{
			{Receiver: "server", Method: "init", Allowed: []string{"starting"}, OnSuccess: "initializing"},
			{Receiver: "server", Method: "ready", Allowed: []string{"initializing"}, OnCall: "ready"},
			{Receiver: "server", Method: "work", Allowed: []string{"ready"}, OnCall: "working", OnSuccess: "ready", OnError: "ready", Requires: []string{"work"}},
			{Receiver: "server", Method: "cancel", Allowed: []string{"working"}, Cancels: &CallReference{WireName: "id", Code: ptr(int64(-32800))}},
			{Receiver: "client", Method: "progress", Allowed: []string{"working"}},
			{Receiver: "client", Method: "confirm", Allowed: []string{"working"}},
		},
	}}
}
func newTestPeer(t *testing.T, name string, options Options) *Peer {
	t.Helper()
	p, err := NewPeer(testContract(), name, options)
	if err != nil {
		t.Fatal(err)
	}
	return p
}
func register(t *testing.T, p *Peer, method string, h Handler) {
	t.Helper()
	if err := p.Register(method, h); err != nil {
		t.Fatal(err)
	}
}
func startPair(t *testing.T, client, server *Peer) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	a, b := net.Pipe()
	results := make(chan error, 2)
	go func() { results <- client.Serve(ctx, Stdio(a, a)) }()
	go func() { results <- server.Serve(ctx, Stdio(b, b)) }()
	<-client.Ready()
	<-server.Ready()
	t.Cleanup(func() {
		cancel()
		_ = a.Close()
		_ = b.Close()
		for range 2 {
			select {
			case <-results:
			case <-time.After(time.Second):
				t.Error("Serve did not stop")
			}
		}
	})
	return ctx
}
func initialize(t *testing.T, ctx context.Context, client *Peer) {
	t.Helper()
	var result any
	if err := client.Call(ctx, "init", struct{}{}, &result); err != nil {
		t.Fatal(err)
	}
	if err := client.Notify(ctx, "ready", struct{}{}); err != nil {
		t.Fatal(err)
	}
}
func TestSessionCallbacksProgressAndLogs(t *testing.T) {
	var log bytes.Buffer
	client, server := newTestPeer(t, "client", Options{Log: &log}), newTestPeer(t, "server", Options{})
	register(t, server, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
	register(t, server, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	register(t, client, "confirm", func(context.Context, json.RawMessage) (any, error) { return true, nil })
	progress := make(chan ID, 1)
	register(t, client, "progress", func(_ context.Context, raw json.RawMessage) (any, error) {
		var v struct {
			RequestID ID `json:"requestId"`
		}
		if err := Decode(raw, &v); err != nil {
			return nil, err
		}
		progress <- v.RequestID
		return nil, nil
	})
	register(t, server, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
		id, ok := RequestID(ctx)
		if !ok {
			return nil, fmt.Errorf("missing ID")
		}
		p := PeerFromContext(ctx)
		if err := p.Notify(ctx, "progress", map[string]any{"requestId": id}); err != nil {
			return nil, err
		}
		var confirmed bool
		if err := p.Call(ctx, "confirm", struct{}{}, &confirmed); err != nil {
			return nil, err
		}
		return confirmed, nil
	})
	ctx := startPair(t, client, server)
	// Check the receiving side refusal with an untyped raw caller below. The typed caller refuses before send.
	var result bool
	if err := client.Call(ctx, "work", struct{}{}, &result); err == nil || err.(*Error).Code != 1007 {
		t.Fatalf("state refusal: %v", err)
	}
	initialize(t, ctx, client)
	if err := client.Call(ctx, "work", struct{}{}, &result); err != nil || !result {
		t.Fatalf("work: %v %v", result, err)
	}
	select {
	case id := <-progress:
		if !id.IsValid() {
			t.Fatal("invalid progress ID")
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if client.State() != "ready" || server.State() != "ready" {
		t.Fatalf("states %s %s", client.State(), server.State())
	}
	// Close before reading the shared writer.
	_ = client.Close()
	_ = server.Close()
	scanner := bufio.NewScanner(&log)
	directions := map[string]bool{}
	for scanner.Scan() {
		var row struct {
			Dir     string          `json:"dir"`
			Message json.RawMessage `json:"message"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &row); err != nil {
			t.Fatal(err)
		}
		directions[row.Dir] = true
		if !json.Valid(row.Message) {
			t.Fatal("invalid log message")
		}
	}
	if !directions["send"] || !directions["recv"] {
		t.Fatal(directions)
	}
}
func TestCancellation(t *testing.T) {
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	register(t, server, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
	register(t, server, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	started := make(chan ID, 1)
	stopped := make(chan struct{})
	register(t, server, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
		id, _ := RequestID(ctx)
		started <- id
		<-ctx.Done()
		close(stopped)
		return nil, ctx.Err()
	})
	ctx := startPair(t, client, server)
	initialize(t, ctx, client)
	result := make(chan error, 1)
	go func() { result <- client.Call(ctx, "work", struct{}{}, nil) }()
	id := <-started
	if err := client.Notify(ctx, "cancel", map[string]any{"id": id}); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err == nil || err.(*Error).Code != -32800 {
			t.Fatalf("cancel response %v", err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	<-stopped
	if server.State() != "ready" || client.State() != "ready" {
		t.Fatal("cancel state")
	}
}
func TestHeaderFramingIDsAndBatch(t *testing.T) {
	p := newTestPeer(t, "server", Options{})
	register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	a, b := net.Pipe()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	defer a.Close()
	done := make(chan error, 1)
	go func() { done <- p.Serve(ctx, Stdio(b, b)) }()
	<-p.Ready()
	frames := Stdio(a, a)
	for _, id := range []string{`"call-1"`, "123456789012345678901234567890", "-0"} {
		raw := fmt.Sprintf(`{"jsonrpc":"2.0","id":%s,"method":"ping","params":{}}`, id)
		go func() { _, _ = fmt.Fprintf(a, "X-Unknown: yes\r\nContent-Length: %d\r\n\r\n%s", len(raw), raw) }()
		response, err := frames.ReadFrame(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var fields map[string]json.RawMessage
		_ = json.Unmarshal(response, &fields)
		if string(fields["id"]) != id || string(fields["result"]) != "null" {
			t.Fatal(string(response))
		}
	}
	go func() { _ = frames.WriteFrame(ctx, []byte(`[{"jsonrpc":"2.0","id":1,"method":"ping"}]`)) }()
	raw, err := frames.ReadFrame(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"code":-32600`) || !strings.Contains(string(raw), `"id":null`) {
		t.Fatal(string(raw))
	}
	_ = a.Close()
	select {
	case err := <-done:
		if err != nil && err != io.EOF {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

func TestUncheckedRefusalsAndCustomIDs(t *testing.T) {
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	register(t, server, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": false}, nil })
	register(t, server, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	register(t, server, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	ctx := startPair(t, client, server)
	if err := client.CallUnchecked(ctx, "work", struct{}{}, nil); err == nil || err.(*Error).Code != 1007 {
		t.Fatalf("refusal %v", err)
	}
	initialize(t, ctx, client)
	if err := client.CallUnchecked(ctx, "work", struct{}{}, nil); err == nil || err.(*Error).Code != 1008 {
		t.Fatalf("capability %v", err)
	}
	if client.State() != "ready" || server.State() != "ready" {
		t.Fatal("refusal changed state")
	}
	for _, id := range []ID{StringID("hello"), func() ID { id, _ := IntegerID("123456789012345678901234567890"); return id }()} {
		if err := client.CallWithID(ctx, id, "ping", struct{}{}, nil); err != nil {
			t.Fatal(err)
		}
	}
}

func TestModeledErrorCodeAndData(t *testing.T) {
	contract := testContract()
	contract.Peers[1].Methods[4].NullResult = false
	contract.Peers[1].Methods[4].Errors = []ErrorContract{{Code: 9007199254740993, DataRequired: true}}
	client, err := NewPeer(contract, "client", Options{})
	if err != nil {
		t.Fatal(err)
	}
	server, err := NewPeer(contract, "server", Options{})
	if err != nil {
		t.Fatal(err)
	}
	register(t, server, "ping", func(context.Context, json.RawMessage) (any, error) {
		return nil, NewError(9007199254740993, "I refused the test call", Number("12345678901234567890.00"))
	})
	ctx := startPair(t, client, server)
	err = client.Call(ctx, "ping", struct{}{}, nil)
	failure, ok := err.(*Error)
	if !ok || failure.Code != 9007199254740993 || string(failure.Data) != "12345678901234567890.00" {
		t.Fatalf("%#v", err)
	}
}

func TestPositionalTypedHandlerAndActiveChecks(t *testing.T) {
	contract := testContract()
	contract.Session = nil
	client, err := NewPeer(contract, "client", Options{})
	if err != nil {
		t.Fatal(err)
	}
	server, err := NewPeer(contract, "server", Options{})
	if err != nil {
		t.Fatal(err)
	}
	type input struct {
		A Number  `json:"a"`
		B Integer `json:"b"`
	}
	register(t, server, "add", Bind(func(_ context.Context, in input) (Number, error) {
		if string(in.B) != "123456789012345678901234567890" {
			return "", fmt.Errorf("integer changed")
		}
		return in.A, nil
	}))
	ctx := startPair(t, client, server)
	var result Number
	if err := client.Call(ctx, "add", []any{Number("12345678901234567890.000"), Integer("123456789012345678901234567890")}, &result); err != nil {
		t.Fatal(err)
	}
	if result != "12345678901234567890.000" {
		t.Fatal(result)
	}
	if err := server.Notify(ctx, "progress", map[string]any{"requestId": StringID("missing")}); err == nil || err.(*Error).Code != -32602 {
		t.Fatalf("inactive progress %v", err)
	}
	if err := client.Notify(ctx, "ping", struct{}{}); err == nil || err.(*Error).Code != -32600 {
		t.Fatalf("method kind %v", err)
	}
}

func TestDuplicateIncomingIDKeepsOriginalCall(t *testing.T) {
	p := newTestPeer(t, "server", Options{})
	started := make(chan struct{}, 2)
	release := make(chan struct{})
	register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { started <- struct{}{}; <-release; return nil, nil })
	a, b := net.Pipe()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	defer a.Close()
	done := make(chan error, 1)
	go func() { done <- p.Serve(ctx, Stdio(b, b)) }()
	<-p.Ready()
	frames := Stdio(a, a)
	raw := []byte(`{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}`)
	if err := frames.WriteFrame(ctx, raw); err != nil {
		t.Fatal(err)
	}
	<-started
	if err := frames.WriteFrame(ctx, raw); err != nil {
		t.Fatal(err)
	}
	duplicate, err := frames.ReadFrame(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(duplicate), `"code":-32600`) {
		t.Fatal(string(duplicate))
	}
	close(release)
	original, err := frames.ReadFrame(ctx)
	if err != nil || !strings.Contains(string(original), `"result":null`) {
		t.Fatalf("%s %v", original, err)
	}
	if err := frames.WriteFrame(ctx, raw); err != nil {
		t.Fatal(err)
	}
	reused, err := frames.ReadFrame(ctx)
	if err != nil || !strings.Contains(string(reused), `"result":null`) {
		t.Fatalf("%s %v", reused, err)
	}
	_ = a.Close()
	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

func TestCallContextSendsModeledCancellation(t *testing.T) {
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	register(t, server, "init", func(context.Context, json.RawMessage) (any, error) { return map[string]bool{"enabled": true}, nil })
	register(t, server, "ready", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	started := make(chan struct{})
	stopped := make(chan struct{})
	register(t, server, "work", func(ctx context.Context, _ json.RawMessage) (any, error) {
		close(started)
		<-ctx.Done()
		close(stopped)
		return nil, ctx.Err()
	})
	ctx := startPair(t, client, server)
	initialize(t, ctx, client)
	callCtx, cancelCall := context.WithCancel(ctx)
	result := make(chan error, 1)
	go func() { result <- client.CallWithID(callCtx, StringID("cancel-me"), "work", struct{}{}, nil) }()
	<-started
	cancelCall()
	select {
	case err := <-result:
		if err != context.Canceled {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	select {
	case <-stopped:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

func TestExplicitNullParamsRejectedAndOmittedParamsAccepted(t *testing.T) {
	p := newTestPeer(t, "server", Options{})
	register(t, p, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	a, b := net.Pipe()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	defer a.Close()
	done := make(chan error, 1)
	go func() { done <- p.Serve(ctx, Stdio(b, b)) }()
	<-p.Ready()
	frames := Stdio(a, a)
	for _, test := range []struct {
		raw  string
		want string
	}{
		{`{"jsonrpc":"2.0","id":1,"method":"ping","params":null}`, `"code":-32602`},
		{`{"jsonrpc":"2.0","id":2,"method":"ping"}`, `"result":null`},
	} {
		if err := frames.WriteFrame(ctx, []byte(test.raw)); err != nil {
			t.Fatal(err)
		}
		raw, err := frames.ReadFrame(ctx)
		if err != nil || !strings.Contains(string(raw), test.want) {
			t.Fatalf("%s %v", raw, err)
		}
	}
	_ = a.Close()
	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

type retainedContextTransport struct {
	Transport
	contexts chan context.Context
}

func (t *retainedContextTransport) WriteFrame(ctx context.Context, raw []byte) error {
	t.contexts <- ctx
	return t.Transport.WriteFrame(ctx, raw)
}
func TestTransportCanRetainWriteContext(t *testing.T) {
	type markerKey struct{}
	ctx, cancel := context.WithTimeout(context.WithValue(context.Background(), markerKey{}, "connection"), 5*time.Second)
	defer cancel()
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	register(t, server, "ping", func(context.Context, json.RawMessage) (any, error) { return nil, nil })
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	transport := &retainedContextTransport{Transport: Stdio(b, b), contexts: make(chan context.Context, 10)}
	done := make(chan error, 2)
	go func() { done <- client.Serve(ctx, Stdio(a, a)) }()
	go func() { done <- server.Serve(ctx, transport) }()
	<-client.Ready()
	<-server.Ready()
	if err := client.CallUnchecked(ctx, "work", nil, nil); err == nil || err.(*Error).Code != 1007 {
		t.Fatalf("refusal %v", err)
	}
	_ = client.Close()
	_ = server.Close()
	for range 2 {
		select {
		case <-done:
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		}
	}
	defer func() {
		if value := recover(); value != nil {
			t.Fatalf("transport retained a recycled context: %v", value)
		}
	}()
	for range 1 {
		retained := <-transport.contexts
		if retained.Value(markerKey{}) != "connection" {
			t.Fatal("connection value was lost")
		}
		_ = retained.Done()
	}
}

func TestUnknownAndUnregisteredIncomingMethods(t *testing.T) {
	p := newTestPeer(t, "server", Options{})
	a, b := net.Pipe()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	defer a.Close()
	done := make(chan error, 1)
	go func() { done <- p.Serve(ctx, Stdio(b, b)) }()
	<-p.Ready()
	frames := Stdio(a, a)
	for _, method := range []string{"missing", "ping"} {
		raw := fmt.Sprintf(`{"jsonrpc":"2.0","id":"%s","method":"%s"}`, method, method)
		if err := frames.WriteFrame(ctx, []byte(raw)); err != nil {
			t.Fatal(err)
		}
		response, err := frames.ReadFrame(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(response), `"code":-32601`) {
			t.Fatal(string(response))
		}
	}
	_ = a.Close()
	select {
	case <-done:
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

func TestConcurrentDuplicateCallIDsKeepConnection(t *testing.T) {
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	release := make(chan struct{})
	register(t, server, "ping", func(context.Context, json.RawMessage) (any, error) { <-release; return nil, nil })
	ctx := startPair(t, client, server)
	start := make(chan struct{})
	results := make(chan error, 32)
	for range 32 {
		go func() { <-start; results <- client.CallWithID(ctx, StringID("shared"), "ping", nil, nil) }()
	}
	close(start)
	for range 31 {
		select {
		case err := <-results:
			failure, ok := err.(*Error)
			if !ok || failure.Code != -32600 {
				t.Fatalf("duplicate result %v", err)
			}
		case <-ctx.Done():
			t.Fatal(ctx.Err())
		}
	}
	close(release)
	select {
	case err := <-results:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if err := client.Call(ctx, "ping", nil, nil); err != nil {
		t.Fatalf("connection failed after local refusal: %v", err)
	}
}
