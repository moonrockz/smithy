package payments

import (
	"bytes"
	"encoding/json"
	"errors"
	"testing"

	rpc "example/payments/pos/rpc"
)

func TestRequiredStringRejectsNull(t *testing.T) {
	var input InitializeInput
	if err := json.Unmarshal([]byte(`{"protocolVersion":"1","posName":null}`), &input); err == nil {
		t.Fatal("I expected member `InitializeInput$posName` to reject null.")
	}
}

func TestPaymentUnionPreservesExactAmount(t *testing.T) {
	raw := []byte(`{"paymentId":"p1","amount":{"amount":9007199254740993.1250,"currency":"USD"},"entry":{"swipe":{"maskedNumber":"**** 1234"}},"futureField":true}`)
	var input StartPaymentInput
	if err := json.Unmarshal(raw, &input); err != nil {
		t.Fatal(err)
	}
	if input.Amount.Amount != "9007199254740993.1250" {
		t.Fatalf("I expected the exact decimal token; I found %q.", input.Amount.Amount)
	}
	card, ok := input.Entry.(EntryMethodSwipe)
	if !ok || card.Value.MaskedNumber != "**** 1234" {
		t.Fatalf("I expected the swipe union member; I found %#v.", input.Entry)
	}
	encoded, err := json.Marshal(input)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(encoded, []byte(`9007199254740993.1250`)) || bytes.Contains(encoded, []byte(`futureField`)) {
		t.Fatalf("I expected exact data and ignored unknown members; I found %s.", encoded)
	}
}

func TestModeledErrorsKeepSelectedAndAbsentData(t *testing.T) {
	wire := (CardDeclined{Reason: "test decline"}).RPCError()
	if wire.Code != 1001 || string(wire.Data) != `"test decline"` {
		t.Fatalf("I expected the prepared CardDeclined mapping; I found %#v.", wire)
	}
	var declined CardDeclined
	if !errors.As(decodeStartPaymentError(wire), &declined) || declined.Reason != "test decline" {
		t.Fatal("I expected a typed CardDeclined error.")
	}
	var removed CardRemoved
	if err := json.Unmarshal([]byte(`{}`), &removed); err != nil {
		t.Fatal(err)
	}
	if wire := removed.RPCError(); wire.Code != 1002 || len(wire.Data) != 0 {
		t.Fatalf("I expected an absent-data CardRemoved mapping; I found %#v.", wire)
	}
	unmapped := rpc.NewError(1999, "I received an unmapped error.", nil)
	if decodeStartPaymentError(unmapped) != unmapped {
		t.Fatal("I expected an unmapped error to retain its runtime value.")
	}
}

func TestContractIsFreshAndKeepsPreparedSessionRules(t *testing.T) {
	first := Contract()
	first.Session.States[0] = "changed"
	contract := Contract()
	if contract.Session.States[0] != "starting" {
		t.Fatal("I expected a fresh session contract.")
	}
	foundCancel, foundProgress := false, false
	for _, rule := range contract.Session.Methods {
		if rule.Method == "$/cancelRequest" {
			foundCancel = rule.Cancels != nil && rule.Cancels.WireName == "id" && *rule.Cancels.Code == -32800
		}
	}
	for _, peer := range contract.Peers {
		for _, method := range peer.Methods {
			if method.Name == "payment.progress" {
				foundProgress = method.Kind == "notification" && method.RefersToCall != nil && method.RefersToCall.WireName == "requestId"
			}
		}
	}
	if !foundCancel || !foundProgress {
		t.Fatal("I expected the prepared cancellation and progress rules.")
	}
}
