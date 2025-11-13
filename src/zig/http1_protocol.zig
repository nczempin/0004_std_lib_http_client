const std = @import("std");
const transport_mod = @import("transport.zig");
const errors = @import("errors.zig");
const Transport = transport_mod.Transport;
const HttpError = errors.HttpError;

/// HTTP request methods
pub const HttpMethod = enum {
    GET,
    POST,

    pub fn toString(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
        };
    }
};

/// HTTP header (view - does not own data)
pub const HttpHeader = struct {
    key: []const u8,
    value: []const u8,
};

/// HTTP header (owned - owns the data)
pub const HttpOwnedHeader = struct {
    key: []u8,
    value: []u8,

    pub fn deinit(self: *HttpOwnedHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

/// HTTP request structure
pub const HttpRequest = struct {
    method: HttpMethod,
    path: []const u8,
    body: []const u8,
    headers: []const HttpHeader,
};

/// Safe HTTP response - owns all data (copying mode)
pub const SafeHttpResponse = struct {
    status_code: u16,
    status_message: []u8,
    body: []u8,
    headers: std.ArrayList(HttpOwnedHeader),
    content_length: ?usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SafeHttpResponse) void {
        self.allocator.free(self.status_message);
        self.allocator.free(self.body);
        for (self.headers.items) |*header| {
            header.deinit(self.allocator);
        }
        self.headers.deinit();
    }
};

/// Unsafe HTTP response - borrows data from protocol buffer (zero-copy mode)
pub const UnsafeHttpResponse = struct {
    status_code: u16,
    status_message: []const u8,
    body: []const u8,
    headers: std.ArrayList(HttpHeader),
    content_length: ?usize,
};

/// HTTP/1.1 Protocol implementation
pub const Http1Protocol = struct {
    transport: Transport,
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    header_size: usize,
    content_length: ?usize,

    const HEADER_SEPARATOR = "\r\n\r\n";
    const CONTENT_LENGTH_HEADER = "Content-Length:";

    pub fn init(allocator: std.mem.Allocator, transport_impl: Transport) !Http1Protocol {
        return Http1Protocol{
            .transport = transport_impl,
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .header_size = 0,
            .content_length = null,
        };
    }

    pub fn deinit(self: *Http1Protocol) void {
        self.buffer.deinit();
    }

    /// Connect to a remote host
    pub fn connect(self: *Http1Protocol, host: []const u8, port: u16) HttpError!void {
        return self.transport.connect(host, port);
    }

    /// Disconnect from the remote host
    pub fn disconnect(self: *Http1Protocol) HttpError!void {
        return self.transport.close();
    }

    /// Perform HTTP request with safe (copying) mode
    pub fn performRequestSafe(self: *Http1Protocol, request: *const HttpRequest) HttpError!SafeHttpResponse {
        try self.buildRequestString(request);
        try self.sendRequest();
        try self.readFullResponse();
        return self.parseSafeResponse();
    }

    /// Perform HTTP request with unsafe (zero-copy) mode
    pub fn performRequestUnsafe(self: *Http1Protocol, request: *const HttpRequest) HttpError!UnsafeHttpResponse {
        try self.buildRequestString(request);
        try self.sendRequest();
        try self.readFullResponse();
        return self.parseUnsafeResponse();
    }

    // --- Private helper methods ---

    /// Build HTTP request string in buffer
    fn buildRequestString(self: *Http1Protocol, request: *const HttpRequest) HttpError!void {
        self.buffer.clearRetainingCapacity();

        const method_str = request.method.toString();

        // Request line: METHOD PATH HTTP/1.1\r\n
        self.buffer.appendSlice(method_str) catch return HttpError.OutOfMemory;
        self.buffer.append(' ') catch return HttpError.OutOfMemory;
        self.buffer.appendSlice(request.path) catch return HttpError.OutOfMemory;
        self.buffer.appendSlice(" HTTP/1.1\r\n") catch return HttpError.OutOfMemory;

        // Headers
        for (request.headers) |header| {
            self.buffer.appendSlice(header.key) catch return HttpError.OutOfMemory;
            self.buffer.appendSlice(": ") catch return HttpError.OutOfMemory;
            self.buffer.appendSlice(header.value) catch return HttpError.OutOfMemory;
            self.buffer.appendSlice("\r\n") catch return HttpError.OutOfMemory;
        }

        // Empty line to separate headers from body
        self.buffer.appendSlice("\r\n") catch return HttpError.OutOfMemory;

        // Body (if POST and body provided)
        if (request.method == .POST and request.body.len > 0) {
            self.buffer.appendSlice(request.body) catch return HttpError.OutOfMemory;
        }
    }

    /// Send the request to the transport
    fn sendRequest(self: *Http1Protocol) HttpError!void {
        const bytes_written = try self.transport.write(self.buffer.items);
        if (bytes_written != self.buffer.items.len) {
            return HttpError.SocketWriteFailure;
        }
    }

    /// Read the full HTTP response (headers + body)
    fn readFullResponse(self: *Http1Protocol) HttpError!void {
        self.buffer.clearRetainingCapacity();
        self.header_size = 0;
        self.content_length = null;

        var read_buffer: [1024]u8 = undefined;

        while (true) {
            const bytes_read = self.transport.read(&read_buffer) catch |err| {
                if (err == HttpError.ConnectionClosed) {
                    // Check if we have complete headers and body
                    if (self.content_length) |content_len| {
                        if (self.buffer.items.len < self.header_size + content_len) {
                            return HttpError.HttpParseFailure;
                        }
                    }
                    break;
                }
                return err;
            };

            if (bytes_read == 0) {
                // Connection closed
                if (self.content_length) |content_len| {
                    if (self.buffer.items.len < self.header_size + content_len) {
                        return HttpError.HttpParseFailure;
                    }
                }
                break;
            }

            self.buffer.appendSlice(read_buffer[0..bytes_read]) catch return HttpError.OutOfMemory;

            // Parse header separator if we haven't found it yet
            if (self.header_size == 0) {
                if (std.mem.indexOf(u8, self.buffer.items, HEADER_SEPARATOR)) |pos| {
                    self.header_size = pos + HEADER_SEPARATOR.len;

                    // Parse Content-Length from headers
                    const headers_view = self.buffer.items[0..self.header_size];
                    self.content_length = self.extractContentLength(headers_view);
                }
            }

            // Check if we have the complete body
            if (self.content_length) |content_len| {
                if (self.buffer.items.len >= self.header_size + content_len) {
                    break;
                }
            }
        }

        if (self.header_size == 0 and self.buffer.items.len > 0) {
            return HttpError.HttpParseFailure;
        }
    }

    /// Extract Content-Length from headers
    fn extractContentLength(self: *Http1Protocol, headers_view: []const u8) ?usize {
        var lines = std.mem.splitScalar(u8, headers_view, '\n');
        _ = lines.next(); // Skip status line

        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed_line.len == 0) break;

            // Check if this line starts with "Content-Length:" (case-insensitive)
            if (std.ascii.startsWithIgnoreCase(trimmed_line, CONTENT_LENGTH_HEADER)) {
                const colon_pos = std.mem.indexOf(u8, trimmed_line, ":") orelse continue;
                const value_slice = trimmed_line[colon_pos + 1 ..];
                const value_trimmed = std.mem.trim(u8, value_slice, &std.ascii.whitespace);

                return std.fmt.parseInt(usize, value_trimmed, 10) catch null;
            }
        }

        return null;
    }

    /// Parse response in safe (copying) mode
    fn parseSafeResponse(self: *Http1Protocol) HttpError!SafeHttpResponse {
        if (self.header_size == 0) {
            return HttpError.HttpParseFailure;
        }

        const headers_block = self.buffer.items[0 .. self.header_size - HEADER_SEPARATOR.len];

        var lines = std.mem.splitScalar(u8, headers_block, '\n');

        // Parse status line
        const status_line = lines.next() orelse return HttpError.HttpParseFailure;
        const trimmed_status = std.mem.trimRight(u8, status_line, "\r");

        var status_parts = std.mem.splitScalar(u8, trimmed_status, ' ');
        _ = status_parts.next(); // Skip HTTP version
        const status_code_str = status_parts.next() orelse return HttpError.HttpParseFailure;
        const status_message_raw = status_parts.rest();

        const status_code = std.fmt.parseInt(u16, status_code_str, 10) catch return HttpError.HttpParseFailure;

        // Copy status message
        const status_message = self.allocator.dupe(u8, status_message_raw) catch return HttpError.OutOfMemory;
        errdefer self.allocator.free(status_message);

        // Parse headers
        var headers_list = std.ArrayList(HttpOwnedHeader).init(self.allocator);
        errdefer {
            for (headers_list.items) |*header| {
                header.deinit(self.allocator);
            }
            headers_list.deinit();
        }

        while (lines.next()) |line| {
            const trimmed_line = std.mem.trimRight(u8, line, "\r");
            if (trimmed_line.len == 0) break;

            if (std.mem.indexOf(u8, trimmed_line, ":")) |colon_pos| {
                const key_slice = trimmed_line[0..colon_pos];
                const value_slice = std.mem.trim(u8, trimmed_line[colon_pos + 1 ..], &std.ascii.whitespace);

                const key = self.allocator.dupe(u8, key_slice) catch return HttpError.OutOfMemory;
                errdefer self.allocator.free(key);
                const value = self.allocator.dupe(u8, value_slice) catch return HttpError.OutOfMemory;
                errdefer self.allocator.free(value);

                headers_list.append(.{ .key = key, .value = value }) catch return HttpError.OutOfMemory;
            }
        }

        // Copy body
        const body_start = self.header_size;
        const body_slice = if (body_start < self.buffer.items.len)
            self.buffer.items[body_start..]
        else
            &[_]u8{};

        const body = self.allocator.dupe(u8, body_slice) catch return HttpError.OutOfMemory;

        return SafeHttpResponse{
            .status_code = status_code,
            .status_message = status_message,
            .body = body,
            .headers = headers_list,
            .content_length = self.content_length,
            .allocator = self.allocator,
        };
    }

    /// Parse response in unsafe (zero-copy) mode - borrows from internal buffer
    fn parseUnsafeResponse(self: *Http1Protocol) HttpError!UnsafeHttpResponse {
        if (self.header_size == 0) {
            return HttpError.HttpParseFailure;
        }

        const headers_block = self.buffer.items[0 .. self.header_size - HEADER_SEPARATOR.len];

        var lines = std.mem.splitScalar(u8, headers_block, '\n');

        // Parse status line
        const status_line = lines.next() orelse return HttpError.HttpParseFailure;
        const trimmed_status = std.mem.trimRight(u8, status_line, "\r");

        var status_parts = std.mem.splitScalar(u8, trimmed_status, ' ');
        _ = status_parts.next(); // Skip HTTP version
        const status_code_str = status_parts.next() orelse return HttpError.HttpParseFailure;
        const status_message = status_parts.rest();

        const status_code = std.fmt.parseInt(u16, status_code_str, 10) catch return HttpError.HttpParseFailure;

        // Parse headers (borrowing)
        var headers_list = std.ArrayList(HttpHeader).init(self.allocator);
        errdefer headers_list.deinit();

        while (lines.next()) |line| {
            const trimmed_line = std.mem.trimRight(u8, line, "\r");
            if (trimmed_line.len == 0) break;

            if (std.mem.indexOf(u8, trimmed_line, ":")) |colon_pos| {
                const key_slice = trimmed_line[0..colon_pos];
                const value_slice = std.mem.trim(u8, trimmed_line[colon_pos + 1 ..], &std.ascii.whitespace);

                headers_list.append(.{ .key = key_slice, .value = value_slice }) catch return HttpError.OutOfMemory;
            }
        }

        // Body (borrowing)
        const body_start = self.header_size;
        const body = if (body_start < self.buffer.items.len)
            self.buffer.items[body_start..]
        else
            &[_]u8{};

        return UnsafeHttpResponse{
            .status_code = status_code,
            .status_message = status_message,
            .body = body,
            .headers = headers_list,
            .content_length = self.content_length,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

/// Mock transport for testing
const MockTransport = struct {
    allocator: std.mem.Allocator,
    write_buffer: std.ArrayList(u8),
    read_data: []const u8,
    read_offset: usize,
    is_connected: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, response_data: []const u8) !Self {
        return .{
            .allocator = allocator,
            .write_buffer = std.ArrayList(u8).init(allocator),
            .read_data = response_data,
            .read_offset = 0,
            .is_connected = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.write_buffer.deinit();
    }

    pub fn transport(self: *Self) Transport {
        return .{
            .ptr = self,
            .vtable = &.{
                .connect = connectImpl,
                .write = writeImpl,
                .read = readImpl,
                .close = closeImpl,
                .deinit = deinitImpl,
            },
        };
    }

    fn connectImpl(ptr: *anyopaque, host: []const u8, port: u16) HttpError!void {
        _ = host;
        _ = port;
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.is_connected = true;
    }

    fn writeImpl(ptr: *anyopaque, buffer: []const u8) HttpError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.write_buffer.appendSlice(buffer);
        return buffer.len;
    }

    fn readImpl(ptr: *anyopaque, buffer: []u8) HttpError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.read_offset >= self.read_data.len) {
            return HttpError.ConnectionClosed;
        }

        const remaining = self.read_data.len - self.read_offset;
        const to_copy = @min(buffer.len, remaining);

        @memcpy(buffer[0..to_copy], self.read_data[self.read_offset..][0..to_copy]);
        self.read_offset += to_copy;

        return to_copy;
    }

    fn closeImpl(ptr: *anyopaque) HttpError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.is_connected = false;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        _ = ptr;
    }
};

test "Http1Protocol init and deinit" {
    const allocator = testing.allocator;

    var mock = try MockTransport.init(allocator, "");
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    try testing.expect(protocol.header_size == 0);
    try testing.expect(protocol.content_length == null);
}

test "Http1Protocol build GET request" {
    const allocator = testing.allocator;

    var mock = try MockTransport.init(allocator, "");
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const headers = [_]HttpHeader{
        .{ .key = "Host", .value = "example.com" },
        .{ .key = "User-Agent", .value = "httpzig/1.0" },
    };

    const request = HttpRequest{
        .method = .GET,
        .path = "/test",
        .body = "",
        .headers = &headers,
    };

    try protocol.buildRequestString(&request);

    const expected = "GET /test HTTP/1.1\r\nHost: example.com\r\nUser-Agent: httpzig/1.0\r\n\r\n";
    try testing.expectEqualStrings(expected, protocol.buffer.items);
}

test "Http1Protocol build POST request" {
    const allocator = testing.allocator;

    var mock = try MockTransport.init(allocator, "");
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const headers = [_]HttpHeader{
        .{ .key = "Host", .value = "example.com" },
        .{ .key = "Content-Type", .value = "application/json" },
    };

    const body = "{\"key\":\"value\"}";

    const request = HttpRequest{
        .method = .POST,
        .path = "/api/data",
        .body = body,
        .headers = &headers,
    };

    try protocol.buildRequestString(&request);

    const expected = "POST /api/data HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\n\r\n{\"key\":\"value\"}";
    try testing.expectEqualStrings(expected, protocol.buffer.items);
}

test "Http1Protocol parse response safe mode" {
    const allocator = testing.allocator;

    const response_data = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

    var mock = try MockTransport.init(allocator, response_data);
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const request = HttpRequest{
        .method = .GET,
        .path = "/",
        .body = "",
        .headers = &[_]HttpHeader{},
    };

    var response = try protocol.performRequestSafe(&request);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("OK", response.status_message);
    try testing.expectEqualStrings("Hello, World!", response.body);
    try testing.expectEqual(@as(?usize, 13), response.content_length);
    try testing.expect(response.headers.items.len >= 2);
}

test "Http1Protocol parse response unsafe mode" {
    const allocator = testing.allocator;

    const response_data = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: 9\r\n\r\nNot Found";

    var mock = try MockTransport.init(allocator, response_data);
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const request = HttpRequest{
        .method = .GET,
        .path = "/missing",
        .body = "",
        .headers = &[_]HttpHeader{},
    };

    var response = try protocol.performRequestUnsafe(&request);
    defer response.headers.deinit();

    try testing.expectEqual(@as(u16, 404), response.status_code);
    try testing.expectEqualStrings("Not Found", response.status_message);
    try testing.expectEqualStrings("Not Found", response.body);
    try testing.expectEqual(@as(?usize, 9), response.content_length);
    try testing.expect(response.headers.items.len >= 2);
}

test "Http1Protocol extract Content-Length" {
    const allocator = testing.allocator;

    var mock = try MockTransport.init(allocator, "");
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const headers = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 42\r\n\r\n";
    const content_length = protocol.extractContentLength(headers);

    try testing.expectEqual(@as(?usize, 42), content_length);
}

test "Http1Protocol parse response without Content-Length" {
    const allocator = testing.allocator;

    // Response without Content-Length - server will close connection to signal end
    const response_data = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nResponse body here";

    var mock = try MockTransport.init(allocator, response_data);
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const request = HttpRequest{
        .method = .GET,
        .path = "/",
        .body = "",
        .headers = &[_]HttpHeader{},
    };

    var response = try protocol.performRequestSafe(&request);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("Response body here", response.body);
    try testing.expectEqual(@as(?usize, null), response.content_length);
}

test "Http1Protocol multiple headers parsing" {
    const allocator = testing.allocator;

    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Server: TestServer/1.0\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 18\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "\r\n" ++
        "{\"status\":\"ok\"}";

    var mock = try MockTransport.init(allocator, response_data);
    defer mock.deinit();

    var protocol = try Http1Protocol.init(allocator, mock.transport());
    defer protocol.deinit();

    const request = HttpRequest{
        .method = .GET,
        .path = "/api/status",
        .body = "",
        .headers = &[_]HttpHeader{},
    };

    var response = try protocol.performRequestSafe(&request);
    defer response.deinit();

    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("{\"status\":\"ok\"}", response.body);
    try testing.expect(response.headers.items.len >= 4);

    // Check one of the headers exists
    var found_server = false;
    for (response.headers.items) |header| {
        if (std.mem.eql(u8, header.key, "Server")) {
            try testing.expectEqualStrings("TestServer/1.0", header.value);
            found_server = true;
            break;
        }
    }
    try testing.expect(found_server);
}
