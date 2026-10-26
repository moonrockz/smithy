// Package sample supplies masked-data payment handlers for generated Go peers.
package sample

import (
	"context"
	"errors"
	"math/big"
	"strings"
	"sync"

	terminal "example/payments/terminal"
	rpc "example/payments/terminal/rpc"
)

type paymentStore struct {
	mu   sync.Mutex
	paid map[string]terminal.Money
}

func newPaymentStore() *paymentStore { return &paymentStore{paid: make(map[string]terminal.Money)} }
func pointer[T any](value T) *T      { return &value }
func money(text string) terminal.Money {
	return terminal.Money{Amount: rpc.Number(text), Currency: terminal.CurrencyUsd}
}

func (store *paymentStore) lookup(id string) (terminal.Money, error) {
	store.mu.Lock()
	defer store.mu.Unlock()
	amount, ok := store.paid[id]
	if !ok {
		return terminal.Money{}, terminal.PaymentNotFound{PaymentId: id}
	}
	return amount, nil
}

func (store *paymentStore) refund(_ context.Context, input terminal.RefundInput) (terminal.RefundOutput, error) {
	paid, err := store.lookup(input.PaymentId)
	if err != nil {
		return terminal.RefundOutput{}, err
	}
	requested, ok := new(big.Rat).SetString(string(input.Amount.Amount))
	if !ok {
		return terminal.RefundOutput{}, errors.New("I could not read the refund amount.")
	}
	limit, ok := new(big.Rat).SetString(string(paid.Amount))
	if !ok {
		return terminal.RefundOutput{}, errors.New("I could not read the paid amount.")
	}
	if requested.Cmp(limit) > 0 {
		return terminal.RefundOutput{}, terminal.RefundExceedsAmount{PaymentId: input.PaymentId, Maximum: paid}
	}
	return terminal.RefundOutput{RefundId: "test-refund", Amount: input.Amount}, nil
}

// NewTerminal creates one session. Each HTTP session gets its own peer and store.
func NewTerminal(options rpc.Options) (*terminal.Peer, error) {
	store := newPaymentStore()
	var peer *terminal.Peer
	handlers := terminal.Handlers{
		Initialize: func(_ context.Context, input terminal.InitializeInput) (terminal.InitializeOutput, error) {
			enabled := !strings.Contains(input.PosName, "no payment")
			return terminal.InitializeOutput{ProtocolVersion: terminal.ProtocolVersionV1, TerminalId: "test-terminal", Capabilities: terminal.Capabilities{
				Payment: pointer(enabled), Swipe: pointer(true), Chip: pointer(true), Contactless: pointer(true), Pin: pointer(true), Tips: pointer(true), Signature: pointer(true), Progress: pointer(true), Cancellation: pointer(true),
			}}, nil
		},
		Initialized:   func(context.Context) error { return nil },
		Ping:          func(context.Context) error { return nil },
		Shutdown:      func(context.Context) error { return nil },
		Exit:          func(context.Context) error { return nil },
		CancelRequest: func(context.Context, terminal.CancelRequestInput) error { return nil },
		RefundPayment: store.refund,
		VoidPayment: func(_ context.Context, input terminal.PaymentIdInput) error {
			if _, err := store.lookup(input.PaymentId); err != nil {
				return err
			}
			store.mu.Lock()
			delete(store.paid, input.PaymentId)
			store.mu.Unlock()
			return nil
		},
		PaymentStatus: func(_ context.Context, input terminal.PaymentIdInput) (terminal.PaymentOutcome, error) {
			if _, err := store.lookup(input.PaymentId); err != nil {
				return nil, err
			}
			return terminal.PaymentOutcomeApproved{Value: terminal.Approved{AuthorizationCode: "TEST-OK"}}, nil
		},
		GetReceipt: func(_ context.Context, input terminal.PaymentIdInput) (terminal.Receipt, error) {
			paid, err := store.lookup(input.PaymentId)
			if err != nil {
				return terminal.Receipt{}, err
			}
			total, err := receiptTotal(paid.Amount)
			if err != nil {
				return terminal.Receipt{}, err
			}
			tip := terminal.Money{Amount: rpc.Number("2.50"), Currency: paid.Currency}
			return terminal.Receipt{PaymentId: input.PaymentId, Merchant: terminal.Merchant{Name: "Test shop", Address: pointer("Test street")}, Lines: terminal.ReceiptLines{
				{Label: "Test item", Amount: paid}, {Label: "Test tip", Amount: tip},
			}, Total: terminal.Money{Amount: total, Currency: paid.Currency}, CustomerCopy: pointer(true)}, nil
		},
		ListTransactions: func(_ context.Context, input terminal.ListTransactionsInput) (terminal.ListTransactionsOutput, error) {
			if input.NextToken != nil {
				return terminal.ListTransactionsOutput{Transactions: terminal.Transactions{}}, nil
			}
			labels := terminal.Labels{"checkout": "test", "card": "**** 4242"}
			return terminal.ListTransactionsOutput{Transactions: terminal.Transactions{{PaymentId: "test-1", CreatedAt: rpc.Number("1792886400"), Amount: money("22.50"), Labels: &labels}}, NextToken: pointer("test-page-2")}, nil
		},
	}
	handlers.StartPayment = func(ctx context.Context, input terminal.StartPaymentInput) (terminal.PaymentOutput, error) {
		if !maskedEntry(input.Entry) {
			return terminal.PaymentOutput{}, rpc.NewError(-32602, "I expected a masked test card in payment.start.", nil)
		}
		value, ok := new(big.Rat).SetString(string(input.Amount.Amount))
		if !ok {
			return terminal.PaymentOutput{}, errors.New("I could not read the payment amount.")
		}
		cents := new(big.Rat).Mul(value, big.NewRat(100, 1))
		ending := int64(-1)
		if cents.IsInt() {
			ending = new(big.Int).Mod(cents.Num(), big.NewInt(100)).Int64()
		}
		switch ending {
		case 13:
			return terminal.PaymentOutput{}, terminal.CardDeclined{Reason: "test decline"}
		case 14:
			return terminal.PaymentOutput{}, terminal.CardRemoved{}
		case 15:
			return terminal.PaymentOutput{}, terminal.TerminalBusy{RetryAfterSeconds: 1}
		case 16:
			return terminal.PaymentOutput{}, terminal.Timeout{}
		case 21:
			return terminal.PaymentOutput{PaymentId: input.PaymentId, Outcome: terminal.PaymentOutcomeDeclined{Value: terminal.Declined{Reason: "test decline"}}}, nil
		case 22:
			return terminal.PaymentOutput{PaymentId: input.PaymentId, Outcome: terminal.PaymentOutcomePartiallyApproved{Value: terminal.PartiallyApproved{AuthorizedAmount: money("1.00")}}}, nil
		}
		id, ok := rpc.RequestID(ctx)
		if !ok {
			return terminal.PaymentOutput{}, errors.New("I could not find the active payment request ID.")
		}
		idJSON, err := id.MarshalJSON()
		if err != nil {
			return terminal.PaymentOutput{}, err
		}
		progress := func(phase terminal.PaymentPhase) error {
			return peer.PaymentProgress(ctx, terminal.PaymentProgressInput{RequestId: idJSON, Phase: phase})
		}
		if err := progress(terminal.PaymentPhaseInsertCard); err != nil {
			return terminal.PaymentOutput{}, err
		}
		if ending == 17 {
			<-ctx.Done()
			return terminal.PaymentOutput{}, ctx.Err()
		}
		if err := progress(terminal.PaymentPhaseEnterPin); err != nil {
			return terminal.PaymentOutput{}, err
		}
		accepted, err := peer.ConfirmTip(ctx, terminal.ConfirmTipInput{PaymentId: input.PaymentId, Amount: money("2.50")})
		if err != nil {
			return terminal.PaymentOutput{}, err
		}
		if !accepted {
			return terminal.PaymentOutput{}, terminal.CardDeclined{Reason: "test tip refused"}
		}
		signature, err := peer.RequestSignature(ctx, terminal.RequestSignatureInput{PaymentId: input.PaymentId, Prompt: "Sign the test receipt"})
		if err != nil {
			return terminal.PaymentOutput{}, err
		}
		if string(signature) != "test-signature" {
			return terminal.PaymentOutput{}, errors.New("I expected the masked test signature.")
		}
		if err := peer.Display(ctx, terminal.DisplayInput{Message: "I am checking the test payment."}); err != nil {
			return terminal.PaymentOutput{}, err
		}
		if err := progress(terminal.PaymentPhaseAuthorizing); err != nil {
			return terminal.PaymentOutput{}, err
		}
		store.mu.Lock()
		store.paid[input.PaymentId] = input.Amount
		store.mu.Unlock()
		return terminal.PaymentOutput{PaymentId: input.PaymentId, Outcome: terminal.PaymentOutcomeApproved{Value: terminal.Approved{AuthorizationCode: "TEST-OK"}}}, nil
	}
	var err error
	peer, err = terminal.NewPeer(handlers, options)
	return peer, err
}

func maskedEntry(entry terminal.EntryMethod) bool {
	var text string
	switch card := entry.(type) {
	case terminal.EntryMethodSwipe:
		text = card.Value.MaskedNumber
	case terminal.EntryMethodChip:
		text = card.Value.MaskedNumber
	case terminal.EntryMethodContactless:
		text = card.Value.MaskedNumber
	case terminal.EntryMethodManualEntry:
		text = card.Value.MaskedNumber
	default:
		return false
	}
	if len(text) != 9 || !strings.HasPrefix(text, "**** ") {
		return false
	}
	for _, digit := range text[5:] {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

func receiptTotal(paid rpc.Number) (rpc.Number, error) {
	value, ok := new(big.Rat).SetString(string(paid))
	if !ok {
		return "", errors.New("I could not read the paid amount for the receipt.")
	}
	value.Add(value, big.NewRat(5, 2))
	denominator := new(big.Int).Set(value.Denom())
	twos := int(denominator.TrailingZeroBits())
	denominator.Rsh(denominator, uint(twos))
	fives := 0
	for denominator.Cmp(big.NewInt(1)) > 0 {
		quotient, remainder := new(big.Int), new(big.Int)
		quotient.QuoRem(denominator, big.NewInt(5), remainder)
		if remainder.Sign() != 0 {
			return "", errors.New("I could not write an exact decimal receipt total.")
		}
		denominator = quotient
		fives++
	}
	places := max(2, max(twos, fives))
	// FloatString writes the exact rational at its full decimal scale.
	return rpc.NewNumber(value.FloatString(places))
}
