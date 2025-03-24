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
    fpsLimiter: bool,
};

pub const Position: type = struct {
    x: f32,
    y: f32,
};

const SIMULATION_MICRO_SECOND_DURATION: i64 = 5_000_000;

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

fn createGameState(allocator: std.mem.Allocator, state: *ChatSimState) !void {
    var citizensList = std.ArrayList(Citizen).init(allocator);
    for (0..10) |_| {
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
        .fpsLimiter = true,
    };
    Citizen.randomlyPlace(state);
    try Paint.initVulkanAndWindow(state);
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
        try Paint.handleEvents(&state);

        while (ticksRequired >= 1) {
            tick(&state);
            ticksRequired -= 1;
            const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
            if (totalPassedTime > SIMULATION_MICRO_SECOND_DURATION) state.gameEnd = true;
            if (state.gameEnd) break :mainLoop;
        }
        try Paint.setupVerticesForCitizens(&state.citizens, &state.vkState);
        try Paint.setupVertexDataForGPU(&state.vkState);
        try Paint.drawFrame(&state.vkState);
        frameCounter += 1;
        if (state.fpsLimiter) {
            const passedTime = @as(u64, @intCast((std.time.microTimestamp() - startTime)));
            const sleepTime = @as(u64, @intCast(state.paintIntervalMs)) * 1_000 -| passedTime;
            std.time.sleep(sleepTime * 1_000);
        }
        const totalPassedTime: i64 = std.time.microTimestamp() - totalStartTime;
        if (totalPassedTime > SIMULATION_MICRO_SECOND_DURATION) state.gameEnd = true;
    }
    const totalLoopTime: u64 = @as(u64, @intCast((std.time.microTimestamp() - totalStartTime)));
    const fps: u64 = @divFloor(frameCounter * 1_000_000, totalLoopTime);
    std.debug.print("FPS: {d}\n", .{fps});
    printOutSomeData(state);
    std.debug.print("finished\n", .{});
}

fn tick(state: *ChatSimState) void {
    state.gameTimeMs += state.tickIntervalMs;
    Citizen.citizensMove(state);
}

fn destroyGameState(state: *ChatSimState) void {
    state.citizens.deinit();
    try Paint.destoryVulkanAndWindow(&state.vkState);
}

fn printOutSomeData(state: ChatSimState) void {
    const oneCitizen = state.citizens.getLast();
    std.debug.print("someData: x:{d}, y:{d}\n", .{ oneCitizen.position.x, oneCitizen.position.y });
}

pub fn calculateDirection(start: Position, end: Position) f32 {
    return std.math.atan2(end.y - start.y, end.x - start.x);
}
