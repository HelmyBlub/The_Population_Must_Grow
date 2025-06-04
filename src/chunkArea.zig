const std = @import("std");
const main = @import("main.zig");
const testZig = @import("test.zig");
const mapZig = @import("map.zig");

pub const ChunkAreaXY: type = struct {
    areaX: i32,
    areaY: i32,
};

pub const ChunkAreaIdleType = enum {
    waitingForCitizens,
    idle,
    notIdle,
};

pub const ChunkAreaIdleTypeData = union(ChunkAreaIdleType) {
    waitingForCitizens: u32,
    idle,
    notIdle,
};

pub const ChunkArea: type = struct {
    areaXY: ChunkAreaXY,
    currentChunkKeyIndex: usize,
    chunkKeyOrder: [SIZE * SIZE]u64,
    tickedCitizenCounter: usize = 0,
    idleTypeData: ChunkAreaIdleTypeData = .notIdle,
    pub const SIZE = 20;
};

test "temp split active chunks" {
    const areaSize = ChunkArea.SIZE;
    const length = areaSize * areaSize;
    var area: [length]u64 = undefined;
    for (0..area.len) |index| {
        const currentKey: u64 = mapZig.getKeyForChunkXY(.{
            .chunkX = @intCast(@mod(index, areaSize)),
            .chunkY = @intCast(@divFloor(index, areaSize)),
        });
        const position = getNewActiveChunkKeyPosition(currentKey);
        area[position] = currentKey;
    }
    // std.debug.print("array: {any}\n", .{area});
    testZig.determineValidanChunkDistanceForArea(area);
}

pub fn getChunkAreaXyForChunkXy(chunkXY: mapZig.ChunkXY) ChunkAreaXY {
    return .{
        .areaX = @divFloor(chunkXY.chunkX, ChunkArea.SIZE),
        .areaY = @divFloor(chunkXY.chunkY, ChunkArea.SIZE),
    };
}

pub fn getKeyForAreaXY(areaXY: ChunkAreaXY) u32 {
    return @intCast(areaXY.areaX * mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS + areaXY.areaY + mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS * mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS);
}

pub fn getAreaXyForKey(chunkKey: u64) ChunkAreaXY {
    var tempAreaXY: ChunkAreaXY = .{
        .areaX = @divFloor(@as(i32, @intCast(chunkKey)) - mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS * mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS, mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS),
        .areaY = @mod(@as(i32, @intCast(chunkKey)) - mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS * mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS, mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS),
    };

    if (tempAreaXY.areaY > mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS / 2) {
        tempAreaXY.areaY -= mapZig.GameMap.MAX_CHUNKS_ROWS_COLUMNS;
        tempAreaXY.areaX += 1;
    }
    return tempAreaXY;
}

pub fn checkIfAreaIsActive(chunkXY: mapZig.ChunkXY, state: *main.ChatSimState) !void {
    const areaXY = getChunkAreaXyForChunkXy(chunkXY);
    const areaKey = getKeyForAreaXY(areaXY);
    if (state.chunkAreas.getPtr(areaKey)) |area| {
        if (area.idleTypeData != .notIdle) {
            try assignChunkAreaBackToThread(area, areaKey, state);
        }
        return;
    }
    var threadWithLeastAreas: ?*main.ThreadData = null;
    for (state.threadData, 0..) |*threadData, index| {
        if (index >= state.usedThreadsCount) break;
        if (threadWithLeastAreas == null or threadWithLeastAreas.?.chunkAreaKeys.items.len > threadData.chunkAreaKeys.items.len) {
            threadWithLeastAreas = threadData;
        }
    }
    if (threadWithLeastAreas) |thread| {
        try thread.chunkAreaKeys.append(areaKey);
        try state.chunkAreas.put(areaKey, .{
            .areaXY = areaXY,
            .chunkKeyOrder = setupChunkAreaKeyOrder(areaXY),
            .currentChunkKeyIndex = 0,
        });
        return;
    }

    std.debug.print("problem?: chunk area not handles\n", .{});
}

fn setupChunkAreaKeyOrder(areaXY: ChunkAreaXY) [ChunkArea.SIZE * ChunkArea.SIZE]u64 {
    var result: [ChunkArea.SIZE * ChunkArea.SIZE]u64 = undefined;
    for (0..ChunkArea.SIZE) |indexX| {
        for (0..ChunkArea.SIZE) |indexY| {
            const chunkXY: mapZig.ChunkXY = .{
                .chunkX = areaXY.areaX * ChunkArea.SIZE + @as(i32, @intCast(indexX)),
                .chunkY = areaXY.areaY * ChunkArea.SIZE + @as(i32, @intCast(indexY)),
            };
            const key = mapZig.getKeyForChunkXY(chunkXY);
            const index = getNewActiveChunkKeyPosition(key);
            result[index] = key;
        }
    }
    return result;
}

fn getNewActiveChunkKeyPosition(newActiveChunkKey: u64) usize {
    const chunkXY = mapZig.getChunkXyForKey(newActiveChunkKey);
    const areaSize = ChunkArea.SIZE;
    const halved = areaSize / 2;
    const areaXY = .{
        .x = @as(u32, @intCast(@mod(chunkXY.chunkX, areaSize))),
        .y = @as(u32, @intCast(@mod(chunkXY.chunkY, areaSize))),
    };

    var result: usize = 0;
    if (areaXY.x < halved and areaXY.y < halved) {
        result = @intCast(areaXY.x + areaXY.y * halved);
    } else if (areaXY.x < halved and areaXY.y >= halved) {
        const diagNumber = diagonalNumbering(areaXY.x, areaXY.y - halved);
        result = halved * halved + diagNumber;
    } else if (areaXY.x >= halved and areaXY.y >= halved) {
        const diagNumber = diagonalNumbering(areaSize - 1 - areaXY.y, areaXY.x - halved);
        result = halved * halved * 2 + diagNumber;
    } else {
        const diagNumber = diagonalNumbering(areaSize - 1 - areaXY.x, halved - 1 - areaXY.y);
        result = halved * halved * 3 + diagNumber;
    }
    return result;
}

fn diagonalNumbering(x: u32, y: u32) usize {
    const areaSize = ChunkArea.SIZE;
    const halved = areaSize / 2;
    if (x >= halved or y >= halved) {
        std.debug.print("xy to big {} {}\n", .{ x, y });
    }
    const sum = x + y;
    if (sum <= halved) {
        const added = @divExact(sum * (sum + 1), 2);
        if (!(x == halved - 1 and y == 1)) return added + x;
        return added;
    }
    const firstPart = @divExact(halved * (halved + 1), 2);
    const rest = sum - halved - 1;
    return @intCast(firstPart + @divExact(rest * (rest + 1), 2) + (halved - 1 - rest) * (rest + 1) + (halved - x - 1));
}

pub fn assignChunkAreaBackToThread(chunkArea: *ChunkArea, areaKey: u64, state: *main.ChatSimState) !void {
    chunkArea.idleTypeData = .notIdle;
    var threadWithLeastAreas: ?*main.ThreadData = null;
    for (state.threadData, 0..) |*threadData, index| {
        if (index >= state.usedThreadsCount) break;
        for (threadData.chunkAreaKeys.items) |key| {
            if (key == areaKey) return;
        }
        if (threadWithLeastAreas == null or threadWithLeastAreas.?.chunkAreaKeys.items.len > threadData.chunkAreaKeys.items.len) {
            threadWithLeastAreas = threadData;
        }
    }
    try threadWithLeastAreas.?.chunkAreaKeys.append(areaKey);
}

pub fn optimizeChunkAreaAssignments(state: *main.ChatSimState) !void {
    if (state.usedThreadsCount > 1) {
        // check balance
        var highestAmountOfWorkThread: ?*main.ThreadData = null;
        var highestAmountOfWork: usize = 0;
        var lowestAmountOfWorkThread: ?*main.ThreadData = null;
        var lowestAmountOfWork: usize = 0;
        for (state.threadData) |*threadData| {
            if (threadData.chunkAreaKeys.items.len < 2) continue;
            const tempAmountOfWork = threadData.tickedCitizenCounter + threadData.chunkAreaKeys.items.len * ChunkArea.SIZE * ChunkArea.SIZE;
            if (highestAmountOfWorkThread == null or highestAmountOfWork < tempAmountOfWork) {
                highestAmountOfWorkThread = threadData;
                highestAmountOfWork = tempAmountOfWork;
            }
            if (lowestAmountOfWorkThread == null or lowestAmountOfWork > tempAmountOfWork) {
                lowestAmountOfWorkThread = threadData;
                lowestAmountOfWork = tempAmountOfWork;
            }
        }
        if (highestAmountOfWork - lowestAmountOfWork > @divFloor(highestAmountOfWork, 2)) {
            const bestSwapWorkAmount = @divFloor(highestAmountOfWork - lowestAmountOfWork, 2);
            var closestMatchAreaLowerIndex: usize = 0;
            var closestMatchAreaHigherIndex: usize = 0;
            var closestMatchWorkAmountDiffToBest: usize = bestSwapWorkAmount;
            var closestMatchWorkAmountChange: usize = 0;
            for (lowestAmountOfWorkThread.?.chunkAreaKeys.items, 0..) |chunkAreaLowerKey, indexLower| {
                const chunkAreaLower = state.chunkAreas.getPtr(chunkAreaLowerKey).?;
                const lowerThreadAreaWorkAmount = chunkAreaLower.tickedCitizenCounter + chunkAreaLower.chunkKeyOrder.len;
                for (highestAmountOfWorkThread.?.chunkAreaKeys.items, 0..) |chunkAreaHigherKey, indexHigher| {
                    const chunkAreaHigher = state.chunkAreas.getPtr(chunkAreaHigherKey).?;
                    const higherThreadAreaWorkAmount = chunkAreaHigher.tickedCitizenCounter + chunkAreaHigher.chunkKeyOrder.len;
                    if (lowerThreadAreaWorkAmount < higherThreadAreaWorkAmount) {
                        const diff: usize = @abs(@as(i32, @intCast(higherThreadAreaWorkAmount - lowerThreadAreaWorkAmount)) - @as(i32, @intCast(bestSwapWorkAmount)));
                        if (diff < closestMatchWorkAmountDiffToBest) {
                            closestMatchWorkAmountDiffToBest = diff;
                            closestMatchWorkAmountChange = higherThreadAreaWorkAmount - lowerThreadAreaWorkAmount;
                            closestMatchAreaHigherIndex = indexHigher;
                            closestMatchAreaLowerIndex = indexLower;
                        }
                    }
                }
            }
            if (0 < closestMatchWorkAmountChange and closestMatchWorkAmountChange < @divFloor(bestSwapWorkAmount * 3, 2)) {
                const removedLowerArea = lowestAmountOfWorkThread.?.chunkAreaKeys.swapRemove(closestMatchAreaLowerIndex);
                const removedHigherArea = highestAmountOfWorkThread.?.chunkAreaKeys.swapRemove(closestMatchAreaHigherIndex);

                try lowestAmountOfWorkThread.?.chunkAreaKeys.append(removedHigherArea);
                try highestAmountOfWorkThread.?.chunkAreaKeys.append(removedLowerArea);
            }
        }
    }
}
