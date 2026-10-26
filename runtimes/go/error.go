package rpc

import (
	"encoding/json"
	"errors"
	"math/big"
	"strconv"
	"strings"

	"go.lsp.dev/jsonrpc2"
)

// Error is a JSON-RPC error with exact, optional data.
type Error struct {
	Code    int64           `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *Error) Error() string { return e.Message }
func NewError(code int64, message string, data any) *Error {
	e := &Error{Code: code, Message: message}
	if data != nil {
		raw, err := json.Marshal(data)
		if err != nil {
			return &Error{Code: -32603, Message: "I could not encode the RPC error data"}
		}
		e.Data = raw
	}
	return e
}
func wireError(err error) error {
	if err == nil {
		return nil
	}
	err = modeledError(err)
	var e *Error
	if errors.As(err, &e) {
		return &jsonrpc2.Error{Code: jsonrpc2.Code(e.Code), Message: e.Message, Data: jsonrpc2.RawMessage(e.Data)}
	}
	var upstream *jsonrpc2.Error
	if errors.As(err, &upstream) {
		return upstream
	}
	return &jsonrpc2.Error{Code: -32603, Message: "I could not complete the RPC request"}
}
func localError(err error) error {
	var e *jsonrpc2.Error
	if errors.As(err, &e) {
		return &Error{Code: int64(e.Code), Message: e.Message, Data: json.RawMessage(e.Data)}
	}
	return err
}

func modeledError(err error) error {
	var modeled interface{ RPCError() *Error }
	if errors.As(err, &modeled) {
		if rpcError := modeled.RPCError(); rpcError != nil {
			return rpcError
		}
	}
	return err
}

// UnmarshalJSON requires an integer code and a string message.
func (e *Error) UnmarshalJSON(raw []byte) error {
	var fields struct {
		Code    Integer         `json:"code"`
		Message *string         `json:"message"`
		Data    json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	if fields.Code == "" || fields.Message == nil {
		return errors.New("I expected an RPC error code and message")
	}
	coefficient, exponent, ok := integerParts(string(fields.Code))
	if !ok || exponent.Cmp(big.NewInt(19)) > 0 {
		return errors.New("I expected an RPC error code within int64")
	}
	count := int(exponent.Int64())
	if len(strings.TrimPrefix(coefficient, "-"))+count > 19 {
		return errors.New("I expected an RPC error code within int64")
	}
	code, err := strconv.ParseInt(coefficient+strings.Repeat("0", count), 10, 64)
	if err != nil {
		return errors.New("I expected an RPC error code within int64")
	}
	*e = Error{Code: code, Message: *fields.Message, Data: fields.Data}
	return nil
}
