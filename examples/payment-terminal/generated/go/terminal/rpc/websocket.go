package rpc

import (
	"context"
	"errors"
	"net/http"

	"github.com/coder/websocket"
)

type websocketTransport struct{ conn *websocket.Conn }

// DialWebSocket opens a connection with one JSON-RPC message per text frame.
func DialWebSocket(ctx context.Context, url string) (Transport, error) {
	conn, response, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		if response != nil && response.Body != nil {
			_ = response.Body.Close()
		}
		return nil, err
	}
	conn.SetReadLimit(maxMessageBytes)
	return &websocketTransport{conn: conn}, nil
}
func (t *websocketTransport) ReadFrame(ctx context.Context) ([]byte, error) {
	kind, raw, err := t.conn.Read(ctx)
	if err != nil {
		return nil, err
	}
	if kind != websocket.MessageText {
		return nil, errors.New("I require a WebSocket text frame")
	}
	return raw, nil
}
func (t *websocketTransport) WriteFrame(ctx context.Context, raw []byte) error {
	return t.conn.Write(ctx, websocket.MessageText, raw)
}
func (t *websocketTransport) Close() error { return t.conn.CloseNow() }

// NewWebSocketHandler creates a separate peer for each WebSocket connection.
func NewWebSocketHandler(factory PeerFactory) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		peer, err := factory()
		if err != nil || peer == nil {
			http.Error(w, "I cannot create the peer", http.StatusInternalServerError)
			return
		}
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.CloseNow()
		conn.SetReadLimit(maxMessageBytes)
		_ = peer.Serve(r.Context(), &websocketTransport{conn: conn})
	})
}
