package transport

import (
	"net"
	"strings"

	"github.com/nczempin/0004_std_lib_http_client/httpgo/errors"
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
		// Determine the specific error type
		if strings.Contains(err.Error(), "no such file") ||
			strings.Contains(err.Error(), "connect: connection refused") {
			return errors.NewTransportError(errors.SocketConnectFailure, err)
		}
		return errors.NewTransportError(errors.SocketConnectFailure, err)
	}

	t.conn = conn
	return nil
}

// Write sends data over the Unix domain socket
func (t *UnixTransport) Write(buf []byte) (int, error) {
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

// Read receives data from the Unix domain socket
func (t *UnixTransport) Read(buf []byte) (int, error) {
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

// Close closes the Unix domain socket connection
func (t *UnixTransport) Close() error {
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
