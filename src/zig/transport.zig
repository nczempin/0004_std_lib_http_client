const std = @import("std");
const errors = @import("errors.zig");
const HttpError = errors.HttpError;

/// Transport interface for network I/O operations.
/// In Zig, we use a pattern with a vtable pointer for polymorphism.
pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        connect: *const fn (ptr: *anyopaque, host: []const u8, port: u16) HttpError!void,
        write: *const fn (ptr: *anyopaque, buffer: []const u8) HttpError!usize,
        read: *const fn (ptr: *anyopaque, buffer: []u8) HttpError!usize,
        close: *const fn (ptr: *anyopaque) HttpError!void,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// Connect to a remote host
    pub fn connect(self: Transport, host: []const u8, port: u16) HttpError!void {
        return self.vtable.connect(self.ptr, host, port);
    }

    /// Write data to the transport
    pub fn write(self: Transport, buffer: []const u8) HttpError!usize {
        return self.vtable.write(self.ptr, buffer);
    }

    /// Read data from the transport
    pub fn read(self: Transport, buffer: []u8) HttpError!usize {
        return self.vtable.read(self.ptr, buffer);
    }

    /// Close the transport connection
    pub fn close(self: Transport) HttpError!void {
        return self.vtable.close(self.ptr);
    }

    /// Cleanup and free resources
    pub fn deinit(self: Transport) void {
        self.vtable.deinit(self.ptr);
    }
};
