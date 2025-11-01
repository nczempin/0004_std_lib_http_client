package transport

import (
	"errors"
	"fmt"
	"io"
	"net"
	"syscall"

	httperrors "github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
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
		// Classify network errors using type assertions
		if opErr, ok := err.(*net.OpError); ok {
			if opErr.Op == "dial" {
				// Check for DNS resolution failures
				if dnsErr, ok := opErr.Err.(*net.DNSError); ok {
					if dnsErr.IsNotFound || dnsErr.IsTemporary {
						return httperrors.NewTransportError(httperrors.DnsFailure, err)
					}
				}
				// Check for connection refused via syscall error
				if errors.Is(opErr.Err, syscall.ECONNREFUSED) {
					return httperrors.NewTransportError(httperrors.SocketConnectFailure, err)
				}
			}
		}
		return httperrors.NewTransportError(httperrors.SocketConnectFailure, err)
	}

	// Set TCP_NODELAY to disable Nagle's algorithm for lower latency
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		if err := tcpConn.SetNoDelay(true); err != nil {
			conn.Close()
			return httperrors.NewTransportError(httperrors.InitFailure, err)
		}
	}

	t.conn = conn
	return nil
}

// Write sends data over the TCP connection
func (t *TcpTransport) Write(buf []byte) (int, error) {
	if t.conn == nil {
		return 0, httperrors.NewTransportError(httperrors.SocketWriteFailure, nil)
	}

	n, err := t.conn.Write(buf)
	if err != nil {
		// Check for broken pipe or connection reset
		if errors.Is(err, syscall.EPIPE) || errors.Is(err, syscall.ECONNRESET) {
			return n, httperrors.NewTransportError(httperrors.ConnectionClosed, err)
		}
		return n, httperrors.NewTransportError(httperrors.SocketWriteFailure, err)
	}

	return n, nil
}

// Read receives data from the TCP connection
func (t *TcpTransport) Read(buf []byte) (int, error) {
	if t.conn == nil {
		return 0, httperrors.NewTransportError(httperrors.SocketReadFailure, nil)
	}

	n, err := t.conn.Read(buf)
	if err != nil {
		if errors.Is(err, io.EOF) || (n == 0 && len(buf) > 0) {
			return n, httperrors.NewTransportError(httperrors.ConnectionClosed, err)
		}
		return n, httperrors.NewTransportError(httperrors.SocketReadFailure, err)
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
		return httperrors.NewTransportError(httperrors.SocketCloseFailure, err)
	}

	return nil
}
