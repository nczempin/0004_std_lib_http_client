const std = @import("std");
const errors = @import("errors.zig");
const transport = @import("transport.zig");
const HttpError = errors.HttpError;
const Transport = transport.Transport;

const os = std.os;
const net = std.net;

/// Unix domain socket transport implementation
pub const UnixTransport = struct {
    allocator: std.mem.Allocator,
    stream: ?net.Stream,

    const Self = @This();

    /// Initialize a new Unix socket transport
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stream = null,
        };
    }

    /// Get the Transport interface for this Unix transport
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

    fn connectImpl(ptr: *anyopaque, path: []const u8, _: u16) HttpError!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // For Unix sockets, the "host" parameter is the socket path
        // The port parameter is ignored
        const stream = net.connectUnixSocket(path) catch {
            return HttpError.SocketConnectFailure;
        };

        self.stream = stream;
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
};

// Tests
test "UnixTransport init" {
    const allocator = std.testing.allocator;
    var unix_transport = UnixTransport.init(allocator);
    defer unix_transport.transport().deinit();

    try std.testing.expect(unix_transport.stream == null);
}

test "UnixTransport connect to socket" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for the socket
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create socket path
    var path_buffer: [4096]u8 = undefined;
    const socket_path = try tmp_dir.dir.realpath(".", &path_buffer);
    const full_socket_path = try std.fmt.allocPrint(
        allocator,
        "{s}/test.sock",
        .{socket_path},
    );
    defer allocator.free(full_socket_path);

    // Start a Unix socket server
    const address = try net.Address.initUnix(full_socket_path);
    var server = try address.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

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

    // Connect using UnixTransport
    var unix_transport = UnixTransport.init(allocator);
    defer unix_transport.transport().deinit();

    var t = unix_transport.transport();
    try t.connect(full_socket_path, 0);
    try std.testing.expect(unix_transport.stream != null);
}
