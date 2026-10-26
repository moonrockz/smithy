package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"sync"

	"go.lsp.dev/jsonrpc2"
)

type peerStream struct {
	peer      *Peer
	transport Transport
	writeMu   sync.Mutex
	sequence  uint64
}

func upstreamID(id jsonrpc2.ID) ID {
	if text, ok := id.StringValue(); ok {
		return StringID(text)
	}
	if number, ok := id.Number(); ok {
		result, _ := IntegerID(strconv.FormatInt(number, 10))
		return result
	}
	return ID{}
}

func (s *peerStream) Read(ctx context.Context) (jsonrpc2.Message, int64, error) {
	for {
		raw, err := s.transport.ReadFrame(ctx)
		if err != nil {
			s.peer.cancelAll()
			return nil, 0, err
		}
		if len(raw) > maxMessageBytes {
			s.peer.cancelAll()
			return nil, 0, errors.New("I received an oversized RPC message")
		}
		if err := s.peer.log("recv", raw); err != nil {
			return nil, 0, err
		}
		fields, problem := envelope(raw)
		if problem != nil {
			if err := s.reject(ctx, ID{}, problem); err != nil {
				return nil, 0, err
			}
			continue
		}
		if _, request := fields["method"]; request {
			if params, present := fields["params"]; present {
				params = bytes.TrimSpace(params)
				if len(params) == 0 || (params[0] != '{' && params[0] != '[') {
					if idRaw, isCall := fields["id"]; isCall {
						var id ID
						code := int64(-32602)
						if json.Unmarshal(idRaw, &id) != nil {
							code = -32600
						}
						if err := s.reject(ctx, id, NewError(code, "I expected object or array RPC parameters", nil)); err != nil {
							return nil, 0, err
						}
					}
					continue
				}
			}
			if idRaw, call := fields["id"]; call {
				var id ID
				if err := json.Unmarshal(idRaw, &id); err != nil {
					if err := s.reject(ctx, ID{}, NewError(-32600, "I expected a string or integer RPC request ID", nil)); err != nil {
						return nil, 0, err
					}
					continue
				}
				// Internal aliases let the upstream dispatcher retain integers beyond int64.
				s.sequence++
				alias := jsonrpc2.NewStringID(fmt.Sprintf("smithy:%d", s.sequence))
				aliasRaw, _ := json.Marshal(fmt.Sprintf("smithy:%d", s.sequence))
				fields["id"] = aliasRaw
				adjusted, _ := json.Marshal(fields)
				message, decodeErr := jsonrpc2.DecodeMessage(adjusted)
				if decodeErr != nil {
					if err := s.reject(ctx, id, NewError(-32600, "I expected a JSON-RPC request", nil)); err != nil {
						return nil, 0, err
					}
					continue
				}
				var name string
				_ = json.Unmarshal(fields["method"], &name)
				p := s.peer
				p.mu.Lock()
				p.incoming[alias] = &pendingCall{id: id, method: p.methods[p.local][name], receiver: p.local, incoming: true}
				p.mu.Unlock()
				return message, int64(len(raw)), nil
			}
			message, err := jsonrpc2.DecodeMessage(raw)
			if err != nil {
				if err := s.reject(ctx, ID{}, NewError(-32600, "I expected a JSON-RPC request", nil)); err != nil {
					return nil, 0, err
				}
				continue
			}
			return message, int64(len(raw)), nil
		}
		var responseID ID
		if err := json.Unmarshal(fields["id"], &responseID); err != nil {
			return nil, 0, errors.New("I require a response ID")
		}
		p := s.peer
		p.mu.Lock()
		internalID, tracked := p.outgoing[responseID.key()]
		p.mu.Unlock()
		if !tracked {
			return nil, 0, errors.New("I found no active call for the response")
		}
		if number, ok := internalID.Number(); ok {
			fields["id"] = json.RawMessage(strconv.FormatInt(number, 10))
		} else {
			text, _ := internalID.StringValue()
			fields["id"], _ = json.Marshal(text)
		}
		var remoteError *Error
		if errorRaw, failed := fields["error"]; failed {
			var failure Error
			if err := Decode(errorRaw, &failure); err != nil {
				return nil, 0, errors.New("I found an invalid response error")
			}
			remoteError = &failure
			fields["error"], _ = json.Marshal(&Error{Code: -32603, Message: failure.Message, Data: failure.Data})
		}
		adjusted, _ := json.Marshal(fields)
		message, err := jsonrpc2.DecodeMessage(adjusted)
		if err != nil {
			return nil, 0, errors.New("I expected a valid JSON-RPC response")
		}
		response, ok := message.(*jsonrpc2.Response)
		if !ok {
			return nil, 0, errors.New("I expected a JSON-RPC response")
		}
		p.mu.Lock()
		call := p.active[activeKey(false, responseID)]
		if call == nil {
			p.mu.Unlock()
			return nil, 0, errors.New("I found no active call for this RPC response")
		}
		if response.Err() == nil {
			if call.method.NullResult && !bytes.Equal(bytes.TrimSpace(response.Result()), []byte("null")) {
				p.mu.Unlock()
				return nil, 0, errors.New("I expected a null RPC result")
			}
			if call.method.ValidateResult != nil && call.method.ValidateResult(json.RawMessage(response.Result())) != nil {
				p.mu.Unlock()
				return nil, 0, errors.New("I expected a valid RPC result")
			}
		}
		if remoteError != nil && !call.refused {
			p.mu.Unlock()
			checked := p.validateError(call, remoteError)
			if checked != remoteError {
				return nil, 0, errors.New("I expected a modeled RPC response error")
			}
			p.mu.Lock()
		}
		if call.refused && (remoteError == nil || (call.refusalCode != nil && remoteError.Code != *call.refusalCode)) {
			p.mu.Unlock()
			return nil, 0, errors.New("I expected the modeled refusal error")
		}
		if call.tracker != nil && remoteError != nil {
			call.tracker.mu.Lock()
			call.tracker.failure = remoteError
			call.tracker.mu.Unlock()
		}
		p.finishLocked(call, json.RawMessage(response.Result()), response.Err() != nil)
		delete(p.outgoing, responseID.key())
		p.mu.Unlock()
		return message, int64(len(raw)), nil
	}
}

func (s *peerStream) Write(ctx context.Context, message jsonrpc2.Message) (int64, error) {
	if err := ctx.Err(); err != nil {
		return 0, err
	}
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	raw, err := jsonrpc2.EncodeMessage(message)
	if err != nil {
		return 0, err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return 0, err
	}
	p := s.peer
	p.mu.Lock()
	if nameRaw, request := fields["method"]; request {
		var name string
		_ = json.Unmarshal(nameRaw, &name)
		method := p.methods[p.remote][name]
		idRaw, isCall := fields["id"]
		var id ID
		if isCall {
			_ = json.Unmarshal(idRaw, &id)
		}
		unchecked := ctx.Value(uncheckedKey{}) == true
		normalized, err := p.checkLocked(false, method, isCall, fields["params"], !unchecked)
		if err != nil {
			p.mu.Unlock()
			return rejectAdmission(ctx, err)
		}
		internalID := id
		if custom, ok := ctx.Value(callerIDKey{}).(ID); ok && isCall {
			id = custom
			fields["id"], _ = json.Marshal(id)
			raw, _ = json.Marshal(fields)
		}
		call := &pendingCall{id: id, method: method, receiver: p.remote}
		call.tracker, _ = ctx.Value(callTrackerKey{}).(*callTracker)
		if unchecked {
			_, policyErr := p.checkLocked(false, method, isCall, fields["params"], true)
			call.refused = policyErr != nil
			if failure, ok := policyErr.(*Error); ok {
				call.refusalCode = &failure.Code
			}
		}
		if err := p.beginLocked(call, isCall, normalized, nil); err != nil {
			p.mu.Unlock()
			return rejectAdmission(ctx, err)
		}
		if isCall {
			var upstream jsonrpc2.ID
			if internalID.text[0] == '"' {
				var text string
				_ = json.Unmarshal([]byte(internalID.text), &text)
				upstream = jsonrpc2.NewStringID(text)
			} else {
				number, _ := strconv.ParseInt(internalID.text, 10, 64)
				upstream = jsonrpc2.NewNumberID(number)
			}
			p.outgoing[id.key()] = upstream
		}
	} else {
		var alias string
		_ = json.Unmarshal(fields["id"], &alias)
		key := jsonrpc2.NewStringID(alias)
		call := p.incoming[key]
		if call != nil {
			fields["id"], _ = json.Marshal(call.id)
			if call.responseError != nil {
				fields["error"], _ = json.Marshal(call.responseError)
				delete(fields, "result")
			}
			p.finishLocked(call, fields["result"], len(fields["error"]) != 0)
			delete(p.incoming, key)
			raw, err = json.Marshal(fields)
		}
	}
	p.mu.Unlock()
	if err != nil {
		return 0, err
	}
	if err := s.send(ctx, raw); err != nil {
		return 0, err
	}
	return int64(len(raw)), nil
}

func (s *peerStream) send(ctx context.Context, raw []byte) error {
	if err := s.peer.log("send", raw); err != nil {
		return err
	}
	// Transport libraries may retain cancellation watchers after Write returns.
	// The upstream per-request context is pooled at that point.
	return s.transport.WriteFrame(jsonrpc2.DetachContext(ctx), raw)
}
func (s *peerStream) reject(ctx context.Context, id ID, problem *Error) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	raw, _ := json.Marshal(struct {
		Version string `json:"jsonrpc"`
		ID      ID     `json:"id"`
		Error   *Error `json:"error"`
	}{"2.0", id, problem})
	return s.send(ctx, raw)
}
func (s *peerStream) Close() error { s.peer.cancelAll(); return s.transport.Close() }

func envelope(raw []byte) (map[string]json.RawMessage, *Error) {
	if !json.Valid(raw) {
		return nil, NewError(-32700, "I could not parse the JSON-RPC message", nil)
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return nil, NewError(-32600, "I expected a JSON-RPC request", nil)
	}
	if string(fields["jsonrpc"]) != `"2.0"` {
		return nil, NewError(-32600, "I expected a JSON-RPC request", nil)
	}
	if method, request := fields["method"]; request {
		var name string
		if len(bytes.TrimSpace(method)) == 0 || bytes.TrimSpace(method)[0] != '"' || json.Unmarshal(method, &name) != nil {
			return nil, NewError(-32600, "I expected a string RPC method name", nil)
		}
		if _, result := fields["result"]; result {
			return nil, NewError(-32600, "I expected a JSON-RPC request", nil)
		}
		if _, failure := fields["error"]; failure {
			return nil, NewError(-32600, "I expected a JSON-RPC request", nil)
		}
	} else {
		_, result := fields["result"]
		_, failure := fields["error"]
		_, id := fields["id"]
		if !id || result == failure {
			return nil, NewError(-32600, "I expected a JSON-RPC response", nil)
		}
	}
	return fields, nil
}

func (p *Peer) log(direction string, raw []byte) error {
	if p.options.Log == nil {
		return nil
	}
	if !json.Valid(raw) {
		raw, _ = json.Marshal(string(raw))
	}
	line, err := json.Marshal(struct {
		Dir     string          `json:"dir"`
		Message json.RawMessage `json:"message"`
	}{direction, raw})
	if err != nil {
		return err
	}
	line = append(line, '\n')
	p.logMu.Lock()
	defer p.logMu.Unlock()
	_, err = p.options.Log.Write(line)
	return err
}

// A local refusal is not a failed transport. Cancel this write's private
// context so the upstream connection does not mark its writer as broken.
func rejectAdmission(ctx context.Context, err error) (int64, error) {
	if cancel, ok := ctx.Value(admissionCancelKey{}).(context.CancelFunc); ok {
		cancel()
	}
	return 0, err
}
