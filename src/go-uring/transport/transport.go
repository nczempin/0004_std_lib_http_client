package transport

// Transport defines the interface for network transports
type Transport interface {
	// Connect establishes a connection to the specified host and port
	Connect(host string, port int) error

	// Write sends data over the connection
	// Returns the number of bytes written
	Write(buf []byte) (int, error)

	// Read receives data from the connection
	// Returns the number of bytes read
	Read(buf []byte) (int, error)

	// Close closes the connection
	Close() error
}
