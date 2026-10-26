package sample

import (
	"context"
	"net"
	"time"

	payments "example/payments/pos"
	posrpc "example/payments/pos/rpc"
	"testing"

	terminal "example/payments/terminal"
	rpc "example/payments/terminal/rpc"
)

func TestRefundKeepsExactAmountAndChecksLimit(t *testing.T) {
	store := newPaymentStore()
	store.paid["test-big"] = terminal.Money{Amount: rpc.Number("12345678901234567.00"), Currency: terminal.CurrencyUsd}
	input := terminal.RefundInput{PaymentId: "test-big", Amount: terminal.Money{Amount: rpc.Number("2.50"), Currency: terminal.CurrencyUsd}}
	result, err := store.refund(context.Background(), input)
	if err != nil || string(result.Amount.Amount) != "2.50" {
		t.Fatalf("refund: %+v %v", result, err)
	}
	input.Amount.Amount = rpc.Number("12345678901234568.00")
	_, err = store.refund(context.Background(), input)
	problem, ok := err.(terminal.RefundExceedsAmount)
	if !ok || string(problem.Maximum.Amount) != "12345678901234567.00" {
		t.Fatalf("limit: %#v", err)
	}
}

func TestGeneratedPeersRunScenarios(t *testing.T) {
	for _, scenario := range []string{"payment", "errors", "cancellation", "refusals"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			terminal, err := NewTerminal(rpc.Options{})
			if err != nil {
				t.Fatal(err)
			}
			defer terminal.Close()
			pos, err := NewPOS(posrpc.Options{}, scenario)
			if err != nil {
				t.Fatal(err)
			}
			defer pos.Close()
			a, b := net.Pipe()
			defer a.Close()
			defer b.Close()
			done := make(chan error, 2)
			go func() { done <- terminal.Serve(ctx, rpc.Stdio(a, a)) }()
			go func() { done <- pos.Serve(ctx, posrpc.Stdio(b, b)) }()
			select {
			case <-pos.Ready():
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			select {
			case <-terminal.Ready():
			case <-ctx.Done():
				t.Fatal(ctx.Err())
			}
			if err := pos.Run(ctx); err != nil {
				t.Fatal(err)
			}
			_ = pos.Close()
			_ = terminal.Close()
			<-done
			<-done
		})
	}
}

func TestTerminalRejectsUnmaskedTestEntry(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	terminal, err := NewTerminal(rpc.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer terminal.Close()
	pos, err := NewPOS(posrpc.Options{}, "payment")
	if err != nil {
		t.Fatal(err)
	}
	defer pos.Close()
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	go func() { _ = terminal.Serve(ctx, rpc.Stdio(a, a)) }()
	go func() { _ = pos.Serve(ctx, posrpc.Stdio(b, b)) }()
	<-pos.Ready()
	<-terminal.Ready()
	if err := pos.initialize(ctx, "test checkout"); err != nil {
		t.Fatal(err)
	}
	input := paymentInput("test-mask", "20.00", "chip")
	input.Entry = payments.EntryMethodChip{Value: payments.TestCard{MaskedNumber: "unmasked-test-value"}}
	_, err = pos.StartPayment(ctx, input)
	if errorCode(err) != -32602 {
		t.Fatalf("I expected an invalid-params refusal for an unmasked test card, found %v.", err)
	}
}

func TestReceiptTipKeepsEveryDecimalPlace(t *testing.T) {
	total, err := receiptTotal(rpc.Number("12345678901234567.001"))
	if err != nil || string(total) != "12345678901234569.501" {
		t.Fatalf("I expected an exact receipt total, found %s, %v.", total, err)
	}
	total, err = receiptTotal(rpc.Number("20.00"))
	if err != nil || string(total) != "22.50" {
		t.Fatalf("I expected total 22.50, found %s, %v.", total, err)
	}
}
