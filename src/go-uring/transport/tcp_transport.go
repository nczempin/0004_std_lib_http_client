package transport

import (
	"fmt"
	"net"
	"syscall"

	"github.com/iceber/iouring-go"
	"github.com/nczempin/httpc-go-uring/errors"
)

// TcpTransport implements Transport using io_uring for async I/O
type TcpTransport struct {
	iour   *iouring.IOURing
	fd     int
	closed bool
}

// NewTcpTransport creates a new TCP transport with io_uring
func NewTcpTransport() (*TcpTransport, error) {
	// Create io_uring instance with queue depth of 32
	iour, err := iouring.New(32)
	if err != nil {
		return nil, errors.NewTransportError(
			errors.TransportErrorIoUringInit,
			"failed to initialize io_uring",
			err,
		)
	}

	return &TcpTransport{
		iour:   iour,
		fd:     -1,
		closed: false,
	}, nil
}

// Connect establishes a TCP connection using io_uring
func (t *TcpTransport) Connect(host string, port int) error {
	if t.fd >= 0 {
		return errors.NewTransportError(
			errors.TransportErrorSocketConnectFailure,
			"already connected",
			nil,
		)
	}

	// Resolve the address
	addr := fmt.Sprintf("%s:%d", host, port)
	tcpAddr, err := net.ResolveTCPAddr("tcp", addr)
	if err != nil {
		return errors.NewTransportError(
			errors.TransportErrorDnsFailure,
			fmt.Sprintf("failed to resolve %s", addr),
			err,
		)
	}

	// Create socket
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM, 0)
	if err != nil {
		return errors.NewTransportError(
			errors.TransportErrorSocketCreateFailure,
			"failed to create socket",
			err,
		)
	}

	// Set socket to non-blocking mode for io_uring
	if err := syscall.SetNonblock(fd, true); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorSocketCreateFailure,
			"failed to set non-blocking mode",
			err,
		)
	}

	// Set TCP_NODELAY
	if err := syscall.SetsockoptInt(fd, syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorSocketCreateFailure,
			"failed to set TCP_NODELAY",
			err,
		)
	}

	// Convert to syscall.Sockaddr
	var sa syscall.Sockaddr
	if ip4 := tcpAddr.IP.To4(); ip4 != nil {
		sa4 := &syscall.SockaddrInet4{Port: tcpAddr.Port}
		copy(sa4.Addr[:], ip4)
		sa = sa4
	} else {
		sa6 := &syscall.SockaddrInet6{Port: tcpAddr.Port}
		copy(sa6.Addr[:], tcpAddr.IP)
		sa = sa6
	}

	// Submit connect operation via io_uring
	ch := make(chan iouring.Result, 1)
	prepReq := iouring.Connect(fd, sa)
	if _, err := t.iour.SubmitRequest(prepReq, ch); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorIoUringSubmit,
			"failed to submit connect request",
			err,
		)
	}

	// Wait for connect to complete
	result := <-ch
	if _, err := result.ReturnInt(); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorSocketConnectFailure,
			fmt.Sprintf("failed to connect to %s", addr),
			err,
		)
	}

	t.fd = fd
	return nil
}

// Write sends data over the connection using io_uring
func (t *TcpTransport) Write(buf []byte) (int, error) {
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

// Read receives data from the connection using io_uring
func (t *TcpTransport) Read(buf []byte) (int, error) {
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

// Close closes the connection
func (t *TcpTransport) Close() error {
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
func (t *TcpTransport) Destroy() {
	t.Close()
	if t.iour != nil {
		t.iour.Close()
		t.iour = nil
	}
}
