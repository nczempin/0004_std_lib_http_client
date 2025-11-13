const std = @import("std");
const httpzig = @import("lib.zig");

const TcpTransport = httpzig.TcpTransport;
const Http1Protocol = httpzig.Http1Protocol;
const HttpMethod = httpzig.HttpMethod;
const HttpHeader = httpzig.HttpHeader;
const HttpRequest = httpzig.HttpRequest;

/// Integration test - demonstrates HTTP/1.1 protocol with TCP transport
/// This test makes a real HTTP request to example.com
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zig HTTP/1.1 Protocol Integration Test ===\n", .{});

    // Create TCP transport
    var tcp = TcpTransport.init(allocator);
    defer tcp.transport().deinit();

    // Create HTTP/1.1 protocol with TCP transport
    var protocol = try Http1Protocol.init(allocator, tcp.transport());
    defer protocol.deinit();

    // Connect to example.com
    std.debug.print("\nConnecting to example.com:80...\n", .{});
    try protocol.connect("93.184.216.34", 80); // example.com IP to avoid DNS lookup

    // Build HTTP GET request
    const headers = [_]HttpHeader{
        .{ .key = "Host", .value = "example.com" },
        .{ .key = "User-Agent", .value = "httpzig/1.0" },
        .{ .key = "Connection", .value = "close" },
    };

    const request = HttpRequest{
        .method = .GET,
        .path = "/",
        .body = "",
        .headers = &headers,
    };

    std.debug.print("Sending GET / request...\n", .{});

    // Perform request (safe mode - copies response)
    var response = try protocol.performRequestSafe(&request);
    defer response.deinit();

    // Print results
    std.debug.print("\n--- Response ---\n", .{});
    std.debug.print("Status: {} {s}\n", .{ response.status_code, response.status_message });
    std.debug.print("Content-Length: {?}\n", .{response.content_length});
    std.debug.print("Headers ({}):\n", .{response.headers.items.len});
    for (response.headers.items) |header| {
        std.debug.print("  {s}: {s}\n", .{ header.key, header.value });
    }
    std.debug.print("\nBody ({} bytes):\n{s}\n", .{ response.body.len, response.body });

    std.debug.print("\n=== Test completed successfully! ===\n", .{});
}
