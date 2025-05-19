const std = @import("std");
const expect = @import("std").testing.expect;
pub const Citizen = @import("citizen.zig").Citizen;
const mapZig = @import("map.zig");
const paintVulkanZig = @import("vulkan/paintVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");
const soundMixerZig = @import("soundMixer.zig");
const inputZig = @import("input.zig");
const testZig = @import("test.zig");
const codePerformanceZig = @import("codePerformance.zig");
const imageZig = @import("image.zig");
pub const pathfindingZig = @import("pathfinding.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const ChatSimState: type = struct {
    map: mapZig.GameMap,
    currentBuildType: u8 = mapZig.BUILD_TYPE_HOUSE,
    buildMode: u8 = mapZig.BUILD_MODE_SINGLE,
    gameSpeed: f32,
    paintIntervalMs: u8,
    tickIntervalMs: u8,
    gameTimeMs: u32,
    gameEnd: bool,
    vkState: paintVulkanZig.Vk_State,
    testData: ?testZig.TestData = null,
    camera: Camera,
    allocator: std.mem.Allocator,
    rectangles: [2]?VulkanRectangle = .{ null, null },
    copyAreaRectangle: ?mapZig.MapTileRectangle = null,
    fpsCounter: f32 = 60,
    framesTotalCounter: u32 = 0,
    cpuPerCent: ?f32 = null,
    citizenCounter: u32 = 0,
    citizenCounterLastTick: u32 = 0,
    citizensPerMinuteCounter: f32 = 0,
    pathfindingData: pathfindingZig.PathfindingData,
    soundMixer: soundMixerZig.SoundMixer,
    keyboardInfo: inputZig.KeyboardInfo = .{},
    mouseInfo: MouseInfo = .{},
    random: std.Random.Xoshiro256,
    codePerformanceData: codePerformanceZig.CodePerformanceData = undefined,
    cpuCount: usize,
    activeChunksThreadSplit: []std.ArrayList(u64) = undefined,
    activeChunkSplitIndex: []usize = undefined,
    activeChunkAllowedIndex: usize = 0,
};

pub const MouseInfo = struct {
    mapDown: ?Position = null,
    currentPos: Position = .{ .x = 0, .y = 0 },
    leftButtonPressedTimeMs: ?i64 = null,
    rightButtonPressedTimeMs: ?i64 = null,
};

pub const VulkanRectangle = struct {
    pos: [2]Position,
    color: [3]f32,
};

pub const Camera: type = struct {
    position: Position,
    zoom: f32,
};

pub const Position: type = struct {
    x: f32,
    y: f32,
};

pub const CITIZEN_TREE_CUT_PART1_DURATION = 1000;
pub const CITIZEN_TREE_CUT_PART2_DURATION_TREE_FALLING = 2000;
pub const CITIZEN_TREE_CUT_PART3_DURATION = 1000;
pub const CITIZEN_TREE_CUT_DURATION = CITIZEN_TREE_CUT_PART1_DURATION + CITIZEN_TREE_CUT_PART2_DURATION_TREE_FALLING + CITIZEN_TREE_CUT_PART3_DURATION;
var SIMULATION_MICRO_SECOND_DURATION: ?i64 = null;

test "test for memory leaks" {
    const test_allocator = std.testing.allocator;
    SIMULATION_MICRO_SECOND_DURATION = 100_000;
    try startGame(test_allocator);
    // testing allocator will fail test if something is not deallocated
}

test "test measure performance" {
    SIMULATION_MICRO_SECOND_DURATION = 30_000_000;
    try testZig.executePerfromanceTest();
}

test "temp split active chunks" {
    const test_allocator = std.testing.allocator;
    var activeChunks = std.ArrayList(u64).init(test_allocator);
    defer activeChunks.deinit();
    for (0..20) |i| {
        const x: i32 = @intCast(i);
        try activeChunks.append(mapZig.getKeyForChunkXY(.{ .chunkX = x, .chunkY = 0 }));
        try activeChunks.append(mapZig.getKeyForChunkXY(.{ .chunkX = x, .chunkY = 1 }));
    }
    const cpuCount = 4;
    var chunkSplits = try test_allocator.alloc(std.ArrayList(u64), cpuCount);
    for (0..cpuCount) |i| {
        chunkSplits[i] = std.ArrayList(u64).init(test_allocator);
    }

    try splitActiveChunksForThreads(activeChunks, chunkSplits);

    for (0..cpuCount) |i| {
        std.debug.print("list {}: {any}\n", .{ i, chunkSplits[i].items });
        chunkSplits[i].deinit();
    }
    test_allocator.free(chunkSplits);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    try startGame(allocator);
}

pub fn calculateDistance(pos1: Position, pos2: Position) f32 {
    const diffX = pos1.x - pos2.x;
    const diffY = pos1.y - pos2.y;
    return @sqrt(diffX * diffX + diffY * diffY);
}

pub fn createGameState(allocator: std.mem.Allocator, state: *ChatSimState, randomSeed: ?u64) !void {
    var seed: u64 = undefined;
    if (randomSeed) |randSeed| {
        seed = randSeed;
    } else {
        seed = std.crypto.random.int(u64);
    }
    const prng = std.Random.DefaultPrng.init(seed);

    const map: mapZig.GameMap = try mapZig.createMap(allocator);
    state.* = ChatSimState{
        .map = map,
        .gameSpeed = 1,
        .paintIntervalMs = 16,
        .tickIntervalMs = 16,
        .gameTimeMs = 0,
        .gameEnd = false,
        .vkState = .{},
        .citizenCounter = 1,
        .camera = .{
            .position = .{ .x = 0, .y = 0 },
            .zoom = 1,
        },
        .allocator = allocator,
        .pathfindingData = try pathfindingZig.createPathfindingData(allocator),
        .soundMixer = undefined,
        .random = prng,
        .cpuCount = std.Thread.getCpuCount() catch 1,
    };
    state.activeChunksThreadSplit = try allocator.alloc(std.ArrayList(u64), state.cpuCount);
    state.activeChunkSplitIndex = try allocator.alloc(usize, state.cpuCount);
    for (0..state.cpuCount) |i| {
        state.activeChunksThreadSplit[i] = std.ArrayList(u64).init(allocator);
    }
    try codePerformanceZig.init(state);
    try mapZig.createSpawnChunk(allocator, state);
    try inputZig.initDefaultKeyBindings(state);
    try initPaintVulkanAndWindowSdl(state);
    state.soundMixer = try soundMixerZig.createSoundMixer(state, allocator);
    try inputZig.executeAction(inputZig.ActionType.buildPath, state);
}

pub fn setupRectangleData(state: *ChatSimState) void {
    if (state.copyAreaRectangle) |copyAreaRectangle| {
        state.rectangles[1] = .{
            .color = .{ 1, 0, 0 },
            .pos = .{
                mapZig.mapTileXyToVulkanSurfacePosition(copyAreaRectangle.topLeftTileXY, state.camera),
                mapZig.mapTileXyToVulkanSurfacePosition(
                    .{
                        .tileX = copyAreaRectangle.topLeftTileXY.tileX + @as(i32, @intCast(copyAreaRectangle.columnCount)),
                        .tileY = copyAreaRectangle.topLeftTileXY.tileY + @as(i32, @intCast(copyAreaRectangle.rowCount)),
                    },
                    state.camera,
                ),
            },
        };
    } else {
        state.rectangles[1] = null;
    }
    if (state.buildMode == mapZig.BUILD_MODE_DRAG_RECTANGLE) {
        if (state.currentBuildType == mapZig.BUILD_TYPE_COPY_PASTE and state.copyAreaRectangle != null) {
            const copyAreaRectangle = state.copyAreaRectangle.?;
            const mapTopLeft = windowSdlZig.mouseWindowPositionToGameMapPoisition(state.mouseInfo.currentPos.x, state.mouseInfo.currentPos.y, state.camera);
            const mapTopLeftMiddleTile = mapZig.mapPositionToTileMiddlePosition(mapTopLeft);
            const mapTopLeftTile: Position = .{
                .x = mapTopLeftMiddleTile.x - mapZig.GameMap.TILE_SIZE / 2,
                .y = mapTopLeftMiddleTile.y - mapZig.GameMap.TILE_SIZE / 2,
            };
            const vulkanTopleft = mapZig.mapPositionToVulkanSurfacePoisition(mapTopLeftTile.x, mapTopLeftTile.y, state.camera);
            const vulkanBottomRight: Position = mapZig.mapPositionToVulkanSurfacePoisition(
                mapTopLeftTile.x + @as(f32, @floatFromInt(copyAreaRectangle.columnCount * mapZig.GameMap.TILE_SIZE)),
                mapTopLeftTile.y + @as(f32, @floatFromInt(copyAreaRectangle.rowCount * mapZig.GameMap.TILE_SIZE)),
                state.camera,
            );
            state.rectangles[0] = .{
                .color = .{ 1, 0, 0 },
                .pos = .{ vulkanTopleft, vulkanBottomRight },
            };
        } else {
            const rectangleTileColumns: u8 = if (state.currentBuildType == mapZig.BUILD_TYPE_BIG_HOUSE) 2 else 1;
            const rectangleTileRows: u8 = if (state.currentBuildType == mapZig.BUILD_TYPE_BIG_HOUSE) 2 else 1;

            if (state.mouseInfo.mapDown != null) {
                const mapMouseDown = state.mouseInfo.mapDown.?;
                const mouseUp = state.mouseInfo.currentPos;
                const mapMouseUp = windowSdlZig.mouseWindowPositionToGameMapPoisition(mouseUp.x, mouseUp.y, state.camera);
                const mapTopLeft: Position = .{
                    .x = @min(mapMouseUp.x, mapMouseDown.x),
                    .y = @min(mapMouseUp.y, mapMouseDown.y),
                };
                const mapTopLeftMiddleTile = mapZig.mapPositionToTileMiddlePosition(mapTopLeft);
                var mapTopLeftTile: Position = .{
                    .x = mapTopLeftMiddleTile.x - mapZig.GameMap.TILE_SIZE / 2,
                    .y = mapTopLeftMiddleTile.y - mapZig.GameMap.TILE_SIZE / 2,
                };

                const bottomRight: Position = .{
                    .x = @max(mapMouseUp.x, mapMouseDown.x),
                    .y = @max(mapMouseUp.y, mapMouseDown.y),
                };
                const mapBottomRightTileMiddle = mapZig.mapPositionToTileMiddlePosition(bottomRight);
                var mapBottomRightTileBottomRight: Position = .{
                    .x = mapBottomRightTileMiddle.x + mapZig.GameMap.TILE_SIZE / 2,
                    .y = mapBottomRightTileMiddle.y + mapZig.GameMap.TILE_SIZE / 2,
                };
                if (rectangleTileColumns != 1 or rectangleTileRows != 1) {
                    const columns: u16 = @intFromFloat((mapBottomRightTileBottomRight.x - mapTopLeftTile.x) / mapZig.GameMap.TILE_SIZE);
                    const rows: u16 = @intFromFloat((mapBottomRightTileBottomRight.y - mapTopLeftTile.y) / mapZig.GameMap.TILE_SIZE);
                    const adjustColumns = @mod(columns, rectangleTileColumns);
                    const adjustRows = @mod(rows, rectangleTileRows);
                    if (mapMouseUp.x < mapMouseDown.x) {
                        mapTopLeftTile.x = mapTopLeftTile.x - @as(f32, @floatFromInt(adjustColumns * mapZig.GameMap.TILE_SIZE));
                    } else {
                        mapBottomRightTileBottomRight.x = mapBottomRightTileBottomRight.x + @as(f32, @floatFromInt(adjustColumns * mapZig.GameMap.TILE_SIZE));
                    }
                    if (mapMouseUp.y < mapMouseDown.y) {
                        mapTopLeftTile.y = mapTopLeftTile.y - @as(f32, @floatFromInt(adjustRows * mapZig.GameMap.TILE_SIZE));
                    } else {
                        mapBottomRightTileBottomRight.y = mapBottomRightTileBottomRight.y + @as(f32, @floatFromInt(adjustRows * mapZig.GameMap.TILE_SIZE));
                    }
                }

                const vulkanBottomRight = mapZig.mapPositionToVulkanSurfacePoisition(mapBottomRightTileBottomRight.x, mapBottomRightTileBottomRight.y, state.camera);
                const vulkanTopleft = mapZig.mapPositionToVulkanSurfacePoisition(mapTopLeftTile.x, mapTopLeftTile.y, state.camera);

                if (state.rectangles[0] == null) {
                    state.rectangles[0] = .{
                        .color = .{ 1, 0, 0 },
                        .pos = .{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 } },
                    };
                }
                state.rectangles[0].?.pos[0] = vulkanTopleft;
                state.rectangles[0].?.pos[1] = vulkanBottomRight;
            }
        }
    }
}

fn initPaintVulkanAndWindowSdl(state: *ChatSimState) !void {
    try windowSdlZig.initWindowSdl();
    try paintVulkanZig.initVulkan(state);
}

fn destroyPaintVulkanAndWindowSdl(state: *ChatSimState) !void {
    try paintVulkanZig.destroyPaintVulkan(&state.vkState, state.allocator);
    windowSdlZig.destroyWindowSdl();
}

fn startGame(allocator: std.mem.Allocator) !void {
    std.debug.print("game run start\n", .{});
    var state: ChatSimState = undefined;
    try createGameState(allocator, &state, null);
    defer destroyGameState(&state);
    try mainLoop(&state);
}

pub fn mainLoop(state: *ChatSimState) !void {
    var ticksRequired: f32 = 0;
    const totalStartTime = std.time.microTimestamp();
    var nextCpuPerCentUpdateTimeMs: i64 = 0;
    mainLoop: while (!state.gameEnd) {
        try codePerformanceZig.startMeasure("main loop", &state.codePerformanceData);
        const startTime = std.time.microTimestamp();
        ticksRequired += state.gameSpeed;
        try windowSdlZig.handleEvents(state);

        while (ticksRequired >= 1) {
            try tick(state);
            ticksRequired -= 1;
            const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
            if (SIMULATION_MICRO_SECOND_DURATION) |duration| {
                if (totalPassedTime > duration) state.gameEnd = true;
            }
            if (state.gameEnd) break :mainLoop;
        }
        try codePerformanceZig.startMeasure("input tick", &state.codePerformanceData);
        inputZig.tick(state);
        codePerformanceZig.endMeasure("input tick", &state.codePerformanceData);
        try codePerformanceZig.startMeasure("sound mixer tick", &state.codePerformanceData);
        try soundMixerZig.tickSoundMixer(state);
        codePerformanceZig.endMeasure("sound mixer tick", &state.codePerformanceData);
        try codePerformanceZig.startMeasure("draw fram", &state.codePerformanceData);
        try paintVulkanZig.drawFrame(state);
        codePerformanceZig.endMeasure("draw fram", &state.codePerformanceData);
        const passedTime = @as(u64, @intCast((std.time.microTimestamp() - startTime)));
        try codePerformanceZig.startMeasure("main loop end stuff", &state.codePerformanceData);
        if (state.testData == null or state.testData.?.fpsLimiter) {
            const sleepTime = @as(u64, @intCast(state.paintIntervalMs)) * 1_000 -| passedTime;
            if (std.time.milliTimestamp() > nextCpuPerCentUpdateTimeMs) {
                state.cpuPerCent = 1.0 - @as(f32, @floatFromInt(sleepTime)) / @as(f32, @floatFromInt(state.paintIntervalMs)) / 1000.0;
                nextCpuPerCentUpdateTimeMs = std.time.milliTimestamp() + 1000;
            }
            std.time.sleep(sleepTime * 1_000);
        }
        const thisFrameFps = @divFloor(1_000_000, @as(u64, @intCast((std.time.microTimestamp() - startTime))));
        state.fpsCounter = state.fpsCounter * 0.99 + @as(f32, @floatFromInt(thisFrameFps)) * 0.01;

        const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
        if (SIMULATION_MICRO_SECOND_DURATION) |duration| {
            if (totalPassedTime > duration) state.gameEnd = true;
        }
        codePerformanceZig.endMeasure("main loop end stuff", &state.codePerformanceData);
        codePerformanceZig.endMeasure("main loop", &state.codePerformanceData);
    }
    std.debug.print("mainloop finished. gameEnd = true\n", .{});
}

pub fn splitActiveChunksForThreads(activeChunks: std.ArrayList(u64), activeChunksSplits: []std.ArrayList(u64)) !void {
    for (0..activeChunksSplits.len) |i| {
        activeChunksSplits[i].clearRetainingCapacity();
    }
    const placeHolder: u64 = 0;
    var highestFreeIndex: usize = 0;
    const minDistance = 6;
    main: for (activeChunks.items) |chunkKey| {
        const chunkXY = mapZig.getChunkXyForKey(chunkKey);
        for (0..(highestFreeIndex + 1)) |indexHeight| {
            var availableSplitIndex: ?usize = null;
            for (activeChunksSplits, 0..) |split, splitIndex| {
                if (split.items.len <= indexHeight or split.items[indexHeight] == placeHolder) {
                    availableSplitIndex = splitIndex;
                    break;
                }
            }
            if (availableSplitIndex != null) {
                var isValidSpot = true;
                for (activeChunksSplits) |split| {
                    if (split.items.len > indexHeight and split.items[indexHeight] != placeHolder) {
                        const otherChunkXY = mapZig.getChunkXyForKey(split.items[indexHeight]);
                        if (@abs(chunkXY.chunkX - otherChunkXY.chunkX) < minDistance and @abs(chunkXY.chunkY - otherChunkXY.chunkY) < minDistance) {
                            isValidSpot = false;
                            break;
                        }
                    }
                }
                if (isValidSpot) {
                    const splitPtr = &activeChunksSplits[availableSplitIndex.?];
                    if (splitPtr.items.len == indexHeight) {
                        try splitPtr.append(chunkKey);
                        if (highestFreeIndex <= indexHeight) highestFreeIndex = indexHeight + 1;
                    } else if (splitPtr.items.len > indexHeight) {
                        splitPtr.items[indexHeight] = chunkKey;
                    } else {
                        while (splitPtr.items.len < indexHeight) {
                            try splitPtr.append(placeHolder);
                        }
                        try splitPtr.append(chunkKey);
                    }
                    continue :main;
                }
            }
        }
    }
}

fn tick(state: *ChatSimState) !void {
    try codePerformanceZig.startMeasure("tick total", &state.codePerformanceData);
    state.gameTimeMs += state.tickIntervalMs;
    try state.map.chunks.ensureTotalCapacity(state.map.chunks.count() + 60);
    try testZig.tick(state);

    // var maxIndex: usize = 0;
    // for (0..state.activeChunkSplitIndex.len) |i| {
    //     state.activeChunkSplitIndex[i] = 0;
    // }
    // state.activeChunkAllowedIndex = 0;
    // var threads: []?std.Thread = try state.allocator.alloc(?std.Thread, state.cpuCount);
    // defer state.allocator.free(threads);
    // for (state.activeChunksThreadSplit, 0..) |split, index| {
    //     threads[index] = try std.Thread.spawn(.{}, tickThreadChunks, .{ index, state });
    //     if (maxIndex < split.items.len) maxIndex = split.items.len;
    // }
    // while (true) {
    //     var chunksDone = true;
    //     for (0..state.cpuCount) |index| {
    //         if (state.activeChunksThreadSplit[index].items.len > state.activeChunkAllowedIndex and state.activeChunkSplitIndex[index] <= state.activeChunkAllowedIndex) {
    //             chunksDone = false;
    //             break;
    //         }
    //     }
    //     if (chunksDone) {
    //         state.activeChunkAllowedIndex += 1;
    //         if (state.activeChunkAllowedIndex >= maxIndex) break;
    //     }
    // }
    // for (threads) |optThread| {
    //     if (optThread) |thread| {
    //         thread.join();
    //     }
    // }

    for (0..state.map.activeChunkKeys.items.len) |i| {
        const chunkKey = state.map.activeChunkKeys.items[i];
        try tickSingleChunk(chunkKey, state);
    }
    const updateTickInterval = 10;
    if (@mod(state.gameTimeMs, state.tickIntervalMs * updateTickInterval) == 0) {
        const citizenChange: f32 = (@as(f32, @floatFromInt(state.citizenCounter)) - @as(f32, @floatFromInt(state.citizenCounterLastTick))) * 60.0 * 60.0 / updateTickInterval;
        if (citizenChange >= 0) {
            state.citizensPerMinuteCounter = state.citizensPerMinuteCounter * (1 - 0.002 * updateTickInterval) + citizenChange * 0.002 * updateTickInterval;
        }
        state.citizenCounterLastTick = state.citizenCounter;
    }
    codePerformanceZig.endMeasure("tick total", &state.codePerformanceData);
    codePerformanceZig.evaluateTickData(&state.codePerformanceData);
}

fn tickThreadChunks(threadNumber: usize, state: *ChatSimState) !void {
    const splitKeys = state.activeChunksThreadSplit[threadNumber];
    while (true) {
        if (state.activeChunkSplitIndex[threadNumber] <= state.activeChunkAllowedIndex) {
            if (splitKeys.items.len <= state.activeChunkAllowedIndex) break;
            try tickSingleChunk(splitKeys.items[state.activeChunkAllowedIndex], state);
            state.activeChunkSplitIndex[threadNumber] += 1;
        } else {
            std.Thread.sleep(1000);
        }
    }
}

fn tickSingleChunk(chunkKey: u64, state: *ChatSimState) !void {
    if (chunkKey == 0) return;
    const chunk = state.map.chunks.getPtr(chunkKey).?;
    try codePerformanceZig.startMeasure(" citizen", &state.codePerformanceData);
    try Citizen.citizensTick(chunk, state);
    try Citizen.citizensMoveTick(chunk, state);
    codePerformanceZig.endMeasure(" citizen", &state.codePerformanceData);

    try codePerformanceZig.startMeasure(" chunkQueue", &state.codePerformanceData);
    while (chunk.queue.items.len > 0) {
        const item = chunk.queue.items[0];
        if (item.executeTime <= state.gameTimeMs) {
            switch (item.itemData) {
                .tree => |data| {
                    chunk.trees.items[data].fullyGrown = true;
                    chunk.trees.items[data].growStartTimeMs = null;
                    chunk.trees.items[data].imageIndex = imageZig.IMAGE_TREE;
                },
                .potatoField => |data| {
                    chunk.potatoFields.items[data].fullyGrown = true;
                    chunk.potatoFields.items[data].growStartTimeMs = null;
                },
            }
            _ = chunk.queue.orderedRemove(0);
        } else {
            break;
        }
    }
    codePerformanceZig.endMeasure(" chunkQueue", &state.codePerformanceData);
    try codePerformanceZig.startMeasure(" chunkBuildOrders", &state.codePerformanceData);

    if (chunk.skipBuildOrdersUntilTimeMs) |time| {
        if (time <= state.gameTimeMs) chunk.skipBuildOrdersUntilTimeMs = null;
    }
    var iterator = chunk.buildOrders.items.len;
    if (chunk.skipBuildOrdersUntilTimeMs == null) {
        while (iterator > 0) {
            iterator -= 1;
            const buildOrder: *mapZig.BuildOrder = &chunk.buildOrders.items[iterator];
            const optMapObject: ?mapZig.MapObject = try mapZig.getObjectOnPosition(buildOrder.position, state);
            if (optMapObject) |mapObject| {
                if (try Citizen.findCloseFreeCitizen(buildOrder.position, state)) |freeCitizen| {
                    switch (mapObject) {
                        mapZig.MapObject.building => |building| {
                            freeCitizen.buildingPosition = building.position;
                            freeCitizen.nextThinkingAction = .buildingStart;
                            freeCitizen.moveTo.clearAndFree();
                            _ = chunk.buildOrders.pop();
                        },
                        mapZig.MapObject.bigBuilding => |building| {
                            freeCitizen.buildingPosition = building.position;
                            freeCitizen.nextThinkingAction = .buildingStart;
                            freeCitizen.moveTo.clearAndFree();
                            if (buildOrder.materialCount > 1) {
                                buildOrder.materialCount -= 1;
                                iterator += 1;
                            } else {
                                _ = chunk.buildOrders.pop();
                            }
                        },
                        mapZig.MapObject.potatoField => |potatoField| {
                            freeCitizen.farmPosition = potatoField.position;
                            freeCitizen.nextThinkingAction = .potatoPlant;
                            freeCitizen.moveTo.clearAndFree();
                            _ = chunk.buildOrders.pop();
                        },
                        mapZig.MapObject.tree => |tree| {
                            freeCitizen.treePosition = tree.position;
                            freeCitizen.nextThinkingAction = .treePlant;
                            freeCitizen.moveTo.clearAndFree();
                            _ = chunk.buildOrders.pop();
                        },
                        mapZig.MapObject.path => {
                            _ = chunk.buildOrders.pop();
                        },
                    }
                } else {
                    chunk.skipBuildOrdersUntilTimeMs = state.gameTimeMs + 250;
                    break;
                }
            }
        }
    }
    codePerformanceZig.endMeasure(" chunkBuildOrders", &state.codePerformanceData);
}

pub fn destroyGameState(state: *ChatSimState) void {
    soundMixerZig.destroySoundMixer(state);
    try destroyPaintVulkanAndWindowSdl(state);
    var iterator = state.map.chunks.valueIterator();
    while (iterator.next()) |chunk| {
        chunk.buildings.deinit();
        chunk.bigBuildings.deinit();
        chunk.trees.deinit();
        chunk.potatoFields.deinit();
        Citizen.destroyCitizens(chunk);
        chunk.citizens.deinit();
        chunk.buildOrders.deinit();
        chunk.pathes.deinit();
        chunk.queue.deinit();
        pathfindingZig.destoryChunkData(&chunk.pathingData);
    }
    for (0..state.cpuCount) |i| {
        state.activeChunksThreadSplit[i].deinit();
    }
    state.allocator.free(state.activeChunksThreadSplit);
    state.allocator.free(state.activeChunkSplitIndex);

    pathfindingZig.destoryPathfindingData(&state.pathfindingData);
    inputZig.destory(state);
    codePerformanceZig.destroy(state);

    state.map.chunks.deinit();
    state.map.activeChunkKeys.deinit();
}

pub fn calculateDirection(start: Position, end: Position) f32 {
    return std.math.atan2(end.y - start.y, end.x - start.x);
}
