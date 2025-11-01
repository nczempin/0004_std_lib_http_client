package transport

import (
	"fmt"
	"net"
	"os"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
)

var unixTestCounter uint64

func setupUnixTestServer(t *testing.T, serverLogic func(net.Conn)) (string, func()) {
	t.Helper()

	// Generate unique socket path
	count := atomic.AddUint64(&unixTestCounter, 1)
	socketPath := fmt.Sprintf("/tmp/httpgo_test_%d_%d.sock", os.Getpid(), count)

	// Remove socket file if it exists
	os.Remove(socketPath)

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("Failed to create Unix test server: %v", err)
	}

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
		os.Remove(socketPath)
	}

	return socketPath, cleanup
}

func TestUnixTransport_Construction(t *testing.T) {
	transport := NewUnixTransport()
	if transport == nil {
		t.Fatal("NewUnixTransport returned nil")
	}
	if transport.conn != nil {
		t.Error("New transport should have nil connection")
	}
}

func TestUnixTransport_Connect_Success(t *testing.T) {
	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {
		// Empty server logic for basic connection test
	})
	defer cleanup()

	transport := NewUnixTransport()
	err := transport.Connect(path, 0)
	if err != nil {
		t.Errorf("Connect failed: %v", err)
	}

	if transport.conn == nil {
		t.Error("Connection should not be nil after successful connect")
	}

	transport.Close()
}

func TestUnixTransport_Connect_Failure_NoSuchFile(t *testing.T) {
	transport := NewUnixTransport()
	err := transport.Connect("/tmp/this-socket-does-not-exist.sock", 0)

	if err == nil {
		t.Fatal("Expected error on non-existent socket")
	}

	httpErr, ok := err.(*errors.Error)
	if !ok {
		t.Fatalf("Expected *errors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != errors.SocketConnectFailure {
		t.Errorf("Expected SocketConnectFailure, got %v", *httpErr.TransportErr)
	}
}

func TestUnixTransport_Write_Success(t *testing.T) {
	messageToSend := "hello unix server"
	received := make(chan string, 1)

	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {
		buf := make([]byte, 1024)
		n, _ := conn.Read(buf)
		received <- string(buf[:n])
	})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
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

func TestUnixTransport_Read_Success(t *testing.T) {
	messageFromServer := "hello unix client"

	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {
		conn.Write([]byte(messageFromServer))
	})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
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

func TestUnixTransport_Read_Failure_ConnectionClosed(t *testing.T) {
	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {
		// Server immediately closes
	})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
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

	httpErr, ok := err.(*errors.Error)
	if !ok {
		t.Fatalf("Expected *errors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != errors.ConnectionClosed {
		t.Errorf("Expected ConnectionClosed, got %v", *httpErr.TransportErr)
	}
}

func TestUnixTransport_Close_Success(t *testing.T) {
	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
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

func TestUnixTransport_Close_Idempotent(t *testing.T) {
	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
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

func TestUnixTransport_Write_Failure_ClosedConnection(t *testing.T) {
	path, cleanup := setupUnixTestServer(t, func(conn net.Conn) {
		// Set SO_LINGER to force immediate close
		if unixConn, ok := conn.(*net.UnixConn); ok {
			raw, err := unixConn.SyscallConn()
			if err == nil {
				raw.Control(func(fd uintptr) {
					linger := syscall.Linger{Onoff: 1, Linger: 0}
					syscall.SetsockoptLinger(int(fd), syscall.SOL_SOCKET, syscall.SO_LINGER, &linger)
				})
			}
		}
	})
	defer cleanup()

	transport := NewUnixTransport()
	if err := transport.Connect(path, 0); err != nil {
		t.Fatalf("Connect failed: %v", err)
	}
	defer transport.Close()

	// Wait for server to close
	time.Sleep(50 * time.Millisecond)

	_, err := transport.Write([]byte("this should fail"))
	if err == nil {
		t.Fatal("Expected error on write to closed connection")
	}

	httpErr, ok := err.(*errors.Error)
	if !ok {
		t.Fatalf("Expected *errors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	// Accept either SocketWriteFailure or ConnectionClosed
	if *httpErr.TransportErr != errors.SocketWriteFailure && *httpErr.TransportErr != errors.ConnectionClosed {
		t.Errorf("Expected SocketWriteFailure or ConnectionClosed, got %v", *httpErr.TransportErr)
	}
}

func TestUnixTransport_Write_Failure_NoConnection(t *testing.T) {
	transport := NewUnixTransport()

	_, err := transport.Write([]byte("test"))
	if err == nil {
		t.Fatal("Expected error when writing without connection")
	}

	httpErr, ok := err.(*errors.Error)
	if !ok {
		t.Fatalf("Expected *errors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != errors.SocketWriteFailure {
		t.Errorf("Expected SocketWriteFailure, got %v", *httpErr.TransportErr)
	}
}

func TestUnixTransport_Read_Failure_NoConnection(t *testing.T) {
	transport := NewUnixTransport()

	buf := make([]byte, 1024)
	_, err := transport.Read(buf)
	if err == nil {
		t.Fatal("Expected error when reading without connection")
	}

	httpErr, ok := err.(*errors.Error)
	if !ok {
		t.Fatalf("Expected *errors.Error, got %T", err)
	}

	if httpErr.TransportErr == nil {
		t.Fatal("Expected TransportError")
	}

	if *httpErr.TransportErr != errors.SocketReadFailure {
		t.Errorf("Expected SocketReadFailure, got %v", *httpErr.TransportErr)
	}
}
