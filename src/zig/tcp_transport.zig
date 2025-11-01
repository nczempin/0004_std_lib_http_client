const std = @import("std");
const errors = @import("errors.zig");
const transport = @import("transport.zig");
const HttpError = errors.HttpError;
const Transport = transport.Transport;

const os = std.os;
const net = std.net;

/// TCP transport implementation
pub const TcpTransport = struct {
    allocator: std.mem.Allocator,
    stream: ?net.Stream,

    const Self = @This();

    /// Initialize a new TCP transport
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stream = null,
        };
    }

    /// Get the Transport interface for this TCP transport
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
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Use Zig's standard library for DNS resolution and connection
        const address = net.Address.parseIp(host, port) catch {
            // If parsing as IP fails, try DNS resolution
            const address_list = net.getAddressList(self.allocator, host, port) catch {
                return HttpError.DnsFailure;
            };
            defer address_list.deinit();

            if (address_list.addrs.len == 0) {
                return HttpError.DnsFailure;
            }

            // Try to connect to the first address
            const stream = net.tcpConnectToAddress(address_list.addrs[0]) catch {
                return HttpError.SocketConnectFailure;
            };
            self.stream = stream;

            // Set TCP_NODELAY
            self.setTcpNoDelay() catch {};
            return;
        };

        // Direct IP address connection
        const stream = net.tcpConnectToAddress(address) catch {
            return HttpError.SocketConnectFailure;
        };
        self.stream = stream;

        // Set TCP_NODELAY
        self.setTcpNoDelay() catch {};
    }

    fn writeImpl(ptr: *anyopaque, buffer: []const u8) HttpError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.stream) |stream| {
            const bytes_written = stream.write(buffer) catch |err| {
                return errors.fromSystemError(err);
            };
            return bytes_written;
        }
        return HttpError.SocketWriteFailure;
    }

    fn readImpl(ptr: *anyopaque, buffer: []u8) HttpError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.stream) |stream| {
            const bytes_read = stream.read(buffer) catch |err| {
                return errors.fromSystemError(err);
            };

            if (bytes_read == 0) {
                return HttpError.ConnectionClosed;
            }

            return bytes_read;
        }
        return HttpError.SocketReadFailure;
    }

    fn closeImpl(ptr: *anyopaque) HttpError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
    }

    fn setTcpNoDelay(self: *Self) !void {
        if (self.stream) |stream| {
            const fd = stream.handle;
            const flag: c_int = 1;

            // Use setsockopt to set TCP_NODELAY
            const flag_bytes = std.mem.asBytes(&flag);
            const result = os.linux.setsockopt(
                fd,
                os.linux.IPPROTO.TCP,
                os.linux.TCP.NODELAY,
                flag_bytes.ptr,
                @intCast(flag_bytes.len),
            );
            _ = result; // Ignore result for now
        }
    }
};

// Tests
test "TcpTransport init" {
    const allocator = std.testing.allocator;
    var tcp = TcpTransport.init(allocator);
    defer tcp.transport().deinit();

    try std.testing.expect(tcp.stream == null);
}

test "TcpTransport connect to localhost" {
    const allocator = std.testing.allocator;

    // Start a simple echo server for testing
    const address = try net.Address.parseIp("127.0.0.1", 0);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    const server_port = server.listen_address.getPort();

    // Create a thread to accept the connection
    const ServerThread = struct {
        fn run(srv: *net.Server) void {
            const conn = srv.accept() catch return;
            defer conn.stream.close();
            // Just accept and close
        }
    };

    const thread = try std.Thread.spawn(.{}, ServerThread.run, .{&server});
    defer thread.join();

    // Connect using TcpTransport
    var tcp = TcpTransport.init(allocator);
    defer tcp.transport().deinit();

    var t = tcp.transport();
    try t.connect("127.0.0.1", server_port);
    try std.testing.expect(tcp.stream != null);
}
