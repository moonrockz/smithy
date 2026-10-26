package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	sample "example/payment-sample"
	rpc "example/payments/pos/rpc"
)

func run() error {
	scenario := flag.String("scenario", "payment", "Payment scenario")
	target := flag.String("connect", "stdio", "Peer transport endpoint")
	logPath := flag.String("log", "", "JSONL log path")
	flag.Parse()
	var log io.Writer
	if *logPath != "" {
		file, err := os.Create(*logPath)
		if err != nil {
			return err
		}
		defer file.Close()
		log = file
	}
	app, err := sample.NewPOS(rpc.Options{Log: log}, *scenario)
	if err != nil {
		return err
	}
	defer app.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	var transport rpc.Transport
	var child *exec.Cmd
	var input io.WriteCloser
	switch {
	case *target == "stdio":
		args := flag.Args()
		if len(args) == 0 {
			return errors.New("I expected the terminal command after -- for stdio.")
		}
		child = exec.CommandContext(ctx, args[0], args[1:]...)
		child.Stderr = os.Stderr
		output, err := child.StdoutPipe()
		if err != nil {
			return err
		}
		input, err = child.StdinPipe()
		if err != nil {
			return err
		}
		if err := child.Start(); err != nil {
			return err
		}
		defer func() {
			_ = input.Close()
			if child.Process != nil {
				_ = child.Process.Kill()
			}
			_ = child.Wait()
		}()
		transport = rpc.Stdio(output, input)
	case strings.HasPrefix(*target, "http://") || strings.HasPrefix(*target, "https://"):
		transport = rpc.NewHTTPTransport(*target, &http.Client{})
	case strings.HasPrefix(*target, "ws://") || strings.HasPrefix(*target, "wss://"):
		transport, err = rpc.DialWebSocket(ctx, *target)
		if err != nil {
			return err
		}
	default:
		return fmt.Errorf("I do not know POS target `%s`.", *target)
	}
	serveDone := make(chan error, 1)
	go func() { serveDone <- app.Serve(ctx, transport) }()
	select {
	case <-app.Ready():
	case err := <-serveDone:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
	err = app.Run(ctx)
	_ = app.Close()
	if input != nil {
		_ = input.Close()
	}
	if child != nil {
		if waitErr := child.Wait(); err == nil && waitErr != nil {
			err = waitErr
		}
	}
	return err
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
