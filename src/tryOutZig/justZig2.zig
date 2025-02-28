const std = @import("std");
pub fn main() !void {
    // first result: just adding no vectors in code
    // ~200_000_000 operations per second
    // ~800_000_000 operations per second (fast)
    // second result: if + add
    // ~80_000_000 ops
    // ~800_000_000 operations per second (fast)
    //
    // vector stuff: estimated 60_000_000 operations
    // expected time without vectors = 0.3seconds => 300_000 microseconds
    // expected time without vectors = 0.3seconds => 75_000 microseconds(fast)
    std.debug.print("start justZig!\n", .{});
    const dataLength = 1_000_000;
    var data: [dataLength]f32 = undefined;
    const rand = std.crypto.random;
    for (&data) |*entry| {
        entry.* = rand.float(f32);
        if (entry.* < 0.5) entry.* = 0;
    }
    const startTime = std.time.microTimestamp();
    var result: f32 = 0;
    for (0..dataLength) |i| {
        result += data[i];
    }
    const endTime = std.time.microTimestamp();
    const timePassed = endTime - startTime;
    const operationCount = dataLength;
    const operationsPerMS = @divFloor(operationCount * 1_000, timePassed);
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
}
