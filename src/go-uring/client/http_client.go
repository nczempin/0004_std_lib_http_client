package client

import (
	"strings"

	"github.com/nczempin/httpc-go-uring/errors"
	"github.com/nczempin/httpc-go-uring/protocol"
)

// HttpClient provides a high-level HTTP client API
type HttpClient struct {
	protocol *protocol.Http1Protocol
}

// NewHttpClient creates a new HTTP client with the given protocol
func NewHttpClient(proto *protocol.Http1Protocol) *HttpClient {
	return &HttpClient{
		protocol: proto,
	}
}

// Connect establishes a connection to the specified host and port
func (c *HttpClient) Connect(host string, port int) error {
	return c.protocol.Connect(host, port)
}

// Disconnect closes the connection
func (c *HttpClient) Disconnect() error {
	return c.protocol.Disconnect()
}

// GetSafe performs a GET request and returns a copied response
func (c *HttpClient) GetSafe(req *protocol.HttpRequest) (*protocol.HttpResponse, error) {
	if len(req.Body) > 0 {
		return nil, errors.NewInvalidArgumentError("GET request cannot have a body")
	}
	req.Method = protocol.MethodGet
	return c.protocol.PerformRequestSafe(req)
}

// GetUnsafe performs a GET request and returns a zero-copy response
// The response is only valid until the next request
func (c *HttpClient) GetUnsafe(req *protocol.HttpRequest) (*protocol.UnsafeHttpResponse, error) {
	if len(req.Body) > 0 {
		return nil, errors.NewInvalidArgumentError("GET request cannot have a body")
	}
	req.Method = protocol.MethodGet
	return c.protocol.PerformRequestUnsafe(req)
}

// PostSafe performs a POST request and returns a copied response
func (c *HttpClient) PostSafe(req *protocol.HttpRequest) (*protocol.HttpResponse, error) {
	if err := c.validatePostRequest(req); err != nil {
		return nil, err
	}
	req.Method = protocol.MethodPost
	return c.protocol.PerformRequestSafe(req)
}

// PostUnsafe performs a POST request and returns a zero-copy response
// The response is only valid until the next request
func (c *HttpClient) PostUnsafe(req *protocol.HttpRequest) (*protocol.UnsafeHttpResponse, error) {
	if err := c.validatePostRequest(req); err != nil {
		return nil, err
	}
	req.Method = protocol.MethodPost
	return c.protocol.PerformRequestUnsafe(req)
}

// validatePostRequest validates that a POST request has required fields
func (c *HttpClient) validatePostRequest(req *protocol.HttpRequest) error {
	if len(req.Body) == 0 {
		return errors.NewInvalidArgumentError("POST request must have a body")
	}

	// Check for Content-Length header
	hasContentLength := false
	for _, header := range req.Headers {
		if strings.EqualFold(header.Key, "Content-Length") {
			hasContentLength = true
			break
		}
	}

	if !hasContentLength {
		return errors.NewInvalidArgumentError("POST request must have Content-Length header")
	}

	return nil
}
