const std = @import("std");
const expect = @import("std").testing.expect;
pub const Citizen = @import("citizen.zig").Citizen;
const mapZig = @import("map.zig");
const paintVulkanZig = @import("vulkan/paintVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const ChatSimState: type = struct {
    map: mapZig.GameMap,
    currentBuildingType: u8 = mapZig.BUILDING_TYPE_HOUSE,
    buildMode: u8 = mapZig.BUILDING_MODE_SINGLE,
    mouseDown: ?Position = null,
    gameSpeed: f32,
    paintIntervalMs: u8,
    tickIntervalMs: u8,
    gameTimeMs: u32,
    gameEnd: bool,
    vkState: paintVulkanZig.Vk_State,
    fpsLimiter: bool,
    camera: Camera,
    allocator: std.mem.Allocator,
    rectangle: ?Rectangle = null,
    currentMouse: ?Position = null,
    fpsCounter: f32 = 60,
    cpuPerCent: ?f32 = null,
    citizenCounter: u32 = 0,
};

pub const Rectangle = struct {
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

var SIMULATION_MICRO_SECOND_DURATION: ?i64 = null;

test "test for memory leaks" {
    const test_allocator = std.testing.allocator;
    SIMULATION_MICRO_SECOND_DURATION = 100_000;
    try startGame(test_allocator);
    // testing allocator will fail test if something is not deallocated
}

test "test measure performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var state: ChatSimState = undefined;
    try createGameState(allocator, &state);
    defer destroyGameState(&state);
    SIMULATION_MICRO_SECOND_DURATION = 5_000_000;
    for (0..10_000) |_| {
        try mapZig.placeCitizen(Citizen.createCitizen());
    }
    Citizen.randomlyPlace(try mapZig.getChunkAndCreateIfNotExistsForChunkXY(0, 0, state));
    state.fpsLimiter = false;
    state.gameSpeed = 1;

    const startTime = std.time.microTimestamp();
    try mainLoop(&state);
    const frames = @divFloor(state.gameTimeMs, state.tickIntervalMs);
    const timePassed = std.time.microTimestamp() - startTime;
    const fps = @divFloor(frames * 1_000_000, timePassed);
    std.debug.print("FPS: {d}", .{fps});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    try startGame(allocator);
}

pub fn mapPositionToTilePosition(pos: Position) Position {
    return Position{
        .x = @round(pos.x / mapZig.GameMap.TILE_SIZE) * mapZig.GameMap.TILE_SIZE,
        .y = @round(pos.y / mapZig.GameMap.TILE_SIZE) * mapZig.GameMap.TILE_SIZE,
    };
}

pub fn calculateDistance(pos1: Position, pos2: Position) f32 {
    const diffX = pos1.x - pos2.x;
    const diffY = pos1.y - pos2.y;
    return @sqrt(diffX * diffX + diffY * diffY);
}

pub fn createGameState(allocator: std.mem.Allocator, state: *ChatSimState) !void {
    const map: mapZig.GameMap = try mapZig.createMap(allocator);

    state.* = .{
        .map = map,
        .gameSpeed = 1,
        .paintIntervalMs = 16,
        .tickIntervalMs = 16,
        .gameTimeMs = 0,
        .gameEnd = false,
        .vkState = .{},
        .fpsLimiter = true,
        .camera = .{
            .position = .{ .x = 0, .y = 0 },
            .zoom = 1,
        },
        .allocator = allocator,
    };
    try mapZig.placeCitizen(Citizen.createCitizen(), state);
    try initPaintVulkanAndWindowSdl(state);
}

fn initPaintVulkanAndWindowSdl(state: *ChatSimState) !void {
    try windowSdlZig.initWindowSdl();
    try paintVulkanZig.initVulkan(state);
}

fn destoryPaintVulkanAndWindowSdl(state: *ChatSimState) !void {
    try paintVulkanZig.destroyPaintVulkan(&state.vkState, state.allocator);
    windowSdlZig.destroyWindowSdl();
}

fn startGame(allocator: std.mem.Allocator) !void {
    std.debug.print("game run start\n", .{});
    var state: ChatSimState = undefined;
    try createGameState(allocator, &state);
    defer destroyGameState(&state);
    try mainLoop(&state);
}

fn mainLoop(state: *ChatSimState) !void {
    var ticksRequired: f32 = 0;
    const totalStartTime = std.time.microTimestamp();
    mainLoop: while (!state.gameEnd) {
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
        try paintVulkanZig.setupVerticesForCitizens(state);
        try paintVulkanZig.setupVertexDataForGPU(&state.vkState);
        try paintVulkanZig.drawFrame(state);
        const passedTime = @as(u64, @intCast((std.time.microTimestamp() - startTime)));
        if (state.fpsLimiter) {
            const sleepTime = @as(u64, @intCast(state.paintIntervalMs)) * 1_000 -| passedTime;
            if (state.gameTimeMs % (@as(u32, state.tickIntervalMs) * 60) == 0) {
                state.cpuPerCent = 1.0 - @as(f32, @floatFromInt(sleepTime)) / @as(f32, @floatFromInt(state.paintIntervalMs)) / 1000.0;
            }
            std.time.sleep(sleepTime * 1_000);
        }
        const thisFrameFps = @divFloor(1_000_000, @as(u64, @intCast((std.time.microTimestamp() - startTime))));
        state.fpsCounter = state.fpsCounter * 0.8 + @as(f32, @floatFromInt(thisFrameFps)) * 0.2;

        const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
        if (SIMULATION_MICRO_SECOND_DURATION) |duration| {
            if (totalPassedTime > duration) state.gameEnd = true;
        }
    }
    std.debug.print("finished\n", .{});
}

fn tick(state: *ChatSimState) !void {
    state.gameTimeMs += state.tickIntervalMs;

    for (0..state.map.activeChunkKeys.items.len) |i| {
        const chunkKey = state.map.activeChunkKeys.items[i];
        try state.map.chunks.ensureTotalCapacity(state.map.chunks.count() + 20);
        const chunk = state.map.chunks.getPtr(chunkKey).?;
        try Citizen.citizensTick(chunk, state);
        for (chunk.trees.items) |*tree| {
            if (tree.grow < 1) {
                tree.grow += 1.0 / 60.0 / 10.0;
                if (tree.grow > 1) tree.grow = 1;
            }
        }
        for (chunk.potatoFields.items) |*potatoField| {
            if (potatoField.grow < 1 and potatoField.planted) {
                potatoField.grow += 1.0 / 60.0 / 10.0;
                if (potatoField.grow > 1) potatoField.grow = 1;
            }
        }
    }
}

pub fn destroyGameState(state: *ChatSimState) void {
    try destoryPaintVulkanAndWindowSdl(state);
    var iterator = state.map.chunks.valueIterator();
    while (iterator.next()) |chunk| {
        chunk.buildings.deinit();
        chunk.trees.deinit();
        chunk.potatoFields.deinit();
        chunk.citizens.deinit();
    }
    state.map.chunks.deinit();
    state.map.activeChunkKeys.deinit();
}

pub fn calculateDirection(start: Position, end: Position) f32 {
    return std.math.atan2(end.y - start.y, end.x - start.x);
}
