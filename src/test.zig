const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const codePerformanceZig = @import("codePerformance.zig");
const windowSdlZig = @import("windowSdl.zig");
const chunkAreaZig = @import("chunkArea.zig");

const TestActionType = enum {
    buildPath,
    buildHouse,
    buildTreeArea,
    buildHouseArea,
    buildPotatoFarmArea,
    demolish,
    copyPaste,
    changeGameSpeed,
    spawnFinishedHouseWithCitizen,
    endGame,
    restart,
};

const TestActionData = union(TestActionType) {
    buildPath: main.Position,
    buildHouse: main.Position,
    buildTreeArea: mapZig.MapTileRectangle,
    buildHouseArea: mapZig.MapTileRectangle,
    buildPotatoFarmArea: mapZig.MapTileRectangle,
    demolish: mapZig.MapTileRectangle,
    copyPaste: CopyPasteData,
    changeGameSpeed: f32,
    spawnFinishedHouseWithCitizen: main.Position,
    endGame,
    restart,
};

const CopyPasteData = struct {
    from: mapZig.TileXY,
    to: mapZig.TileXY,
    columns: u32,
    rows: u32,
};

const TestInput = struct {
    data: TestActionData,
    executeTime: u32,
};

pub const TestData = struct {
    currenTestInputIndex: usize = 0,
    testInputs: std.ArrayList(TestInput) = undefined,
    fpsLimiter: bool = true,
    testStartTimeMircoSeconds: i64,
    forceSingleCore: bool = false,
    skipSaveAndLoad: bool = true,
};

pub fn executePerfromanceTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var state: main.GameState = undefined;
    try main.createGameState(allocator, &state, 0, true);
    defer main.destroyGameState(&state);
    state.testData = createTestData(state.allocator);
    const testData = &state.testData.?;
    state.desiredGameSpeed = 1;
    try setupTestInputs(testData);

    try main.mainLoop(&state);
}

pub fn createTestData(allocator: std.mem.Allocator) TestData {
    return .{
        .testStartTimeMircoSeconds = std.time.microTimestamp(),
        .fpsLimiter = false,
        .testInputs = std.ArrayList(TestInput).init(allocator),
    };
}

pub fn tick(state: *main.GameState) !void {
    if (state.testData) |*testData| {
        while (testData.currenTestInputIndex < testData.testInputs.items.len) {
            const currentInput = testData.testInputs.items[testData.currenTestInputIndex];
            if (currentInput.executeTime <= state.gameTimeMs) {
                switch (currentInput.data) {
                    .buildPath => |data| {
                        _ = try mapZig.placePath(mapZig.mapPositionToTileMiddlePosition(data), state);
                    },
                    .buildHouse => |data| {
                        _ = try mapZig.placeHouse(mapZig.mapPositionToTileMiddlePosition(data), state, true, true, 0);
                    },
                    .buildTreeArea => |data| {
                        state.currentBuildType = mapZig.BUILD_TYPE_TREE_FARM;
                        try windowSdlZig.handleRectangleAreaAction(data, state);
                    },
                    .buildHouseArea => |data| {
                        state.currentBuildType = mapZig.BUILD_TYPE_HOUSE;
                        try windowSdlZig.handleRectangleAreaAction(data, state);
                    },
                    .buildPotatoFarmArea => |data| {
                        state.currentBuildType = mapZig.BUILD_TYPE_POTATO_FARM;
                        try windowSdlZig.handleRectangleAreaAction(data, state);
                    },
                    .demolish => |data| {
                        state.currentBuildType = mapZig.BUILD_TYPE_DEMOLISH;
                        try windowSdlZig.handleRectangleAreaAction(data, state);
                    },
                    .copyPaste => |data| {
                        try mapZig.copyFromTo(data.from, data.to, data.columns, data.rows, state);
                    },
                    .changeGameSpeed => |data| {
                        main.setGameSpeed(data, state);
                    },
                    .spawnFinishedHouseWithCitizen => |data| {
                        _ = try mapZig.placeHouse(mapZig.mapPositionToTileMiddlePosition(data), state, false, true, 0);
                        if (try mapZig.getBuildingOnPosition(data, 0, state)) |building| {
                            try mapZig.finishBuilding(building, 0, state);
                        }
                    },
                    .endGame => {
                        printTestEndData(state);
                        state.gameEnd = true;
                    },
                    .restart => {
                        //not a real restart yet
                        const spawnChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(.{ .chunkX = 0, .chunkY = 0 }, 0, false, state);
                        const spawnCitizen = &spawnChunk.citizens.items[0];
                        spawnCitizen.position.x = 0;
                        spawnCitizen.position.y = 0;
                        spawnCitizen.foodLevel = 1;
                        state.gameTimeMs = 0;
                    },
                }
                testData.currenTestInputIndex += 1;
            } else {
                break;
            }
        }
    }
}

pub fn determineValidanChunkDistanceForArea(chunkXyArray: [chunkAreaZig.ChunkArea.SIZE * chunkAreaZig.ChunkArea.SIZE]mapZig.ChunkXY) void {
    const minDistance = 9;
    const areaSize = chunkAreaZig.ChunkArea.SIZE;
    var validationChunkDistance: usize = areaSize * areaSize;
    for (0..chunkXyArray.len) |index1| {
        const chunkXY1 = chunkXyArray[index1];
        for (index1..chunkXyArray.len) |index2| {
            const chunkXY2 = chunkXyArray[index2];
            var isTooClose = false;
            if (@abs(chunkXY1.chunkX + areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY + areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX - areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY + areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX + areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY - areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX - areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY - areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX - areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX + areaSize - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY - areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            } else if (@abs(chunkXY1.chunkX - chunkXY2.chunkX) < minDistance and @abs(chunkXY1.chunkY + areaSize - chunkXY2.chunkY) < minDistance) {
                isTooClose = true;
            }
            if (isTooClose) {
                const distance = index2 - index1;
                if (distance < validationChunkDistance) {
                    // std.debug.print("found lower distance {}, {}, {} <-> {}, distance: {}\n", .{ index1, index2, chunkXY1, chunkXY2, distance });
                    validationChunkDistance = distance;
                }
            }
        }
    }
    std.debug.print("lowest validationChunkDistance: {}", .{validationChunkDistance});
}

fn printTestEndData(state: *main.GameState) void {
    const timePassed = std.time.microTimestamp() - state.testData.?.testStartTimeMircoSeconds;
    const fps = @divFloor(@as(i64, @intCast(state.framesTotalCounter)) * 1_000_000, timePassed);
    codePerformanceZig.printToConsole(state);
    for (0..state.maxThreadCount) |i| {
        std.debug.print("list {}: {d}\n", .{ i, state.threadData[i].chunkAreaKeys.items.len });
        // for (state.threadData[i].chunkAreas.items) |chunkArea| {
        //     std.debug.print("   {} \n", .{chunkArea.areaXY});
        // std.debug.print("{}: {any}\n", .{ chunkArea.areaXY, chunkArea. });
        // }
    }

    std.debug.print("FPS: {d}, citizens: {d}, gameTime: {d}, end FPS: {d}\n", .{ fps, state.citizenCounter, state.gameTimeMs, state.fpsCounter });
}

fn setupTestInputs(testData: *TestData) !void {
    try testData.testInputs.append(.{ .data = .{ .changeGameSpeed = 10 }, .executeTime = 0 });
    try testData.testInputs.append(.{ .data = .{ .demolish = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = 0 }, .columnCount = 2, .rowCount = 1 } }, .executeTime = 0 });
    //city block
    for (0..10) |counter| {
        const x: i32 = @intCast(counter);
        try testData.testInputs.append(.{ .data = .{ .buildPath = tileToPos(x, 1) }, .executeTime = 0 });
        try testData.testInputs.append(.{ .data = .{ .buildHouse = tileToPos(x, 0) }, .executeTime = 0 });
    }
    for (0..13) |counter| {
        const y: i32 = @as(i32, @intCast(counter)) - 2;
        try testData.testInputs.append(.{ .data = .{ .buildPath = tileToPos(10, y) }, .executeTime = 0 });
    }
    try testData.testInputs.append(.{ .data = .{ .buildTreeArea = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = -2 }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 30_000 });
    try testData.testInputs.append(.{ .data = .{ .buildPotatoFarmArea = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = -1 }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 30_000 });
    try testData.testInputs.append(.{ .data = .{ .buildHouseArea = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = 2 }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 0 });
    try testData.testInputs.append(.{ .data = .{ .copyPaste = .{ .from = .{ .tileX = 0, .tileY = 0 }, .to = .{ .tileX = 0, .tileY = 3 }, .columns = 10, .rows = 3 } }, .executeTime = 20_000 });
    try testData.testInputs.append(.{ .data = .{ .copyPaste = .{ .from = .{ .tileX = 0, .tileY = 0 }, .to = .{ .tileX = 0, .tileY = 6 }, .columns = 10, .rows = 3 } }, .executeTime = 20_000 });
    try testData.testInputs.append(.{ .data = .{ .buildTreeArea = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = 10 }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 60_000 });
    try testData.testInputs.append(.{ .data = .{ .buildPotatoFarmArea = .{ .topLeftTileXY = .{ .tileX = 0, .tileY = 9 }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 60_000 });

    //copy paste entire city block
    for (1..18) |distance| {
        for (0..(distance * 2)) |pos| {
            const executeTime: u32 = @intCast(60_000 + distance * 10_000 + pos * 100);
            const toOffset1: i32 = -@as(i32, @intCast(distance)) + @as(i32, @intCast(pos));
            var toOffset2: i32 = -@as(i32, @intCast(distance));
            //left
            try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                .from = .{ .tileX = 0, .tileY = -2 },
                .to = .{ .tileX = toOffset2 * 11, .tileY = toOffset1 * 13 - 2 },
                .columns = 11,
                .rows = 13,
            } }, .executeTime = executeTime });
            // top
            try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                .from = .{ .tileX = 0, .tileY = -2 },
                .to = .{ .tileX = (toOffset1 + 1) * 11, .tileY = toOffset2 * 13 - 2 },
                .columns = 11,
                .rows = 13,
            } }, .executeTime = executeTime });
            //right
            toOffset2 = -toOffset2;
            try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                .from = .{ .tileX = 0, .tileY = -2 },
                .to = .{ .tileX = toOffset2 * 11, .tileY = (toOffset1 + 1) * 13 - 2 },
                .columns = 11,
                .rows = 13,
            } }, .executeTime = executeTime });
            //bottom
            try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                .from = .{ .tileX = 0, .tileY = -2 },
                .to = .{ .tileX = toOffset1 * 11, .tileY = toOffset2 * 13 - 2 },
                .columns = 11,
                .rows = 13,
            } }, .executeTime = executeTime });
        }
    }
    try testData.testInputs.append(.{ .data = .{ .changeGameSpeed = 2 }, .executeTime = 250_000 });
    try testData.testInputs.append(.{ .data = .endGame, .executeTime = 330_000 });
}

pub fn setupTestInputsXAreas(testData: *TestData) !void {
    try testData.testInputs.append(.{ .data = .restart, .executeTime = 0 });
    // try testData.testInputs.append(.{ .data = .{ .changeGameSpeed = 10 }, .executeTime = 0 });
    const centerTileXYs = [_]mapZig.TileXY{
        .{ .tileX = 0, .tileY = 0 },
        // .{ .tileX = 1000, .tileY = 0 },
    };
    for (centerTileXYs, 0..) |tileXY, index| {
        if (index == 0) continue;
        try testData.testInputs.append(.{ .data = .{ .spawnFinishedHouseWithCitizen = tileToPos(tileXY.tileX, tileXY.tileY) }, .executeTime = 0 });
    }
    //city block
    for (centerTileXYs) |tileXY| {
        for (0..10) |counter| {
            const x: i32 = @intCast(counter);
            try testData.testInputs.append(.{ .data = .{ .buildPath = tileToPos(x + tileXY.tileX, 1 + tileXY.tileY) }, .executeTime = 0 });
            try testData.testInputs.append(.{ .data = .{ .buildHouse = tileToPos(x + tileXY.tileX, 0 + tileXY.tileY) }, .executeTime = 0 });
        }
        for (0..13) |counter| {
            const y: i32 = @as(i32, @intCast(counter)) - 2;
            try testData.testInputs.append(.{ .data = .{ .buildPath = tileToPos(10 + tileXY.tileX, y + tileXY.tileY) }, .executeTime = 0 });
        }
    }
    for (centerTileXYs) |tileXY| {
        try testData.testInputs.append(.{ .data = .{ .buildTreeArea = .{ .topLeftTileXY = .{ .tileX = 0 + tileXY.tileX, .tileY = -2 + tileXY.tileY }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 30_000 });
        try testData.testInputs.append(.{ .data = .{ .buildPotatoFarmArea = .{ .topLeftTileXY = .{ .tileX = 0 + tileXY.tileX, .tileY = -1 + tileXY.tileY }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 30_000 });
        try testData.testInputs.append(.{ .data = .{ .buildHouseArea = .{ .topLeftTileXY = .{ .tileX = 0 + tileXY.tileX, .tileY = 2 + tileXY.tileY }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 30_000 });
        try testData.testInputs.append(.{ .data = .{ .copyPaste = .{ .from = .{ .tileX = 0 + tileXY.tileX, .tileY = 0 + tileXY.tileY }, .to = .{ .tileX = 0 + tileXY.tileX, .tileY = 3 + tileXY.tileY }, .columns = 10, .rows = 3 } }, .executeTime = 30_000 });
        try testData.testInputs.append(.{ .data = .{ .copyPaste = .{ .from = .{ .tileX = 0 + tileXY.tileX, .tileY = 0 + tileXY.tileY }, .to = .{ .tileX = 0 + tileXY.tileX, .tileY = 6 + tileXY.tileY }, .columns = 10, .rows = 3 } }, .executeTime = 30_000 });
    }
    for (centerTileXYs) |tileXY| {
        try testData.testInputs.append(.{ .data = .{ .buildTreeArea = .{ .topLeftTileXY = .{ .tileX = 0 + tileXY.tileX, .tileY = 10 + tileXY.tileY }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 60_000 });
        try testData.testInputs.append(.{ .data = .{ .buildPotatoFarmArea = .{ .topLeftTileXY = .{ .tileX = 0 + tileXY.tileX, .tileY = 9 + tileXY.tileY }, .columnCount = 10, .rowCount = 1 } }, .executeTime = 60_000 });
    }

    //copy paste entire city block
    for (1..10) |distance| {
        for (centerTileXYs) |tileXY| {
            for (0..(distance * 2)) |pos| {
                const executeTime: u32 = @intCast(60_000 + distance * 10_000 + pos * 100);
                const toOffset1: i32 = -@as(i32, @intCast(distance)) + @as(i32, @intCast(pos));
                var toOffset2: i32 = -@as(i32, @intCast(distance));
                //left
                try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                    .from = .{ .tileX = 0, .tileY = -2 },
                    .to = .{ .tileX = toOffset2 * 11 + tileXY.tileX, .tileY = toOffset1 * 13 - 2 + tileXY.tileY },
                    .columns = 11,
                    .rows = 13,
                } }, .executeTime = executeTime });
                // top
                try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                    .from = .{ .tileX = 0, .tileY = -2 },
                    .to = .{ .tileX = (toOffset1 + 1) * 11 + tileXY.tileX, .tileY = toOffset2 * 13 - 2 + tileXY.tileY },
                    .columns = 11,
                    .rows = 13,
                } }, .executeTime = executeTime });
                //right
                toOffset2 = -toOffset2;
                try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                    .from = .{ .tileX = 0, .tileY = -2 },
                    .to = .{ .tileX = toOffset2 * 11 + tileXY.tileX, .tileY = (toOffset1 + 1) * 13 - 2 + tileXY.tileY },
                    .columns = 11,
                    .rows = 13,
                } }, .executeTime = executeTime });
                //bottom
                try testData.testInputs.append(.{ .data = .{ .copyPaste = .{
                    .from = .{ .tileX = 0, .tileY = -2 },
                    .to = .{ .tileX = toOffset1 * 11 + tileXY.tileX, .tileY = toOffset2 * 13 - 2 + tileXY.tileY },
                    .columns = 11,
                    .rows = 13,
                } }, .executeTime = executeTime });
            }
        }
    }
    // try testData.testInputs.append(.{ .data = .{ .changeGameSpeed = 2 }, .executeTime = 250_000 });
    // try testData.testInputs.append(.{ .data = .endGame, .executeTime = 300_000 });
}

fn tileToPos(tileX: i32, tileY: i32) main.Position {
    return mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = tileX, .tileY = tileY });
}
