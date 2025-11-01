package client

import (
	"fmt"
	"net"
	"testing"

	"github.com/nczempin/httpc-go-uring/protocol"
	"github.com/nczempin/httpc-go-uring/transport"
)

// setupTestServer creates a simple HTTP test server
func setupTestServer(t *testing.T, handler func(net.Conn)) (string, int, func()) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("Failed to create listener: %v", err)
	}

	addr := listener.Addr().(*net.TCPAddr)

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		handler(conn)
	}()

	cleanup := func() {
		listener.Close()
	}

	return addr.IP.String(), addr.Port, cleanup
}

func TestHttpClient_GetSafe(t *testing.T) {
	// Setup test server
	responseBody := "Hello, World!"
	response := fmt.Sprintf("HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n%s", len(responseBody), responseBody)

	host, port, cleanup := setupTestServer(t, func(conn net.Conn) {
		// Read request
		buf := make([]byte, 1024)
		conn.Read(buf)

		// Send response
		conn.Write([]byte(response))
	})
	defer cleanup()

	// Create client
	trans, err := transport.NewTcpTransport()
	if err != nil {
		t.Fatalf("Failed to create transport: %v", err)
	}
	defer trans.Destroy()

	proto := protocol.NewHttp1Protocol(trans)
	client := NewHttpClient(proto)

	// Connect
	if err := client.Connect(host, port); err != nil {
		t.Fatalf("Failed to connect: %v", err)
	}
	defer client.Disconnect()

	// Perform GET request
	req := &protocol.HttpRequest{
		Path: "/test",
		Headers: []protocol.HttpHeader{
			{Key: "Host", Value: "localhost"},
		},
	}

	resp, err := client.GetSafe(req)
	if err != nil {
		t.Fatalf("GET request failed: %v", err)
	}

	// Verify response
	if resp.StatusCode != 200 {
		t.Errorf("Expected status code 200, got %d", resp.StatusCode)
	}

	if string(resp.Body) != responseBody {
		t.Errorf("Expected body %q, got %q", responseBody, string(resp.Body))
	}
}

func TestHttpClient_PostSafe(t *testing.T) {
	// Setup test server
	responseBody := "Created"
	response := fmt.Sprintf("HTTP/1.1 201 Created\r\nContent-Length: %d\r\n\r\n%s", len(responseBody), responseBody)

	host, port, cleanup := setupTestServer(t, func(conn net.Conn) {
		// Read request
		buf := make([]byte, 1024)
		conn.Read(buf)

		// Send response
		conn.Write([]byte(response))
	})
	defer cleanup()

	// Create client
	trans, err := transport.NewTcpTransport()
	if err != nil {
		t.Fatalf("Failed to create transport: %v", err)
	}
	defer trans.Destroy()

	proto := protocol.NewHttp1Protocol(trans)
	client := NewHttpClient(proto)

	// Connect
	if err := client.Connect(host, port); err != nil {
		t.Fatalf("Failed to connect: %v", err)
	}
	defer client.Disconnect()

	// Perform POST request
	postBody := []byte("test data")
	req := &protocol.HttpRequest{
		Path: "/create",
		Headers: []protocol.HttpHeader{
			{Key: "Host", Value: "localhost"},
			{Key: "Content-Length", Value: fmt.Sprintf("%d", len(postBody))},
		},
		Body: postBody,
	}

	resp, err := client.PostSafe(req)
	if err != nil {
		t.Fatalf("POST request failed: %v", err)
	}

	// Verify response
	if resp.StatusCode != 201 {
		t.Errorf("Expected status code 201, got %d", resp.StatusCode)
	}

	if string(resp.Body) != responseBody {
		t.Errorf("Expected body %q, got %q", responseBody, string(resp.Body))
	}
}

func TestHttpClient_GetWithBody_ReturnsError(t *testing.T) {
	trans, _ := transport.NewTcpTransport()
	defer trans.Destroy()

	proto := protocol.NewHttp1Protocol(trans)
	client := NewHttpClient(proto)

	req := &protocol.HttpRequest{
		Path: "/test",
		Body: []byte("should not have body"),
	}

	_, err := client.GetSafe(req)
	if err == nil {
		t.Error("Expected error for GET request with body, got nil")
	}
}

func TestHttpClient_PostWithoutContentLength_ReturnsError(t *testing.T) {
	trans, _ := transport.NewTcpTransport()
	defer trans.Destroy()

	proto := protocol.NewHttp1Protocol(trans)
	client := NewHttpClient(proto)

	req := &protocol.HttpRequest{
		Path: "/test",
		Body: []byte("test body"),
		Headers: []protocol.HttpHeader{
			{Key: "Host", Value: "localhost"},
		},
	}

	_, err := client.PostSafe(req)
	if err == nil {
		t.Error("Expected error for POST request without Content-Length, got nil")
	}
}
