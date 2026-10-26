package rpc

import (
	"context"
	"encoding/json"
	"testing"
)

func TestUnassignedReservedErrorRejected(t *testing.T) {
	client, server := newTestPeer(t, "client", Options{}), newTestPeer(t, "server", Options{})
	register(t, server, "ping", func(context.Context, json.RawMessage) (any, error) {
		return nil, NewError(-32604, "I returned an unassigned code", nil)
	})
	ctx := startPair(t, client, server)
	err := client.Call(ctx, "ping", nil, nil)
	if failure, ok := err.(*Error); !ok || failure.Code != -32603 {
		t.Fatalf("%#v", err)
	}
}
