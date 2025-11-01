package transport

import (
	"syscall"

	"github.com/iceber/iouring-go"
	"github.com/nczempin/httpc-go-uring/errors"
)

// UnixTransport implements Transport using Unix domain sockets with io_uring
type UnixTransport struct {
	iour   *iouring.IOURing
	fd     int
	closed bool
}

// NewUnixTransport creates a new Unix domain socket transport with io_uring
func NewUnixTransport() (*UnixTransport, error) {
	// Create io_uring instance with queue depth of 32
	iour, err := iouring.New(32)
	if err != nil {
		return nil, errors.NewTransportError(
			errors.TransportErrorIoUringInit,
			"failed to initialize io_uring",
			err,
		)
	}

	return &UnixTransport{
		iour:   iour,
		fd:     -1,
		closed: false,
	}, nil
}

// Connect establishes a connection to a Unix domain socket
// For Unix sockets, the host parameter is the socket path, and port is ignored
func (t *UnixTransport) Connect(path string, port int) error {
	if t.fd >= 0 {
		return errors.NewTransportError(
			errors.TransportErrorSocketConnectFailure,
			"already connected",
			nil,
		)
	}

	// Create Unix domain socket
	fd, err := syscall.Socket(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err != nil {
		return errors.NewTransportError(
			errors.TransportErrorSocketCreateFailure,
			"failed to create socket",
			err,
		)
	}

	// Prepare Unix socket address
	sa := &syscall.SockaddrUnix{Name: path}

	// Use blocking connect (io_uring connect support is limited)
	if err := syscall.Connect(fd, sa); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorSocketConnectFailure,
			"failed to connect to unix socket",
			err,
		)
	}

	t.fd = fd
	return nil
}

// Write sends data over the Unix socket using io_uring
func (t *UnixTransport) Write(buf []byte) (int, error) {
	if t.fd < 0 {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketWriteFailure,
			"not connected",
			nil,
		)
	}

	if t.closed {
		return 0, errors.NewTransportError(
			errors.TransportErrorConnectionClosed,
			"connection closed",
			nil,
		)
	}

	totalWritten := 0
	for totalWritten < len(buf) {
		ch := make(chan iouring.Result, 1)
		prepReq := iouring.Send(t.fd, buf[totalWritten:], 0)
		if _, err := t.iour.SubmitRequest(prepReq, ch); err != nil {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorIoUringSubmit,
				"failed to submit write request",
				err,
			)
		}

		result := <-ch
		n, err := result.ReturnInt()
		if err != nil {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorSocketWriteFailure,
				"write failed",
				err,
			)
		}

		if n <= 0 {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorConnectionClosed,
				"connection closed during write",
				nil,
			)
		}

		totalWritten += n
	}

	return totalWritten, nil
}

// Read receives data from the Unix socket using io_uring
func (t *UnixTransport) Read(buf []byte) (int, error) {
	if t.fd < 0 {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketReadFailure,
			"not connected",
			nil,
		)
	}

	if t.closed {
		return 0, errors.NewTransportError(
			errors.TransportErrorConnectionClosed,
			"connection closed",
			nil,
		)
	}

	ch := make(chan iouring.Result, 1)
	prepReq := iouring.Recv(t.fd, buf, 0)
	if _, err := t.iour.SubmitRequest(prepReq, ch); err != nil {
		return 0, errors.NewTransportError(
			errors.TransportErrorIoUringSubmit,
			"failed to submit read request",
			err,
		)
	}

	result := <-ch
	n, err := result.ReturnInt()
	if err != nil {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketReadFailure,
			"read failed",
			err,
		)
	}

	if n == 0 && len(buf) > 0 {
		return 0, errors.NewTransportError(
			errors.TransportErrorConnectionClosed,
			"connection closed by peer",
			nil,
		)
	}

	return n, nil
}

// Close closes the Unix socket connection
func (t *UnixTransport) Close() error {
	if t.fd < 0 {
		return nil // Already closed or never connected
	}

	if !t.closed {
		t.closed = true
		if err := syscall.Close(t.fd); err != nil {
			return errors.NewTransportError(
				errors.TransportErrorConnectionClosed,
				"failed to close socket",
				err,
			)
		}
		t.fd = -1
	}

	return nil
}

// Destroy cleans up resources including the io_uring instance
func (t *UnixTransport) Destroy() {
	t.Close()
	if t.iour != nil {
		t.iour.Close()
		t.iour = nil
	}
}
