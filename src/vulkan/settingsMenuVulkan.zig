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

pub const VkSettingsUx = struct {
    triangles: paintVulkanZig.VkTriangles = undefined,
    lines: paintVulkanZig.VkLines = undefined,
    sprites: paintVulkanZig.VkSprites = undefined,
    font: paintVulkanZig.VkFont = undefined,
    settingsIcon: UiRectangle = undefined,
    settingsMenuRectangle: UiRectangle = undefined,
    restart: struct {
        rec: UiRectangle = undefined,
        holdStartTime: ?i64 = null,
    } = undefined,
    volumeSliderRectangle: UiRectangle = undefined,
    menuOpen: bool = false,
    settingsIconHovered: bool = false,
    const UX_RECTANGLES = 16;
    const MAX_FONT_TOOLTIP = 100;
    pub const MAX_VERTICES_TRIANGLES = 6 * UX_RECTANGLES;
    pub const MAX_VERTICES_LINES = 8 * UX_RECTANGLES;
    pub const MAX_VERTICES_SPRITES = UX_RECTANGLES;
    pub const MAX_VERTICES_FONT = UX_RECTANGLES + MAX_FONT_TOOLTIP;
    const RESTART_HOLD_DURATION_MS = 3000;
};

const UiRectangle = struct {
    pos: main.Position = .{ .x = 0, .y = 0 },
    width: f32 = 0,
    height: f32 = 0,
};

pub fn onWindowResize(state: *main.GameState) !void {
    setupUiLocations(&state.vkState);
    try setupVertices(state);
}

pub fn setupUiLocations(vkState: *paintVulkanZig.Vk_State) void {
    const vulkanSpacingX = 10.0 / windowSdlZig.windowData.widthFloat;
    const vulkanSpacingY = 10.0 / windowSdlZig.windowData.heightFloat;

    const iconWidth = 80 / windowSdlZig.windowData.widthFloat;
    const iconHeight = 80 / windowSdlZig.windowData.heightFloat;
    vkState.settingsMenuUx.settingsIcon = .{
        .height = iconHeight,
        .width = iconWidth,
        .pos = .{
            .x = 1 - iconWidth - vulkanSpacingX,
            .y = -1 + vulkanSpacingY,
        },
    };

    const menuWidth = 510 / windowSdlZig.windowData.widthFloat;
    vkState.settingsMenuUx.settingsMenuRectangle = .{
        .height = 300 / windowSdlZig.windowData.heightFloat,
        .width = menuWidth,
        .pos = .{
            .x = 1 - menuWidth - vulkanSpacingX,
            .y = -1 + vulkanSpacingY + iconHeight,
        },
    };
    const settingsMenuRec = vkState.settingsMenuUx.settingsMenuRectangle;

    vkState.settingsMenuUx.restart.rec = .{
        .height = 80 / windowSdlZig.windowData.heightFloat,
        .width = menuWidth - vulkanSpacingX * 2,
        .pos = .{
            .x = settingsMenuRec.pos.x + vulkanSpacingX,
            .y = settingsMenuRec.pos.y + vulkanSpacingY,
        },
    };
}

fn initUi(state: *main.GameState) !void {
    state.vkState.settingsMenuUx.restart.holdStartTime = null;
    setupUiLocations(&state.vkState);
}

pub fn mouseMove(state: *main.GameState) !void {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(state.mouseInfo.currentPos.x, state.mouseInfo.currentPos.y);
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    const icon = settingsMenuUx.settingsIcon;
    if (icon.pos.x <= vulkanMousePos.x and icon.pos.x + icon.width >= vulkanMousePos.x and
        icon.pos.y <= vulkanMousePos.y and icon.pos.y + icon.height >= vulkanMousePos.y)
    {
        settingsMenuUx.settingsIconHovered = true;
        try setupVertices(state);
        return;
    }
    if (settingsMenuUx.settingsIconHovered) {
        settingsMenuUx.settingsIconHovered = false;
        try setupVertices(state);
    }
    if (!settingsMenuUx.menuOpen) return;

    const restartRec = settingsMenuUx.restart.rec;
    if (settingsMenuUx.restart.holdStartTime != null and (restartRec.pos.x > vulkanMousePos.x or restartRec.pos.x + restartRec.width < vulkanMousePos.x or
        restartRec.pos.y > vulkanMousePos.y or restartRec.pos.y + restartRec.height < vulkanMousePos.y))
    {
        settingsMenuUx.restart.holdStartTime = null;
        try setupVertices(state);
    }
}

/// returns true if a button was released
pub fn mouseUp(state: *main.GameState, mouseWindowPosition: main.PositionF32) !bool {
    _ = mouseWindowPosition;
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    if (settingsMenuUx.restart.holdStartTime != null) {
        settingsMenuUx.restart.holdStartTime = null;
        try setupVertices(state);
        return true;
    }
    return false;
}

/// returns true if a button was clicked
pub fn mouseDown(state: *main.GameState, mouseWindowPosition: main.PositionF32) !bool {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(mouseWindowPosition.x, mouseWindowPosition.y);
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    const icon = settingsMenuUx.settingsIcon;
    if (icon.pos.x <= vulkanMousePos.x and icon.pos.x + icon.width >= vulkanMousePos.x and
        icon.pos.y <= vulkanMousePos.y and icon.pos.y + icon.height >= vulkanMousePos.y)
    {
        settingsMenuUx.menuOpen = !settingsMenuUx.menuOpen;
        try setupVertices(state);
        return true;
    }
    if (!settingsMenuUx.menuOpen) return false;

    const restartRec = settingsMenuUx.restart.rec;
    if (restartRec.pos.x <= vulkanMousePos.x and restartRec.pos.x + restartRec.width >= vulkanMousePos.x and
        restartRec.pos.y <= vulkanMousePos.y and restartRec.pos.y + restartRec.height >= vulkanMousePos.y)
    {
        settingsMenuUx.restart.holdStartTime = std.time.milliTimestamp();
        return true;
    }
    const menuRec = settingsMenuUx.settingsMenuRectangle;
    if (menuRec.pos.x <= vulkanMousePos.x and menuRec.pos.x + menuRec.width >= vulkanMousePos.x and
        menuRec.pos.y <= vulkanMousePos.y and menuRec.pos.y + menuRec.height >= vulkanMousePos.y)
    {
        std.debug.print("check \n", .{});
        return true;
    }
    return false;
}

pub fn tick(state: *main.GameState) !void {
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    if (settingsMenuUx.restart.holdStartTime == null) return;
    const timeDiff = settingsMenuUx.restart.holdStartTime.? + VkSettingsUx.RESTART_HOLD_DURATION_MS - std.time.milliTimestamp();
    if (timeDiff < 0) {
        try main.deleteSaveAndRestart(state);
        settingsMenuUx.restart.holdStartTime = null;
    }
    try setupVertices(state);
}

pub fn init(state: *main.GameState) !void {
    try createVertexBuffers(&state.vkState, state.allocator);
    try initUi(state);
    try setupVertices(state);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory, null);
    allocator.free(vkState.settingsMenuUx.triangles.vertices);
    allocator.free(vkState.settingsMenuUx.lines.vertices);
    allocator.free(vkState.settingsMenuUx.sprites.vertices);
    allocator.free(vkState.settingsMenuUx.font.vertices);
}

fn createVertexBuffers(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    vkState.settingsMenuUx.triangles.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkSettingsUx.MAX_VERTICES_TRIANGLES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkSettingsUx.MAX_VERTICES_TRIANGLES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.settingsMenuUx.triangles.vertexBuffer,
        &vkState.settingsMenuUx.triangles.vertexBufferMemory,
        vkState,
    );
    vkState.settingsMenuUx.lines.vertices = try allocator.alloc(paintVulkanZig.ColoredVertex, VkSettingsUx.MAX_VERTICES_LINES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.ColoredVertex) * VkSettingsUx.MAX_VERTICES_LINES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.settingsMenuUx.lines.vertexBuffer,
        &vkState.settingsMenuUx.lines.vertexBufferMemory,
        vkState,
    );
    vkState.settingsMenuUx.sprites.vertices = try allocator.alloc(paintVulkanZig.SpriteVertex, VkSettingsUx.MAX_VERTICES_SPRITES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.SpriteVertex) * VkSettingsUx.MAX_VERTICES_SPRITES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.settingsMenuUx.sprites.vertexBuffer,
        &vkState.settingsMenuUx.sprites.vertexBufferMemory,
        vkState,
    );

    vkState.settingsMenuUx.font.vertices = try allocator.alloc(fontVulkanZig.FontVertex, VkSettingsUx.MAX_VERTICES_FONT);
    try paintVulkanZig.createBuffer(
        @sizeOf(fontVulkanZig.FontVertex) * VkSettingsUx.MAX_VERTICES_FONT,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.settingsMenuUx.font.vertexBuffer,
        &vkState.settingsMenuUx.font.vertexBufferMemory,
        vkState,
    );
}

pub fn setupVertices(state: *main.GameState) !void {
    const buttonFillColor: [3]f32 = .{ 0.7, 0.7, 0.7 };
    const borderColor: [3]f32 = .{ 0, 0, 0 };
    const color: [3]f32 = .{ 1, 1, 1 };
    const triangles = &state.vkState.settingsMenuUx.triangles;
    const lines = &state.vkState.settingsMenuUx.lines;
    const sprites = &state.vkState.settingsMenuUx.sprites;
    const font = &state.vkState.settingsMenuUx.font;
    triangles.verticeCount = 0;
    lines.verticeCount = 0;
    sprites.verticeCount = 0;
    font.verticeCount = 0;

    const settingsMenuUx = &state.vkState.settingsMenuUx;
    const icon = settingsMenuUx.settingsIcon;

    if (settingsMenuUx.settingsIconHovered) {
        setupVerticeForRectangle(icon, settingsMenuUx, color, borderColor);
    }

    sprites.vertices[sprites.verticeCount] = .{ .pos = .{ icon.pos.x, icon.pos.y }, .imageIndex = imageZig.IMAGE_ICON_SETTINGS, .width = icon.width, .height = icon.height };
    sprites.verticeCount += 1;

    if (settingsMenuUx.menuOpen) {
        const menuRec = settingsMenuUx.settingsMenuRectangle;
        setupVerticeForRectangle(menuRec, settingsMenuUx, color, borderColor);
        setupVerticeForRectangle(settingsMenuUx.restart.rec, settingsMenuUx, buttonFillColor, borderColor);
        if (settingsMenuUx.restart.holdStartTime) |time| {
            const timeDiff = @max(0, time + VkSettingsUx.RESTART_HOLD_DURATION_MS - std.time.milliTimestamp());
            const fillPerCent: f32 = 1 - @as(f32, @floatFromInt(timeDiff)) / VkSettingsUx.RESTART_HOLD_DURATION_MS;
            const holdRecColor: [3]f32 = .{ 0.2, 0.2, 0.2 };
            const fillRec: UiRectangle = .{
                .pos = .{
                    .x = settingsMenuUx.restart.rec.pos.x,
                    .y = settingsMenuUx.restart.rec.pos.y,
                },
                .width = settingsMenuUx.restart.rec.width * fillPerCent,
                .height = settingsMenuUx.restart.rec.height,
            };
            setupVerticeForRectangle(fillRec, settingsMenuUx, holdRecColor, borderColor);
        }
        const text = "Hold to Restart";
        const fontSize = 26;
        var width: f32 = 0;
        for (text) |char| {
            font.vertices[font.verticeCount] = fontVulkanZig.getCharFontVertex(char, .{
                .x = settingsMenuUx.restart.rec.pos.x + width,
                .y = settingsMenuUx.restart.rec.pos.y + settingsMenuUx.restart.rec.height / 5.0,
            }, fontSize);
            width += font.vertices[font.verticeCount].texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSize * 0.8;
            font.verticeCount += 1;
        }
    }

    try setupVertexDataForGPU(&state.vkState);
}

fn setupVerticeForRectangle(rec: UiRectangle, settingsMenuUx: *VkSettingsUx, fillColor: [3]f32, borderColor: [3]f32) void {
    const triangles = &settingsMenuUx.triangles;
    triangles.vertices[triangles.verticeCount + 0] = .{ .pos = .{ rec.pos.x, rec.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 1] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 2] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y + rec.height }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 3] = .{ .pos = .{ rec.pos.x, rec.pos.y }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 4] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y + rec.height }, .color = fillColor };
    triangles.vertices[triangles.verticeCount + 5] = .{ .pos = .{ rec.pos.x, rec.pos.y + rec.height }, .color = fillColor };
    triangles.verticeCount += 6;

    const lines = &settingsMenuUx.lines;
    lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ rec.pos.x, rec.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 2] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y }, .color = borderColor };
    lines.vertices[lines.verticeCount + 3] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y + rec.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 4] = .{ .pos = .{ rec.pos.x + rec.width, rec.pos.y + rec.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 5] = .{ .pos = .{ rec.pos.x, rec.pos.y + rec.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 6] = .{ .pos = .{ rec.pos.x, rec.pos.y + rec.height }, .color = borderColor };
    lines.vertices[lines.verticeCount + 7] = .{ .pos = .{ rec.pos.x, rec.pos.y }, .color = borderColor };
    lines.verticeCount += 8;
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.settingsMenuUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    var gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.settingsMenuUx.triangles.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.settingsMenuUx.lines.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    gpu_vertices = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.settingsMenuUx.lines.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.settingsMenuUx.sprites.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesSprite: [*]paintVulkanZig.SpriteVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesSprite, vkState.settingsMenuUx.sprites.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.settingsMenuUx.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesFont: [*]fontVulkanZig.FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesFont, vkState.settingsMenuUx.font.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    var vertexBuffers: [1]vk.VkBuffer = .{vkState.settingsMenuUx.triangles.vertexBuffer};
    var offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.settingsMenuUx.triangles.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.spriteGraphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.sprites.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.settingsMenuUx.sprites.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.font.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.settingsMenuUx.font.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.lines.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.settingsMenuUx.lines.verticeCount), 1, 0, 0);
}
