package values

import (
	"bytes"
	"encoding/json"
	"testing"
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
