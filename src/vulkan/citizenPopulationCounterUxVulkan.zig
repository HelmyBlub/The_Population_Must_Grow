const std = @import("std");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const fontVulkanZig = @import("fontVulkan.zig");
const imageZig = @import("../image.zig");
const mapZig = @import("../map.zig");
const inputZig = @import("../input.zig");
const windowSdlZig = @import("../windowSdl.zig");
const countryPopulationDataZig = @import("../countryPopulationData.zig");
const steamZig = @import("../steam.zig");

pub const VkCitizenPopulationCounterUx = struct {
    triangles: paintVulkanZig.VkTriangles = undefined,
    lines: paintVulkanZig.VkLines = undefined,
    font: fontVulkanZig.VkFont = undefined,
    nextCountryPopulationIndex: usize = countryPopulationDataZig.WORLD_POPULATION.len,
    surpassedMessageDisplayTime: i64 = 0,
    houseBuildPathMessageDisplayTime: ?i64 = null,
    const MAX_VERTICES_TRIANGLES = 6 * 2;
    const MAX_VERTICES_LINES = 8 + 8;
    const MAX_VERTICES_FONT = 200;
    const MESSAGE_SURPASSED_DURATION = 4000;
    const MESSAGE_PLACE_BESIDE_PATH_DURATION = 2000;
};

pub fn init(state: *main.GameState) !void {
    try createVertexBuffers(&state.vkState, state.allocator);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.citizenPopulationCounterUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.citizenPopulationCounterUx.lines.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.citizenPopulationCounterUx.font.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.lines.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.font.vertexBufferMemory, null);
    allocator.free(vkState.citizenPopulationCounterUx.triangles.vertices);
    allocator.free(vkState.citizenPopulationCounterUx.lines.vertices);
    allocator.free(vkState.citizenPopulationCounterUx.font.vertices);
}

fn createVertexBuffers(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.citizenPopulationCounterUx.triangles.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkCitizenPopulationCounterUx.MAX_VERTICES_TRIANGLES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkCitizenPopulationCounterUx.MAX_VERTICES_TRIANGLES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.citizenPopulationCounterUx.triangles.vertexBuffer,
        &vkState.citizenPopulationCounterUx.triangles.vertexBufferMemory,
        vkState,
    );
    vkState.citizenPopulationCounterUx.lines.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkCitizenPopulationCounterUx.MAX_VERTICES_LINES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkCitizenPopulationCounterUx.MAX_VERTICES_LINES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.citizenPopulationCounterUx.lines.vertexBuffer,
        &vkState.citizenPopulationCounterUx.lines.vertexBufferMemory,
        vkState,
    );

    vkState.citizenPopulationCounterUx.font.vertices = try allocator.alloc(fontVulkanZig.FontVertex, VkCitizenPopulationCounterUx.MAX_VERTICES_FONT);
    try paintVulkanZig.createBuffer(
        @sizeOf(fontVulkanZig.FontVertex) * VkCitizenPopulationCounterUx.MAX_VERTICES_FONT,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.citizenPopulationCounterUx.font.vertexBuffer,
        &vkState.citizenPopulationCounterUx.font.vertexBufferMemory,
        vkState,
    );
}

pub fn updateCountryPopulationIndexOnGameLoad(state: *main.GameState) void {
    while (state.vkState.citizenPopulationCounterUx.nextCountryPopulationIndex > 0 and state.citizenCounter > countryPopulationDataZig.WORLD_POPULATION[state.vkState.citizenPopulationCounterUx.nextCountryPopulationIndex - 1].population) {
        state.vkState.citizenPopulationCounterUx.nextCountryPopulationIndex -= 1;
    }
}

pub fn setupVertices(state: *main.GameState) !void {
    const fillColor: [3]f32 = .{ 0.25, 0.25, 0.25 };
    const borderColor: [3]f32 = .{ 0, 0, 0 };
    const popCounterUx = &state.vkState.citizenPopulationCounterUx;
    const triangles = &popCounterUx.triangles;
    const lines = &popCounterUx.lines;
    const font = &popCounterUx.font;
    const onePixelXInVulkan = 2 / windowSdlZig.windowData.widthFloat;
    const onePixelYInVulkan = 2 / windowSdlZig.windowData.heightFloat;

    triangles.verticeCount = 0;
    lines.verticeCount = 0;
    font.verticeCount = 0;

    const rectangleVulkanWidth = 1.0;
    const fontSize = 50.0 * state.vkState.uiSizeFactor;
    const fontSizeSmaller: f32 = 25 * state.vkState.uiSizeFactor;
    const populationRectangle: mapZig.MapRectangle = .{
        .pos = .{ .x = -rectangleVulkanWidth / 2.0, .y = -1.0 + onePixelYInVulkan * fontSizeSmaller },
        .width = rectangleVulkanWidth,
        .height = fontSize * onePixelYInVulkan,
    };
    var fillPerCent: f32 = 1;
    var nextCountryPopulationGoal: ?countryPopulationDataZig.CountryData = null;
    if (popCounterUx.nextCountryPopulationIndex > 0) {
        nextCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex - 1];
        fillPerCent = @as(f32, @floatFromInt(state.citizenCounter)) / @as(f32, @floatFromInt(nextCountryPopulationGoal.?.population));
        if (fillPerCent > 1) {
            popCounterUx.nextCountryPopulationIndex -|= 1;
            try steamZig.setAchievement(popCounterUx.nextCountryPopulationIndex, state);
            popCounterUx.surpassedMessageDisplayTime = std.time.milliTimestamp();
            fillPerCent = 1;
            if (popCounterUx.nextCountryPopulationIndex > 0) {
                nextCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex - 1];
            } else {
                nextCountryPopulationGoal = null;
            }
        }
    }
    var optLastCountryPopulationGoal: ?countryPopulationDataZig.CountryData = null;
    if (popCounterUx.nextCountryPopulationIndex < countryPopulationDataZig.WORLD_POPULATION.len) {
        optLastCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex];
    }

    triangles.vertices[triangles.verticeCount + 0] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 1] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width * fillPerCent, populationRectangle.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 2] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width * fillPerCent, populationRectangle.pos.y + populationRectangle.height }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 3] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 4] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width * fillPerCent, populationRectangle.pos.y + populationRectangle.height }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 5] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y + populationRectangle.height }, .color = fillColor };
    triangles.verticeCount += 6;

    lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width, populationRectangle.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 2] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width, populationRectangle.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 3] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 4] = .{ .pos = .{ populationRectangle.pos.x + populationRectangle.width, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 5] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 6] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 7] = .{ .pos = .{ populationRectangle.pos.x, populationRectangle.pos.y }, .color = borderColor };
    lines.verticeCount += 8;

    const citizenTextWidth = fontVulkanZig.paintText("Citizens: ", .{
        .x = populationRectangle.pos.x,
        .y = populationRectangle.pos.y,
    }, fontSize, &state.vkState.citizenPopulationCounterUx.font);
    _ = try fontVulkanZig.paintNumber(state.citizenCounter, .{
        .x = populationRectangle.pos.x + citizenTextWidth,
        .y = populationRectangle.pos.y,
    }, fontSize, &state.vkState.citizenPopulationCounterUx.font);

    const citizenPerMinuteTextWidth = fontVulkanZig.paintText("Citizen Grows Per Minute: ", .{
        .x = populationRectangle.pos.x,
        .y = populationRectangle.pos.y + onePixelYInVulkan * fontSize,
    }, fontSizeSmaller, &state.vkState.citizenPopulationCounterUx.font);
    _ = try fontVulkanZig.paintNumber(@as(u32, @intFromFloat(state.citizensPerMinuteCounter)), .{
        .x = populationRectangle.pos.x + citizenPerMinuteTextWidth,
        .y = populationRectangle.pos.y + onePixelYInVulkan * fontSize,
    }, fontSizeSmaller, &state.vkState.citizenPopulationCounterUx.font);

    const timeXOffset = onePixelXInVulkan * fontSize * 5;
    const timeTextWidth = fontVulkanZig.paintText("Time: ", .{ .x = populationRectangle.pos.x - timeXOffset, .y = populationRectangle.pos.y }, fontSizeSmaller, &state.vkState.citizenPopulationCounterUx.font);
    _ = try fontVulkanZig.paintNumber(@divFloor(state.gameTimeMs, 1000), .{ .x = populationRectangle.pos.x - timeXOffset + timeTextWidth, .y = populationRectangle.pos.y }, fontSizeSmaller, &state.vkState.citizenPopulationCounterUx.font);

    if (optLastCountryPopulationGoal) |lastCountryPopulationGoal| {
        if (nextCountryPopulationGoal) |popGoal| {
            _ = fontVulkanZig.paintText(popGoal.name, .{
                .x = populationRectangle.pos.x + populationRectangle.width,
                .y = populationRectangle.pos.y,
            }, fontSize / 2.0, &state.vkState.citizenPopulationCounterUx.font);
            _ = try fontVulkanZig.paintNumber(popGoal.population, .{
                .x = populationRectangle.pos.x + populationRectangle.width,
                .y = populationRectangle.pos.y + fontSize / 2.0 * onePixelYInVulkan,
            }, fontSize / 2.0, &state.vkState.citizenPopulationCounterUx.font);
        }

        const timeDiffSurpassed = popCounterUx.surpassedMessageDisplayTime + VkCitizenPopulationCounterUx.MESSAGE_SURPASSED_DURATION -| std.time.milliTimestamp();
        if (timeDiffSurpassed > 0) {
            const surpassedOffsetY: f32 = (1.0 - @as(f32, @floatFromInt(timeDiffSurpassed)) / VkCitizenPopulationCounterUx.MESSAGE_SURPASSED_DURATION) * onePixelYInVulkan * 100.0;
            _ = fontVulkanZig.paintText("surpassed population of country: ", .{
                .x = populationRectangle.pos.x,
                .y = -surpassedOffsetY,
            }, fontSize, &state.vkState.citizenPopulationCounterUx.font);

            _ = fontVulkanZig.paintText(lastCountryPopulationGoal.name, .{
                .x = populationRectangle.pos.x,
                .y = -surpassedOffsetY + fontSize * onePixelYInVulkan,
            }, fontSize, &state.vkState.citizenPopulationCounterUx.font);
        }

        const lastCountryFontSize = fontSize / 2.5;
        const upperBound: f32 = if (nextCountryPopulationGoal) |popGoal| @as(f32, @floatFromInt(popGoal.population)) else @as(f32, @floatFromInt(state.citizenCounter));
        const lastXPerCent: f32 = @as(f32, @floatFromInt(lastCountryPopulationGoal.population)) / upperBound;
        const lastCountryX = populationRectangle.pos.x + populationRectangle.width * lastXPerCent;
        lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ lastCountryX, populationRectangle.pos.y - lastCountryFontSize * onePixelYInVulkan }, .color = borderColor };
        lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ lastCountryX, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
        lines.verticeCount += 2;
        _ = fontVulkanZig.paintText(lastCountryPopulationGoal.name, .{
            .x = lastCountryX,
            .y = populationRectangle.pos.y - lastCountryFontSize * onePixelYInVulkan,
        }, lastCountryFontSize, &state.vkState.citizenPopulationCounterUx.font);
    }
    if (state.vkState.citizenPopulationCounterUx.houseBuildPathMessageDisplayTime) |houseBuildPathMessageDisplayTime| {
        const timeDiffHouseMessage = houseBuildPathMessageDisplayTime + VkCitizenPopulationCounterUx.MESSAGE_PLACE_BESIDE_PATH_DURATION -| std.time.milliTimestamp();
        const offsetY: f32 = (1.0 - @as(f32, @floatFromInt(timeDiffHouseMessage)) / VkCitizenPopulationCounterUx.MESSAGE_PLACE_BESIDE_PATH_DURATION) * onePixelYInVulkan * 100.0;
        _ = fontVulkanZig.paintText("must be placed beside a Path", .{
            .x = -onePixelXInVulkan * fontSize * 10,
            .y = -offsetY,
        }, fontSize, &state.vkState.citizenPopulationCounterUx.font);
        if (timeDiffHouseMessage <= 0) state.vkState.citizenPopulationCounterUx.houseBuildPathMessageDisplayTime = null;
    }

    try setupVertexDataForGPU(&state.vkState);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.citizenPopulationCounterUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    var gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.citizenPopulationCounterUx.triangles.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.triangles.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.lines.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.citizenPopulationCounterUx.lines.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    gpu_vertices = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.citizenPopulationCounterUx.lines.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.lines.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.font.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.citizenPopulationCounterUx.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesFont: [*]fontVulkanZig.FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesFont, vkState.citizenPopulationCounterUx.font.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.citizenPopulationCounterUx.font.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    try setupVertices(state);
    if (state.vkState.citizenPopulationCounterUx.triangles.verticeCount <= 0) return;
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    var vertexBuffers: [1]vk.VkBuffer = .{vkState.citizenPopulationCounterUx.triangles.vertexBuffer};
    var offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.citizenPopulationCounterUx.triangles.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    vertexBuffers = .{vkState.citizenPopulationCounterUx.font.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.citizenPopulationCounterUx.font.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    vertexBuffers = .{vkState.citizenPopulationCounterUx.lines.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.citizenPopulationCounterUx.lines.verticeCount), 1, 0, 0);
}
