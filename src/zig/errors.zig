const std = @import("std");

/// Error types for the HTTP client library
pub const HttpError = error{
    // Transport errors
    DnsFailure,
    SocketCreateFailure,
    SocketConnectFailure,
    SocketWriteFailure,
    SocketReadFailure,
    ConnectionClosed,
    SocketCloseFailure,
    TransportInitFailure,

    // HTTP client errors (for later phases)
    UrlParseFailure,
    HttpParseFailure,
    InvalidRequestSyntax,
    ClientInitFailure,

    // Memory allocation errors (Zig convention)
    OutOfMemory,
};

/// Convert system errors to HttpError
pub fn fromSystemError(err: anyerror) HttpError {
    return switch (err) {
        error.OutOfMemory => HttpError.OutOfMemory,
        error.ConnectionRefused => HttpError.SocketConnectFailure,
        error.NetworkUnreachable => HttpError.SocketConnectFailure,
        error.ConnectionResetByPeer => HttpError.ConnectionClosed,
        error.BrokenPipe => HttpError.ConnectionClosed,
        else => HttpError.TransportInitFailure, // Default fallback for unknown errors
    };
}
