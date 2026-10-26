package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"time"

	"go.lsp.dev/jsonrpc2"
)

// Options sets bounds and optional JSONL logging. Log must not be stdout.
type Options struct {
	Log            io.Writer
	MaxActiveCalls int
}

type pendingCall struct {
	responseError *Error
	tracker       *callTracker
	refusalCode   *int64
	id            ID
	method        MethodContract
	receiver      string
	incoming      bool
	cancel        context.CancelFunc
	cancelCode    *int64
	accepted      bool
	refused       bool
}

// Peer shares one dispatcher and one session across a transport.
type Peer struct {
	outgoing      map[string]jsonrpc2.ID
	mu            sync.Mutex
	logMu         sync.Mutex
	local, remote string
	contract      Contract
	methods       map[string]map[string]MethodContract
	rules         map[string]MethodRule
	handlers      map[string]Handler
	active        map[string]*pendingCall
	incoming      map[jsonrpc2.ID]*pendingCall
	state         string
	capabilities  map[string]bool
	options       Options
	conn          jsonrpc2.Conn
	transport     Transport
	serving       bool
	ready         chan struct{}
}

func NewPeer(contract Contract, localPeer string, options Options) (*Peer, error) {
	if len(contract.Peers) != 2 {
		return nil, errors.New("I expected two peers in the RPC contract")
	}
	if options.Log == os.Stdout {
		return nil, errors.New("I cannot write RPC logs to stdout")
	}
	if options.MaxActiveCalls < 0 {
		return nil, errors.New("I expected a positive active call limit")
	}
	if options.MaxActiveCalls == 0 {
		options.MaxActiveCalls = 1024
	}
	p := &Peer{outgoing: map[string]jsonrpc2.ID{}, local: localPeer, contract: contract, options: options, methods: map[string]map[string]MethodContract{}, rules: map[string]MethodRule{}, handlers: map[string]Handler{}, active: map[string]*pendingCall{}, incoming: map[jsonrpc2.ID]*pendingCall{}, capabilities: map[string]bool{}, ready: make(chan struct{})}
	for _, peer := range contract.Peers {
		if peer.Name == "" || p.methods[peer.Name] != nil {
			return nil, errors.New("I expected distinct nonempty RPC peer names")
		}
		methods := map[string]MethodContract{}
		for _, m := range peer.Methods {
			if m.Name == "" {
				return nil, errors.New("I expected a nonempty RPC method name")
			}
			if _, ok := methods[m.Name]; ok {
				return nil, errors.New("I expected distinct RPC method names")
			}
			if m.Kind == "" {
				m.Kind = "either"
			}
			if m.Params == "" {
				m.Params = "named"
			}
			if m.Kind != "request" && m.Kind != "notification" && m.Kind != "either" {
				return nil, errors.New("I expected a valid RPC method kind")
			}
			if m.Params != "named" && m.Params != "positional" && m.Params != "either" {
				return nil, errors.New("I expected a valid RPC parameter mode")
			}
			methods[m.Name] = m
		}
		p.methods[peer.Name] = methods
		if peer.Name != localPeer {
			p.remote = peer.Name
		}
	}
	if p.methods[localPeer] == nil {
		return nil, errors.New("I expected the local peer in the RPC contract")
	}
	if session := contract.Session; session != nil {
		if len(session.States) == 0 {
			return nil, errors.New("I expected session states")
		}
		states := map[string]bool{}
		for _, state := range session.States {
			if state == "" || states[state] {
				return nil, errors.New("I expected distinct nonempty session states")
			}
			states[state] = true
		}
		p.state = session.States[0]
		for _, rule := range session.Methods {
			if _, ok := p.methods[rule.Receiver][rule.Method]; !ok {
				return nil, errors.New("I expected the session rule to name a known RPC method")
			}
			key := rule.Receiver + "\x00" + rule.Method
			if _, ok := p.rules[key]; ok {
				return nil, errors.New("I expected one session rule for each RPC method")
			}
			for _, state := range append(append([]string{}, rule.Allowed...), rule.OnCall, rule.OnSuccess, rule.OnError) {
				if state != "" && !states[state] {
					return nil, errors.New("I expected the session rule to name a known state")
				}
			}
			p.rules[key] = rule
		}
	}
	return p, nil
}

func (p *Peer) Register(method string, handler Handler) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, ok := p.methods[p.local][method]; !ok {
		return errors.New("I expected a known local RPC method")
	}
	if handler == nil {
		return errors.New("I expected an RPC handler")
	}
	if p.handlers[method] != nil {
		return errors.New("I found an RPC handler for this method")
	}
	p.handlers[method] = handler
	return nil
}

func (p *Peer) State() string { p.mu.Lock(); defer p.mu.Unlock(); return p.state }
func (p *Peer) HasCapability(name string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.capabilities[name]
}

// Ready closes when Serve has started its dispatcher.
func (p *Peer) Ready() <-chan struct{} { return p.ready }

// Serve runs until the transport ends or ctx is canceled. It can run once.
func (p *Peer) Serve(ctx context.Context, transport Transport) error {
	p.mu.Lock()
	if p.serving {
		p.mu.Unlock()
		return errors.New("I started this RPC peer already")
	}
	p.serving = true
	stream := &peerStream{peer: p, transport: transport}
	p.transport = transport
	p.conn = jsonrpc2.NewConn(stream, jsonrpc2.WithCodec(exactCodec{}))
	conn := p.conn
	p.mu.Unlock()
	conn.Go(ctx, p.handle)
	close(p.ready)
	select {
	case <-ctx.Done():
		p.cancelAll()
		_ = transport.Close()
		_ = conn.Close()
	case <-conn.Done():
	}
	p.cancelAll()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return conn.Err()
}

func (p *Peer) Close() error {
	p.mu.Lock()
	conn := p.conn
	transport := p.transport
	p.mu.Unlock()
	p.cancelAll()
	if conn == nil {
		return nil
	}
	// Close the transport before waiting for handlers that need a response.
	if transport != nil {
		_ = transport.Close()
	}
	return conn.Close()
}

func (p *Peer) cancelAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, call := range p.active {
		if call.cancel != nil {
			call.cancel()
		}
	}
}

type callTracker struct {
	mu      sync.Mutex
	failure *Error
}
type callTrackerKey struct{}
type admissionCancelKey struct{}
type uncheckedKey struct{}
type callerIDKey struct{}

// CallUnchecked sends a call without local state or capability checks.
// Use it to test a receiver's refusal rules.
func (p *Peer) CallUnchecked(ctx context.Context, method string, params, result any) error {
	return p.Call(context.WithValue(ctx, uncheckedKey{}, true), method, params, result)
}

// CallWithID uses the supplied exact string or integer ID.
func (p *Peer) CallWithID(ctx context.Context, id ID, method string, params, result any) error {
	if !id.IsValid() {
		return NewError(-32600, "I require a string or integer request ID", nil)
	}
	return p.Call(context.WithValue(ctx, callerIDKey{}, id), method, params, result)
}

func (p *Peer) Call(ctx context.Context, method string, params, result any) error {
	raw, err := json.Marshal(params)
	if params == nil {
		raw = nil
	}
	if err != nil {
		return err
	}
	p.mu.Lock()
	m, ok := p.methods[p.remote][method]
	if !ok {
		p.mu.Unlock()
		return NewError(-32601, "I found no RPC method with this name", nil)
	}
	if custom, ok := ctx.Value(callerIDKey{}).(ID); ok && p.active[activeKey(false, custom)] != nil {
		p.mu.Unlock()
		return NewError(-32600, "I found an active RPC request with this ID", nil)
	}
	_, err = p.checkLocked(false, m, true, raw, ctx.Value(uncheckedKey{}) != true)
	conn := p.conn
	p.mu.Unlock()
	if err != nil {
		return err
	}
	if conn == nil {
		return errors.New("I have not started this RPC peer")
	}
	callerCtx := ctx
	writeCtx, writeCancel := context.WithCancel(ctx)
	defer writeCancel()
	ctx = context.WithValue(writeCtx, admissionCancelKey{}, writeCancel)
	tracker := &callTracker{}
	ctx = context.WithValue(ctx, callTrackerKey{}, tracker)
	var payload any
	if len(raw) != 0 {
		payload = json.RawMessage(raw)
	}
	id, err := conn.Call(ctx, method, payload, result)
	if callerCtx.Err() != nil && id.IsValid() {
		p.sendCancellation(callerCtx, id)
	}
	tracker.mu.Lock()
	failure := tracker.failure
	tracker.mu.Unlock()
	if failure != nil {
		return failure
	}
	return localError(err)
}

func (p *Peer) Notify(ctx context.Context, method string, params any) error {
	raw, err := json.Marshal(params)
	if params == nil {
		raw = nil
	}
	if err != nil {
		return err
	}
	p.mu.Lock()
	m, ok := p.methods[p.remote][method]
	if !ok {
		p.mu.Unlock()
		return NewError(-32601, "I found no RPC method with this name", nil)
	}
	_, err = p.checkLocked(false, m, false, raw, true)
	conn := p.conn
	p.mu.Unlock()
	if err != nil {
		return err
	}
	if conn == nil {
		return errors.New("I have not started this RPC peer")
	}
	var payload any
	if len(raw) != 0 {
		payload = json.RawMessage(raw)
	}
	writeCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	writeCtx = context.WithValue(writeCtx, admissionCancelKey{}, cancel)
	return localError(conn.Notify(writeCtx, method, payload))
}

func (p *Peer) sendCancellation(ctx context.Context, wireID jsonrpc2.ID) {
	p.mu.Lock()
	var method string
	var rule CallReference
	for _, r := range p.rules {
		if r.Receiver == p.remote && r.Cancels != nil {
			method, rule = r.Method, *r.Cancels
			break
		}
	}
	p.mu.Unlock()
	if method == "" {
		return
	}
	id := upstreamID(wireID)
	if custom, ok := ctx.Value(callerIDKey{}).(ID); ok {
		id = custom
	}
	cancelCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = p.Notify(cancelCtx, method, map[string]any{rule.WireName: id})
}

type requestContextKey struct{}
type peerContextKey struct{}

func RequestID(ctx context.Context) (ID, bool) {
	id, ok := ctx.Value(requestContextKey{}).(ID)
	return id, ok
}
func PeerFromContext(ctx context.Context) *Peer {
	p, _ := ctx.Value(peerContextKey{}).(*Peer)
	return p
}

func (p *Peer) handle(ctx context.Context, request *jsonrpc2.Request) (result any, err error) {
	defer func() {
		err = localError(modeledError(err))
		var failure *Error
		if request.IsCall() && errors.As(err, &failure) {
			p.mu.Lock()
			if call := p.incoming[request.ID()]; call != nil {
				call.responseError = failure
			}
			p.mu.Unlock()
		}
		err = wireError(err)
	}()
	dispatchCtx := ctx
	p.mu.Lock()
	method, ok := p.methods[p.local][request.Method()]
	if !ok {
		p.mu.Unlock()
		if !request.IsCall() {
			return nil, nil
		}
		return nil, NewError(-32601, "I found no RPC method with this name", nil)
	}
	params := json.RawMessage(request.Params())
	normalized, err := p.checkLocked(true, method, request.IsCall(), params, true)
	var call *pendingCall
	if request.IsCall() {
		call = p.incoming[request.ID()]
	}
	if err == nil {
		var cancel context.CancelFunc
		// The upstream request context can be pooled after a refused call.
		// A child cancellation watcher must use the connection context.
		ctx, cancel = context.WithCancel(jsonrpc2.DetachContext(dispatchCtx))
		if call == nil {
			call = &pendingCall{method: method, receiver: p.local, incoming: true}
		}
		err = p.beginLocked(call, request.IsCall(), normalized, cancel)
		if err != nil {
			cancel()
		}
	}
	handler := p.handlers[request.Method()]
	p.mu.Unlock()
	if err != nil {
		if !request.IsCall() {
			return nil, nil
		}
		return nil, err
	}
	// Admission and state changes run in wire order before the read loop continues.
	jsonrpc2.Async(dispatchCtx)
	if call.cancel != nil {
		defer call.cancel()
	}
	ctx = context.WithValue(ctx, peerContextKey{}, p)
	if request.IsCall() {
		ctx = context.WithValue(ctx, requestContextKey{}, call.id)
	}
	if handler == nil {
		// Cancellation works without an application handler.
		p.mu.Lock()
		rule := p.rules[p.local+"\x00"+method.Name]
		p.mu.Unlock()
		if rule.Cancels != nil {
			return nil, nil
		}
		return nil, NewError(-32601, "I found no RPC method with this name", nil)
	}
	result, err = handler(ctx, normalized)
	if errors.Is(err, context.Canceled) {
		p.mu.Lock()
		code := call.cancelCode
		p.mu.Unlock()
		if code != nil {
			err = NewError(*code, "I cancelled the RPC request", nil)
		}
	}
	if !request.IsCall() {
		return nil, nil
	}
	if err == nil {
		if method.NullResult {
			result = nil
		}
		raw, encodeErr := json.Marshal(result)
		if encodeErr != nil {
			return nil, NewError(-32603, "I could not produce a valid RPC result", nil)
		}
		if method.ValidateResult != nil && method.ValidateResult(raw) != nil {
			return nil, NewError(-32603, "I could not produce a valid RPC result", nil)
		}
	}
	if err != nil {
		err = p.validateError(call, err)
	}
	return result, err
}

type exactCodec struct{}

func (exactCodec) Marshal(value any) ([]byte, error)      { return json.Marshal(value) }
func (exactCodec) Unmarshal(data []byte, value any) error { return Decode(data, value) }

func activeKey(incoming bool, id ID) string { return fmt.Sprintf("%t:%s", incoming, id.key()) }
