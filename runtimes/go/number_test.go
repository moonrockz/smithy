package rpc

import (
	"encoding/json"
	"testing"
)

func TestExactNumbers(t *testing.T) {
	for _, text := range []string{"90071992547409931234567890.0100", "-0.00", "1e+200", "123456789012345678901234567890", "1e+200", "1.000", "0.000e-99999999999999999999999"} {
		var n Number
		if err := json.Unmarshal([]byte(text), &n); err != nil {
			t.Fatal(err)
		}
		out, err := json.Marshal(n)
		if err != nil || string(out) != text {
			t.Fatalf("%s: %s, %v", text, out, err)
		}
	}
	for _, text := range []string{`"1"`, "null", "true", "01", "+1", "NaN"} {
		if _, err := NewNumber(text); err == nil {
			t.Fatalf("accepted %s", text)
		}
	}
	for _, text := range []string{"1.01", "1e-2", `"1"`, "null"} {
		if _, err := NewInteger(text); err == nil {
			t.Fatalf("accepted integer %s", text)
		}
	}
	var doc any
	if err := Decode([]byte(`{"n":900719925474099312345}`), &doc); err != nil {
		t.Fatal(err)
	}
	if doc.(map[string]any)["n"].(json.Number).String() != "900719925474099312345" {
		t.Fatal(doc)
	}
}

func TestExactID(t *testing.T) {
	for _, text := range []string{`"request-1"`, "9007199254740993123456789", "-0", `""`} {
		var id ID
		if err := json.Unmarshal([]byte(text), &id); err != nil {
			t.Fatal(err)
		}
		out, err := json.Marshal(id)
		if err != nil || string(out) != text {
			t.Fatalf("%s: %s, %v", text, out, err)
		}
	}
}

func TestIntegralNumberText(t *testing.T) {
	for _, text := range []string{"1e30", "1.0", "100.000", "1.000e2", "0e-99999999999999999999999999999"} {
		n, err := NewInteger(text)
		if err != nil {
			t.Fatal(err)
		}
		raw, err := json.Marshal(n)
		if err != nil || string(raw) != text {
			t.Fatalf("%s %s %v", text, raw, err)
		}
	}
	a, _ := IntegerID("100")
	b, _ := IntegerID("1e2")
	if a.key() != b.key() {
		t.Fatal("unequal integral IDs")
	}
}
