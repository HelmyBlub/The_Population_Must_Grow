const std = @import("std");
const vectorLength = 8;
pub fn main() !void {
    // multi thread and vector performance notes:
    // - with debug build -> multi core is worse than single threaded
    //      -> use ReleaseFast for performance measures
    //   ~ 180_000_000 operations per second (1 Thread, vectorSize=1, debug build)
    //   ~ 120_000_000 operations per second (2 Thread, vectorSize=1, debug build)
    //   ~ 1_000_000_000 operations per second (1 Thread, vectorSize=8, debug build)
    //   ~ 2_000_000_000 operations per second (2 Thread, vectorSize=8, debug build)
    //   ~ 2_600_000_000 operations per second (1 Thread, vectorSize=8, ReleaseFast build)
    //   ~ 4_600_000_000 operations per second (2 Thread, vectorSize=8, ReleaseFast build)
    std.debug.print("start multi thread + vector!\n", .{});
    const dataLength = 2_000_000;
    const loops = 1000;
    const arrayLength = @divExact(dataLength, vectorLength);
    var data: [arrayLength]@Vector(vectorLength, f32) = undefined;
    const rand = std.crypto.random;
    for (&data) |*entry| {
        entry.* = @splat(0);
        for (0..vectorLength) |i| {
            entry.*[i] = rand.float(f32);
        }
    }
    const threadCount = 1;
    const stepSize = @divExact(dataLength, threadCount * vectorLength);
    var threads: [threadCount]std.Thread = undefined;
    var results: [threadCount]@Vector(vectorLength, f64) = undefined;
    const startTime = std.time.microTimestamp();
    for (0..threadCount - 1) |i| {
        results[i] = @splat(0);
        threads[i] = try std.Thread.spawn(.{}, addStuff, .{ &data, i, stepSize, &results[i], loops });
    }
    results[threadCount - 1] = @splat(0);
    addStuff(&data, threadCount - 1, stepSize, &results[threadCount - 1], loops);
    for (0..threadCount - 1) |i| {
        threads[i].join();
    }

    var result: f64 = 0;
    for (0..threadCount) |i| {
        for (0..vectorLength) |j| {
            result += results[i][j];
        }
    }
    const endTime = std.time.microTimestamp();
    const timePassed = endTime - startTime;
    const operationCount = dataLength * loops;
    const operationsPerMS = @divFloor(operationCount * 1000, timePassed);
    std.debug.print("time: {d}\n", .{timePassed});
    std.debug.print("result: {d}\n", .{result});
    std.debug.print("op ms: {d}\n", .{operationsPerMS});
}

fn addStuff(data: []@Vector(vectorLength, f32), index: usize, stepSize: u32, result: *@Vector(vectorLength, f64), loops: u16) void {
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
