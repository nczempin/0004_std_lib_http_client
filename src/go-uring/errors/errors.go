package errors

import "fmt"

// ErrorType represents the category of error
type ErrorType int

const (
	ErrorNone ErrorType = iota
	ErrorTransport
	ErrorProtocol
	ErrorInvalidArgument
	ErrorMemory
)

// TransportError represents transport-layer specific errors
type TransportError int

const (
	TransportErrorNone TransportError = iota
	TransportErrorSocketCreateFailure
	TransportErrorSocketConnectFailure
	TransportErrorSocketReadFailure
	TransportErrorSocketWriteFailure
	TransportErrorConnectionClosed
	TransportErrorDnsFailure
	TransportErrorTimeout
	TransportErrorIoUringInit
	TransportErrorIoUringSubmit
)

// ProtocolError represents protocol-layer specific errors
type ProtocolError int

const (
	ProtocolErrorNone ProtocolError = iota
	ProtocolErrorInvalidStatusLine
	ProtocolErrorInvalidHeader
	ProtocolErrorInvalidChunkedEncoding
	ProtocolErrorMessageTooLarge
	ProtocolErrorIncompleteResponse
)

// HttpError is the main error type for the HTTP client
type HttpError struct {
	Type          ErrorType
	TransportErr  TransportError
	ProtocolErr   ProtocolError
	Message       string
	UnderlyingErr error
}

// Error implements the error interface
func (e *HttpError) Error() string {
	if e == nil {
		return "no error"
	}

	var typeStr string
	switch e.Type {
	case ErrorTransport:
		typeStr = fmt.Sprintf("Transport error (%d)", e.TransportErr)
	case ErrorProtocol:
		typeStr = fmt.Sprintf("Protocol error (%d)", e.ProtocolErr)
	case ErrorInvalidArgument:
		typeStr = "Invalid argument"
	case ErrorMemory:
		typeStr = "Memory error"
	default:
		typeStr = "Unknown error"
	}

	if e.Message != "" {
		typeStr = fmt.Sprintf("%s: %s", typeStr, e.Message)
	}

	if e.UnderlyingErr != nil {
		return fmt.Sprintf("%s (caused by: %v)", typeStr, e.UnderlyingErr)
	}

	return typeStr
}

// Unwrap returns the underlying error for error chain support
func (e *HttpError) Unwrap() error {
	return e.UnderlyingErr
}

// NewTransportError creates a new transport error
func NewTransportError(err TransportError, message string, underlying error) *HttpError {
	return &HttpError{
		Type:          ErrorTransport,
		TransportErr:  err,
		Message:       message,
		UnderlyingErr: underlying,
	}
}

// NewProtocolError creates a new protocol error
func NewProtocolError(err ProtocolError, message string) *HttpError {
	return &HttpError{
		Type:        ErrorProtocol,
		ProtocolErr: err,
		Message:     message,
	}
}

// NewInvalidArgumentError creates a new invalid argument error
func NewInvalidArgumentError(message string) *HttpError {
	return &HttpError{
		Type:    ErrorInvalidArgument,
		Message: message,
	}
}
