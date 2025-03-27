const std = @import("std");
const expect = @import("std").testing.expect;
pub const Citizen = @import("citizen.zig").Citizen;
const paintVulkanZig = @import("vulkan/paintVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const ChatSimState: type = struct {
    citizens: std.ArrayList(Citizen),
    chunks: std.StringHashMap(MapChunk),
    currentBuildingType: u8 = BUILDING_TYPE_HOUSE,
    buildMode: u8 = BUILDING_MODE_SINGLE,
    mouseDown: ?Position = null,
    gameSpeed: f32,
    paintIntervalMs: u8,
    tickIntervalMs: u8,
    gameTimeMs: u32,
    gameEnd: bool,
    vkState: paintVulkanZig.Vk_State,
    fpsLimiter: bool,
    camera: Camera,
    pub const TILE_SIZE: u16 = 20;
};

pub const BUILDING_MODE_SINGLE = 0;
pub const BUILDING_MODE_DRAG_RECTANGLE = 1;
pub const BUILDING_TYPE_HOUSE = 0;
pub const BUILDING_TYPE_TREE_FARM = 1;

pub const MapTree = struct {
    position: Position,
    citizenOnTheWay: bool = false,
    ///  values from 0 to 1
    grow: f32,
};

pub const Building = struct {
    type: u8,
    position: Position,
    inConstruction: bool = true,
};

pub const MapChunk = struct {
    trees: std.ArrayList(MapTree),
    buildings: std.ArrayList(Building),
};

pub const Camera: type = struct {
    position: Position,
    zoom: f32,
};

pub const Position: type = struct {
    x: f32,
    y: f32,
};

const SIMULATION_MICRO_SECOND_DURATION: ?i64 = null; //10_000_000;

test "test for memory leaks" {
    const test_allocator = std.testing.allocator;
    std.debug.print("just a test message: \n", .{});
    try runGame(test_allocator);
}

test "test measure performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const startTime = std.time.microTimestamp();
    try runGame(allocator);
    std.debug.print("time: {d}\n", .{std.time.microTimestamp() - startTime});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const startTime = std.time.microTimestamp();
    try runGame(allocator);
    std.debug.print("time: {d}\n", .{std.time.microTimestamp() - startTime});
}

pub fn mapPositionToTilePosition(pos: Position) Position {
    return Position{
        .x = @round(pos.x / ChatSimState.TILE_SIZE) * ChatSimState.TILE_SIZE,
        .y = @round(pos.y / ChatSimState.TILE_SIZE) * ChatSimState.TILE_SIZE,
    };
}

pub fn mapIsTilePositionFree(pos: Position, state: *ChatSimState) bool {
    const chunk = state.chunks.get("0_0").?;
    for (chunk.buildings.items) |building| {
        if (calculateDistance(pos, building.position) < ChatSimState.TILE_SIZE) {
            return false;
        }
    }
    for (chunk.trees.items) |tree| {
        if (calculateDistance(pos, tree.position) < ChatSimState.TILE_SIZE) {
            return false;
        }
    }
    return true;
}

pub fn calculateDistance(pos1: Position, pos2: Position) f32 {
    const diffX = pos1.x - pos2.x;
    const diffY = pos1.y - pos2.y;
    return @sqrt(diffX * diffX + diffY * diffY);
}

fn createGameState(allocator: std.mem.Allocator, state: *ChatSimState) !void {
    var citizensList = std.ArrayList(Citizen).init(allocator);
    var chunks = std.StringHashMap(MapChunk).init(allocator);
    var mapChunk: MapChunk = .{
        .buildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
    };
    try mapChunk.buildings.append(.{ .position = .{ .x = 0, .y = 0 }, .inConstruction = false, .type = BUILDING_TYPE_HOUSE });
    try mapChunk.trees.append(.{ .position = .{ .x = ChatSimState.TILE_SIZE, .y = 0 }, .grow = 1 });
    try mapChunk.trees.append(.{ .position = .{ .x = ChatSimState.TILE_SIZE, .y = ChatSimState.TILE_SIZE }, .grow = 1 });

    try chunks.put("0_0", mapChunk);
    for (0..1) |_| {
        try citizensList.append(Citizen.createCitizen());
    }

    state.* = .{
        .citizens = citizensList,
        .chunks = chunks,
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
    };
    Citizen.randomlyPlace(state);
    try initPaintVulkanAndWindowSdl(state);
}

fn initPaintVulkanAndWindowSdl(state: *ChatSimState) !void {
    try windowSdlZig.initWindowSdl();
    try paintVulkanZig.initVulkan(state);
}

fn destoryPaintVulkanAndWindowSdl(vkState: *paintVulkanZig.Vk_State) !void {
    try paintVulkanZig.destroyPaintVulkan(vkState);
    windowSdlZig.destroyWindowSdl();
}

fn runGame(allocator: std.mem.Allocator) !void {
    std.debug.print("game run start\n", .{});
    var state: ChatSimState = undefined;
    try createGameState(allocator, &state);
    defer destroyGameState(&state);
    var ticksRequired: f32 = 0;
    const totalStartTime = std.time.microTimestamp();
    var frameCounter: u64 = 0;
    mainLoop: while (!state.gameEnd) {
        const startTime = std.time.microTimestamp();
        ticksRequired += state.gameSpeed;
        try windowSdlZig.handleEvents(&state);

        while (ticksRequired >= 1) {
            try tick(&state);
            ticksRequired -= 1;
            const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
            if (SIMULATION_MICRO_SECOND_DURATION) |duration| {
                if (totalPassedTime > duration) state.gameEnd = true;
            }
            if (state.gameEnd) break :mainLoop;
        }
        try paintVulkanZig.setupVerticesForCitizens(&state);
        try paintVulkanZig.setupVertexDataForGPU(&state.vkState);
        try paintVulkanZig.drawFrame(&state);
        frameCounter += 1;
        if (state.fpsLimiter) {
            const passedTime = @as(u64, @intCast((std.time.microTimestamp() - startTime)));
            const sleepTime = @as(u64, @intCast(state.paintIntervalMs)) * 1_000 -| passedTime;
            std.time.sleep(sleepTime * 1_000);
        }
        if (frameCounter % 600 == 0) {
            std.debug.print("citizenCounter: {d}\n", .{state.citizens.items.len});
        }

        const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
        if (SIMULATION_MICRO_SECOND_DURATION) |duration| {
            if (totalPassedTime > duration) state.gameEnd = true;
        }
    }
    const totalLoopTime: u64 = @as(u64, @intCast((std.time.microTimestamp() - totalStartTime)));
    const fps: u64 = @divFloor(frameCounter * 1_000_000, totalLoopTime);
    std.debug.print("FPS: {d}\n", .{fps});
    printOutSomeData(state);
    std.debug.print("finished\n", .{});
}

fn tick(state: *ChatSimState) !void {
    state.gameTimeMs += state.tickIntervalMs;
    try Citizen.citizensMove(state);

    //trees
    const chunk = state.chunks.getPtr("0_0").?;
    for (chunk.trees.items) |*tree| {
        if (tree.grow < 1) {
            tree.grow += 1.0 / 60.0 / 10.0;
            if (tree.grow > 1) tree.grow = 1;
        }
    }
}

fn destroyGameState(state: *ChatSimState) void {
    try destoryPaintVulkanAndWindowSdl(&state.vkState);
    state.citizens.deinit();
    var iterator = state.chunks.valueIterator();
    while (iterator.next()) |chunk| {
        chunk.buildings.deinit();
        chunk.trees.deinit();
    }
    state.chunks.deinit();
}

fn printOutSomeData(state: ChatSimState) void {
    const oneCitizen = state.citizens.getLast();
    std.debug.print("someData: x:{d}, y:{d}\n", .{ oneCitizen.position.x, oneCitizen.position.y });
}

pub fn calculateDirection(start: Position, end: Position) f32 {
    return std.math.atan2(end.y - start.y, end.x - start.x);
}
