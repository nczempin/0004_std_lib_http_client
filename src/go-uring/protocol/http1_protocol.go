package protocol

import (
	"bytes"
	"fmt"
	"strconv"
	"strings"

	"github.com/nczempin/httpc-go-uring/errors"
	"github.com/nczempin/httpc-go-uring/transport"
)

var (
	headerSeparator = []byte("\r\n\r\n")
	contentLengthKey = []byte("Content-Length:")
)

// Http1Protocol implements HTTP/1.1 protocol over a transport
type Http1Protocol struct {
	transport     transport.Transport
	buffer        []byte
	headerSize    int
	contentLength int
}

// NewHttp1Protocol creates a new HTTP/1.1 protocol handler
func NewHttp1Protocol(t transport.Transport) *Http1Protocol {
	return &Http1Protocol{
		transport:     t,
		buffer:        make([]byte, 0, 1024),
		headerSize:    0,
		contentLength: -1,
	}
}

// Connect establishes a connection to the specified host and port
func (p *Http1Protocol) Connect(host string, port int) error {
	return p.transport.Connect(host, port)
}

// Disconnect closes the connection
func (p *Http1Protocol) Disconnect() error {
	return p.transport.Close()
}

// buildRequest formats an HTTP request into the internal buffer
func (p *Http1Protocol) buildRequest(req *HttpRequest) {
	p.buffer = p.buffer[:0] // Reset buffer

	// Request line
	method := "GET"
	if req.Method == MethodPost {
		method = "POST"
	}
	p.buffer = append(p.buffer, []byte(fmt.Sprintf("%s %s HTTP/1.1\r\n", method, req.Path))...)

	// Headers
	for _, header := range req.Headers {
		p.buffer = append(p.buffer, []byte(fmt.Sprintf("%s: %s\r\n", header.Key, header.Value))...)
	}

	// Blank line
	p.buffer = append(p.buffer, []byte("\r\n")...)

	// Body (for POST)
	if req.Method == MethodPost && len(req.Body) > 0 {
		p.buffer = append(p.buffer, req.Body...)
	}
}

// readFullResponse reads the complete HTTP response into the buffer
func (p *Http1Protocol) readFullResponse() error {
	p.buffer = p.buffer[:0]
	p.headerSize = 0
	p.contentLength = -1

	readBuf := make([]byte, 1024)

	for {
		n, err := p.transport.Read(readBuf)
		if err != nil {
			httpErr, ok := err.(*errors.HttpError)
			if ok && httpErr.Type == errors.ErrorTransport &&
			   httpErr.TransportErr == errors.TransportErrorConnectionClosed {
				// Connection closed - check if we have complete response
				if p.contentLength >= 0 && len(p.buffer) < p.headerSize + p.contentLength {
					return errors.NewProtocolError(
						errors.ProtocolErrorIncompleteResponse,
						"connection closed before complete response received",
					)
				}
				break
			}
			return err
		}

		p.buffer = append(p.buffer, readBuf[:n]...)

		// Look for header separator if we haven't found it yet
		if p.headerSize == 0 {
			if pos := bytes.Index(p.buffer, headerSeparator); pos >= 0 {
				p.headerSize = pos + len(headerSeparator)

				// Parse Content-Length from headers
				headersView := p.buffer[:p.headerSize]
				p.contentLength = p.parseContentLength(headersView)
			}
		}

		// Check if we have complete response
		if p.contentLength >= 0 && len(p.buffer) >= p.headerSize + p.contentLength {
			break
		}
	}

	if p.headerSize == 0 && len(p.buffer) > 0 {
		return errors.NewProtocolError(
			errors.ProtocolErrorInvalidStatusLine,
			"failed to parse HTTP response headers",
		)
	}

	return nil
}

// parseContentLength extracts Content-Length from headers
func (p *Http1Protocol) parseContentLength(headersView []byte) int {
	lines := bytes.Split(headersView, []byte("\n"))
	for _, line := range lines[1:] { // Skip status line
		line = bytes.TrimSuffix(line, []byte("\r"))
		if len(line) == 0 {
			break
		}

		if bytes.HasPrefix(bytes.ToLower(line), bytes.ToLower(contentLengthKey)) {
			parts := bytes.SplitN(line, []byte(":"), 2)
			if len(parts) == 2 {
				valueStr := strings.TrimSpace(string(parts[1]))
				if length, err := strconv.Atoi(valueStr); err == nil {
					return length
				}
			}
		}
	}
	return -1
}

// parseResponse parses the response buffer into an UnsafeHttpResponse
func (p *Http1Protocol) parseResponse() (*UnsafeHttpResponse, error) {
	if p.headerSize == 0 {
		return nil, errors.NewProtocolError(
			errors.ProtocolErrorInvalidStatusLine,
			"no headers found",
		)
	}

	headersBlock := p.buffer[:p.headerSize-len(headerSeparator)]

	// Split into status line and rest of headers
	parts := bytes.SplitN(headersBlock, []byte("\n"), 2)
	statusLine := bytes.TrimSuffix(parts[0], []byte("\r"))

	// Parse status line: "HTTP/1.1 200 OK"
	statusParts := bytes.SplitN(statusLine, []byte(" "), 3)
	if len(statusParts) < 2 {
		return nil, errors.NewProtocolError(
			errors.ProtocolErrorInvalidStatusLine,
			"invalid status line format",
		)
	}

	statusCode, err := strconv.Atoi(string(statusParts[1]))
	if err != nil {
		return nil, errors.NewProtocolError(
			errors.ProtocolErrorInvalidStatusLine,
			fmt.Sprintf("invalid status code: %s", statusParts[1]),
		)
	}

	statusMessage := ""
	if len(statusParts) >= 3 {
		statusMessage = string(statusParts[2])
	}

	// Parse headers
	var headers []HttpHeaderView
	if len(parts) > 1 {
		headerLines := bytes.Split(parts[1], []byte("\n"))
		for _, line := range headerLines {
			line = bytes.TrimSuffix(line, []byte("\r"))
			if len(line) == 0 {
				break
			}

			headerParts := bytes.SplitN(line, []byte(":"), 2)
			if len(headerParts) == 2 {
				headers = append(headers, HttpHeaderView{
					Key:   string(headerParts[0]),
					Value: strings.TrimSpace(string(headerParts[1])),
				})
			}
		}
	}

	// Extract body
	var body []byte
	if p.contentLength >= 0 {
		body = p.buffer[p.headerSize : p.headerSize+p.contentLength]
	} else {
		body = p.buffer[p.headerSize:]
	}

	return &UnsafeHttpResponse{
		StatusCode:    statusCode,
		StatusMessage: statusMessage,
		Headers:       headers,
		Body:          body,
		ContentLength: p.contentLength,
	}, nil
}

// PerformRequestUnsafe performs an HTTP request and returns zero-copy response
func (p *Http1Protocol) PerformRequestUnsafe(req *HttpRequest) (*UnsafeHttpResponse, error) {
	p.buildRequest(req)

	if _, err := p.transport.Write(p.buffer); err != nil {
		return nil, err
	}

	if err := p.readFullResponse(); err != nil {
		return nil, err
	}

	return p.parseResponse()
}

// PerformRequestSafe performs an HTTP request and returns a copied response
func (p *Http1Protocol) PerformRequestSafe(req *HttpRequest) (*HttpResponse, error) {
	unsafeResp, err := p.PerformRequestUnsafe(req)
	if err != nil {
		return nil, err
	}

	// Copy all data to ensure it remains valid
	headers := make([]HttpHeader, len(unsafeResp.Headers))
	for i, h := range unsafeResp.Headers {
		headers[i] = HttpHeader{
			Key:   h.Key,
			Value: h.Value,
		}
	}

	body := make([]byte, len(unsafeResp.Body))
	copy(body, unsafeResp.Body)

	return &HttpResponse{
		StatusCode:    unsafeResp.StatusCode,
		StatusMessage: unsafeResp.StatusMessage,
		Headers:       headers,
		Body:          body,
		ContentLength: unsafeResp.ContentLength,
	}, nil
}
