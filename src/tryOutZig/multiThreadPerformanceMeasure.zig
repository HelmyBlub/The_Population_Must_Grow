const std = @import("std");
pub fn main() !void {
    // multi thread performance notes:
    // - with debug build -> multi core is worse than single threaded
    //      -> use ReleaseFast for performance measures
    //   ~182_000_000 operations per second (1 Thread, debug build)
    //   ~144_000_000 operations per second (2 Thread, debug build)
    //   ~650_000_000 operations per second (1 Thread, releaseFast build)
    // ~1_200_000_000 operations per second (2 Thread, releaseFast build)
    std.debug.print("start multi thread!\n", .{});
    const dataLength = 2_000_000;
    const loops = 1000;
    var data: [dataLength]f32 = undefined;
    const rand = std.crypto.random;
    for (&data) |*entry| {
        entry.* = rand.float(f32);
    }
    const threadCount = 2;
    const stepSize = @divExact(dataLength, threadCount);
    var threads: [threadCount]std.Thread = undefined;
    var results: [threadCount]f32 = undefined;
    const startTime = std.time.microTimestamp();
    for (0..threadCount - 1) |i| {
        results[i] = 0;
        threads[i] = try std.Thread.spawn(.{}, addStuff, .{ &data, i, stepSize, &results[i], loops });
    }
    results[threadCount - 1] = 0;
    addStuff(&data, threadCount - 1, stepSize, &results[threadCount - 1], loops);
    for (0..threadCount - 1) |i| {
        threads[i].join();
    }

    var result: f32 = 0;
    for (0..threadCount) |i| {
        result += results[i];
    }
    const endTime = std.time.microTimestamp();
    const timePassed = endTime - startTime;
    const operationCount = dataLength * loops;
    const operationsPerMS = @divFloor(operationCount * 1000, timePassed);
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
}

fn addStuff(data: []f32, index: usize, stepSize: u32, result: *f32, loops: u16) void {
    const start = stepSize * index;
    const end = start + stepSize;
    // std.debug.print("from: {d} to {d}\n", .{ start, end });
    // const startTime = std.time.microTimestamp();
    for (0..loops) |_| {
        for (start..end) |i| {
            result.* += data[i];
        }
    }
    // const timePassed = std.time.microTimestamp() - startTime;
    std.debug.print("finished: {d}, time: \n", .{index});
}
