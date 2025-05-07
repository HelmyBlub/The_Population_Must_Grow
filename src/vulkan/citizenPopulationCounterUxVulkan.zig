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

pub const VkCitizenPopulationCounterUx = struct {
    triangles: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []paintVulkanZig.ColoredVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    lines: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []paintVulkanZig.ColoredVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    font: struct {
        vertexBuffer: vk.VkBuffer = undefined,
        vertexBufferMemory: vk.VkDeviceMemory = undefined,
        vertices: []fontVulkanZig.FontVertex = undefined,
        verticeCount: usize = 0,
    } = undefined,
    nextCountryPopulationIndex: usize = countryPopulationDataZig.WORLD_POPULATION.len - 1,
    surpassedMessageDisplayTime: i64 = 0,
    const MAX_VERTICES_TRIANGLES = 6 * 2;
    const MAX_VERTICES_LINES = 8 + 8;
    const MAX_VERTICES_FONT = 200;
    const MESSAGE_SURPASSED_DURATION = 5000;
};

pub fn init(state: *main.ChatSimState) !void {
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

    std.debug.print("citizenPopulationCounterUx createVertexBuffer finished\n", .{});
}

pub fn setupVertices(state: *main.ChatSimState) !void {
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
    const fontSize = 50.0;
    const populationRectangle: mapZig.MapRectangle = .{
        .pos = .{ .x = -rectangleVulkanWidth / 2.0, .y = -1.0 + onePixelYInVulkan * 20.0 },
        .width = rectangleVulkanWidth,
        .height = fontSize * onePixelYInVulkan,
    };
    var nextCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex];
    var fillPerCent: f32 = @as(f32, @floatFromInt(state.citizenCounter)) / @as(f32, @floatFromInt(nextCountryPopulationGoal.population));
    if (fillPerCent > 1) {
        popCounterUx.nextCountryPopulationIndex -|= 1;
        popCounterUx.surpassedMessageDisplayTime = std.time.milliTimestamp();
        fillPerCent = 1;
        nextCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex];
    }
    var optLastCountryPopulationGoal: ?countryPopulationDataZig.CountryData = null;
    if (popCounterUx.nextCountryPopulationIndex + 1 < countryPopulationDataZig.WORLD_POPULATION.len) {
        optLastCountryPopulationGoal = countryPopulationDataZig.WORLD_POPULATION[popCounterUx.nextCountryPopulationIndex + 1];
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

    const citizenTextWidth = paintText("Citizens: ", .{
        .x = populationRectangle.pos.x,
        .y = populationRectangle.pos.y,
    }, fontSize, state);
    _ = try paintNumber(@intCast(state.citizenCounter), .{
        .x = populationRectangle.pos.x + citizenTextWidth,
        .y = populationRectangle.pos.y,
    }, fontSize, state);

    const citizenPerMinuteTextWidth = paintText("Citizen Grows Per Minute: ", .{
        .x = populationRectangle.pos.x,
        .y = populationRectangle.pos.y + onePixelYInVulkan * fontSize,
    }, 25, state);
    _ = try paintNumber(@intFromFloat(state.citizensPerMinuteCounter), .{
        .x = populationRectangle.pos.x + citizenPerMinuteTextWidth,
        .y = populationRectangle.pos.y + onePixelYInVulkan * fontSize,
    }, 25, state);

    const timeXOffset = onePixelXInVulkan * fontSize * 4;
    const timeTextWidth = paintText("Time: ", .{ .x = populationRectangle.pos.x - timeXOffset, .y = populationRectangle.pos.y }, 25, state);
    _ = try paintNumber(@divFloor(state.gameTimeMs, 1000), .{ .x = populationRectangle.pos.x - timeXOffset + timeTextWidth, .y = populationRectangle.pos.y }, 25, state);

    _ = paintText(nextCountryPopulationGoal.name, .{
        .x = populationRectangle.pos.x + populationRectangle.width,
        .y = populationRectangle.pos.y,
    }, fontSize / 2.0, state);
    _ = try paintNumber(@intCast(nextCountryPopulationGoal.population), .{
        .x = populationRectangle.pos.x + populationRectangle.width,
        .y = populationRectangle.pos.y + fontSize / 2.0 * onePixelYInVulkan,
    }, fontSize / 2.0, state);

    if (optLastCountryPopulationGoal) |lastCountryPopulationGoal| {
        const timeDiffSurpassed = popCounterUx.surpassedMessageDisplayTime + VkCitizenPopulationCounterUx.MESSAGE_SURPASSED_DURATION -| std.time.milliTimestamp();
        if (timeDiffSurpassed > 0) {
            const surpassedOffsetY: f32 = (1.0 - @as(f32, @floatFromInt(timeDiffSurpassed)) / VkCitizenPopulationCounterUx.MESSAGE_SURPASSED_DURATION) * onePixelYInVulkan * 100.0;
            _ = paintText("surpassed population of country: ", .{
                .x = populationRectangle.pos.x,
                .y = -surpassedOffsetY,
            }, fontSize, state);

            _ = paintText(lastCountryPopulationGoal.name, .{
                .x = populationRectangle.pos.x,
                .y = -surpassedOffsetY + fontSize * onePixelYInVulkan,
            }, fontSize, state);
        }

        const lastCountryFontSize = fontSize / 2.5;
        const lastXPerCent: f32 = @as(f32, @floatFromInt(lastCountryPopulationGoal.population)) / @as(f32, @floatFromInt(nextCountryPopulationGoal.population));
        const lastCountryX = populationRectangle.pos.x + populationRectangle.width * lastXPerCent;
        lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ lastCountryX, populationRectangle.pos.y - lastCountryFontSize * onePixelYInVulkan }, .color = borderColor };
        lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ lastCountryX, populationRectangle.pos.y + populationRectangle.height }, .color = borderColor };
        lines.verticeCount += 2;
        _ = paintText(lastCountryPopulationGoal.name, .{
            .x = lastCountryX,
            .y = populationRectangle.pos.y - lastCountryFontSize * onePixelYInVulkan,
        }, lastCountryFontSize, state);
    }

    try setupVertexDataForGPU(&state.vkState);
}

/// returns vulkan surface width of text
fn paintText(chars: []const u8, vulkanSurfacePosition: main.Position, fontSize: f32, state: *main.ChatSimState) f32 {
    var texX: f32 = 0;
    var texWidth: f32 = 0;
    var xOffset: f32 = 0;
    for (chars) |char| {
        if (state.vkState.citizenPopulationCounterUx.font.verticeCount >= VkCitizenPopulationCounterUx.MAX_VERTICES_FONT) break;
        fontVulkanZig.charToTexCoords(char, &texX, &texWidth);
        state.vkState.citizenPopulationCounterUx.font.vertices[state.vkState.citizenPopulationCounterUx.font.verticeCount] = .{
            .pos = .{ vulkanSurfacePosition.x + xOffset, vulkanSurfacePosition.y },
            .color = .{ 1, 0, 0 },
            .texX = texX,
            .texWidth = texWidth,
            .size = fontSize,
        };
        xOffset += texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
        state.vkState.citizenPopulationCounterUx.font.verticeCount += 1;
    }
    return xOffset;
}

fn paintNumber(number: u32, vulkanSurfacePosition: main.Position, fontSize: f32, state: *main.ChatSimState) !f32 {
    const max_len = 20;
    var buf: [max_len]u8 = undefined;
    const numberAsString = try std.fmt.bufPrint(&buf, "{}", .{number});
    var texX: f32 = 0;
    var texWidth: f32 = 0;
    var xOffset: f32 = 0;
    const spacingPosition = (numberAsString.len + 2) % 3;
    const spacing = 20 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
    for (numberAsString, 0..) |char, i| {
        if (state.vkState.citizenPopulationCounterUx.font.verticeCount >= VkCitizenPopulationCounterUx.MAX_VERTICES_FONT) break;
        fontVulkanZig.charToTexCoords(char, &texX, &texWidth);
        state.vkState.citizenPopulationCounterUx.font.vertices[state.vkState.citizenPopulationCounterUx.font.verticeCount] = .{
            .pos = .{ vulkanSurfacePosition.x + xOffset, vulkanSurfacePosition.y },
            .color = .{ 1, 0, 0 },
            .texX = texX,
            .texWidth = texWidth,
            .size = fontSize,
        };
        xOffset += texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
        if (i % 3 == spacingPosition) xOffset += spacing;
        state.vkState.citizenPopulationCounterUx.font.verticeCount += 1;
    }
    return xOffset;
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

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
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
