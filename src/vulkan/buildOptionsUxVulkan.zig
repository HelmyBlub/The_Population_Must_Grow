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

pub const VkBuildOptionsUx = struct {
    triangles: paintVulkanZig.VkTriangles = undefined,
    lines: paintVulkanZig.VkLines = undefined,
    sprites: paintVulkanZig.VkSprites = undefined,
    font: fontVulkanZig.VkFont = undefined,
    selectedButtonIndex: usize = 0,
    mouseHoverButtonIndex: ?usize = null,
    uiButtons: []UiButton = undefined,
    const UX_RECTANGLES = 16;
    const MAX_FONT_TOOLTIP = 200;
    pub const MAX_VERTICES_TRIANGLES = 6 * UX_RECTANGLES;
    pub const MAX_VERTICES_LINES = 8 * UX_RECTANGLES;
    pub const MAX_VERTICES_SPRITES = UX_RECTANGLES;
    pub const MAX_VERTICES_FONT = UX_RECTANGLES + MAX_FONT_TOOLTIP;
};

const UiButtonFill = enum {
    empty,
    imageIndex,
    text,
};

const UiButtonFillData = union(UiButtonFill) {
    empty,
    imageIndex: u8,
    text: []const u8,
};

const UiButtonType = enum {
    action,
    display,
};

const UiButtonDisplay = enum {
    speed,
    zoom,
};

const UiButtonTypeData = union(UiButtonType) {
    action: inputZig.ActionType,
    display: UiButtonDisplay,
};

const UiButton = struct {
    pos: main.Position = .{ .x = 0, .y = 0 },
    width: f32 = 0,
    height: f32 = 0,
    fill: UiButtonFillData,
    type: UiButtonTypeData,
    tooltip: [][]const u8,
};

pub fn onWindowResize(state: *main.GameState) !void {
    setupUiButtonLocations(&state.vkState);
    try setupVertices(state);
}

pub fn setupUiButtonLocations(vkState: *paintVulkanZig.Vk_State) void {
    const sizePixels = 80.0;
    const spacingPixels = 5.0;
    const vulkanWidth = sizePixels / windowSdlZig.windowData.widthFloat;
    const vulkanHeight = sizePixels / windowSdlZig.windowData.heightFloat;
    const vulkanSpacing = spacingPixels / windowSdlZig.windowData.widthFloat;
    const posY = 0.99 - vulkanHeight;
    const buildButtons = 9;
    const posX: f32 = -(vulkanWidth + vulkanSpacing) * buildButtons / 2.0;

    for (vkState.buildOptionsUx.uiButtons, 0..) |*uiButton, index| {
        switch (uiButton.type) {
            .action => |actionType| {
                switch (actionType) {
                    .speedDown => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * @as(f32, @floatFromInt(index + 1)), .y = posY + vulkanHeight / 2 };
                        uiButton.width = vulkanWidth;
                        uiButton.height = vulkanHeight / 2;
                    },
                    .speedUp => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * @as(f32, @floatFromInt(index + 2)), .y = posY };
                        uiButton.width = vulkanWidth;
                        uiButton.height = vulkanHeight / 2;
                    },
                    .zoomIn => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * -7, .y = posY + vulkanHeight / 2 };
                        uiButton.width = vulkanWidth;
                        uiButton.height = vulkanHeight / 2;
                    },
                    .zoomOut => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * -7, .y = posY };
                        uiButton.width = vulkanWidth;
                        uiButton.height = vulkanHeight / 2;
                    },
                    else => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * @as(f32, @floatFromInt(index)), .y = posY };
                        uiButton.width = vulkanWidth;
                        uiButton.height = vulkanHeight;
                    },
                }
            },
            .display => |display| {
                switch (display) {
                    .speed => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * @as(f32, @floatFromInt(index + 1)), .y = posY };
                        uiButton.width = vulkanWidth * 5;
                        uiButton.height = vulkanHeight;
                    },
                    .zoom => {
                        uiButton.pos = .{ .x = posX + (vulkanWidth + vulkanSpacing) * -6, .y = posY };
                        uiButton.width = vulkanWidth * 5;
                        uiButton.height = vulkanHeight;
                    },
                }
            },
        }
    }
}

fn initUiButtons(state: *main.GameState) !void {
    const buttonCountMax = 15;
    state.vkState.buildOptionsUx.uiButtons = try state.allocator.alloc(UiButton, buttonCountMax);
    var buttonCounter: usize = 0;

    var tooltip = try state.allocator.alloc([]const u8, 3);
    tooltip[0] = "Path:";
    tooltip[1] = "Hold Mouse to paint a Path";
    tooltip[2] = "Path required for Houses";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildPath },
        .fill = .{ .imageIndex = imageZig.IMAGE_PATH },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 5);
    tooltip[0] = "House:";
    tooltip[2] = "Click Mouse to place a House";
    tooltip[1] = "Must be placed beside a Path";
    tooltip[3] = "Requires 1 Tree";
    tooltip[4] = "Produces 1 Citizen";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildHouse },
        .fill = .{ .imageIndex = imageZig.IMAGE_HOUSE },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 3);
    tooltip[0] = "Tree Area:";
    tooltip[1] = "Drag Area with Mouse for Tree planting";
    tooltip[2] = "Each Tree fully grows in 10 seconds";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildTreeArea },
        .fill = .{ .imageIndex = imageZig.IMAGE_ICON_TREE_AREA },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 4);
    tooltip[0] = "House Area:";
    tooltip[1] = "Drag Area with Mouse for House contruction";
    tooltip[2] = "Each House requires 1 Tree";
    tooltip[3] = "Each House produces 1 Citizen";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildHouseArea },
        .fill = .{ .imageIndex = imageZig.IMAGE_ICON_HOUSE_AREA },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 4);
    tooltip[0] = "Potato Fields Area:";
    tooltip[1] = "Drag Area with Mouse for Potato Fields";
    tooltip[2] = "Each Potato Field Produces a Potato every 10 seconds";
    tooltip[3] = "Each Citizen wants to eat a Potato every 30 seconds";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildPotatoFarmArea },
        .fill = .{ .imageIndex = imageZig.IMAGE_POTATO },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 4);
    tooltip[0] = "Copy Paste:";
    tooltip[1] = "First Drag Area with Mouse to Mark Area to Copy";
    tooltip[2] = "Second select Area to Paste to";
    tooltip[3] = "Right Mouse Button: Reset Area";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.copyPaste },
        .fill = .{ .imageIndex = imageZig.IMAGE_ICON_COPY_PASTE },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 6);
    tooltip[0] = "Big House Area:";
    tooltip[1] = "Drag Area with Mouse for Big House contruction";
    tooltip[2] = "Each Big House requires 16 Trees";
    tooltip[3] = "Each Big House produces 8 Citizen";
    tooltip[4] = "Size: 2x2";
    tooltip[5] = "Can be placed over Houses to replace them";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.buildBigHouseArea },
        .fill = .{ .imageIndex = imageZig.IMAGE_BIG_HOUSE },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 4);
    tooltip[0] = "Delete Area:";
    tooltip[1] = "Drag Area with Mouse to delete everything inside";
    tooltip[2] = "Deletes instantly";
    tooltip[3] = "Will not delete when only 1 citizen left";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.remove },
        .fill = .{ .imageIndex = imageZig.IMAGE_ICON_DELETE },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Move back to world spawn";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.cameraToWorldCenter },
        .fill = .{ .imageIndex = imageZig.IMAGE_CITIZEN_PUPIL1 },
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Speed x2";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.speedUp },
        .fill = .empty,
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Speed Halved";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.speedDown },
        .fill = .empty,
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 2);
    tooltip[0] = "Current Speed";
    tooltip[1] = "Can Limit Speed if FPS low.";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .fill = .empty,
        .tooltip = tooltip,
        .type = .{ .display = .speed },
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Zoom In";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.zoomIn },
        .fill = .empty,
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Zoom Out";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .type = .{ .action = inputZig.ActionType.zoomOut },
        .fill = .empty,
        .tooltip = tooltip,
    };
    buttonCounter += 1;

    tooltip = try state.allocator.alloc([]const u8, 1);
    tooltip[0] = "Current Zoom";
    state.vkState.buildOptionsUx.uiButtons[buttonCounter] = UiButton{
        .fill = .empty,
        .tooltip = tooltip,
        .type = .{ .display = .zoom },
    };
    buttonCounter += 1;

    setupUiButtonLocations(&state.vkState);
}

pub fn mouseMove(state: *main.GameState) !void {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(state.mouseInfo.currentPos.x, state.mouseInfo.currentPos.y);
    for (state.vkState.buildOptionsUx.uiButtons, 0..) |uiButton, index| {
        if (uiButton.pos.x <= vulkanMousePos.x and uiButton.pos.x + uiButton.width >= vulkanMousePos.x and
            uiButton.pos.y <= vulkanMousePos.y and uiButton.pos.y + uiButton.height >= vulkanMousePos.y)
        {
            state.vkState.buildOptionsUx.mouseHoverButtonIndex = index;
            try setupVertices(state);
            return;
        }
    }
    state.vkState.buildOptionsUx.mouseHoverButtonIndex = null;
    try setupVertices(state);
}

/// returns true if a button was clicked
pub fn mouseClick(state: *main.GameState, mouseWindowPosition: main.PositionF32) !bool {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(mouseWindowPosition.x, mouseWindowPosition.y);
    for (state.vkState.buildOptionsUx.uiButtons) |uiButton| {
        if (uiButton.pos.x <= vulkanMousePos.x and uiButton.pos.x + uiButton.width >= vulkanMousePos.x and
            uiButton.pos.y <= vulkanMousePos.y and uiButton.pos.y + uiButton.height >= vulkanMousePos.y)
        {
            if (uiButton.type == .action) {
                try setupVertices(state);
                try inputZig.executeAction(uiButton.type.action, state);
            }
            return true;
        }
    }
    return false;
}

pub fn init(state: *main.GameState) !void {
    try createVertexBuffers(&state.vkState, state.allocator);
    try createGraphicsPipeline(&state.vkState, state.allocator);
    try initUiButtons(state);
    try setupVertices(state);
}

pub fn destroy(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) void {
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBuffer, null);
    vk.vkDestroyBuffer(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBuffer, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory, null);
    vk.vkFreeMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory, null);
    allocator.free(vkState.buildOptionsUx.triangles.vertices);
    allocator.free(vkState.buildOptionsUx.lines.vertices);
    allocator.free(vkState.buildOptionsUx.sprites.vertices);
    allocator.free(vkState.buildOptionsUx.font.vertices);
    for (vkState.buildOptionsUx.uiButtons) |*uiButton| {
        allocator.free(uiButton.tooltip);
    }
    allocator.free(vkState.buildOptionsUx.uiButtons);
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
    vkState.buildOptionsUx.sprites.vertices = try allocator.alloc(paintVulkanZig.SpriteVertex, VkBuildOptionsUx.MAX_VERTICES_SPRITES);
    try paintVulkanZig.createBuffer(
        @sizeOf(paintVulkanZig.SpriteVertex) * VkBuildOptionsUx.MAX_VERTICES_SPRITES,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.sprites.vertexBuffer,
        &vkState.buildOptionsUx.sprites.vertexBufferMemory,
        vkState,
    );

    vkState.buildOptionsUx.font.vertices = try allocator.alloc(fontVulkanZig.FontVertex, VkBuildOptionsUx.MAX_VERTICES_FONT);
    try paintVulkanZig.createBuffer(
        @sizeOf(fontVulkanZig.FontVertex) * VkBuildOptionsUx.MAX_VERTICES_FONT,
        vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        &vkState.buildOptionsUx.font.vertexBuffer,
        &vkState.buildOptionsUx.font.vertexBufferMemory,
        vkState,
    );
}

pub fn setSelectedButtonIndex(actionType: inputZig.ActionType, state: *main.GameState) !void {
    for (state.vkState.buildOptionsUx.uiButtons, 0..) |uiButton, uiButtonIndex| {
        if (uiButton.type == .action and uiButton.type.action == actionType) {
            state.vkState.buildOptionsUx.selectedButtonIndex = uiButtonIndex;
            try setupVertices(state);
            break;
        }
    }
}

pub fn setupVertices(state: *main.GameState) !void {
    const unselectedFillColor: [3]f32 = .{ 0.75, 0.75, 0.75 };
    const selectedFillColor: [3]f32 = .{ 0.25, 0.25, 0.25 };
    const mouseHoverFillColor: [3]f32 = .{ 0, 0, 1 };
    const unselectedBorderColor: [3]f32 = .{ 0, 0, 0 };
    const selectedBorderColor: [3]f32 = .{ 1, 1, 1 };
    const hoverBorderColor: [3]f32 = .{ 0, 1, 0 };
    const triangles = &state.vkState.buildOptionsUx.triangles;
    const lines = &state.vkState.buildOptionsUx.lines;
    const sprites = &state.vkState.buildOptionsUx.sprites;
    const font = &state.vkState.buildOptionsUx.font;
    triangles.verticeCount = 0;
    lines.verticeCount = 0;
    sprites.verticeCount = 0;
    font.verticeCount = 0;

    for (state.vkState.buildOptionsUx.uiButtons, 0..) |uiButton, uiButtonIndex| {
        var optKeyBindChar: ?u8 = null;
        for (state.keyboardInfo.keybindings) |keybind| {
            if (uiButton.type == .action and keybind.action == uiButton.type.action) {
                optKeyBindChar = keybind.displayChar;
                break;
            }
        }
        var fillColor: [3]f32 = undefined;
        var borderColor: [3]f32 = undefined;
        if (state.vkState.buildOptionsUx.selectedButtonIndex == uiButtonIndex) {
            fillColor = selectedFillColor;
            borderColor = selectedBorderColor;
        } else if (state.vkState.buildOptionsUx.mouseHoverButtonIndex == uiButtonIndex) {
            fillColor = mouseHoverFillColor;
            borderColor = hoverBorderColor;
        } else {
            fillColor = unselectedFillColor;
            borderColor = unselectedBorderColor;
        }
        triangles.vertices[triangles.verticeCount + 0] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y }, .color = fillColor };
        triangles.vertices[triangles.verticeCount + 1] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y }, .color = fillColor };
        triangles.vertices[triangles.verticeCount + 2] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y + uiButton.height }, .color = fillColor };
        triangles.vertices[triangles.verticeCount + 3] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y }, .color = fillColor };
        triangles.vertices[triangles.verticeCount + 4] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y + uiButton.height }, .color = fillColor };
        triangles.vertices[triangles.verticeCount + 5] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y + uiButton.height }, .color = fillColor };
        triangles.verticeCount += 6;

        lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y }, .color = borderColor };
        lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y }, .color = borderColor };
        lines.vertices[lines.verticeCount + 2] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y }, .color = borderColor };
        lines.vertices[lines.verticeCount + 3] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y + uiButton.height }, .color = borderColor };
        lines.vertices[lines.verticeCount + 4] = .{ .pos = .{ uiButton.pos.x + uiButton.width, uiButton.pos.y + uiButton.height }, .color = borderColor };
        lines.vertices[lines.verticeCount + 5] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y + uiButton.height }, .color = borderColor };
        lines.vertices[lines.verticeCount + 6] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y + uiButton.height }, .color = borderColor };
        lines.vertices[lines.verticeCount + 7] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y }, .color = borderColor };
        lines.verticeCount += 8;

        switch (uiButton.fill) {
            .empty => {},
            .imageIndex => |data| {
                sprites.vertices[sprites.verticeCount] = .{ .pos = .{ uiButton.pos.x, uiButton.pos.y }, .imageIndex = data, .width = uiButton.width, .height = uiButton.height };
                sprites.verticeCount += 1;
            },
            .text => {},
        }

        if (optKeyBindChar) |keyBindChar| {
            font.vertices[font.verticeCount] = fontVulkanZig.getCharFontVertex(keyBindChar, uiButton.pos, 16);
            font.verticeCount += 1;
        }
        if (state.vkState.buildOptionsUx.mouseHoverButtonIndex == uiButtonIndex) {
            const paddingPixels = 2;
            const paddingXVulkan = paddingPixels / windowSdlZig.windowData.widthFloat * 2;
            const paddingYVulkan = paddingPixels / windowSdlZig.windowData.heightFloat * 2;
            const fontSizePixels = 20.0;
            const fontSizeVulkan = fontSizePixels / windowSdlZig.windowData.heightFloat * 2;
            const tooltipBoxVertSpacing = paddingYVulkan * 10;
            var width: f32 = 0;
            var maxWidth: f32 = 0;
            const height: f32 = fontSizeVulkan * @as(f32, @floatFromInt(uiButton.tooltip.len)) + paddingYVulkan * 2;
            for (uiButton.tooltip, 0..) |line, tooltipLineIndex| {
                for (line) |char| {
                    font.vertices[font.verticeCount] = fontVulkanZig.getCharFontVertex(char, .{
                        .x = uiButton.pos.x + width + paddingXVulkan,
                        .y = uiButton.pos.y - height + @as(f32, @floatFromInt(tooltipLineIndex)) * fontSizeVulkan + paddingYVulkan - tooltipBoxVertSpacing,
                    }, fontSizePixels);
                    width += font.vertices[font.verticeCount].texWidth * 1600 / windowSdlZig.windowData.widthFloat * 2 / 40 * fontSizePixels * 0.8;
                    font.verticeCount += 1;
                }
                if (maxWidth < width) maxWidth = width;
                width = 0;
            }
            maxWidth += paddingXVulkan * 2;
            const tooltipRectangle = mapZig.MapRectangle{
                .pos = .{ .x = uiButton.pos.x, .y = uiButton.pos.y - height - tooltipBoxVertSpacing },
                .width = maxWidth,
                .height = height,
            };
            fillColor = selectedFillColor;
            borderColor = unselectedBorderColor;
            triangles.vertices[triangles.verticeCount + 0] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y }, .color = fillColor };
            triangles.vertices[triangles.verticeCount + 1] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y }, .color = fillColor };
            triangles.vertices[triangles.verticeCount + 2] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = fillColor };
            triangles.vertices[triangles.verticeCount + 3] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y }, .color = fillColor };
            triangles.vertices[triangles.verticeCount + 4] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = fillColor };
            triangles.vertices[triangles.verticeCount + 5] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = fillColor };
            triangles.verticeCount += 6;

            lines.vertices[lines.verticeCount + 0] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y }, .color = borderColor };
            lines.vertices[lines.verticeCount + 1] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y }, .color = borderColor };
            lines.vertices[lines.verticeCount + 2] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y }, .color = borderColor };
            lines.vertices[lines.verticeCount + 3] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = borderColor };
            lines.vertices[lines.verticeCount + 4] = .{ .pos = .{ tooltipRectangle.pos.x + tooltipRectangle.width, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = borderColor };
            lines.vertices[lines.verticeCount + 5] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = borderColor };
            lines.vertices[lines.verticeCount + 6] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y + tooltipRectangle.height }, .color = borderColor };
            lines.vertices[lines.verticeCount + 7] = .{ .pos = .{ tooltipRectangle.pos.x, tooltipRectangle.pos.y }, .color = borderColor };
            lines.verticeCount += 8;
        }
    }

    try setupVertexDataForGPU(&state.vkState);
}

fn setupVertexDataForGPU(vkState: *paintVulkanZig.Vk_State) !void {
    var data: ?*anyopaque = undefined;
    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.buildOptionsUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    var gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.buildOptionsUx.triangles.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.triangles.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.buildOptionsUx.lines.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    gpu_vertices = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.buildOptionsUx.lines.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.lines.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.buildOptionsUx.sprites.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesSprite: [*]paintVulkanZig.SpriteVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesSprite, vkState.buildOptionsUx.sprites.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.sprites.vertexBufferMemory);

    if (vk.vkMapMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.buildOptionsUx.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesFont: [*]fontVulkanZig.FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesFont, vkState.buildOptionsUx.font.vertices[0..]);
    vk.vkUnmapMemory(vkState.logicalDevice, vkState.buildOptionsUx.font.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    if (state.vkState.buildOptionsUx.triangles.verticeCount <= 0) return;
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    var vertexBuffers: [1]vk.VkBuffer = .{vkState.buildOptionsUx.triangles.vertexBuffer};
    var offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.triangles.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.spriteGraphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.sprites.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.sprites.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.font.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.font.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    vertexBuffers = .{vkState.buildOptionsUx.lines.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw(commandBuffer, @intCast(state.vkState.buildOptionsUx.lines.verticeCount), 1, 0, 0);
}

fn createGraphicsPipeline(vkState: *paintVulkanZig.Vk_State, allocator: std.mem.Allocator) !void {
    const vertShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteVert.spv", allocator);
    defer allocator.free(vertShaderCode);
    const geomShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/spriteGeom.spv", allocator);
    defer allocator.free(geomShaderCode);
    const fragShaderCode = try paintVulkanZig.readShaderFile("shaders/compiled/imageFrag.spv", allocator);
    defer allocator.free(fragShaderCode);
    const vertShaderModule = try paintVulkanZig.createShaderModule(vertShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, vertShaderModule, null);
    const geomShaderModule = try paintVulkanZig.createShaderModule(geomShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, geomShaderModule, null);
    const fragShaderModule = try paintVulkanZig.createShaderModule(fragShaderCode, vkState);
    defer vk.vkDestroyShaderModule(vkState.logicalDevice, fragShaderModule, null);

    const vertShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
    };

    const geomShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .module = geomShaderModule,
        .pName = "main",
    };

    const fragShaderStageInfo = vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
    };

    const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo, geomShaderStageInfo };
    const bindingDescription = paintVulkanZig.SpriteVertex.getBindingDescription();
    const attributeDescriptions = paintVulkanZig.SpriteVertex.getAttributeDescriptions();
    var vertexInputInfo = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &bindingDescription,
        .vertexAttributeDescriptionCount = attributeDescriptions.len,
        .pVertexAttributeDescriptions = &attributeDescriptions,
    };

    var inputAssembly = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        .primitiveRestartEnable = vk.VK_FALSE,
    };

    var viewportState = vk.VkPipelineViewportStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    var rasterizer = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = vk.VK_FALSE,
        .rasterizerDiscardEnable = vk.VK_FALSE,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = vk.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    var multisampling = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = vk.VK_FALSE,
        .rasterizationSamples = vkState.msaaSamples,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    var colorBlendAttachment = vk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = vk.VK_TRUE,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
    };

    var colorBlending = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const dynamicStates = [_]vk.VkDynamicState{
        vk.VK_DYNAMIC_STATE_VIEWPORT,
        vk.VK_DYNAMIC_STATE_SCISSOR,
    };

    var dynamicState = vk.VkPipelineDynamicStateCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamicStates.len,
        .pDynamicStates = &dynamicStates,
    };

    var pipelineInfo = vk.VkGraphicsPipelineCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = shaderStages.len,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &colorBlending,
        .pDynamicState = &dynamicState,
        .layout = vkState.pipeline_layout,
        .renderPass = vkState.render_pass,
        .subpass = 2,
        .basePipelineHandle = null,
        .pNext = null,
    };
    if (vk.vkCreateGraphicsPipelines(vkState.logicalDevice, null, 1, &pipelineInfo, null, &vkState.spriteGraphicsPipeline) != vk.VK_SUCCESS) return error.FailedToCreateGraphicsPipeline;
}
