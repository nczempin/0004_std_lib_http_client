package client

import (
	"fmt"
	"net"
	"testing"

	"github.com/nczempin/httpc-go-uring/protocol"
	"github.com/nczempin/httpc-go-uring/transport"
)

func TestHttpClient_GetSafe_V2(t *testing.T) {
	// Setup test server
	responseBody := "Hello from V2!"
	response := fmt.Sprintf("HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n%s", len(responseBody), responseBody)

	host, port, cleanup := setupTestServer(t, func(conn net.Conn) {
		// Read request
		buf := make([]byte, 1024)
		conn.Read(buf)

		// Send response
		conn.Write([]byte(response))
	})
	defer cleanup()

	// Create client with V2 transport
	trans, err := transport.NewTcpTransportV2()
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

	t.Logf("SUCCESS: V2 transport with godzie44/go-uring works!")
}
