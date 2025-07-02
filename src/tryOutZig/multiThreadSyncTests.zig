const std = @import("std");

// what i learned
// - be carefull: some values can be in same cache line used by multiple threads. Assume cache size of 64 byte
//      - reduces perfromance by a lot (~80%). When values not in same cache line performance improves a lot.
//          -  using padded values increased performance by alot, instead of values in an array being directly besides each other ending up in the same cache line
// - for best performance different cpu should access the same data as few times as possible.
//     - And when accessing them, try doing all code close ot each other and not spread out
//          -  "result2 += rand.float(f32);" moving this calculation around in my code changed measurments by huge amounts (~25%)

const COUNT_TO = 2_000_000;

pub fn main() !void {
    testSingleThreadAdding();
    // try testMultiThread();
    // try testMultiThread_2();
    // try testMultiThreadEveryThreadForHimself();
    try testMultiThreadEveryThreadForHimselfPaddedCounter();
    try testMultiThreadSynchroniedNotAtomic();
    // try testMultiThreadEveryThreadForHimselfNoArray();
    // try testMultiThread2Counters();
    try testMultiThreadSynchronized();
    // try testMultiThread4();
}

fn testSingleThreadAdding() void {
    const rand = std.crypto.random;
    const startTime = std.time.nanoTimestamp();
    var result2: f64 = 0;
    for (0..COUNT_TO) |_| {
        result2 += rand.float(f32);
    }
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - Single thread counting\n", .{@divFloor(diff, 1_000_000)});
}

fn testMultiThread() !void {
    var counter = std.atomic.Value(usize).init(0);
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadThreadTick, .{ &counter, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadThreadTick, .{ &counter, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2-Threads counting one together {}\n", .{ @divFloor(diff, 1_000_000), counter.load(.seq_cst) });
}

fn testMultiThreadThreadTick(counter: *std.atomic.Value(usize), threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    const threadCount = 2;
    while (counter.load(.seq_cst) < countTo) {
        if (counter.load(.seq_cst) % threadCount == threadIndex) {
            counter.store(counter.load(.seq_cst) + 1, .seq_cst);
            result2 += rand.float(f32);
        }
    }
}

fn testMultiThread_2() !void {
    var counter = std.atomic.Value(usize).init(0);
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadThreadTick_2, .{ &counter, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadThreadTick_2, .{ &counter, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2-Threads counting one together 2 {}\n", .{ @divFloor(diff, 1_000_000), counter.load(.seq_cst) });
}

fn testMultiThreadThreadTick_2(counter: *std.atomic.Value(usize), threadIndex: usize) void {
    var result1: f64 = 0;
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    const threadCount = 2;
    while (counter.load(.seq_cst) < countTo) {
        if (counter.load(.seq_cst) % threadCount == threadIndex) {
            counter.store(counter.load(.seq_cst) + 1, .seq_cst);
            result1 += rand.float(f32);
            result2 += rand.float(f32);
        }
    }
}

fn testMultiThread2Counters() !void {
    var counter1 = std.atomic.Value(usize).init(0);
    var counter2 = std.atomic.Value(usize).init(0);
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadThreadTick2, .{ &counter1, &counter2, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadThreadTick2, .{ &counter1, &counter2, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting two counters, second counter increased when waiting on first {} {}\n", .{ @divFloor(diff, 1_000_000), counter1.load(.seq_cst), counter2.load(.seq_cst) });
}

fn testMultiThreadThreadTick2(counter1: *std.atomic.Value(usize), counter2: *std.atomic.Value(usize), threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    const threadCount = 2;
    while (counter1.load(.seq_cst) < countTo) {
        if (counter1.load(.seq_cst) % threadCount == threadIndex) {
            counter1.store(counter1.load(.seq_cst) + 1, .seq_cst);
            result2 += rand.float(f32);
        } else {
            counter2.store(counter2.load(.seq_cst) + 1, .seq_cst);
            result2 += rand.float(f32);
        }
    }
}

fn testMultiThreadSynchronized() !void {
    var atomics = [_]PaddedAtomic{
        .{ .value = std.atomic.Value(usize).init(0) },
        .{ .value = std.atomic.Value(usize).init(0) },
    };
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThread3ThreadTick, .{ &atomics, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThread3ThreadTick, .{ &atomics, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting synchronized {} {}\n", .{ @divFloor(diff, 1_000_000), atomics[0].value.load(.seq_cst), atomics[1].value.load(.seq_cst) });
}

fn testMultiThread3ThreadTick(atomics: []PaddedAtomic, threadIndex: usize) !void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    const distance = 20;
    var currentIndex: usize = 0;
    while (currentIndex < countTo) {
        const other_index = 1 - threadIndex;
        currentIndex = atomics[threadIndex].value.load(.acquire);
        const other_value = atomics[other_index].value.load(.acquire);

        var allowed = false;
        if (threadIndex == 0) {
            allowed = (other_value + distance > currentIndex);
        } else {
            allowed = (other_value > currentIndex);
        }

        if (allowed) {
            result2 += rand.float(f32);
            atomics[threadIndex].value.store(currentIndex + 1, .release);
        } else {
            // try std.Thread.yield();
        }
    }
}

const PaddedAtomic = extern struct {
    value: std.atomic.Value(usize),
    padding: [64 - @sizeOf(std.atomic.Value(usize))]u8 = undefined,
};

fn testMultiThread4() !void {
    var atomics = [_]std.atomic.Value(usize){
        std.atomic.Value(usize).init(0),
        std.atomic.Value(usize).init(0),
    };
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThread4_0ThreadTick, .{ &atomics, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThread4_1ThreadTick, .{ &atomics, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads synchronized with own functions {} {}\n", .{ @divFloor(diff, 1_000_000), atomics[0].load(.seq_cst), atomics[1].load(.seq_cst) });
}

fn testMultiThread4_0ThreadTick(atomics: []std.atomic.Value(usize), threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    while (atomics[threadIndex].load(.seq_cst) < countTo) {
        if (atomics[1].load(.seq_cst) + 2 > atomics[threadIndex].load(.seq_cst)) {
            atomics[threadIndex].store(atomics[threadIndex].load(.seq_cst) + 1, .seq_cst);
            result2 += rand.float(f32);
        }
    }
}

fn testMultiThread4_1ThreadTick(atomics: []std.atomic.Value(usize), threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    while (atomics[threadIndex].load(.seq_cst) < countTo) {
        if (atomics[0].load(.seq_cst) > atomics[threadIndex].load(.seq_cst)) {
            atomics[threadIndex].store(atomics[threadIndex].load(.seq_cst) + 1, .seq_cst);
            result2 += rand.float(f32);
        }
    }
}
fn testMultiThreadEveryThreadForHimself() !void {
    var counter = [_]usize{ 0, 0 };
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselfTick, .{ &counter, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselfTick, .{ &counter, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting independently {d} {d}\n", .{ @divFloor(diff, 1_000_000), counter[0], counter[1] });
}

fn testMultiThreadEveryThreadForHimselfTick(counter: []usize, threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    while (counter[threadIndex] < countTo) {
        counter[threadIndex] += 1;
        result2 += rand.float(f32);
    }
}

fn testMultiThreadEveryThreadForHimselfNoArray() !void {
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselffNoArrayTick, .{});
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselffNoArrayTick, .{});
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting independently without array\n", .{
        @divFloor(diff, 1_000_000),
    });
}

fn testMultiThreadEveryThreadForHimselffNoArrayTick() void {
    var counter: usize = 0;
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    while (counter < countTo) {
        counter += 1;
        result2 += rand.float(f32);
    }
}

fn testMultiThreadEveryThreadForHimselfPaddedCounter() !void {
    var counter = [_]PaddedCounter{ PaddedCounter{}, PaddedCounter{} };
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselfPaddedCounterTick, .{ &counter, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadEveryThreadForHimselfPaddedCounterTick, .{ &counter, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting independently with padded counter\n", .{
        @divFloor(diff, 1_000_000),
    });
}

fn testMultiThreadEveryThreadForHimselfPaddedCounterTick(counter: []PaddedCounter, threadIndex: usize) void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    while (counter[threadIndex].value < countTo) {
        counter[threadIndex].value += 1;
        result2 += rand.float(f32);
    }
}

const PaddedCounter = extern struct {
    value: usize = 0,
    _padding: [64 - @sizeOf(usize)]u8 = [_]u8{0} ** (64 - @sizeOf(usize)),
};

fn testMultiThreadSynchroniedNotAtomic() !void {
    var counter = [_]PaddedCounter{ .{}, .{} };
    const startTime = std.time.nanoTimestamp();
    const thread1 = try std.Thread.spawn(.{}, testMultiThreadSynchroniedNotAtomicTick, .{ &counter, 0 });
    const thread2 = try std.Thread.spawn(.{}, testMultiThreadSynchroniedNotAtomicTick, .{ &counter, 1 });
    thread1.join();
    thread2.join();
    const finished = std.time.nanoTimestamp();
    const diff = finished - startTime;
    std.debug.print("{} - 2 threads counting synchronized no atomic {} {}\n", .{ @divFloor(diff, 1_000_000), counter[0].value, counter[1].value });
}

fn testMultiThreadSynchroniedNotAtomicTick(counter: []PaddedCounter, threadIndex: usize) !void {
    const rand = std.crypto.random;
    var result2: f64 = 0;
    const countTo = COUNT_TO;
    const distance = 10;
    const other_index = 1 - threadIndex;
    var other_value = counter[other_index].value;
    while (counter[threadIndex].value < countTo) {
        const my_value = counter[threadIndex].value;

        var allowed = false;
        if (threadIndex == 0) {
            allowed = (other_value + distance > my_value);
        } else {
            allowed = (other_value > my_value);
        }

        if (allowed) {
            result2 += rand.float(f32);
            counter[threadIndex].value += 1;
        } else {
            other_value = counter[other_index].value;
        }
    }
}
