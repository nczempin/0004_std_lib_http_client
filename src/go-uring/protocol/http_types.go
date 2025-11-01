package protocol

// HttpMethod represents HTTP request methods
type HttpMethod int

const (
	MethodGet HttpMethod = iota
	MethodPost
)

// HttpHeader represents an HTTP header key-value pair
type HttpHeader struct {
	Key   string
	Value string
}

// HttpRequest represents an HTTP request
type HttpRequest struct {
	Method  HttpMethod
	Path    string
	Headers []HttpHeader
	Body    []byte
}

// HttpResponse represents an HTTP response (safe mode - copies data)
type HttpResponse struct {
	StatusCode    int
	StatusMessage string
	Headers       []HttpHeader
	Body          []byte
	ContentLength int
}

// UnsafeHttpResponse represents an HTTP response (unsafe mode - references buffer)
// The data is only valid while the protocol's internal buffer is not reused
type UnsafeHttpResponse struct {
	StatusCode    int
	StatusMessage string
	Headers       []HttpHeaderView
	Body          []byte
	ContentLength int
}

// HttpHeaderView is a view into the buffer for zero-copy header access
type HttpHeaderView struct {
	Key   string
	Value string
}
