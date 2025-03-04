const std = @import("std");
const net = std.net;
const io = std.io;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    // Twitch IRC server details
    const host = "irc.chat.twitch.tv";
    const port = 6667; // Use 6697 for TLS (requires additional setup)

    // Twitch credentials
    const oauth_token = "something";
    const username = "justinfan7531"; // anonymous username justinfanxxxx
    const channel = "#helmiblub";

    // Connect to Twitch IRC server
    var conn = try net.tcpConnectToHost(gpa, host, port);
    defer conn.close();

    var reader = io.bufferedReader(conn.reader());
    var writer = io.bufferedWriter(conn.writer());
    const out_stream = writer.writer();

    // Authenticate with Twitch
    try out_stream.print("PASS {s}\r\n", .{oauth_token});
    try out_stream.print("NICK {s}\r\n", .{username});
    try out_stream.print("JOIN {s}\r\n", .{channel});
    try writer.flush();

    // Read and print incoming messages
    var buf: [600]u8 = undefined;
    while (true) {
        const line = try reader.reader().readUntilDelimiterOrEof(&buf, '\n') orelse break;
        std.debug.print("{s}\n", .{line});

        // Respond to PING to stay connected
        if (std.mem.startsWith(u8, line, "PING")) {
            try out_stream.print("PONG :tmi.twitch.tv\r\n", .{});
            try writer.flush();
        }
    }
}
