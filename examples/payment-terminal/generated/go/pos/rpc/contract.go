// Package rpc runs generated Smithy JSON-RPC peers.
package rpc

import (
	"context"
	"encoding/json"
)

// Contract holds the prepared two-peer protocol.
type Contract struct {
	Peers   []PeerContract
	Session *SessionContract
}

type PeerContract struct {
	Name    string
	Methods []MethodContract
}

type MethodContract struct {
	Name           string
	Kind           string   // request, notification, or either
	Params         string   // named, positional, or either
	Positional     []string // Member wire names in parameter order.
	NullResult     bool
	RefersToCall   *CallReference
	Errors         []ErrorContract
	ValidateParams func(json.RawMessage) error
	ValidateResult func(json.RawMessage) error
}

type ErrorContract struct {
	Code         int64
	DataRequired bool
	DataAbsent   bool
	ValidateData func(json.RawMessage) error
}

type CallReference struct {
	WireName string
	Position *int
	Code     *int64
}

type SessionContract struct {
	States            []string // The first state is the initial state.
	Capabilities      []CapabilityContract
	Methods           []MethodRule
	Refusals          []StateRefusal
	CapabilityRefusal *int64
}

type CapabilityContract struct {
	Name    string
	Method  string
	Pointer string
}

type MethodRule struct {
	Receiver  string
	Method    string
	Allowed   []string // nil permits every state.
	OnCall    string
	OnSuccess string
	OnError   string
	Requires  []string
	Cancels   *CallReference
}

type StateRefusal struct {
	State string
	Code  int64
}

// Handler returns the wire result or an error. It can call the other peer.
type Handler func(context.Context, json.RawMessage) (any, error)

// Bind decodes typed parameters. Unknown members are ignored.
func Bind[I, O any](handler func(context.Context, I) (O, error)) Handler {
	return func(ctx context.Context, params json.RawMessage) (any, error) {
		var input I
		if len(params) == 0 {
			params = json.RawMessage(`{}`)
		}
		if err := Decode(params, &input); err != nil {
			return nil, NewError(-32602, "I expected valid RPC parameters", nil)
		}
		return handler(ctx, input)
	}
}
