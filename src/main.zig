const std = @import("std");
const expect = @import("std").testing.expect;
pub const Citizen = @import("citizen.zig").Citizen;
const Paint = @import("paintVulkan.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const ChatSimState: type = struct {
    citizens: std.ArrayList(Citizen),
    gameSpeed: f32,
    paintIntervalMs: u8,
    tickIntervalMs: u8,
    gameTimeMs: u32,
    gameEnd: bool,
    vkState: Paint.Vk_State,
};

pub const Position: type = struct {
    x: f32,
    y: f32,
};

test "test for memory leaks" {
    const test_allocator = std.testing.allocator;
    std.debug.print("just a test message: \n", .{});
    try runGame(test_allocator);
    try std.testing.expect(2 + 7 == 8);
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

fn runGame(allocator: std.mem.Allocator) !void {
    std.debug.print("game run start\n", .{});
    var state: ChatSimState = undefined;
    try createGameState(allocator, &state);
    defer destroyGameState(&state);
    var ticksRequired: f32 = 0;
    mainLoop: while (!state.gameEnd) {
        const startTime = std.time.microTimestamp();
        ticksRequired += state.gameSpeed;
        while (ticksRequired >= 1) {
            tick(&state);
            ticksRequired -= 1;
            if (state.gameEnd) break :mainLoop;
        }
        try Paint.setupVerticesForCitizens(&state.citizens);
        try Paint.setupVertexDataForGPU(&state.vkState);
        try Paint.drawFrame(&state.vkState);
        const passedTime = @as(u64, @intCast((std.time.microTimestamp() - startTime)));
        const sleepTime = @as(u64, @intCast(state.paintIntervalMs)) * 1_000 -| passedTime;
        std.time.sleep(sleepTime * 1_000);
    }
    printOutSomeData(state);
    std.debug.print("finished\n", .{});
}

fn tick(state: *ChatSimState) void {
    state.gameTimeMs += state.tickIntervalMs;
    Citizen.citizensMove(state);
    if (state.gameTimeMs > 10_000) state.gameEnd = true;
}

fn createGameState(allocator: std.mem.Allocator, state: *ChatSimState) !void {
    var citizensList = std.ArrayList(Citizen).init(allocator);
    for (0..10_000) |_| {
        try citizensList.append(Citizen.createCitizen());
    }

    state.* = .{
        .citizens = citizensList,
        .gameSpeed = 1,
        .paintIntervalMs = 16,
        .tickIntervalMs = 16,
        .gameTimeMs = 0,
        .gameEnd = false,
        .vkState = .{},
    };
    try Paint.setupVerticesForCitizens(&state.citizens);
    try Paint.initVulkanAndWindow(&state.vkState);
}

fn destroyGameState(state: *ChatSimState) void {
    state.citizens.deinit();
    try Paint.destoryVulkanAndWindow(&state.vkState);
}

fn printOutSomeData(state: ChatSimState) void {
    const oneCitizen = state.citizens.getLast();
    std.debug.print("someData: x:{d}, y:{d}\n", .{ oneCitizen.position.x, oneCitizen.position.y });
}

pub fn calculateDirectionApproximate(startPos: Position, targetPos: Position) f32 {
    const yDiff = (startPos.y - targetPos.y);
    const xDiff = (startPos.x - targetPos.x);
    if (xDiff == 0) {
        return if (yDiff < 0) 90 else -90;
    }
    return std.math.pi / 4.0 * (yDiff / xDiff) - 0.273 * (@abs(yDiff / xDiff) * (@abs(yDiff / xDiff) - 1));
}

pub fn calculateDirection(startPos: Position, targetPos: Position) f32 {
    var direction: f32 = 0;
    const yDiff = (startPos.y - targetPos.y);
    const xDiff = (startPos.x - targetPos.x);

    if (xDiff >= 0) {
        if (xDiff == 0) return 0;
        direction = -std.math.pi + std.math.atan(yDiff / xDiff);
    } else if (yDiff < 0) {
        direction = -std.math.atan(xDiff / yDiff) + std.math.pi / 2.0;
    } else {
        if (yDiff == 0) return 0;
        direction = -std.math.atan(xDiff / yDiff) - std.math.pi / 2.0;
    }
    return direction;
}
