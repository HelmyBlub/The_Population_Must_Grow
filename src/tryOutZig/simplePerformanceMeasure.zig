const std = @import("std");
pub fn main() !void {
    // first result: just adding no vectors in code
    // ~200_000_000 operations per second
    // ~800_000_000 operations per second (fast)
    // ~1_600_000 operations per second (Vector8)
    // ~3_800_000 operations per second (Vector8+fast)
    // ~2_900_000 operations per second (Vector16)
    // ~4_000_000 operations per second (Vector16+fast)
    //
    // vector stuff: estimated 60_000_000 operations
    // expected time without vectors = 0.3seconds => 300_000 microseconds
    // expected time without vectors = 0.3seconds => 75_000 microseconds(fast)
    // tried with u32 and f32. Both same result.
    std.debug.print("start justZig!\n", .{});
    const dataLength = 2_000_000;
    var data: [dataLength]u32 = undefined;
    const rand = std.crypto.random;
    for (&data) |*entry| {
        entry.* = rand.int(u8);
    }
    const startTime = std.time.microTimestamp();
    var result: u32 = 0;
    for (0..dataLength) |i| {
        result += data[i];
    }
    const endTime = std.time.microTimestamp();
    const timePassed = endTime - startTime;
    const operationCount = dataLength;
    const operationsPerMS = @divFloor(operationCount * 1000, timePassed);
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
    vectorTry(dataLength);
}

fn vectorTry(comptime dataLength: usize) void {
    const rand = std.crypto.random;
    const vectorLength = 8;
    const arrayLength: usize = @divExact(dataLength, vectorLength);
    var data: [arrayLength]@Vector(vectorLength, u32) = undefined;
    for (0..arrayLength) |i| {
        data[i] = @splat(0);
        for (0..vectorLength) |j| {
            data[i][j] = rand.int(u8);
        }
    }
    const startTime = std.time.microTimestamp();
    var resultVector: @Vector(vectorLength, u32) = @splat(0);
    for (0..arrayLength) |i| {
        resultVector += data[i];
    }
    const endTime = std.time.microTimestamp();
    var result: u32 = 0;
    for (0..vectorLength) |i| {
        result += resultVector[i];
    }
    const timePassed = endTime - startTime;
    const operationCount: i64 = dataLength;
    const operationsPerMS = @divFloor(operationCount * 1000, timePassed);
    std.debug.print("\nVectors:\n", .{});
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
}
