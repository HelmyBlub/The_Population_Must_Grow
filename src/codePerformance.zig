const std = @import("std");
const main = @import("main.zig");
const fontVulkanZig = @import("vulkan/fontVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");

pub const CodePerformanceData = struct {
    entries: std.StringArrayHashMap(CodePerformanceEntry),
};

pub const MEASURE: bool = false;

pub const CodePerformanceEntry = struct {
    name: []const u8,
    startNanoSeconds: ?i128 = null,
    currentAddedTime: i128 = 0,
    lastMeasurement: i128 = 0,
};

pub fn init(state: *main.ChatSimState) !void {
    state.codePerformanceData = .{
        .entries = std.StringArrayHashMap(CodePerformanceEntry).init(state.allocator),
    };
}

pub fn destroy(state: *main.ChatSimState) void {
    state.codePerformanceData.entries.deinit();
}

pub fn startMeasure(name: []const u8, codePerformanceData: *CodePerformanceData) !void {
    if (!MEASURE) return;
    if (!codePerformanceData.entries.contains(name)) {
        try codePerformanceData.entries.put(name, .{ .name = name });
    }
    const entry = codePerformanceData.entries.getPtr(name).?;
    entry.startNanoSeconds = std.time.nanoTimestamp();
}

pub fn endMeasure(name: []const u8, codePerformanceData: *CodePerformanceData) void {
    if (!MEASURE) return;
    if (!codePerformanceData.entries.contains(name)) {
        std.debug.print("missing startMeasure(1) for {s}", .{name});
        return;
    }
    const entry = codePerformanceData.entries.getPtr(name).?;
    if (entry.startNanoSeconds) |startTime| {
        entry.currentAddedTime += std.time.nanoTimestamp() - startTime;
        entry.startNanoSeconds = null;
    } else {
        std.debug.print("missing startMeasure(2) for {s}", .{name});
    }
}

pub fn evaluateTickData(codePerformanceData: *CodePerformanceData) void {
    var iterator = codePerformanceData.entries.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.lastMeasurement = @divFloor(entry.value_ptr.lastMeasurement * 63, 64) + @divFloor(entry.value_ptr.currentAddedTime, 64);
        entry.value_ptr.currentAddedTime = 0;
    }
}

pub fn paintData(state: *main.ChatSimState, startY: f32) !void {
    const performanceFontSize = 20.0;
    const onePixelYInVulkan = 2 / windowSdlZig.windowData.heightFloat;
    const onePixelXInVulkan = 2 / windowSdlZig.windowData.widthFloat;
    var iterator = state.codePerformanceData.entries.iterator();
    var yOffset: f32 = 0.0;
    while (iterator.next()) |entry| {
        const textWidth = fontVulkanZig.paintText(entry.key_ptr.*, .{ .x = -0.99, .y = startY + yOffset }, performanceFontSize, state) + onePixelXInVulkan * 5;
        _ = try fontVulkanZig.paintNumber(@intCast(entry.value_ptr.lastMeasurement), .{ .x = -0.99 + textWidth, .y = startY + yOffset }, performanceFontSize, state);
        yOffset += onePixelYInVulkan * performanceFontSize;
    }
}

pub fn printToConsole(state: *main.ChatSimState) void {
    if (!MEASURE) return;
    std.debug.print("Performance", .{});
    var iterator = state.codePerformanceData.entries.iterator();
    while (iterator.next()) |entry| {
        std.debug.print("  {s}: {d}\n", .{ entry.value_ptr.name, entry.value_ptr.lastMeasurement });
    }
}
