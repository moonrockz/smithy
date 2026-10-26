package rpc

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHTTPSSERejectsOversizedEventBeforeDelimiter(t *testing.T) {
	// The first 1024 lines join to 1 MiB minus one byte. The next two
	// empty data lines add two newline bytes and exceed the message limit.
	payload := strings.Repeat("data: "+strings.Repeat(" ", 1023)+"\n", 1024) + "data:\ndata:\n"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		_, _ = io.Copy(io.Discard, r.Body)
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(w, payload)
		w.(http.Flusher).Flush()
		// Do not send an event delimiter or EOF. The size check must end
		// the request while the event is still in progress.
		<-r.Context().Done()
	}))
	defer server.Close()
	transport := NewHTTPTransport(server.URL, nil)
	defer transport.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := transport.WriteFrame(ctx, []byte(`{"jsonrpc":"2.0","method":"ping","id":"size-test"}`)); err != nil {
		t.Fatal(err)
	}
	_, err := transport.ReadFrame(ctx)
	if err == nil || errors.Is(err, context.DeadlineExceeded) || !strings.Contains(err.Error(), "oversized") {
		t.Fatalf("I expected an oversized SSE event error before EOF, found %v", err)
	}
}

func TestHTTPSSEAcceptsMultilineEventWithinLimit(t *testing.T) {
	for _, size := range []int{256, maxMessageBytes} {
		t.Run(fmt.Sprint(size), func(t *testing.T) {
			base := "{\n\n\"jsonrpc\":\"2.0\",\n\"id\":\"size-test\",\n\"result\":true\n}"
			raw := strings.Replace(base, "{", "{"+strings.Repeat(" ", size-len(base)), 1)
			var event strings.Builder
			for _, line := range strings.Split(raw, "\n") {
				event.WriteString("data: " + line + "\n")
			}
			event.WriteByte('\n')
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				defer r.Body.Close()
				_, _ = io.Copy(io.Discard, r.Body)
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = io.WriteString(w, event.String())
			}))
			defer server.Close()
			transport := NewHTTPTransport(server.URL, nil)
			defer transport.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if err := transport.WriteFrame(ctx, []byte(`{"jsonrpc":"2.0","method":"ping","id":"size-test"}`)); err != nil {
				t.Fatal(err)
			}
			got, err := transport.ReadFrame(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if string(got) != raw {
				t.Fatal("I expected the exact multiline response bytes")
			}
		})
	}
}

func TestHTTPSSEAcceptsSingleLineEventAtLimit(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		t.Run(fmt.Sprintf("ending-%q", ending), func(t *testing.T) {
			base := `{"jsonrpc":"2.0","id":"size-test","result":true}`
			raw := strings.Replace(base, "{", "{"+strings.Repeat(" ", maxMessageBytes-len(base)), 1)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				defer r.Body.Close()
				_, _ = io.Copy(io.Discard, r.Body)
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = io.WriteString(w, "data: "+raw+ending+ending)
			}))
			defer server.Close()
			transport := NewHTTPTransport(server.URL, nil)
			defer transport.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if err := transport.WriteFrame(ctx, []byte(`{"jsonrpc":"2.0","method":"ping","id":"size-test"}`)); err != nil {
				t.Fatal(err)
			}
			got, err := transport.ReadFrame(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if string(got) != raw {
				t.Fatal("I expected the exact single-line response bytes")
			}
		})
	}
}
