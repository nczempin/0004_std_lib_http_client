package transport

import (
	"fmt"
	"net"
	"os"
	"syscall"

	"github.com/godzie44/go-uring/uring"
	"github.com/nczempin/httpc-go-uring/errors"
)

// TcpTransportV2 implements Transport using godzie44/go-uring for async I/O
type TcpTransportV2 struct {
	ring *uring.Ring
	fd   int
	file *os.File
}

// NewTcpTransportV2 creates a new TCP transport with io_uring (v2 using godzie44/go-uring)
func NewTcpTransportV2() (*TcpTransportV2, error) {
	// Create io_uring instance with queue depth of 32
	ring, err := uring.New(32)
	if err != nil {
		return nil, errors.NewTransportError(
			errors.TransportErrorIoUringInit,
			"failed to initialize io_uring",
			err,
		)
	}

	return &TcpTransportV2{
		ring: ring,
		fd:   -1,
	}, nil
}

// Connect establishes a TCP connection
func (t *TcpTransportV2) Connect(host string, port int) error {
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

	// Use blocking connect for now
	if err := syscall.Connect(fd, sa); err != nil {
		syscall.Close(fd)
		return errors.NewTransportError(
			errors.TransportErrorSocketConnectFailure,
			fmt.Sprintf("failed to connect to %s", addr),
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

	t.fd = fd
	t.file = os.NewFile(uintptr(fd), "socket")
	return nil
}

// Write sends data over the connection using io_uring
func (t *TcpTransportV2) Write(buf []byte) (int, error) {
	if t.fd < 0 {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketWriteFailure,
			"not connected",
			nil,
		)
	}

	totalWritten := 0
	for totalWritten < len(buf) {
		// Queue write operation
		sqe := uring.Write(t.file.Fd(), buf[totalWritten:], uint64(totalWritten))
		if err := t.ring.QueueSQE(sqe, 0, 0); err != nil {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorIoUringSubmit,
				"failed to queue write request",
				err,
			)
		}

		// Submit and wait
		if _, err := t.ring.Submit(); err != nil {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorIoUringSubmit,
				"failed to submit write request",
				err,
			)
		}

		// Wait for completion
		cqe, err := t.ring.WaitCQEvents(1)
		if err != nil {
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorSocketWriteFailure,
				"failed to wait for write completion",
				err,
			)
		}

		if err := cqe.Error(); err != nil {
			t.ring.SeenCQE(cqe)
			return totalWritten, errors.NewTransportError(
				errors.TransportErrorSocketWriteFailure,
				"write operation failed",
				err,
			)
		}

		n := int(cqe.Res)
		t.ring.SeenCQE(cqe)

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
func (t *TcpTransportV2) Read(buf []byte) (int, error) {
	if t.fd < 0 {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketReadFailure,
			"not connected",
			nil,
		)
	}

	// Queue read operation
	sqe := uring.Read(t.file.Fd(), buf, 0)
	if err := t.ring.QueueSQE(sqe, 0, 0); err != nil {
		return 0, errors.NewTransportError(
			errors.TransportErrorIoUringSubmit,
			"failed to queue read request",
			err,
		)
	}

	// Submit and wait
	if _, err := t.ring.Submit(); err != nil {
		return 0, errors.NewTransportError(
			errors.TransportErrorIoUringSubmit,
			"failed to submit read request",
			err,
		)
	}

	// Wait for completion
	cqe, err := t.ring.WaitCQEvents(1)
	if err != nil {
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketReadFailure,
			"failed to wait for read completion",
			err,
		)
	}

	if err := cqe.Error(); err != nil {
		t.ring.SeenCQE(cqe)
		return 0, errors.NewTransportError(
			errors.TransportErrorSocketReadFailure,
			"read operation failed",
			err,
		)
	}

	n := int(cqe.Res)
	t.ring.SeenCQE(cqe)

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
func (t *TcpTransportV2) Close() error {
	if t.fd < 0 {
		return nil
	}

	if t.file != nil {
		t.file.Close()
		t.file = nil
	}
	t.fd = -1

	return nil
}

// Destroy cleans up resources including the io_uring instance
func (t *TcpTransportV2) Destroy() {
	t.Close()
	if t.ring != nil {
		t.ring.Close()
		t.ring = nil
	}
}
