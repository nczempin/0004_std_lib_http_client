package transport

import (
	"errors"
	"io"
	"net"
	"os"
	"syscall"

	httperrors "github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
)

// UnixTransport implements the Transport interface using Unix domain sockets
type UnixTransport struct {
	conn net.Conn
}

// NewUnixTransport creates a new UnixTransport instance
func NewUnixTransport() *UnixTransport {
	return &UnixTransport{
		conn: nil,
	}
}

// Connect establishes a Unix domain socket connection to the specified path.
// The port parameter is ignored for Unix sockets.
func (t *UnixTransport) Connect(path string, port uint16) error {
	conn, err := net.Dial("unix", path)
	if err != nil {
		// Classify errors using type assertions and os package helpers
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOENT) {
			return httperrors.NewTransportError(httperrors.SocketConnectFailure, err)
		}
		if errors.Is(err, syscall.ECONNREFUSED) {
			return httperrors.NewTransportError(httperrors.SocketConnectFailure, err)
		}
		return httperrors.NewTransportError(httperrors.SocketConnectFailure, err)
	}

	t.conn = conn
	return nil
}

// Write sends data over the Unix domain socket
func (t *UnixTransport) Write(buf []byte) (int, error) {
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

// Read receives data from the Unix domain socket
func (t *UnixTransport) Read(buf []byte) (int, error) {
	if t.conn == nil {
		return 0, httperrors.NewTransportError(httperrors.SocketReadFailure, nil)
	}

	n, err := t.conn.Read(buf)
	if err != nil {
		if errors.Is(err, io.EOF) || n == 0 && len(buf) > 0 {
			return n, httperrors.NewTransportError(httperrors.ConnectionClosed, err)
		}
		return n, httperrors.NewTransportError(httperrors.SocketReadFailure, err)
	}

	return n, nil
}

// Close closes the Unix domain socket connection
func (t *UnixTransport) Close() error {
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
