package rpc

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"regexp"
	"strings"
)

var numberSyntax = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$`)

// Number keeps the exact JSON text of a Smithy bigDecimal.
type Number string

func NewNumber(text string) (Number, error) {
	if !numberSyntax.MatchString(text) {
		return "", errors.New("I expected a JSON number")
	}
	return Number(text), nil
}
func (n Number) MarshalJSON() ([]byte, error) { v, err := NewNumber(string(n)); return []byte(v), err }
func (n *Number) UnmarshalJSON(data []byte) error {
	v, err := NewNumber(string(bytes.TrimSpace(data)))
	if err == nil {
		*n = v
	}
	return err
}

// Integer keeps the exact JSON text of a Smithy bigInteger.
type Integer string

func NewInteger(text string) (Integer, error) {
	if _, _, valid := integerParts(text); !valid {
		return "", errors.New("I expected an exact integer JSON number")
	}
	return Integer(text), nil
}
func (n Integer) MarshalJSON() ([]byte, error) {
	v, err := NewInteger(string(n))
	return []byte(v), err
}
func (n *Integer) UnmarshalJSON(data []byte) error {
	v, err := NewInteger(string(bytes.TrimSpace(data)))
	if err == nil {
		*n = v
	}
	return err
}

// Decode keeps numbers in document values as json.Number.
func Decode(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("I expected one JSON value")
	}
	return nil
}

// ID is a string or an integer of any size. Its JSON text is retained.
type ID struct{ text string }

func StringID(text string) ID { data, _ := json.Marshal(text); return ID{text: string(data)} }
func IntegerID(text string) (ID, error) {
	if _, err := NewInteger(text); err != nil {
		return ID{}, err
	}
	return ID{text: text}, nil
}
func (id ID) MarshalJSON() ([]byte, error) {
	if id.text == "" {
		return []byte("null"), nil
	}
	return []byte(id.text), nil
}
func (id *ID) UnmarshalJSON(data []byte) error {
	data = bytes.TrimSpace(data)
	if len(data) > 0 && data[0] == '"' {
		var text string
		if err := json.Unmarshal(data, &text); err != nil {
			return err
		}
		*id = StringID(text)
		return nil
	}
	value, err := IntegerID(string(data))
	if err == nil {
		*id = value
	}
	return err
}
func (id ID) String() string { return id.text }
func (id ID) IsValid() bool  { return id.text != "" }
func (id ID) key() string {
	if id.text == "" || id.text[0] == '"' {
		return id.text
	}
	coefficient, exponent, _ := integerParts(id.text)
	return coefficient + "e" + exponent.String()
}

// integerParts proves integrality without expanding a decimal exponent.
func integerParts(text string) (string, *big.Int, bool) {
	if !numberSyntax.MatchString(text) {
		return "", nil, false
	}
	negative := strings.HasPrefix(text, "-")
	unsigned := strings.TrimPrefix(text, "-")
	exponent := new(big.Int)
	if at := strings.IndexAny(unsigned, "eE"); at >= 0 {
		exponent.SetString(strings.TrimPrefix(unsigned[at+1:], "+"), 10)
		unsigned = unsigned[:at]
	}
	if at := strings.IndexByte(unsigned, '.'); at >= 0 {
		exponent.Sub(exponent, big.NewInt(int64(len(unsigned)-at-1)))
		unsigned = unsigned[:at] + unsigned[at+1:]
	}
	coefficient := strings.TrimLeft(unsigned, "0")
	if coefficient == "" {
		return "0", new(big.Int), true
	}
	trimmed := strings.TrimRight(coefficient, "0")
	exponent.Add(exponent, big.NewInt(int64(len(coefficient)-len(trimmed))))
	if exponent.Sign() < 0 {
		return "", nil, false
	}
	if negative {
		trimmed = "-" + trimmed
	}
	return trimmed, exponent, true
}
