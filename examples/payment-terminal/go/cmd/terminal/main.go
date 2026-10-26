package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	sample "example/payment-sample"
	rpc "example/payments/terminal/rpc"
)

func run() error {
	if len(os.Args) < 2 {
		return errors.New("I expected terminal command stdio or serve.")
	}
	mode := os.Args[1]
	flags := flag.NewFlagSet("terminal", flag.ContinueOnError)
	port := flags.Int("port", 8080, "Local port")
	logPath := flags.String("log", "", "JSONL log path")
	if err := flags.Parse(os.Args[2:]); err != nil {
		return err
	}
	var log io.Writer
	if *logPath != "" {
		file, err := os.Create(*logPath)
		if err != nil {
			return err
		}
		defer file.Close()
		log = file
	}
	options := rpc.Options{Log: log}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if mode == "stdio" {
		peer, err := sample.NewTerminal(options)
		if err != nil {
			return err
		}
		defer peer.Close()
		err = peer.Serve(ctx, rpc.Stdio(os.Stdin, os.Stdout))
		if errors.Is(err, io.EOF) || errors.Is(err, context.Canceled) {
			return nil
		}
		return err
	}
	if mode != "serve" {
		return fmt.Errorf("I do not know terminal command `%s`.", mode)
	}
	factory := func() (*rpc.Peer, error) {
		peer, err := sample.NewTerminal(options)
		if err != nil {
			return nil, err
		}
		return peer.Peer, nil
	}
	httpPeer := rpc.NewHTTPHandler(factory)
	defer httpPeer.Close()
	mux := http.NewServeMux()
	mux.Handle("/rpc", httpPeer)
	mux.Handle("/ws", rpc.NewWebSocketHandler(factory))
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		return err
	}
	server := &http.Server{Handler: mux}
	defer server.Close()
	go func() { <-ctx.Done(); _ = server.Close() }()
	fmt.Fprintf(os.Stderr, "listening %d\n", listener.Addr().(*net.TCPAddr).Port)
	err = server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
