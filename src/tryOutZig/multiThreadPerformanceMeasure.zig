const std = @import("std");
pub fn main() !void {
    std.debug.print("start multi thread!\n", .{});
    const dataLength = 4_000_000;
    var data: [dataLength]u32 = undefined;
    const rand = std.crypto.random;
    for (&data) |*entry| {
        entry.* = rand.int(u4);
    }
    const threadCount = 2;
    const stepSize = @divExact(dataLength, threadCount);
    var threads: [threadCount]std.Thread = undefined;
    var results: [threadCount]u32 = undefined;
    const startTime = std.time.microTimestamp();
    for (0..threadCount - 1) |i| {
        results[i] = 0;
        threads[i] = std.Thread.spawn(.{}, addStuff, .{ &data, i, stepSize, &results[i] }) catch unreachable;
    }
    results[threadCount - 1] = 0;
    addStuff(&data, threadCount - 1, stepSize, &results[threadCount - 1]);
    for (0..threadCount - 1) |i| {
        threads[i].join();
    }

    var result: u32 = 0;
    for (0..threadCount) |i| {
        result += results[i];
    }
    const endTime = std.time.microTimestamp();
    const timePassed = endTime - startTime;
    const operationCount = dataLength;
    const operationsPerMS = @divFloor(operationCount * 1000, timePassed);
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
}

fn addStuff(data: []u32, index: usize, stepSize: u32, result: *u32) void {
    const start = stepSize * index;
    const end = start + stepSize;
    const loops = 100;
    for (0..loops) |_| {
        for (start..end) |i| {
            result.* += data[i];
        }
    }
}
