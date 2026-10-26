package sample

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"

	pos "example/payments/pos"
	rpc "example/payments/pos/rpc"
)

type POS struct {
	*pos.Peer
	mu         sync.Mutex
	scenario   string
	progress   int
	tips       int
	signatures int
	displays   int
}

func NewPOS(options rpc.Options, scenario string) (*POS, error) {
	application := &POS{scenario: scenario}
	peer, err := pos.NewPeer(pos.Handlers{
		ConfirmTip: func(_ context.Context, input pos.ConfirmTipInput) (bool, error) {
			if string(input.Amount.Amount) != "2.50" {
				return false, errors.New("I expected exact tip amount 2.50.")
			}
			application.mu.Lock()
			application.tips++
			application.mu.Unlock()
			return true, nil
		},
		RequestSignature: func(_ context.Context, input pos.RequestSignatureInput) ([]byte, error) {
			if input.Prompt != "Sign the test receipt" {
				return nil, errors.New("I expected the test signature prompt.")
			}
			application.mu.Lock()
			application.signatures++
			application.mu.Unlock()
			return []byte("test-signature"), nil
		},
		Display: func(_ context.Context, input pos.DisplayInput) error {
			if input.Message != "I am checking the test payment." {
				return errors.New("I expected the test display message.")
			}
			application.mu.Lock()
			application.displays++
			application.mu.Unlock()
			return nil
		},
		PaymentProgress: func(ctx context.Context, input pos.PaymentProgressInput) error {
			application.mu.Lock()
			application.progress++
			application.mu.Unlock()
			if scenario == "cancellation" && input.Phase == pos.PaymentPhaseInsertCard {
				return application.CancelRequest(ctx, pos.CancelRequestInput{Id: input.RequestId})
			}
			return nil
		},
	}, options)
	if err != nil {
		return nil, err
	}
	application.Peer = peer
	return application, nil
}

func posMoney(text string) pos.Money {
	return pos.Money{Amount: rpc.Number(text), Currency: pos.CurrencyUsd}
}
func paymentInput(id, amount, entry string) pos.StartPaymentInput {
	card := pos.TestCard{MaskedNumber: "**** 4242"}
	var method pos.EntryMethod
	switch entry {
	case "swipe":
		method = pos.EntryMethodSwipe{Value: card}
	case "contactless":
		method = pos.EntryMethodContactless{Value: card}
	case "manualEntry":
		method = pos.EntryMethodManualEntry{Value: card}
	default:
		method = pos.EntryMethodChip{Value: card}
	}
	return pos.StartPaymentInput{PaymentId: id, Amount: posMoney(amount), Entry: method}
}

func errorCode(err error) int64 {
	if err == nil {
		return 0
	}
	var wire *rpc.Error
	if errors.As(err, &wire) {
		return wire.Code
	}
	var modeled interface{ RPCError() *rpc.Error }
	if errors.As(err, &modeled) {
		return modeled.RPCError().Code
	}
	return -1
}
func requireCode(err error, code int64) error {
	if errorCode(err) != code {
		return fmt.Errorf("I expected error code %d for the payment scenario, found %v.", code, err)
	}
	return nil
}

func (app *POS) initialize(ctx context.Context, name string) error {
	result, err := app.Initialize(ctx, pos.InitializeInput{ProtocolVersion: pos.ProtocolVersionV1, PosName: name})
	if err != nil {
		return err
	}
	if result.TerminalId != "test-terminal" || result.ProtocolVersion != pos.ProtocolVersionV1 {
		return errors.New("I expected the test terminal initialize result.")
	}
	return app.Initialized(ctx)
}

func (app *POS) Run(ctx context.Context) error {
	if app.scenario == "refusals" {
		return app.refusals(ctx)
	}
	if app.scenario == "payment" {
		id, err := rpc.IntegerID("900719925474099312345")
		if err != nil {
			return err
		}
		if err := app.Peer.Peer.CallWithID(ctx, id, "terminal.ping", struct{}{}, nil); err != nil {
			return err
		}
	}
	if err := app.initialize(ctx, "test checkout"); err != nil {
		return err
	}
	switch app.scenario {
	case "payment":
		if err := app.payment(ctx); err != nil {
			return err
		}
	case "errors":
		if err := app.errorScenario(ctx); err != nil {
			return err
		}
	case "cancellation":
		_, err := app.StartPayment(ctx, paymentInput("test-cancel", "12345678901234567.17", "chip"))
		if err := requireCode(err, -32800); err != nil {
			return err
		}
	default:
		return fmt.Errorf("I do not know payment scenario `%s`.", app.scenario)
	}
	if err := app.Shutdown(ctx); err != nil {
		return err
	}
	if err := app.Exit(ctx); err != nil {
		return err
	}
	// A request after exit proves that the terminal processed the notification.
	return app.Ping(ctx)
}

func (app *POS) payment(ctx context.Context) error {
	var paid pos.PaymentOutput
	if err := app.Peer.Peer.CallWithID(ctx, rpc.StringID("payment-1"), "payment.start", paymentInput("test-1", "20.00", "chip"), &paid); err != nil {
		return err
	}
	if _, ok := paid.Outcome.(pos.PaymentOutcomeApproved); !ok {
		return errors.New("I expected an approved test payment.")
	}
	outcome, err := app.PaymentStatus(ctx, pos.PaymentIdInput{PaymentId: "test-1"})
	if err != nil {
		return err
	}
	if _, ok := outcome.(pos.PaymentOutcomeApproved); !ok {
		return errors.New("I expected an approved payment status.")
	}
	receipt, err := app.GetReceipt(ctx, pos.PaymentIdInput{PaymentId: "test-1"})
	if err != nil {
		return err
	}
	if string(receipt.Total.Amount) != "22.50" || len(receipt.Lines) != 2 || receipt.Merchant.Name != "Test shop" {
		return errors.New("I expected the complete test receipt.")
	}
	since := rpc.Number("0")
	page, err := app.ListTransactions(ctx, pos.ListTransactionsInput{Since: &since})
	if err != nil {
		return err
	}
	if len(page.Transactions) != 1 || page.NextToken == nil {
		return errors.New("I expected a first transaction page.")
	}
	last, err := app.ListTransactions(ctx, pos.ListTransactionsInput{NextToken: page.NextToken})
	if err != nil {
		return err
	}
	if len(last.Transactions) != 0 {
		return errors.New("I expected an empty last transaction page.")
	}
	refund, err := app.RefundPayment(ctx, pos.RefundInput{PaymentId: "test-1", Amount: posMoney("2.50")})
	if err != nil {
		return err
	}
	if string(refund.Amount.Amount) != "2.50" {
		return errors.New("I expected the exact refund amount 2.50.")
	}
	if err := app.VoidPayment(ctx, pos.PaymentIdInput{PaymentId: "test-1"}); err != nil {
		return err
	}
	app.mu.Lock()
	defer app.mu.Unlock()
	if app.progress != 3 || app.tips != 1 || app.signatures != 1 || app.displays != 1 {
		return fmt.Errorf("I expected payment progress and callbacks, found %d, %d, %d, %d.", app.progress, app.tips, app.signatures, app.displays)
	}
	return nil
}

func (app *POS) errorScenario(ctx context.Context) error {
	for index, fixture := range []struct {
		amount, entry string
		code          int64
	}{{"1.13", "swipe", 1001}, {"1.14", "contactless", 1002}, {"1.15", "manualEntry", 1003}, {"1.16", "chip", 1004}} {
		_, err := app.StartPayment(ctx, paymentInput(fmt.Sprintf("test-%d", index+1), fixture.amount, fixture.entry))
		if err := requireCode(err, fixture.code); err != nil {
			return err
		}
	}
	declined, err := app.StartPayment(ctx, paymentInput("test-declined", "1.21", "chip"))
	if err != nil {
		return err
	}
	if _, ok := declined.Outcome.(pos.PaymentOutcomeDeclined); !ok {
		return errors.New("I expected the declined outcome union member.")
	}
	partial, err := app.StartPayment(ctx, paymentInput("test-partial", "1.22", "chip"))
	if err != nil {
		return err
	}
	if _, ok := partial.Outcome.(pos.PaymentOutcomePartiallyApproved); !ok {
		return errors.New("I expected the partially approved outcome union member.")
	}
	if _, err := app.StartPayment(ctx, paymentInput("test-big", "12345678901234567.00", "chip")); err != nil {
		return err
	}
	_, err = app.RefundPayment(ctx, pos.RefundInput{PaymentId: "test-big", Amount: posMoney("12345678901234568.00")})
	if err := requireCode(err, 1006); err != nil {
		return err
	}
	var limit pos.RefundExceedsAmount
	if !errors.As(err, &limit) || string(limit.Maximum.Amount) != "12345678901234567.00" {
		return errors.New("I expected the exact maximum refund amount.")
	}
	return requireCode(app.VoidPayment(ctx, pos.PaymentIdInput{PaymentId: "test-missing"}), 1005)
}

func (app *POS) refusals(ctx context.Context) error {
	status := pos.PaymentIdInput{PaymentId: "test-missing"}
	_, err := app.PaymentStatus(ctx, status)
	if err := requireCode(err, 1007); err != nil {
		return err
	}
	var raw json.RawMessage
	if err := requireCode(app.Peer.Peer.CallUnchecked(ctx, "payment.status", status, &raw), 1007); err != nil {
		return err
	}
	if err := app.initialize(ctx, "test checkout (no payment)"); err != nil {
		return err
	}
	input := paymentInput("test-refused", "20.00", "chip")
	_, err = app.StartPayment(ctx, input)
	if err := requireCode(err, 1008); err != nil {
		return err
	}
	if err := requireCode(app.Peer.Peer.CallUnchecked(ctx, "payment.start", input, &raw), 1008); err != nil {
		return err
	}
	if err := app.Shutdown(ctx); err != nil {
		return err
	}
	_, err = app.PaymentStatus(ctx, status)
	if err := requireCode(err, 1007); err != nil {
		return err
	}
	if err := requireCode(app.Peer.Peer.CallUnchecked(ctx, "payment.status", status, &raw), 1007); err != nil {
		return err
	}
	if err := app.Exit(ctx); err != nil {
		return err
	}
	return app.Ping(ctx)
}
