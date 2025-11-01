package errors

import "fmt"

// TransportError represents errors that occur at the transport layer
type TransportError int

const (
	DnsFailure TransportError = iota
	SocketCreateFailure
	SocketConnectFailure
	SocketWriteFailure
	SocketReadFailure
	ConnectionClosed
	SocketCloseFailure
	InitFailure
)

func (e TransportError) Error() string {
	switch e {
	case DnsFailure:
		return "DNS lookup failed"
	case SocketCreateFailure:
		return "Socket creation failed"
	case SocketConnectFailure:
		return "Socket connection failed"
	case SocketWriteFailure:
		return "Socket write failed"
	case SocketReadFailure:
		return "Socket read failed"
	case ConnectionClosed:
		return "Connection closed"
	case SocketCloseFailure:
		return "Socket close failed"
	case InitFailure:
		return "Initialization failed"
	default:
		return fmt.Sprintf("Unknown transport error: %d", e)
	}
}

// HttpClientError represents errors that occur at the HTTP protocol layer
type HttpClientError int

const (
	UrlParseFailure HttpClientError = iota
	HttpParseFailure
	InvalidRequest
	HttpInitFailure
)

func (e HttpClientError) Error() string {
	switch e {
	case UrlParseFailure:
		return "URL parsing failed"
	case HttpParseFailure:
		return "HTTP parsing failed"
	case InvalidRequest:
		return "Invalid HTTP request"
	case HttpInitFailure:
		return "HTTP client initialization failed"
	default:
		return fmt.Sprintf("Unknown HTTP client error: %d", e)
	}
}

// Error is the top-level error type that wraps transport and HTTP errors
type Error struct {
	TransportErr *TransportError
	HttpErr      *HttpClientError
	underlying   error
}

func (e *Error) Error() string {
	if e.TransportErr != nil {
		if e.underlying != nil {
			return fmt.Sprintf("Transport Error: %s (underlying: %v)", e.TransportErr.Error(), e.underlying)
		}
		return fmt.Sprintf("Transport Error: %s", e.TransportErr.Error())
	}
	if e.HttpErr != nil {
		if e.underlying != nil {
			return fmt.Sprintf("HTTP Client Error: %s (underlying: %v)", e.HttpErr.Error(), e.underlying)
		}
		return fmt.Sprintf("HTTP Client Error: %s", e.HttpErr.Error())
	}
	if e.underlying != nil {
		return e.underlying.Error()
	}
	return "Unknown error"
}

func (e *Error) Unwrap() error {
	return e.underlying
}

// NewTransportError creates a new Error with a TransportError
func NewTransportError(te TransportError, underlying error) *Error {
	return &Error{
		TransportErr: &te,
		underlying:   underlying,
	}
}

// NewHttpError creates a new Error with an HttpClientError
func NewHttpError(he HttpClientError, underlying error) *Error {
	return &Error{
		HttpErr:    &he,
		underlying: underlying,
	}
}
