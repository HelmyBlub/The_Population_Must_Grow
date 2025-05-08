const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");

const InputType = enum {
    buildPath,
    buildHouse,
    buildTree,
    buildPotatoFarm,
    copyPaste,
};

const TestInput = struct {
    type: InputType,
    executeTime: u32,
    mapPosition: main.Position,
};

pub const TestData = struct {
    currenTestInputIndex: usize = 0,
    testInputs: std.ArrayList(TestInput) = undefined,
    fpsLimiter: bool = true,
};

pub fn executePerfromanceTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var state: main.ChatSimState = undefined;
    try main.createGameState(allocator, &state);
    defer main.destroyGameState(&state);
    state.testData = .{};
    const testData = &state.testData.?;
    testData.fpsLimiter = false;
    state.gameSpeed = 1;
    testData.testInputs = std.ArrayList(TestInput).init(state.allocator);
    defer testData.testInputs.deinit();
    try setupTestInputs(testData);

    const startTime = std.time.microTimestamp();
    try main.mainLoop(&state);
    const frames: i64 = @intFromFloat(@as(f32, @floatFromInt(@divFloor(state.gameTimeMs, state.tickIntervalMs))) / state.gameSpeed);
    const timePassed = std.time.microTimestamp() - startTime;
    const fps = @divFloor(frames * 1_000_000, timePassed);
    std.debug.print("FPS: {d}", .{fps});
}

pub fn tick(state: *main.ChatSimState) !void {
    if (state.testData) |*testData| {
        while (testData.currenTestInputIndex < testData.testInputs.items.len) {
            const currentInput = testData.testInputs.items[testData.currenTestInputIndex];
            if (currentInput.executeTime <= state.gameTimeMs) {
                switch (currentInput.type) {
                    InputType.buildPath => {
                        _ = try mapZig.placePath(mapZig.mapPositionToTileMiddlePosition(currentInput.mapPosition), state);
                    },
                    InputType.buildHouse => {
                        _ = try mapZig.placeHouse(mapZig.mapPositionToTileMiddlePosition(currentInput.mapPosition), state, true, true);
                    },
                    else => {
                        std.debug.print("not yet implemented {}", .{currentInput.type});
                    },
                }
                testData.currenTestInputIndex += 1;
            } else {
                break;
            }
        }
    }
}

fn setupTestInputs(testData: *TestData) !void {
    const tileSize = mapZig.GameMap.TILE_SIZE;
    try testData.testInputs.append(.{ .type = InputType.buildPath, .executeTime = 0, .mapPosition = .{ .x = 0 * tileSize + tileSize / 2, .y = 1 * tileSize + tileSize / 2 } });
    try testData.testInputs.append(.{ .type = InputType.buildPath, .executeTime = 0, .mapPosition = .{ .x = 1 * tileSize + tileSize / 2, .y = 1 * tileSize + tileSize / 2 } });
    try testData.testInputs.append(.{ .type = InputType.buildPath, .executeTime = 0, .mapPosition = .{ .x = 2 * tileSize + tileSize / 2, .y = 1 * tileSize + tileSize / 2 } });
    try testData.testInputs.append(.{ .type = InputType.buildPath, .executeTime = 0, .mapPosition = .{ .x = 3 * tileSize + tileSize / 2, .y = 1 * tileSize + tileSize / 2 } });
    try testData.testInputs.append(.{ .type = InputType.buildHouse, .executeTime = 0, .mapPosition = .{ .x = 1 * tileSize + tileSize / 2, .y = 0 * tileSize + tileSize / 2 } });

    try testData.testInputs.append(.{ .type = InputType.buildPath, .executeTime = 0, .mapPosition = .{ .x = -1 * tileSize + tileSize / 2, .y = -1 * tileSize + tileSize / 2 } });
    try testData.testInputs.append(.{ .type = InputType.buildHouse, .executeTime = 0, .mapPosition = .{ .x = -2 * tileSize + tileSize / 2, .y = -1 * tileSize + tileSize / 2 } });
}
