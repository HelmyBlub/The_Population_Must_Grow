const std = @import("std");
const main = @import("main.zig");
const fontVulkanZig = @import("vulkan/fontVulkan.zig");
const windowSdlZig = @import("windowSdl.zig");

pub const CodePerformanceData = struct {
    entries: std.StringArrayHashMap(CodePerformanceEntry),
};

pub const CodePerformanceEntry = struct {
    name: []const u8,
    startMicroSeconds: ?i64 = null,
    ///micro seconde
    currentAddedTime: i64 = 0,
    lastMeasurement: i64 = 0,
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
    if (!codePerformanceData.entries.contains(name)) {
        try codePerformanceData.entries.put(name, .{ .name = name });
    }
    const entry = codePerformanceData.entries.getPtr(name).?;
    entry.startMicroSeconds = std.time.microTimestamp();
}

pub fn endMeasure(name: []const u8, codePerformanceData: *CodePerformanceData) void {
    if (!codePerformanceData.entries.contains(name)) {
        std.debug.print("missing startMeasure(1) for {s}", .{name});
        return;
    }
    const entry = codePerformanceData.entries.getPtr(name).?;
    if (entry.startMicroSeconds) |startTime| {
        entry.currentAddedTime += std.time.microTimestamp() - startTime;
        entry.startMicroSeconds = null;
    } else {
        std.debug.print("missing startMeasure(2) for {s}", .{name});
    }
}

pub fn evaluateTickData(codePerformanceData: *CodePerformanceData) void {
    var iterator = codePerformanceData.entries.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.lastMeasurement = entry.value_ptr.currentAddedTime;
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
