package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

func contains(values []string, value string) bool {
	for _, found := range values {
		if found == value {
			return true
		}
	}
	return false
}

// normalizeParams converts positional wire parameters to member names.
func normalizeParams(method MethodContract, raw json.RawMessage) (json.RawMessage, error) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return json.RawMessage(`{}`), nil
	}
	switch raw[0] {
	case '{':
		if method.Params == "positional" {
			return nil, NewError(-32602, "I expected positional RPC parameters", nil)
		}
		return append(json.RawMessage(nil), raw...), nil
	case '[':
		if method.Params == "named" {
			return nil, NewError(-32602, "I expected named RPC parameters", nil)
		}
		var values []json.RawMessage
		if err := json.Unmarshal(raw, &values); err != nil {
			return nil, NewError(-32602, "I expected valid RPC parameters", nil)
		}
		if len(values) > len(method.Positional) {
			return nil, NewError(-32602, "I found too many positional RPC parameters", nil)
		}
		fields := map[string]json.RawMessage{}
		for i, value := range values {
			fields[method.Positional[i]] = value
		}
		return json.Marshal(fields)
	default:
		return nil, NewError(-32602, "I expected object or array RPC parameters", nil)
	}
}

func (p *Peer) checkLocked(incoming bool, method MethodContract, isCall bool, raw json.RawMessage, checkSession bool) (json.RawMessage, error) {
	if (method.Kind == "request" && !isCall) || (method.Kind == "notification" && isCall) {
		return nil, NewError(-32600, "I expected the modeled RPC request kind", nil)
	}
	params, err := normalizeParams(method, raw)
	if err != nil {
		return nil, err
	}
	if method.ValidateParams != nil {
		if err := method.ValidateParams(params); err != nil {
			return nil, NewError(-32602, "I expected valid RPC parameters", nil)
		}
	}
	receiver := p.remote
	if incoming {
		receiver = p.local
	}
	rule := p.rules[receiver+"\x00"+method.Name]
	if checkSession && rule.Allowed != nil && !contains(rule.Allowed, p.state) {
		code := int64(-32600)
		if p.contract.Session != nil {
			for _, refusal := range p.contract.Session.Refusals {
				if refusal.State == p.state {
					code = refusal.Code
					break
				}
			}
		}
		return nil, NewError(code, "I cannot accept this RPC method in the current state", nil)
	}
	for _, capability := range rule.Requires {
		if checkSession && !p.capabilities[capability] {
			code := int64(-32600)
			if p.contract.Session != nil && p.contract.Session.CapabilityRefusal != nil {
				code = *p.contract.Session.CapabilityRefusal
			}
			return nil, NewError(code, "I require an advertised capability for this RPC method", nil)
		}
	}
	if method.RefersToCall != nil {
		id, err := referenceID(params, *method.RefersToCall)
		if err != nil {
			return nil, err
		}
		if p.active[activeKey(!incoming, id)] == nil {
			code := int64(-32602)
			if method.RefersToCall.Code != nil {
				code = *method.RefersToCall.Code
			}
			return nil, NewError(code, "I found no active RPC call for this reference", nil)
		}
	}
	if rule.Cancels != nil {
		if _, err := referenceID(params, *rule.Cancels); err != nil {
			return nil, err
		}
	}
	if isCall {
		count := 0
		for _, call := range p.active {
			if call.incoming == incoming {
				count++
			}
		}
		if count >= p.options.MaxActiveCalls {
			return nil, NewError(-32603, "I reached the active RPC call limit", nil)
		}
	}
	return params, nil
}

func referenceID(params json.RawMessage, rule CallReference) (ID, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(params, &fields); err != nil {
		return ID{}, NewError(-32602, "I expected a valid active RPC call reference", nil)
	}
	var id ID
	if err := json.Unmarshal(fields[rule.WireName], &id); err != nil {
		return ID{}, NewError(-32602, "I expected a valid active RPC call reference", nil)
	}
	return id, nil
}

func (p *Peer) beginLocked(call *pendingCall, isCall bool, params json.RawMessage, cancel context.CancelFunc) error {
	key := activeKey(call.incoming, call.id)
	if isCall && p.active[key] != nil {
		return NewError(-32600, "I found an active RPC request with this ID", nil)
	}
	rule := p.rules[call.receiver+"\x00"+call.method.Name]
	if !call.refused && rule.OnCall != "" {
		p.state = rule.OnCall
	}
	if !call.refused && rule.Cancels != nil {
		id, _ := referenceID(params, *rule.Cancels)
		if active := p.active[activeKey(call.incoming, id)]; active != nil {
			active.cancelCode = rule.Cancels.Code
			if active.cancel != nil {
				active.cancel()
			}
		}
	}
	call.accepted = true
	call.cancel = cancel
	if isCall {
		p.active[key] = call
	}
	return nil
}

func (p *Peer) finishLocked(call *pendingCall, result json.RawMessage, failed bool) {
	if call == nil || !call.accepted {
		return
	}
	delete(p.active, activeKey(call.incoming, call.id))
	if call.refused {
		return
	}
	rule := p.rules[call.receiver+"\x00"+call.method.Name]
	next := rule.OnSuccess
	if failed {
		next = rule.OnError
	}
	if next != "" {
		p.state = next
	}
	if failed || p.contract.Session == nil {
		return
	}
	for _, capability := range p.contract.Session.Capabilities {
		if capability.Method != call.method.Name {
			continue
		}
		value := resolvePointer(result, capability.Pointer)
		if len(value) != 0 && !bytes.Equal(value, []byte("false")) && !bytes.Equal(value, []byte("null")) {
			p.capabilities[capability.Name] = true
		}
	}
}

func resolvePointer(raw json.RawMessage, pointer string) json.RawMessage {
	if pointer == "" {
		return raw
	}
	if !strings.HasPrefix(pointer, "/") {
		return nil
	}
	for _, token := range strings.Split(pointer[1:], "/") {
		token = strings.ReplaceAll(strings.ReplaceAll(token, "~1", "/"), "~0", "~")
		raw = bytes.TrimSpace(raw)
		if len(raw) == 0 {
			return nil
		}
		switch raw[0] {
		case '{':
			var fields map[string]json.RawMessage
			if json.Unmarshal(raw, &fields) != nil {
				return nil
			}
			raw = fields[token]
		case '[':
			var values []json.RawMessage
			if json.Unmarshal(raw, &values) != nil {
				return nil
			}
			index, err := strconv.Atoi(token)
			if err != nil || index < 0 || index >= len(values) || strconv.Itoa(index) != token {
				return nil
			}
			raw = values[index]
		default:
			return nil
		}
	}
	return bytes.TrimSpace(raw)
}

func (p *Peer) validateError(call *pendingCall, err error) error {
	err = modeledError(err)
	var rpcError *Error
	if !errors.As(err, &rpcError) {
		return err
	}
	// Standard errors and the declared cancellation code need no data contract.
	if rpcError.Code >= -32768 && rpcError.Code <= -32000 {
		code := rpcError.Code
		if code == -32700 || (code >= -32603 && code <= -32600) || (code >= -32099 && code <= -32000) {
			return err
		}
		return NewError(-32603, "I expected a defined RPC protocol error code", nil)
	}
	p.mu.Lock()
	cancelCode := call.cancelCode
	p.mu.Unlock()
	if cancelCode != nil && rpcError.Code == *cancelCode {
		return err
	}
	for _, contract := range call.method.Errors {
		if contract.Code != rpcError.Code {
			continue
		}
		present := len(rpcError.Data) != 0
		if (contract.DataRequired && !present) || (contract.DataAbsent && present) {
			return NewError(-32603, "I expected the modeled RPC error data", nil)
		}
		if present && contract.ValidateData != nil && contract.ValidateData(rpcError.Data) != nil {
			return NewError(-32603, "I expected the modeled RPC error data", nil)
		}
		return err
	}
	return NewError(-32603, "I expected a modeled RPC application error", nil)
}
