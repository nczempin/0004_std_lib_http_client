package transport

import (
	"fmt"
	"net"
	"strings"

	"github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
)

// TcpTransport implements the Transport interface using TCP sockets
type TcpTransport struct {
	conn net.Conn
}

// NewTcpTransport creates a new TcpTransport instance
func NewTcpTransport() *TcpTransport {
	return &TcpTransport{
		conn: nil,
	}
}

// Connect establishes a TCP connection to the specified host and port
func (t *TcpTransport) Connect(host string, port uint16) error {
	addr := fmt.Sprintf("%s:%d", host, port)

	conn, err := net.Dial("tcp", addr)
	if err != nil {
		// Determine the specific error type
		if strings.Contains(err.Error(), "no such host") ||
			strings.Contains(err.Error(), "Name or service not known") ||
			strings.Contains(err.Error(), "Temporary failure in name resolution") {
			return errors.NewTransportError(errors.DnsFailure, err)
		}
		if strings.Contains(err.Error(), "connection refused") {
			return errors.NewTransportError(errors.SocketConnectFailure, err)
		}
		return errors.NewTransportError(errors.SocketConnectFailure, err)
	}

	// Set TCP_NODELAY to disable Nagle's algorithm for lower latency
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		if err := tcpConn.SetNoDelay(true); err != nil {
			conn.Close()
			return errors.NewTransportError(errors.InitFailure, err)
		}
	}

	t.conn = conn
	return nil
}

// Write sends data over the TCP connection
func (t *TcpTransport) Write(buf []byte) (int, error) {
	if t.conn == nil {
		return 0, errors.NewTransportError(errors.SocketWriteFailure, nil)
	}

	n, err := t.conn.Write(buf)
	if err != nil {
		if strings.Contains(err.Error(), "broken pipe") ||
			strings.Contains(err.Error(), "connection reset") {
			return n, errors.NewTransportError(errors.ConnectionClosed, err)
		}
		return n, errors.NewTransportError(errors.SocketWriteFailure, err)
	}

	return n, nil
}

// Read receives data from the TCP connection
func (t *TcpTransport) Read(buf []byte) (int, error) {
	if t.conn == nil {
		return 0, errors.NewTransportError(errors.SocketReadFailure, nil)
	}

	n, err := t.conn.Read(buf)
	if err != nil {
		if err.Error() == "EOF" || n == 0 && len(buf) > 0 {
			return n, errors.NewTransportError(errors.ConnectionClosed, err)
		}
		return n, errors.NewTransportError(errors.SocketReadFailure, err)
	}

	// Check for connection closed (0 bytes read with non-empty buffer)
	if n == 0 && len(buf) > 0 {
		return n, errors.NewTransportError(errors.ConnectionClosed, nil)
	}

	return n, nil
}

// Close closes the TCP connection
func (t *TcpTransport) Close() error {
	if t.conn == nil {
		return nil // Idempotent close
	}

	err := t.conn.Close()
	t.conn = nil

	if err != nil {
		return errors.NewTransportError(errors.SocketCloseFailure, err)
	}

	return nil
}
