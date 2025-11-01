package transport

import (
	"net"
	"syscall"
	"testing"
	"time"

	httperrors "github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
)

func setupTcpTestServer(t *testing.T, serverLogic func(net.Conn)) (string, uint16, func()) {
	t.Helper()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("Failed to create test server: %v", err)
	}

	addr := listener.Addr().(*net.TCPAddr)

	done := make(chan struct{})
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		serverLogic(conn)
		conn.Close()
		close(done)
	}()

	cleanup := func() {
		listener.Close()
		<-done
	}

	return addr.IP.String(), uint16(addr.Port), cleanup
}

func TestTcpTransport_Construction(t *testing.T) {
	transport := NewTcpTransport()
	if transport == nil {
		t.Fatal("NewTcpTransport returned nil")
	}
	if transport.conn != nil {
		t.Error("New transport should have nil connection")
	}
}

func TestTcpTransport_Connect_Success(t *testing.T) {
	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {
		// Empty server logic for basic connection test
	})
	defer cleanup()

	transport := NewTcpTransport()
	err := transport.Connect(host, port)
	if err != nil {
		t.Errorf("Connect failed: %v", err)
	}

	if transport.conn == nil {
		t.Error("Connection should not be nil after successful connect")
	}

	transport.Close()
}

func TestTcpTransport_Connect_Failure_DnsError(t *testing.T) {
	transport := NewTcpTransport()
	err := transport.Connect("this-is-not-a-real-domain.invalid", 80)

	if err == nil {
		t.Fatal("Expected error on DNS failure")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.DnsFailure {
		t.Errorf("Expected DnsFailure, got %v", *httpErr.TransportErr)
	}
}

func TestTcpTransport_Connect_Failure_ConnectionRefused(t *testing.T) {
	transport := NewTcpTransport()
	// Use a port that's likely not listening
	err := transport.Connect("127.0.0.1", 65531)

	if err == nil {
		t.Fatal("Expected error on connection refused")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.SocketConnectFailure {
		t.Errorf("Expected SocketConnectFailure, got %v", *httpErr.TransportErr)
	}
}

func TestTcpTransport_Write_Success(t *testing.T) {
	messageToSend := "hello server"
	received := make(chan string, 1)

	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {
		buf := make([]byte, 1024)
		n, _ := conn.Read(buf)
		received <- string(buf[:n])
	})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}
	defer transport.Close()

	n, err := transport.Write([]byte(messageToSend))
	if err != nil {
		t.Errorf("Write failed: %v", err)
	}

	if n != len(messageToSend) {
		t.Errorf("Expected to write %d bytes, wrote %d", len(messageToSend), n)
	}

	select {
	case msg := <-received:
		if msg != messageToSend {
			t.Errorf("Expected %q, got %q", messageToSend, msg)
		}
	case <-time.After(time.Second):
		t.Error("Timeout waiting for message")
	}
}

func TestTcpTransport_Read_Success(t *testing.T) {
	messageFromServer := "hello client"

	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {
		conn.Write([]byte(messageFromServer))
	})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}
	defer transport.Close()

	buf := make([]byte, 1024)
	n, err := transport.Read(buf)
	if err != nil {
		t.Errorf("Read failed: %v", err)
	}

	if n != len(messageFromServer) {
		t.Errorf("Expected to read %d bytes, read %d", len(messageFromServer), n)
	}

	received := string(buf[:n])
	if received != messageFromServer {
		t.Errorf("Expected %q, got %q", messageFromServer, received)
	}
}

func TestTcpTransport_Read_Failure_ConnectionClosed(t *testing.T) {
	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {
		// Server immediately closes
	})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}
	defer transport.Close()

	// Give server time to close
	time.Sleep(50 * time.Millisecond)

	buf := make([]byte, 1024)
	_, err := transport.Read(buf)

	if err == nil {
		t.Fatal("Expected error on closed connection")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.ConnectionClosed {
		t.Errorf("Expected ConnectionClosed, got %v", *httpErr.TransportErr)
	}
}

func TestTcpTransport_Close_Success(t *testing.T) {
	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}

	err := transport.Close()
	if err != nil {
		t.Errorf("Close failed: %v", err)
	}

	if transport.conn != nil {
		t.Error("Connection should be nil after close")
	}
}

func TestTcpTransport_Close_Idempotent(t *testing.T) {
	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}

	// First close
	if err := transport.Close(); err != nil {
		t.Errorf("First close failed: %v", err)
	}

	// Second close should also succeed
	if err := transport.Close(); err != nil {
		t.Errorf("Second close failed: %v", err)
	}
}

func TestTcpTransport_Write_Failure_ClosedConnection(t *testing.T) {
	host, port, cleanup := setupTcpTestServer(t, func(conn net.Conn) {
		// Set SO_LINGER to force RST on close
		if tcpConn, ok := conn.(*net.TCPConn); ok {
			raw, err := tcpConn.SyscallConn()
			if err == nil {
				raw.Control(func(fd uintptr) {
					linger := syscall.Linger{Onoff: 1, Linger: 0}
					syscall.SetsockoptLinger(int(fd), syscall.SOL_SOCKET, syscall.SO_LINGER, &linger)
				})
			}
		}
	})
	defer cleanup()

	transport := NewTcpTransport()
	if err := transport.Connect(host, port); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}
	defer transport.Close()

	// Wait for server to close with RST
	time.Sleep(50 * time.Millisecond)

	_, err := transport.Write([]byte("this should fail"))
	if err == nil {
		t.Fatal("Expected error on write to closed connection")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.ConnectionClosed {
		t.Errorf("Expected ConnectionClosed, got %v", *httpErr.TransportErr)
	}
}

func TestTcpTransport_Write_Failure_NoConnection(t *testing.T) {
	transport := NewTcpTransport()

	_, err := transport.Write([]byte("test"))
	if err == nil {
		t.Fatal("Expected error when writing without connection")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.SocketWriteFailure {
		t.Errorf("Expected SocketWriteFailure, got %v", *httpErr.TransportErr)
	}
}

func TestTcpTransport_Read_Failure_NoConnection(t *testing.T) {
	transport := NewTcpTransport()

	buf := make([]byte, 1024)
	_, err := transport.Read(buf)
	if err == nil {
		t.Fatal("Expected error when reading without connection")
	}

	httpErr, ok := err.(*httperrors.Error)
	if !ok {
		t.Fatalf("Expected *httperrors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != httperrors.SocketReadFailure {
		t.Errorf("Expected SocketReadFailure, got %v", *httpErr.TransportErr)
	}
}
