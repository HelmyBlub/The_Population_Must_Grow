const std = @import("std");
const vk = @cImport({
    @cDefine("VK_USE_PLATFORM_WIN32_KHR", "1");
    @cInclude("vulkan.h");
});
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const imageZig = @import("../image.zig");
const mapZig = @import("../map.zig");
const windowSdlZig = @import("../windowSdl.zig");

pub const VkBuildOptionsUx = struct {
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
    pub const MAX_VERTICES_TRIANGLES = 6 * 10;
    pub const MAX_VERTICES_LINES = 8 * 10;
};

pub fn init(state: *main.ChatSimState) !void {
    try createVertexBuffers(&state.vkState, state.allocator);
    try setupVertices(state);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory, null);
    allocator.free(vkState.buildOptionsUx.triangles.vertices);
    allocator.free(vkState.buildOptionsUx.lines.vertices);
}

fn createVertexBuffers(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.buildOptionsUx.triangles.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkBuildOptionsUx.MAX_VERTICES_TRIANGLES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkBuildOptionsUx.MAX_VERTICES_TRIANGLES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.triangles.vertexBuffer,
        &vkState.buildOptionsUx.triangles.vertexBufferMemory,
        vkState,
    );
    vkState.buildOptionsUx.lines.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkBuildOptionsUx.MAX_VERTICES_LINES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkBuildOptionsUx.MAX_VERTICES_LINES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.lines.vertexBuffer,
        &vkState.buildOptionsUx.lines.vertexBufferMemory,
        vkState,
    );

    std.debug.print("buildOptionsUx createVertexBuffer finished\n", .{});
}

pub fn setupVertices(state: *main.ChatSimState) !void {
    const triangles = &state.vkState.buildOptionsUx.triangles;
    const vulkanRectanlge = mapZig.MapRectangle{
        .pos = .{ .x = 0, .y = 0.85 },
        .width = 0.05,
        .height = 0.1,
    };
    triangles.verticeCount = 6;
    triangles.vertices[0] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = .{ 0, 0, 0 } };
    triangles.vertices[1] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y }, .color = .{ 0, 0, 0 } };
    triangles.vertices[2] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = .{ 0, 0, 0 } };
    triangles.vertices[3] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y }, .color = .{ 0, 0, 0 } };
    triangles.vertices[4] = .{ .pos = .{ vulkanRectanlge.pos.x + vulkanRectanlge.width, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = .{ 0, 0, 0 } };
    triangles.vertices[5] = .{ .pos = .{ vulkanRectanlge.pos.x, vulkanRectanlge.pos.y + vulkanRectanlge.height }, .color = .{ 0, 0, 0 } };
    try setupVertexDataForGPU(&state.vkState);
}

pub fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.buildOptionsUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.buildOptionsUx.triangles.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.ChatSimState) !void {
    if (state.vkState.buildOptionsUx.triangles.verticeCount <= 0) return;
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    const vertexBuffers: [1]vk.VkBuffer = .{vkState.buildOptionsUx.triangles.vertexBuffer};
    const offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.triangles.verticeCount), 1, 0, 0);
}
