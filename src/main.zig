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
    soundMixer: soundMixerZig.SoundMixer,
    keyboardInfo: inputZig.KeyboardInfo = .{},
    mouseInfo: MouseInfo = .{},
    random: std.Random.Xoshiro256,
    codePerformanceData: codePerformanceZig.CodePerformanceData = undefined,
    cpuCount: usize,
    threadData: []ThreadData = undefined,
    activeChunksThreadSplit: []std.ArrayList(u64) = undefined,
    activeChunkSplitIndex: []usize = undefined,
    activeChunkAllowedIndex: usize = 0,
    activeChunksThreadSplitLongest: usize = 0,
    wasSingleCore: bool = true,
};

pub const ThreadData = struct {
    pathfindingTempData: pathfindingZig.PathfindingTempData,
    thread: ?std.Thread = null,
    splitIndexCounter: usize = 0,
    tickedCitizenCounter: usize = 0,
    idleTicks: u64 = 0,
    averageIdleTicks: u64 = 0,
    finishedTick: bool = true,
    citizensAddedThisTick: u32 = 0,
    pub const CHUNKKEY_PLACEHOLDER = 0;
    pub const VALIDATION_CHUNK_DISTANCE = 40;
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
    for (0..10) |i| {
        for (0..5) |j| {
            const x: i32 = @intCast(i * 10);
            const y: i32 = @intCast(j * 5);
            try activeChunks.append(mapZig.getKeyForChunkXY(.{ .chunkX = x, .chunkY = y }));
        }
    }
    const cpuCount = 4;
    var chunkSplits = try test_allocator.alloc(std.ArrayList(u64), cpuCount);
    for (0..cpuCount) |i| {
        chunkSplits[i] = std.ArrayList(u64).init(test_allocator);
    }

    var state = ChatSimState{
        .map = undefined,
        .gameSpeed = 1,
        .paintIntervalMs = 16,
        .tickIntervalMs = 16,
        .gameTimeMs = 0,
        .gameEnd = false,
        .vkState = .{},
        .citizenCounter = 1,
        .camera = undefined,
        .allocator = test_allocator,
        .soundMixer = undefined,
        .random = undefined,
        .cpuCount = cpuCount,
    };
    state.threadData = try test_allocator.alloc(ThreadData, state.cpuCount);
    defer test_allocator.free(state.threadData);
    for (0..state.cpuCount) |i| {
        state.threadData[i] = .{ .pathfindingTempData = undefined };
    }
    try splitActiveChunksForThreads(activeChunks, chunkSplits, &state);

    for (0..cpuCount) |i| {
        std.debug.print("list {}: {d}\n", .{ i, chunkSplits[i].items.len });
        std.debug.print("{any}\n", .{chunkSplits[i].items});
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
        .soundMixer = undefined,
        .random = prng,
        .cpuCount = std.Thread.getCpuCount() catch 1,
    };
    state.cpuCount = 2;
    state.activeChunksThreadSplit = try allocator.alloc(std.ArrayList(u64), state.cpuCount);
    state.activeChunkSplitIndex = try allocator.alloc(usize, state.cpuCount);
    state.threadData = try allocator.alloc(ThreadData, state.cpuCount);
    for (0..state.cpuCount) |i| {
        state.threadData[i] = .{ .pathfindingTempData = try pathfindingZig.createPathfindingData(allocator) };
        state.activeChunksThreadSplit[i] = std.ArrayList(u64).init(allocator);
        state.activeChunkSplitIndex[i] = 1;
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

pub fn addActiveChunkForThreads(newActiveChunkKey: u64, activeChunksSplits: []std.ArrayList(u64), state: *ChatSimState) !void {
    const chunkXY = mapZig.getChunkXyForKey(newActiveChunkKey);
    if (chunkXY.chunkX < 35) {
        try activeChunksSplits[0].append(newActiveChunkKey);
        state.threadData[0].splitIndexCounter += 1;
    } else {
        try activeChunksSplits[1].append(newActiveChunkKey);
        state.threadData[1].splitIndexCounter += 1;
    }

    if (true) return;
    const minDistance = 12;
    for (0..(state.activeChunksThreadSplitLongest + ThreadData.VALIDATION_CHUNK_DISTANCE)) |indexHeight| {
        var availableSplitIndex: ?usize = null;
        for (activeChunksSplits, 0..) |split, splitIndex| {
            if (split.items.len <= indexHeight or split.items[indexHeight] == ThreadData.CHUNKKEY_PLACEHOLDER) {
                availableSplitIndex = splitIndex;
                break;
            }
        }
        if (availableSplitIndex != null) {
            var isValid = true;
            validationMain: for (0..ThreadData.VALIDATION_CHUNK_DISTANCE) |validationRound| {
                if (indexHeight < validationRound) break;
                const indexToCheck = indexHeight - validationRound;
                const roundMinDistance = minDistance + ThreadData.VALIDATION_CHUNK_DISTANCE - validationRound - 1;

                for (activeChunksSplits, 0..) |split, splitIndex| {
                    if (splitIndex == availableSplitIndex) continue;
                    if (split.items.len > indexToCheck and split.items[indexToCheck] != ThreadData.CHUNKKEY_PLACEHOLDER) {
                        const otherChunkXY = mapZig.getChunkXyForKey(split.items[indexToCheck]);
                        if (@abs(chunkXY.chunkX - otherChunkXY.chunkX) < roundMinDistance and @abs(chunkXY.chunkY - otherChunkXY.chunkY) < roundMinDistance) {
                            isValid = false;
                            break :validationMain;
                        }
                    }
                }
            }

            if (isValid) {
                const splitPtr = &activeChunksSplits[availableSplitIndex.?];
                if (splitPtr.items.len == indexHeight) {
                    try splitPtr.append(newActiveChunkKey);
                    state.threadData[availableSplitIndex.?].splitIndexCounter += 1;
                    if (state.activeChunksThreadSplitLongest <= indexHeight) state.activeChunksThreadSplitLongest = indexHeight + 1;
                } else if (splitPtr.items.len > indexHeight) {
                    splitPtr.items[indexHeight] = newActiveChunkKey;
                    state.threadData[availableSplitIndex.?].splitIndexCounter += 1;
                } else {
                    while (splitPtr.items.len < indexHeight) {
                        try splitPtr.append(ThreadData.CHUNKKEY_PLACEHOLDER);
                    }
                    state.threadData[availableSplitIndex.?].splitIndexCounter += 1;
                    try splitPtr.append(newActiveChunkKey);
                    if (state.activeChunksThreadSplitLongest <= indexHeight) state.activeChunksThreadSplitLongest = indexHeight + 1;
                }
                return;
            }
        }
    }
    std.debug.print("should not happen. {}\n", .{newActiveChunkKey});
}

pub fn splitActiveChunksForThreads(activeChunks: std.ArrayList(u64), activeChunksSplits: []std.ArrayList(u64), state: *ChatSimState) !void {
    for (0..activeChunksSplits.len) |i| {
        activeChunksSplits[i].clearRetainingCapacity();
    }
    state.activeChunksThreadSplitLongest = 0;
    for (activeChunks.items) |chunkKey| {
        try addActiveChunkForThreads(chunkKey, activeChunksSplits, state);
    }
}

fn tick(state: *ChatSimState) !void {
    try codePerformanceZig.startMeasure("tick total", &state.codePerformanceData);
    state.gameTimeMs += state.tickIntervalMs;
    try state.map.chunks.ensureTotalCapacity(state.map.chunks.count() + 60);
    try testZig.tick(state);

    var maxIndex: usize = 0;

    var nonMainThreadsDataCount: usize = 0;
    for (state.activeChunksThreadSplit, 0..) |split, i| {
        if (maxIndex < split.items.len) maxIndex = split.items.len;
        if (split.items.len > 0) {
            if (i > 0) {
                nonMainThreadsDataCount += state.threadData[i].splitIndexCounter;
                if (state.threadData[i].thread == null) {
                    state.threadData[i].thread = try std.Thread.spawn(.{}, tickThreadChunks, .{ i, state });
                }
            }
        }
    }
    const singleCore = nonMainThreadsDataCount <= 100;
    state.wasSingleCore = singleCore;
    if (singleCore) {
        state.citizenCounter += state.threadData[0].citizensAddedThisTick;
        state.threadData[0].tickedCitizenCounter = 0;
        state.threadData[0].citizensAddedThisTick = 0;
        for (0..state.map.activeChunkKeys.items.len) |i| {
            const chunkKey = state.map.activeChunkKeys.items[i];
            try tickSingleChunk(chunkKey, 0, state);
        }
    } else {
        state.activeChunkAllowedIndex = ThreadData.VALIDATION_CHUNK_DISTANCE - 1;
        for (0..state.activeChunkSplitIndex.len) |i| {
            const threadData = &state.threadData[i];
            try state.activeChunksThreadSplit[i].ensureUnusedCapacity(50);
            threadData.tickedCitizenCounter = 0;
            state.citizenCounter += threadData.citizensAddedThisTick;
            threadData.citizensAddedThisTick = 0;
            threadData.averageIdleTicks = @divFloor(threadData.averageIdleTicks * 255 + threadData.idleTicks, 256);
            state.activeChunkSplitIndex[i] = 0;
            threadData.finishedTick = false;
        }
        const splitKeys = state.activeChunksThreadSplit[0];
        while (true) {
            if (state.gameEnd) break;
            if (state.activeChunkAllowedIndex + ThreadData.VALIDATION_CHUNK_DISTANCE - 1 >= state.activeChunkSplitIndex[0]) {
                try tickSingleChunk(splitKeys.items[state.activeChunkSplitIndex[0]], 0, state);
                state.activeChunkSplitIndex[0] += 1;
                if (state.activeChunkSplitIndex[0] >= splitKeys.items.len) break;
            }
            var minIndex = state.activeChunkSplitIndex[0];
            for (1..state.cpuCount) |i| {
                if (state.activeChunkSplitIndex[i] < minIndex and !state.threadData[i].finishedTick) {
                    minIndex = state.activeChunkSplitIndex[i];
                }
            }
            state.activeChunkAllowedIndex = minIndex;
        }
        const startWaitTime = std.time.nanoTimestamp();
        for (1..state.cpuCount) |i| {
            while (!state.threadData[i].finishedTick) {
                if (state.gameEnd) break;
                //waiting
            }
        }
        state.threadData[0].idleTicks = @intCast(std.time.nanoTimestamp() - startWaitTime);
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
    while (true) {
        if (state.gameEnd) return;
        if (!state.threadData[threadNumber].finishedTick) {
            const splitKeys = state.activeChunksThreadSplit[threadNumber];
            var index: usize = 0;
            main: while (true) {
                if (state.gameEnd) return;
                var allowedTicks: i32 = @as(i32, @intCast(state.activeChunkAllowedIndex + ThreadData.VALIDATION_CHUNK_DISTANCE - 1)) - @as(i32, @intCast(index));
                while (allowedTicks < 0) {
                    //wait
                    allowedTicks = @as(i32, @intCast(state.activeChunkAllowedIndex + ThreadData.VALIDATION_CHUNK_DISTANCE - 1)) - @as(i32, @intCast(index));
                }
                for (0..@intCast(allowedTicks + 1)) |_| {
                    state.activeChunkSplitIndex[threadNumber] += 1;
                    try tickSingleChunk(splitKeys.items[index], threadNumber, state);
                    index += 1;
                    if (index >= splitKeys.items.len) break :main;
                }
            }
            state.threadData[threadNumber].finishedTick = true;
        }
    }
}

fn tickSingleChunk(chunkKey: u64, threadIndex: usize, state: *ChatSimState) !void {
    if (chunkKey == ThreadData.CHUNKKEY_PLACEHOLDER) return;
    const chunk = state.map.chunks.getPtr(chunkKey).?;
    state.threadData[threadIndex].tickedCitizenCounter += chunk.citizens.items.len;
    try codePerformanceZig.startMeasure(" citizen", &state.codePerformanceData);
    try Citizen.citizensTick(chunk, threadIndex, state);
    try Citizen.citizensMoveTick(chunk);
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
    for (state.threadData) |threadData| {
        if (threadData.thread) |thread| {
            thread.join();
        }
    }
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

    for (0..state.cpuCount) |i| {
        pathfindingZig.destoryPathfindingData(&state.threadData[i].pathfindingTempData);
    }
    inputZig.destory(state);
    codePerformanceZig.destroy(state);

    state.map.chunks.deinit();
    state.map.activeChunkKeys.deinit();
}

pub fn calculateDirection(start: Position, end: Position) f32 {
    return std.math.atan2(end.y - start.y, end.x - start.x);
}
