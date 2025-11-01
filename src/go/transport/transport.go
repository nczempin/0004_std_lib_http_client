package transport

// Transport defines the interface for network I/O operations.
// Implementations include TCP and Unix domain sockets.
type Transport interface {
	// Connect establishes a connection to the specified host and port.
	// For Unix sockets, the host parameter is the socket path and port is ignored.
	Connect(host string, port uint16) error

	// Write sends data to the connected peer.
	// Returns the number of bytes written or an error.
	Write(buf []byte) (int, error)

	// Read receives data from the connected peer.
	// Returns the number of bytes read or an error.
	Read(buf []byte) (int, error)

	// Close closes the connection.
	Close() error
}
