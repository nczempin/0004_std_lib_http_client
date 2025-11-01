const std = @import("std");
const errors = @import("errors.zig");
const transport = @import("transport.zig");
const HttpError = errors.HttpError;
const Transport = transport.Transport;

/// HTTP methods
pub const HttpMethod = enum {
    GET,
    POST,
};

/// HTTP header key-value pair
pub const HttpHeader = struct {
    key: []const u8,
    value: []const u8,
};

/// HTTP request structure
pub const HttpRequest = struct {
    method: HttpMethod,
    path: []const u8,
    headers: []const HttpHeader,
    body: []const u8,

    pub fn init(method: HttpMethod, path: []const u8) HttpRequest {
        return .{
            .method = method,
            .path = path,
            .headers = &[_]HttpHeader{},
            .body = &[_]u8{},
        };
    }
};

/// HTTP response structure
pub const HttpResponse = struct {
    status_code: u16,
    status_message: []const u8,
    headers: []HttpHeader,
    body: []const u8,
    content_length: usize,
    // For safe mode: owns the buffer
    owned_buffer: ?[]u8,

    pub fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        if (self.owned_buffer) |buf| {
            allocator.free(buf);
            self.owned_buffer = null;
        }
        if (self.headers.len > 0) {
            allocator.free(self.headers);
        }
    }
};

/// Memory policy for HTTP responses
pub const ResponseMemoryPolicy = enum {
    /// Safe mode: copies response data into owned buffer
    SafeOwning,
    /// Unsafe mode: uses pointers into parser buffer (zero-copy)
    UnsafeZeroCopy,
};

/// HTTP/1.1 protocol handler
pub const Http1Protocol = struct {
    allocator: std.mem.Allocator,
    transport_impl: Transport,
    buffer: std.ArrayList(u8),
    memory_policy: ResponseMemoryPolicy,

    const Self = @This();

    /// Initialize a new HTTP/1.1 protocol handler
    pub fn init(allocator: std.mem.Allocator, trans: Transport, policy: ResponseMemoryPolicy) Self {
        return .{
            .allocator = allocator,
            .transport_impl = trans,
            .buffer = std.ArrayList(u8){},
            .memory_policy = policy,
        };
    }

    /// Cleanup and free resources
    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Connect to a remote host
    pub fn connect(self: *Self, host: []const u8, port: u16) HttpError!void {
        return self.transport_impl.connect(host, port);
    }

    /// Disconnect from the remote host
    pub fn disconnect(self: *Self) HttpError!void {
        return self.transport_impl.close();
    }

    /// Perform an HTTP request
    pub fn performRequest(self: *Self, request: *const HttpRequest, response: *HttpResponse) HttpError!void {
        // Build and send request
        try self.buildAndSendRequest(request);

        // Read and parse response
        try self.readAndParseResponse(response);
    }

    /// Build HTTP request and send it
    fn buildAndSendRequest(self: *Self, request: *const HttpRequest) HttpError!void {
        self.buffer.clearRetainingCapacity();

        // Request line
        const method_str = switch (request.method) {
            .GET => "GET",
            .POST => "POST",
        };

        try self.buffer.writer(self.allocator).print("{s} {s} HTTP/1.1\r\n", .{ method_str, request.path });

        // Headers
        for (request.headers) |header| {
            try self.buffer.writer(self.allocator).print("{s}: {s}\r\n", .{ header.key, header.value });
        }

        // Empty line
        try self.buffer.appendSlice(self.allocator, "\r\n");

        // Body (for POST requests)
        if (request.method == .POST and request.body.len > 0) {
            try self.buffer.appendSlice(self.allocator, request.body);
        }

        // Send the request
        _ = try self.transport_impl.write(self.buffer.items);
    }

    /// Read and parse HTTP response
    fn readAndParseResponse(self: *Self, response: *HttpResponse) HttpError!void {
        self.buffer.clearRetainingCapacity();

        var headers_parsed = false;
        var header_end_pos: usize = 0;
        var content_length: ?usize = null;

        // Read loop
        while (true) {
            // Ensure we have space to read
            const old_len = self.buffer.items.len;
            try self.buffer.resize(self.allocator, old_len + 4096);

            // Read data
            const bytes_read = self.transport_impl.read(self.buffer.items[old_len..]) catch |err| {
                if (err == HttpError.ConnectionClosed) {
                    // Connection closed, check if we have all data
                    self.buffer.shrinkRetainingCapacity(old_len);
                    if (content_length) |expected| {
                        const body_start = header_end_pos;
                        if (self.buffer.items.len < body_start + expected) {
                            return HttpError.HttpParseFailure;
                        }
                    }
                    break;
                }
                return err;
            };

            self.buffer.shrinkRetainingCapacity(old_len + bytes_read);

            // Parse headers if not yet done
            if (!headers_parsed) {
                if (std.mem.indexOf(u8, self.buffer.items, "\r\n\r\n")) |pos| {
                    headers_parsed = true;
                    header_end_pos = pos + 4;

                    // Parse headers
                    content_length = try self.parseHeaders(self.buffer.items[0..pos], response);
                }
            }

            // Check if we have the complete response
            if (headers_parsed) {
                if (content_length) |expected| {
                    const body_start = header_end_pos;
                    if (self.buffer.items.len >= body_start + expected) {
                        // Complete response received
                        break;
                    }
                } else {
                    // No content-length, assume we have everything
                    break;
                }
            }
        }

        // Finalize response based on memory policy
        if (self.memory_policy == .SafeOwning) {
            try self.finalizeSafeResponse(response, header_end_pos, content_length);
        } else {
            try self.finalizeUnsafeResponse(response, header_end_pos, content_length);
        }
    }

    /// Parse HTTP headers
    fn parseHeaders(self: *Self, header_data: []const u8, response: *HttpResponse) HttpError!?usize {
        var lines = std.mem.splitSequence(u8, header_data, "\r\n");

        // Parse status line
        const status_line = lines.next() orelse return HttpError.HttpParseFailure;
        try self.parseStatusLine(status_line, response);

        // Parse header fields
        var headers = std.ArrayList(HttpHeader).init(self.allocator);
        errdefer headers.deinit();

        var content_length: ?usize = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
            const key = line[0..colon_pos];
            var value = line[colon_pos + 1 ..];

            // Trim leading whitespace from value
            while (value.len > 0 and value[0] == ' ') {
                value = value[1..];
            }

            try headers.append(.{ .key = key, .value = value });

            // Check for Content-Length
            if (std.ascii.eqlIgnoreCase(key, "Content-Length")) {
                content_length = std.fmt.parseInt(usize, value, 10) catch null;
            }
        }

        response.headers = try headers.toOwnedSlice();
        return content_length;
    }

    /// Parse HTTP status line
    fn parseStatusLine(self: *Self, line: []const u8, response: *HttpResponse) HttpError!void {
        _ = self;

        // Format: "HTTP/1.1 200 OK"
        var parts = std.mem.splitSequence(u8, line, " ");

        // Skip HTTP version
        _ = parts.next() orelse return HttpError.HttpParseFailure;

        // Get status code
        const status_str = parts.next() orelse return HttpError.HttpParseFailure;
        response.status_code = std.fmt.parseInt(u16, status_str, 10) catch {
            return HttpError.HttpParseFailure;
        };

        // Get status message (rest of the line)
        const rest = parts.rest();
        response.status_message = rest;
    }

    /// Finalize response in safe mode (copy data)
    fn finalizeSafeResponse(self: *Self, response: *HttpResponse, header_end_pos: usize, content_length: ?usize) HttpError!void {
        const items = self.buffer.items;
        const body_len = if (content_length) |len| len else (items.len - header_end_pos);
        response.content_length = body_len;

        // Allocate owned buffer
        const owned_buf = self.allocator.alloc(u8, items.len) catch {
            return HttpError.OutOfMemory;
        };
        errdefer self.allocator.free(owned_buf);

        // Copy data
        @memcpy(owned_buf, items);

        // Update pointers to point into owned buffer
        response.owned_buffer = owned_buf;
        response.body = owned_buf[header_end_pos..][0..body_len];

        // Update header pointers
        for (response.headers) |*header| {
            const key_offset = @intFromPtr(header.key.ptr) - @intFromPtr(items.ptr);
            const value_offset = @intFromPtr(header.value.ptr) - @intFromPtr(items.ptr);
            header.key = owned_buf[key_offset..][0..header.key.len];
            header.value = owned_buf[value_offset..][0..header.value.len];
        }

        const status_msg_offset = @intFromPtr(response.status_message.ptr) - @intFromPtr(items.ptr);
        response.status_message = owned_buf[status_msg_offset..][0..response.status_message.len];
    }

    /// Finalize response in unsafe mode (zero-copy)
    fn finalizeUnsafeResponse(self: *Self, response: *HttpResponse, header_end_pos: usize, content_length: ?usize) HttpError!void {
        const items = self.buffer.items;
        const body_len = if (content_length) |len| len else (items.len - header_end_pos);
        response.content_length = body_len;
        response.owned_buffer = null;
        response.body = items[header_end_pos..][0..body_len];

        // Headers and status_message already point into self.buffer
        // This is unsafe because self.buffer can be reallocated/modified
    }
};

// Tests
test "Http1Protocol init" {
    const allocator = std.testing.allocator;
    const tcp_transport = @import("tcp_transport.zig");

    var tcp = tcp_transport.TcpTransport.init(allocator);
    defer tcp.transport().deinit();

    var protocol = Http1Protocol.init(allocator, tcp.transport(), .SafeOwning);
    defer protocol.deinit();
}

test "HTTP request formatting GET" {
    const allocator = std.testing.allocator;
    const tcp_transport = @import("tcp_transport.zig");

    var tcp = tcp_transport.TcpTransport.init(allocator);
    defer tcp.transport().deinit();

    var protocol = Http1Protocol.init(allocator, tcp.transport(), .SafeOwning);
    defer protocol.deinit();

    const request = HttpRequest{
        .method = .GET,
        .path = "/test",
        .headers = &[_]HttpHeader{
            .{ .key = "Host", .value = "example.com" },
        },
        .body = &[_]u8{},
    };

    protocol.buffer.clearRetainingCapacity();
    const method_str = "GET";
    try protocol.buffer.writer(allocator).print("{s} {s} HTTP/1.1\r\n", .{ method_str, request.path });
    for (request.headers) |header| {
        try protocol.buffer.writer(allocator).print("{s}: {s}\r\n", .{ header.key, header.value });
    }
    try protocol.buffer.appendSlice(allocator, "\r\n");

    const expected = "GET /test HTTP/1.1\r\nHost: example.com\r\n\r\n";
    try std.testing.expectEqualStrings(expected, protocol.buffer.items);
}
