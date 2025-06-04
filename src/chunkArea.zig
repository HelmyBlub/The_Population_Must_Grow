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

pub fn checkIfAreaIsActive(chunkXY: mapZig.ChunkXY, state: *main.ChatSimState) !void {
    const areaXY = getChunkAreaXyForChunkXy(chunkXY);
    for (state.threadData) |*threadData| {
        for (threadData.chunkAreas.items) |*area| {
            if (area.areaXY.areaX == areaXY.areaX and area.areaXY.areaY == areaXY.areaY) {
                return;
            }
        }
    }
    for (state.idleChunkAreas.items) |*area| {
        if (area.areaXY.areaX == areaXY.areaX and area.areaXY.areaY == areaXY.areaY) {
            area.idleTypeData = .notIdle;
            return;
        }
    }
    var threadWithLeastAreas: ?*main.ThreadData = null;
    for (state.threadData, 0..) |*threadData, index| {
        if (index >= state.usedThreadsCount) break;
        if (threadWithLeastAreas == null or threadWithLeastAreas.?.chunkAreas.items.len > threadData.chunkAreas.items.len) {
            threadWithLeastAreas = threadData;
        }
    }
    if (threadWithLeastAreas) |thread| {
        try thread.chunkAreas.append(.{
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

pub fn optimizeChunkAreaAssignments(state: *main.ChatSimState) !void {
    const visibleAndTickRectangle = mapZig.getVisibleAndAdjacentChunkRectangle(state);
    // handle idle chunkAreas
    for (state.threadData) |*threadData| {
        var currendIndex: usize = 0;
        while (currendIndex < threadData.chunkAreas.items.len) {
            const chunkArea = threadData.chunkAreas.items[currendIndex];
            if (chunkArea.idleTypeData != .notIdle and !mapZig.isChunkAreaInVisibleData(visibleAndTickRectangle, chunkArea.areaXY)) {
                const removedArea = threadData.chunkAreas.swapRemove(currendIndex);
                try state.idleChunkAreas.append(removedArea);
            } else {
                currendIndex += 1;
            }
        }
    }
    // move active chunkAreas out of idle
    {
        var currendIndex: usize = 0;
        while (currendIndex < state.idleChunkAreas.items.len) {
            const chunkArea = &state.idleChunkAreas.items[currendIndex];
            var idleTypeWakeUp = false;
            if (chunkArea.idleTypeData != .idle) {
                if (chunkArea.idleTypeData != .waitingForCitizens or chunkArea.idleTypeData.waitingForCitizens < state.gameTimeMs) {
                    idleTypeWakeUp = true;
                }
            }
            if (idleTypeWakeUp or mapZig.isChunkAreaInVisibleData(visibleAndTickRectangle, chunkArea.areaXY)) {
                const removedArea = state.idleChunkAreas.swapRemove(currendIndex);
                var threadWithLeastAreas: ?*main.ThreadData = null;
                for (state.threadData, 0..) |*threadData, index| {
                    if (index >= state.usedThreadsCount) break;
                    if (threadWithLeastAreas == null or threadWithLeastAreas.?.chunkAreas.items.len > threadData.chunkAreas.items.len) {
                        threadWithLeastAreas = threadData;
                    }
                }
                try threadWithLeastAreas.?.chunkAreas.append(removedArea);
            } else {
                currendIndex += 1;
            }
        }
    }
    if (state.usedThreadsCount > 1) {
        // check balance
        var highestAmountOfWorkThread: ?*main.ThreadData = null;
        var highestAmountOfWork: usize = 0;
        var lowestAmountOfWorkThread: ?*main.ThreadData = null;
        var lowestAmountOfWork: usize = 0;
        for (state.threadData) |*threadData| {
            if (threadData.chunkAreas.items.len < 2) continue;
            const tempAmountOfWork = threadData.tickedCitizenCounter + threadData.chunkAreas.items.len * ChunkArea.SIZE * ChunkArea.SIZE;
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
            for (lowestAmountOfWorkThread.?.chunkAreas.items, 0..) |chunkAreaLower, indexLower| {
                const lowerThreadAreaWorkAmount = chunkAreaLower.tickedCitizenCounter + chunkAreaLower.chunkKeyOrder.len;
                for (highestAmountOfWorkThread.?.chunkAreas.items, 0..) |chunkAreaHigher, indexHigher| {
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
                const removedLowerArea = lowestAmountOfWorkThread.?.chunkAreas.swapRemove(closestMatchAreaLowerIndex);
                const removedHigherArea = highestAmountOfWorkThread.?.chunkAreas.swapRemove(closestMatchAreaHigherIndex);

                try lowestAmountOfWorkThread.?.chunkAreas.append(removedHigherArea);
                try highestAmountOfWorkThread.?.chunkAreas.append(removedLowerArea);
            }
        }
    }
}
