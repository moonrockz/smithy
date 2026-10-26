package values

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"testing"
	"time"

	rpc "example/values/rpc"
)

func TestSparseCollectionsKeepNullValues(t *testing.T) {
	var input Envelope
	raw := []byte(`{"list":[null,"x"],"map":{"none":null,"some":"x"},"strict":{"text":"ok"}}`)
	if err := json.Unmarshal(raw, &input); err != nil {
		t.Fatal(err)
	}
	encoded, err := json.Marshal(input)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(encoded, []byte(`"list":[null,"x"]`)) || !bytes.Contains(encoded, []byte(`"none":null`)) {
		t.Fatalf("I expected null collection values; I found %s.", encoded)
	}
}

func TestOptionalValuesRejectNullAndDocumentPermitsIt(t *testing.T) {
	for _, member := range []string{`"choice":null`, `"blob":null`} {
		var input Envelope
		raw := `{"list":[],"map":{},"strict":{"text":"ok"},` + member + `}`
		if err := json.Unmarshal([]byte(raw), &input); err == nil {
			t.Fatalf("I expected optional member %s to reject null.", member)
		}
	}
	var input Envelope
	if err := json.Unmarshal([]byte(`{"list":[],"map":{},"strict":{"text":"ok"},"document":null}`), &input); err != nil {
		t.Fatal(err)
	}
	if input.Document == nil || string(*input.Document) != "null" {
		t.Fatal("I expected the document member to keep null.")
	}
	if err := json.Unmarshal([]byte(`{"list":[],"map":{},"strict":{"text":"ok","unknown":true}}`), &input); err == nil {
		t.Fatal("I expected the nested Strict structure to reject its unknown member.")
	}
}

func TestEnumOutputRejectsAnUnknownValue(t *testing.T) {
	if _, err := json.Marshal(Choice("unknown")); err == nil {
		t.Fatal("I expected enum Choice to reject an unknown output value.")
	}
}

func TestRequiredCyclesKeepNonnullChecks(t *testing.T) {
	var mutual CycleA
	if err := json.Unmarshal([]byte(`{"b":{}}`), &mutual); err != nil {
		t.Fatal(err)
	}
	if mutual.B.A != nil {
		t.Fatal("I expected the optional cycle edge to start nil.")
	}
	if err := json.Unmarshal([]byte(`{"b":null}`), &mutual); err == nil {
		t.Fatal("I expected the required cycle edge to reject null.")
	}
}

func TestRequiredDocumentPreservesNullAndExactInteger(t *testing.T) {
	for _, token := range []string{"null", "900719925474099312345678901234567890"} {
		t.Run(token, func(t *testing.T) {
			raw := []byte(`{"value":` + token + `}`)
			var box DocBox
			if err := json.Unmarshal(raw, &box); err != nil {
				t.Fatal(err)
			}
			if string(box.Value) != token {
				t.Fatalf("I expected the exact Document token %s; I found %s.", token, box.Value)
			}
			encoded, err := json.Marshal(box)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(encoded, raw) {
				t.Fatalf("I expected the required Document round trip %s; I found %s.", raw, encoded)
			}
		})
	}
}

func fixtureClient(t *testing.T, method string, handler rpc.Handler) (*Peer, context.Context) {
	t.Helper()
	client, err := NewPeer(Handlers{}, rpc.Options{})
	if err != nil {
		t.Fatal(err)
	}
	server, err := rpc.NewPeer(Contract(), "server", rpc.Options{})
	if err != nil {
		t.Fatal(err)
	}
	if err := server.Register(method, handler); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	a, b := net.Pipe()
	results := make(chan error, 2)
	go func() { results <- client.Serve(ctx, rpc.Stdio(a, a)) }()
	go func() { results <- server.Serve(ctx, rpc.Stdio(b, b)) }()
	t.Cleanup(func() {
		cancel()
		_ = a.Close()
		_ = b.Close()
		for range 2 {
			select {
			case <-results:
			case <-time.After(time.Second):
				t.Error("I expected the fixture peer to stop.")
			}
		}
	})
	select {
	case <-client.Ready():
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	select {
	case <-server.Ready():
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	return client, ctx
}

func TestOptionalErrorDataPreservesAbsenceAndRequiredDocumentNull(t *testing.T) {
	detail := "declined"
	for _, tc := range []struct {
		name    string
		modeled error
	}{
		{"optional-absent", OptionalDetail{}},
		{"optional-present", OptionalDetail{Detail: &detail}},
		{"required-document-null", RequiredDocumentError{Detail: json.RawMessage(`null`)}},
		{"required-document-nil", RequiredDocumentError{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client, ctx := fixtureClient(t, "exchange", func(context.Context, json.RawMessage) (any, error) { return nil, tc.modeled })
			_, err := client.Exchange(ctx, Envelope{List: SparseList{}, Map: SparseMap{}, Strict: Strict{Text: "ok"}})
			switch expected := tc.modeled.(type) {
			case OptionalDetail:
				var actual OptionalDetail
				if !errors.As(err, &actual) {
					t.Fatalf("I expected OptionalDetail; I found %T: %v.", err, err)
				}
				if (expected.Detail == nil) != (actual.Detail == nil) || (expected.Detail != nil && *expected.Detail != *actual.Detail) {
					t.Fatal("I expected OptionalDetail to keep the selected data presence and value.")
				}
			case RequiredDocumentError:
				var actual RequiredDocumentError
				if !errors.As(err, &actual) || string(actual.Detail) != "null" {
					t.Fatalf("I expected required Document null; I found %T: %v.", err, err)
				}
			}
		})
	}
}

func TestEnumMapKeysUseTheirTargetContract(t *testing.T) {
	var exchange rpc.MethodContract
	for _, peer := range Contract().Peers {
		for _, method := range peer.Methods {
			if method.Name == "exchange" {
				exchange = method
			}
		}
	}
	if exchange.ValidateParams == nil || exchange.ValidateResult == nil {
		t.Fatal("I expected the Exchange value validators.")
	}
	for _, tc := range []struct {
		name, member string
		valid        bool
	}{
		{"unknown-enum-key", `"choiceMap":{"unknown":"value"}`, false},
		{"known-enum-key", `"choiceMap":{"yes":"value"}`, true},
		{"unknown-sparse-enum-key", `"choiceSparseMap":{"unknown":null}`, false},
		{"known-sparse-enum-key", `"choiceSparseMap":{"no":null}`, true},
		{"ordinary-string-key", `"stringMap":{"unknown":"value"}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw := json.RawMessage(`{"list":[],"map":{},"strict":{"text":"ok"},` + tc.member + `}`)
			for _, check := range []struct {
				name     string
				validate func(json.RawMessage) error
			}{{"params", exchange.ValidateParams}, {"result", exchange.ValidateResult}} {
				t.Run(check.name, func(t *testing.T) {
					if err := check.validate(raw); (err == nil) != tc.valid {
						t.Fatalf("I expected Exchange %s validity %t; I found %v.", check.name, tc.valid, err)
					}
				})
			}
		})
	}
}

func TestTimestampFormatUsesMemberThenTargetThenDefault(t *testing.T) {
	for _, member := range []string{
		`"plainDefault":1700000000.1250`,
		`"memberDate":"2026-10-25T12:30:00Z"`,
		`"targetDate":"2026-10-25T12:30:00Z"`,
		`"memberEpoch":1700000000.1250`,
		`"overrideEpoch":"2026-10-25T12:30:00Z"`,
		`"dates":["2026-10-25T12:30:00Z"]`,
		`"epochs":[1700000000.1250]`,
		`"values":{"one":"2026-10-25T12:30:00Z"}`,
		`"tagged":{"date":"2026-10-25T12:30:00Z"}`,
		`"tagged":{"epoch":1700000000.1250}`,
	} {
		t.Run(member, func(t *testing.T) {
			raw := []byte(`{` + member + `}`)
			var box TimestampBox
			if err := json.Unmarshal(raw, &box); err != nil {
				t.Fatal(err)
			}
			encoded, err := json.Marshal(box)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(encoded, raw) {
				t.Fatalf("I expected the timestamp format round trip %s; I found %s.", raw, encoded)
			}
		})
	}
}

func TestSelectedTimestampResultAndErrorKeepMemberFormat(t *testing.T) {
	t.Run("result", func(t *testing.T) {
		client, ctx := fixtureClient(t, "time.read", func(context.Context, json.RawMessage) (any, error) { return "2026-10-25T12:30:00Z", nil })
		actual, err := client.ReadTime(ctx)
		if err != nil || actual != "2026-10-25T12:30:00Z" {
			t.Fatalf("I expected the selected timestamp date-time result; I found %v, %v.", actual, err)
		}
	})
	t.Run("error", func(t *testing.T) {
		client, ctx := fixtureClient(t, "time.read", func(context.Context, json.RawMessage) (any, error) {
			return nil, TimeError{Detail: rpc.Number("1700000000.1250")}
		})
		_, err := client.ReadTime(ctx)
		var actual TimeError
		if !errors.As(err, &actual) || actual.Detail != "1700000000.1250" {
			t.Fatalf("I expected selected error timestamp epoch-seconds; I found %T: %v.", err, err)
		}
	})
}

func TestStringMapReportsTheFirstInvalidKeyLexically(t *testing.T) {
	for range 256 {
		var value StringMap
		err := json.Unmarshal([]byte(`{"a":1,"z":true}`), &value)
		var mismatch *json.UnmarshalTypeError
		if !errors.As(err, &mismatch) || mismatch.Value != "number" {
			t.Fatalf("I expected the numeric value at first key `a` to fail; I found %v.", err)
		}
	}
}
