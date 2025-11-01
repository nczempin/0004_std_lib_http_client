const std = @import("std");
const errors = @import("errors.zig");
const transport = @import("transport.zig");
const tcp_transport = @import("tcp_transport.zig");
const unix_transport = @import("unix_transport.zig");
const http1_protocol = @import("http1_protocol.zig");

const HttpError = errors.HttpError;
const Transport = transport.Transport;
const TcpTransport = tcp_transport.TcpTransport;
const UnixTransport = unix_transport.UnixTransport;
const Http1Protocol = http1_protocol.Http1Protocol;
const HttpMethod = http1_protocol.HttpMethod;
const HttpHeader = http1_protocol.HttpHeader;
const HttpRequest = http1_protocol.HttpRequest;
const HttpResponse = http1_protocol.HttpResponse;
const ResponseMemoryPolicy = http1_protocol.ResponseMemoryPolicy;

/// Transport type for HTTP client
pub const TransportType = enum {
    TCP,
    UnixSocket,
};

/// Simple URL structure
pub const Url = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,

    /// Parse a URL string into components
    /// Supports: http://host:port/path or unix:///path/to/socket
    pub fn parse(url: []const u8) HttpError!Url {
        // Find scheme
        const scheme_end = std.mem.indexOf(u8, url, "://") orelse {
            return HttpError.UrlParseFailure;
        };

        const scheme = url[0..scheme_end];
        const rest = url[scheme_end + 3 ..];

        if (std.mem.eql(u8, scheme, "unix")) {
            // Unix socket: unix:///path/to/socket
            return .{
                .scheme = scheme,
                .host = "", // Not used for Unix sockets
                .port = 0, // Not used for Unix sockets
                .path = rest, // Full path including socket path
            };
        }

        if (std.mem.eql(u8, scheme, "http")) {
            // HTTP URL: http://host:port/path
            const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
            const host_port = rest[0..path_start];
            const path = if (path_start < rest.len) rest[path_start..] else "/";

            // Parse host:port
            if (std.mem.indexOf(u8, host_port, ":")) |colon_pos| {
                const host = host_port[0..colon_pos];
                const port_str = host_port[colon_pos + 1 ..];
                const port = std.fmt.parseInt(u16, port_str, 10) catch {
                    return HttpError.UrlParseFailure;
                };

                return .{
                    .scheme = scheme,
                    .host = host,
                    .port = port,
                    .path = path,
                };
            } else {
                // No port specified, use default 80
                return .{
                    .scheme = scheme,
                    .host = host_port,
                    .port = 80,
                    .path = path,
                };
            }
        }

        return HttpError.UrlParseFailure;
    }
};

/// HTTP Client
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    transport_type: TransportType,
    memory_policy: ResponseMemoryPolicy,
    tcp: ?TcpTransport,
    unix: ?UnixTransport,
    protocol: ?Http1Protocol,

    const Self = @This();

    /// Initialize a new HTTP client
    pub fn init(
        allocator: std.mem.Allocator,
        transport_type: TransportType,
        policy: ResponseMemoryPolicy,
    ) Self {
        return .{
            .allocator = allocator,
            .transport_type = transport_type,
            .memory_policy = policy,
            .tcp = if (transport_type == .TCP) TcpTransport.init(allocator) else null,
            .unix = if (transport_type == .UnixSocket) UnixTransport.init(allocator) else null,
            .protocol = null,
        };
    }

    /// Cleanup and free resources
    pub fn deinit(self: *Self) void {
        if (self.protocol) |*p| {
            p.deinit();
        }
        if (self.tcp) |*t| {
            t.transport().deinit();
        }
        if (self.unix) |*u| {
            u.transport().deinit();
        }
    }

    /// Perform a GET request
    pub fn get(
        self: *Self,
        url: []const u8,
        headers: []const HttpHeader,
        response: *HttpResponse,
    ) HttpError!void {
        const parsed_url = try Url.parse(url);

        // Connect if not already connected
        try self.ensureConnected(parsed_url);

        // Build request
        const request = HttpRequest{
            .method = .GET,
            .path = parsed_url.path,
            .headers = headers,
            .body = &[_]u8{},
        };

        // Perform request
        if (self.protocol) |*protocol| {
            try protocol.performRequest(&request, response);
        } else {
            return HttpError.ClientInitFailure;
        }
    }

    /// Perform a POST request
    pub fn post(
        self: *Self,
        url: []const u8,
        headers: []const HttpHeader,
        body: []const u8,
        response: *HttpResponse,
    ) HttpError!void {
        const parsed_url = try Url.parse(url);

        // Connect if not already connected
        try self.ensureConnected(parsed_url);

        // Validate Content-Length header is present
        var has_content_length = false;
        for (headers) |header| {
            if (std.ascii.eqlIgnoreCase(header.key, "Content-Length")) {
                has_content_length = true;
                break;
            }
        }

        if (!has_content_length) {
            return HttpError.InvalidRequestSyntax;
        }

        // Build request
        const request = HttpRequest{
            .method = .POST,
            .path = parsed_url.path,
            .headers = headers,
            .body = body,
        };

        // Perform request
        if (self.protocol) |*protocol| {
            try protocol.performRequest(&request, response);
        } else {
            return HttpError.ClientInitFailure;
        }
    }

    /// Ensure connection is established
    fn ensureConnected(self: *Self, url: Url) HttpError!void {
        if (self.protocol != null) {
            // Already connected
            return;
        }

        // Create protocol with appropriate transport
        if (self.transport_type == .TCP) {
            if (self.tcp) |*tcp| {
                var proto = Http1Protocol.init(
                    self.allocator,
                    tcp.transport(),
                    self.memory_policy,
                );
                try proto.connect(url.host, url.port);
                self.protocol = proto;
            }
        } else {
            if (self.unix) |*unix_sock| {
                var proto = Http1Protocol.init(
                    self.allocator,
                    unix_sock.transport(),
                    self.memory_policy,
                );
                try proto.connect(url.path, 0);
                self.protocol = proto;
            }
        }
    }
};

// Tests
test "URL parsing HTTP" {
    const url1 = try Url.parse("http://example.com:8080/test/path");
    try std.testing.expectEqualStrings("http", url1.scheme);
    try std.testing.expectEqualStrings("example.com", url1.host);
    try std.testing.expectEqual(@as(u16, 8080), url1.port);
    try std.testing.expectEqualStrings("/test/path", url1.path);

    const url2 = try Url.parse("http://example.com/path");
    try std.testing.expectEqualStrings("http", url2.scheme);
    try std.testing.expectEqualStrings("example.com", url2.host);
    try std.testing.expectEqual(@as(u16, 80), url2.port);
    try std.testing.expectEqualStrings("/path", url2.path);
}

test "URL parsing Unix socket" {
    const url = try Url.parse("unix:///tmp/test.sock");
    try std.testing.expectEqualStrings("unix", url.scheme);
    try std.testing.expectEqualStrings("/tmp/test.sock", url.path);
}

test "HttpClient init and deinit" {
    const allocator = std.testing.allocator;

    var client = HttpClient.init(allocator, .TCP, .SafeOwning);
    defer client.deinit();

    try std.testing.expect(client.tcp != null);
    try std.testing.expect(client.unix == null);
}
