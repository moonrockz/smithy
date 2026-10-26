package rpc

import (
	"context"
	"io"
	"sync"

	"go.lsp.dev/jsonrpc2"
)

// Transport carries one complete JSON-RPC message at a time.
// ReadFrame has one reader. WriteFrame must permit concurrent calls.
// Close must unblock ReadFrame.
type Transport interface {
	ReadFrame(context.Context) ([]byte, error)
	WriteFrame(context.Context, []byte) error
	Close() error
}

type headerFrames interface {
	ReadFrame(context.Context) ([]byte, int64, error)
	WriteFrame(context.Context, []byte) (int64, error)
	Close() error
}

type stdioTransport struct{ frames headerFrames }

// Stdio uses the upstream Content-Length framer. Close closes reader.
func Stdio(reader io.ReadCloser, writer io.Writer) Transport {
	stream := jsonrpc2.NewHeaderStream(&splitStream{reader: reader, writer: writer})
	return &stdioTransport{frames: stream.(headerFrames)}
}
func (s *stdioTransport) ReadFrame(ctx context.Context) ([]byte, error) {
	data, _, err := s.frames.ReadFrame(ctx)
	return data, err
}
func (s *stdioTransport) WriteFrame(ctx context.Context, data []byte) error {
	_, err := s.frames.WriteFrame(ctx, data)
	return err
}
func (s *stdioTransport) Close() error { return s.frames.Close() }

type splitStream struct {
	reader io.ReadCloser
	writer io.Writer
	once   sync.Once
	err    error
}

func (s *splitStream) Read(data []byte) (int, error)  { return s.reader.Read(data) }
func (s *splitStream) Write(data []byte) (int, error) { return s.writer.Write(data) }
func (s *splitStream) Close() error                   { s.once.Do(func() { s.err = s.reader.Close() }); return s.err }
