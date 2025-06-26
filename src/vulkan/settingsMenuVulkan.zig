const std = @import("std");
const main = @import("../main.zig");
const paintVulkanZig = @import("paintVulkan.zig");
const vk = paintVulkanZig.vk;
const fontVulkanZig = @import("fontVulkan.zig");
const buildOptionsUxVulkanZig = @import("buildOptionsUxVulkan.zig");
const imageZig = @import("../image.zig");
const mapZig = @import("../map.zig");
const inputZig = @import("../input.zig");
const windowSdlZig = @import("../windowSdl.zig");

pub const VkSettingsUx = struct {
    uiSizeDelayed: f32 = 1,
    triangles: paintVulkanZig.VkTriangles = undefined,
    lines: paintVulkanZig.VkLines = undefined,
    sprites: paintVulkanZig.VkSprites = undefined,
    font: fontVulkanZig.VkFont = undefined,
    settingsIcon: UiRectangle = undefined,
    settingsMenuRectangle: UiRectangle = undefined,
    restart: struct {
        rec: UiRectangle = undefined,
        holdStartTime: ?i64 = null,
        hovering: bool = false,
    } = undefined,
    sliders: [2]struct {
        recSlider: UiRectangle = undefined,
        recDragArea: UiRectangle = undefined,
        hovering: bool = false,
        holding: bool = false,
    } = undefined,
    fullscreen: struct {
        rec: UiRectangle = undefined,
        checked: bool = false,
        hovering: bool = false,
    } = undefined,
    quit: struct {
        rec: UiRectangle = undefined,
        hovering: bool = false,
    } = undefined,
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
    setupUiLocations(state);
    try setupVertices(state);
}

pub fn setupUiLocations(state: *main.GameState) void {
    const vkState = &state.vkState;
    const uiSizeFactor = state.vkState.settingsMenuUx.uiSizeDelayed;
    const settingsMenuUx = &vkState.settingsMenuUx;
    const vulkanSpacingX = 10.0 / windowSdlZig.windowData.widthFloat * uiSizeFactor;
    const vulkanSpacingY = 10.0 / windowSdlZig.windowData.heightFloat * uiSizeFactor;
    const vulkanSpacingLargerY = 40.0 / windowSdlZig.windowData.heightFloat * uiSizeFactor;

    const iconWidth = 80 / windowSdlZig.windowData.widthFloat * uiSizeFactor;
    const iconHeight = 80 / windowSdlZig.windowData.heightFloat * uiSizeFactor;
    settingsMenuUx.settingsIcon = .{
        .height = iconHeight,
        .width = iconWidth,
        .pos = .{
            .x = 1 - iconWidth - vulkanSpacingX,
            .y = -1 + vulkanSpacingY,
        },
    };

    const menuWidth = 510 / windowSdlZig.windowData.widthFloat * uiSizeFactor;
    settingsMenuUx.settingsMenuRectangle = .{
        .height = 600 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = menuWidth,
        .pos = .{
            .x = 1 - menuWidth - vulkanSpacingX,
            .y = -1 + vulkanSpacingY + iconHeight,
        },
    };
    const settingsMenuRec = settingsMenuUx.settingsMenuRectangle;

    settingsMenuUx.restart.rec = .{
        .height = 80 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = menuWidth - vulkanSpacingX * 2,
        .pos = .{
            .x = settingsMenuRec.pos.x + vulkanSpacingX,
            .y = settingsMenuRec.pos.y + vulkanSpacingY,
        },
    };

    const sliderSpacingX = 40.0 / windowSdlZig.windowData.widthFloat * uiSizeFactor;
    const sliderWidth = 40 / windowSdlZig.windowData.widthFloat * uiSizeFactor;
    const dragAreaWidth = (menuWidth - sliderSpacingX * 2 - sliderWidth);
    const sliderVolumeOffsetX = state.soundMixer.volume * dragAreaWidth;
    settingsMenuUx.sliders[0].recSlider = .{
        .height = 40 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = sliderWidth,
        .pos = .{
            .x = settingsMenuRec.pos.x + sliderVolumeOffsetX + vulkanSpacingX,
            .y = settingsMenuUx.restart.rec.pos.y + settingsMenuUx.restart.rec.height + vulkanSpacingLargerY + 60 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        },
    };
    settingsMenuUx.sliders[0].recDragArea = .{
        .height = 10 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = dragAreaWidth,
        .pos = .{
            .x = settingsMenuRec.pos.x + sliderWidth / 2 + vulkanSpacingX,
            .y = settingsMenuUx.sliders[0].recSlider.pos.y + 15 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        },
    };

    const sliderUiScaleOffsetX = (state.vkState.uiSizeFactor - 0.5) / 1.5 * dragAreaWidth;
    settingsMenuUx.sliders[1].recSlider = .{
        .height = 40 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = sliderWidth,
        .pos = .{
            .x = settingsMenuRec.pos.x + sliderUiScaleOffsetX + vulkanSpacingX,
            .y = settingsMenuUx.sliders[0].recSlider.pos.y + settingsMenuUx.sliders[1].recSlider.height + vulkanSpacingLargerY + 60 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        },
    };

    settingsMenuUx.sliders[1].recDragArea = .{
        .height = 10 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = dragAreaWidth,
        .pos = .{
            .x = settingsMenuRec.pos.x + sliderWidth / 2 + vulkanSpacingX,
            .y = settingsMenuUx.sliders[1].recSlider.pos.y + 15 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        },
    };

    settingsMenuUx.fullscreen.rec = .{
        .height = 50 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = 50 / windowSdlZig.windowData.widthFloat * uiSizeFactor,
        .pos = .{
            .x = settingsMenuRec.pos.x + vulkanSpacingX,
            .y = settingsMenuUx.sliders[1].recSlider.pos.y + settingsMenuUx.sliders[1].recSlider.height + vulkanSpacingLargerY,
        },
    };

    settingsMenuUx.quit.rec = .{
        .height = 80 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .width = 100 / windowSdlZig.windowData.heightFloat * uiSizeFactor,
        .pos = .{
            .x = settingsMenuRec.pos.x + vulkanSpacingX,
            .y = settingsMenuUx.fullscreen.rec.pos.y + settingsMenuUx.fullscreen.rec.height + vulkanSpacingLargerY,
        },
    };
}

fn initUi(state: *main.GameState) !void {
    const settings = &state.vkState.settingsMenuUx;
    settings.restart.holdStartTime = null;
    settings.restart.hovering = false;

    settings.sliders[0].holding = false;
    settings.sliders[0].hovering = false;

    settings.sliders[1].holding = false;
    settings.sliders[1].hovering = false;

    settings.fullscreen.checked = false;
    settings.fullscreen.hovering = false;

    settings.quit.hovering = false;
    setupUiLocations(state);
}

pub fn mouseMove(state: *main.GameState) !void {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(state.mouseInfo.currentPos.x, state.mouseInfo.currentPos.y);
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    if (isPositionInUiRec(settingsMenuUx.settingsIcon, vulkanMousePos)) {
        settingsMenuUx.settingsIconHovered = true;
        try setupVertices(state);
        return;
    }
    if (settingsMenuUx.settingsIconHovered) {
        settingsMenuUx.settingsIconHovered = false;
        try setupVertices(state);
    }
    if (!settingsMenuUx.menuOpen) return;

    settingsMenuUx.quit.hovering = false;
    settingsMenuUx.fullscreen.hovering = false;
    settingsMenuUx.restart.hovering = false;
    settingsMenuUx.sliders[0].hovering = false;
    settingsMenuUx.sliders[1].hovering = false;
    const restartRec = settingsMenuUx.restart.rec;
    if (settingsMenuUx.restart.holdStartTime != null and (restartRec.pos.x > vulkanMousePos.x or restartRec.pos.x + restartRec.width < vulkanMousePos.x or
        restartRec.pos.y > vulkanMousePos.y or restartRec.pos.y + restartRec.height < vulkanMousePos.y))
    {
        settingsMenuUx.restart.holdStartTime = null;
        try setupVertices(state);
        return;
    }

    for (settingsMenuUx.sliders, 0..) |slider, index| {
        if (slider.holding) {
            const rec = slider.recDragArea;
            if (index == 0) {
                state.soundMixer.volume = @min(@max(0, @as(f32, @floatCast(vulkanMousePos.x - rec.pos.x)) / rec.width), 1);
            } else {
                state.vkState.uiSizeFactor = @min(@max(0.5, @as(f32, @floatCast(vulkanMousePos.x - rec.pos.x)) / rec.width * 1.5 + 0.5), 2);
                if (@abs(state.vkState.uiSizeFactor - 1) < 0.05) state.vkState.uiSizeFactor = 1;
                try buildOptionsUxVulkanZig.onWindowResize(state);
            }
            setupUiLocations(state);
            try setupVertices(state);
            return;
        }
    }

    if (isPositionInUiRec(settingsMenuUx.restart.rec, vulkanMousePos)) {
        settingsMenuUx.restart.hovering = true;
        try setupVertices(state);
        return;
    }
    for (settingsMenuUx.sliders, 0..) |slider, index| {
        if (isPositionInUiRec(slider.recSlider, vulkanMousePos)) {
            settingsMenuUx.sliders[index].hovering = true;
            try setupVertices(state);
            return;
        }
    }
    if (isPositionInUiRec(settingsMenuUx.fullscreen.rec, vulkanMousePos)) {
        settingsMenuUx.fullscreen.hovering = true;
        try setupVertices(state);
        return;
    }
    if (isPositionInUiRec(settingsMenuUx.quit.rec, vulkanMousePos)) {
        settingsMenuUx.quit.hovering = true;
        try setupVertices(state);
        return;
    }
    try setupVertices(state);
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

    for (settingsMenuUx.sliders, 0..) |slider, index| {
        if (slider.holding) {
            settingsMenuUx.sliders[index].holding = false;
            if (index == 1) {
                state.vkState.settingsMenuUx.uiSizeDelayed = state.vkState.uiSizeFactor;
                setupUiLocations(state);
                try setupVertices(state);
            }
            return true;
        }
    }
    return false;
}

/// returns true if a button was clicked
pub fn mouseDown(state: *main.GameState, mouseWindowPosition: main.PositionF32) !bool {
    const vulkanMousePos = windowSdlZig.mouseWindowPositionToVulkanSurfacePoisition(mouseWindowPosition.x, mouseWindowPosition.y);
    const settingsMenuUx = &state.vkState.settingsMenuUx;
    if (isPositionInUiRec(settingsMenuUx.settingsIcon, vulkanMousePos)) {
        settingsMenuUx.menuOpen = !settingsMenuUx.menuOpen;
        try setupVertices(state);
        return true;
    }
    if (!settingsMenuUx.menuOpen) return false;

    if (isPositionInUiRec(settingsMenuUx.restart.rec, vulkanMousePos)) {
        settingsMenuUx.restart.holdStartTime = std.time.milliTimestamp();
        return true;
    }

    for (settingsMenuUx.sliders, 0..) |slider, index| {
        if (slider.recDragArea.pos.x <= vulkanMousePos.x and slider.recDragArea.pos.x + slider.recDragArea.width >= vulkanMousePos.x and
            slider.recSlider.pos.y <= vulkanMousePos.y and slider.recSlider.pos.y + slider.recSlider.height >= vulkanMousePos.y)
        {
            if (index == 0) {
                state.soundMixer.volume = @min(@max(0, @as(f32, @floatCast(vulkanMousePos.x - slider.recDragArea.pos.x)) / slider.recDragArea.width), 1);
            } else {
                state.vkState.uiSizeFactor = @min(@max(0.5, @as(f32, @floatCast(vulkanMousePos.x - slider.recDragArea.pos.x)) / slider.recDragArea.width * 1.5 + 0.5), 2);
                if (@abs(state.vkState.uiSizeFactor - 1) < 0.05) state.vkState.uiSizeFactor = 1;
                try buildOptionsUxVulkanZig.onWindowResize(state);
            }
            settingsMenuUx.sliders[index].holding = true;
            setupUiLocations(state);
            try setupVertices(state);
            return true;
        }
    }

    if (isPositionInUiRec(settingsMenuUx.quit.rec, vulkanMousePos)) {
        state.gameEnd = true;
        return true;
    }

    if (isPositionInUiRec(settingsMenuUx.fullscreen.rec, vulkanMousePos)) {
        settingsMenuUx.fullscreen.checked = windowSdlZig.toggleFullscreen();
        try setupVertices(state);
        return true;
    }

    if (isPositionInUiRec(settingsMenuUx.settingsMenuRectangle, vulkanMousePos)) {
        return true;
    }

    return false;
}

fn isPositionInUiRec(rec: UiRectangle, pos: main.Position) bool {
    return rec.pos.x <= pos.x and rec.pos.x + rec.width >= pos.x and
        rec.pos.y <= pos.y and rec.pos.y + rec.height >= pos.y;
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
    vk.vkDestroyBuffer.?(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBuffer, null);
    vk.vkDestroyBuffer.?(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBuffer, null);
    vk.vkDestroyBuffer.?(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBuffer, null);
    vk.vkDestroyBuffer.?(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBuffer, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory, null);
    vk.vkFreeMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory, null);
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
    const hoverColor: [3]f32 = .{ 0.4, 0.4, 0.4 };
    const color: [3]f32 = .{ 1, 1, 1 };
    const triangles = &state.vkState.settingsMenuUx.triangles;
    const lines = &state.vkState.settingsMenuUx.lines;
    const sprites = &state.vkState.settingsMenuUx.sprites;
    const font = &state.vkState.settingsMenuUx.font;
    triangles.verticeCount = 0;
    lines.verticeCount = 0;
    sprites.verticeCount = 0;
    font.verticeCount = 0;
    const uiSizeFactor = state.vkState.settingsMenuUx.uiSizeDelayed;
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
        const restartFillColor = if (settingsMenuUx.restart.hovering) hoverColor else buttonFillColor;
        setupVerticeForRectangle(settingsMenuUx.restart.rec, settingsMenuUx, restartFillColor, borderColor);
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
        const fontSize: f32 = 26 * uiSizeFactor;
        const fontVulkanHeight = fontSize / windowSdlZig.windowData.heightFloat * 2;
        _ = fontVulkanZig.paintText(
            "Hold to Restart",
            .{
                .x = settingsMenuUx.restart.rec.pos.x,
                .y = settingsMenuUx.restart.rec.pos.y + settingsMenuUx.restart.rec.height / 5.0,
            },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );

        for (settingsMenuUx.sliders) |slider| {
            setupVerticeForRectangle(slider.recDragArea, settingsMenuUx, color, borderColor);
            const sliderFillColor = if (slider.hovering) hoverColor else buttonFillColor;
            setupVerticeForRectangle(slider.recSlider, settingsMenuUx, sliderFillColor, borderColor);
        }

        const textWidthVolume = fontVulkanZig.paintText(
            "Volume: ",
            .{ .x = settingsMenuUx.sliders[0].recDragArea.pos.x, .y = settingsMenuUx.sliders[0].recSlider.pos.y - fontVulkanHeight },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );
        _ = try fontVulkanZig.paintNumber(
            @as(u32, @intFromFloat(state.soundMixer.volume * 100)),
            .{ .x = settingsMenuUx.sliders[0].recDragArea.pos.x + textWidthVolume, .y = settingsMenuUx.sliders[0].recSlider.pos.y - fontVulkanHeight },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );

        const textWidthUiScale = fontVulkanZig.paintText(
            "UI Scale: ",
            .{ .x = settingsMenuUx.sliders[1].recDragArea.pos.x, .y = settingsMenuUx.sliders[1].recSlider.pos.y - fontVulkanHeight },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );
        _ = try fontVulkanZig.paintNumber(
            @as(u32, @intFromFloat(state.vkState.uiSizeFactor * 100)),
            .{ .x = settingsMenuUx.sliders[1].recDragArea.pos.x + textWidthUiScale, .y = settingsMenuUx.sliders[1].recSlider.pos.y - fontVulkanHeight },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );

        const fullscreenFillColor = if (settingsMenuUx.fullscreen.hovering) hoverColor else buttonFillColor;
        setupVerticeForRectangle(settingsMenuUx.fullscreen.rec, settingsMenuUx, fullscreenFillColor, borderColor);
        _ = fontVulkanZig.paintText(
            "Fullscreen",
            .{
                .x = settingsMenuUx.fullscreen.rec.pos.x + settingsMenuUx.fullscreen.rec.width * 1.05,
                .y = settingsMenuUx.fullscreen.rec.pos.y - settingsMenuUx.fullscreen.rec.height * 0.1,
            },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );
        if (settingsMenuUx.fullscreen.checked) {
            sprites.vertices[sprites.verticeCount] = .{
                .pos = .{ settingsMenuUx.fullscreen.rec.pos.x, settingsMenuUx.fullscreen.rec.pos.y },
                .imageIndex = imageZig.IMAGE_CHECKMARK,
                .width = settingsMenuUx.fullscreen.rec.width,
                .height = settingsMenuUx.fullscreen.rec.height,
            };
            sprites.verticeCount += 1;
        }

        const quitFillColor = if (settingsMenuUx.quit.hovering) hoverColor else buttonFillColor;
        setupVerticeForRectangle(settingsMenuUx.quit.rec, settingsMenuUx, quitFillColor, borderColor);
        _ = fontVulkanZig.paintText(
            "Quit",
            .{
                .x = settingsMenuUx.quit.rec.pos.x + settingsMenuUx.quit.rec.width * 0.15,
                .y = settingsMenuUx.quit.rec.pos.y + settingsMenuUx.quit.rec.height * 0.15,
            },
            fontSize,
            &state.vkState.settingsMenuUx.font,
        );
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
    if (vk.vkMapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.settingsMenuUx.triangles.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    var gpu_vertices: [*]paintVulkanZig.ColoredVertex = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.settingsMenuUx.triangles.vertices[0..]);
    vk.vkUnmapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.triangles.vertexBufferMemory);

    if (vk.vkMapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.ColoredVertex) * vkState.settingsMenuUx.lines.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    gpu_vertices = @ptrCast(@alignCast(data));
    @memcpy(gpu_vertices, vkState.settingsMenuUx.lines.vertices[0..]);
    vk.vkUnmapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.lines.vertexBufferMemory);

    if (vk.vkMapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.settingsMenuUx.sprites.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesSprite: [*]paintVulkanZig.SpriteVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesSprite, vkState.settingsMenuUx.sprites.vertices[0..]);
    vk.vkUnmapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.sprites.vertexBufferMemory);

    if (vk.vkMapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory, 0, @sizeOf(paintVulkanZig.SpriteVertex) * vkState.settingsMenuUx.font.vertices.len, 0, &data) != vk.VK_SUCCESS) return error.MapMemory;
    const gpuVerticesFont: [*]fontVulkanZig.FontVertex = @ptrCast(@alignCast(data));
    @memcpy(gpuVerticesFont, vkState.settingsMenuUx.font.vertices[0..]);
    vk.vkUnmapMemory.?(vkState.logicalDevice, vkState.settingsMenuUx.font.vertexBufferMemory);
}

pub fn recordCommandBuffer(commandBuffer: vk.VkCommandBuffer, state: *main.GameState) !void {
    const vkState = &state.vkState;
    vk.vkCmdBindPipeline.?(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.triangleGraphicsPipeline);
    var vertexBuffers: [1]vk.VkBuffer = .{vkState.settingsMenuUx.triangles.vertexBuffer};
    var offsets: [1]vk.VkDeviceSize = .{0};
    vk.vkCmdBindVertexBuffers.?(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw.?(commandBuffer, @intCast(state.vkState.settingsMenuUx.triangles.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline.?(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.spriteGraphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.sprites.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers.?(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw.?(commandBuffer, @intCast(state.vkState.settingsMenuUx.sprites.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline.?(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.font.graphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.font.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers.?(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw.?(commandBuffer, @intCast(state.vkState.settingsMenuUx.font.verticeCount), 1, 0, 0);

    vk.vkCmdBindPipeline.?(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, vkState.rectangle.graphicsPipeline);
    vertexBuffers = .{vkState.settingsMenuUx.lines.vertexBuffer};
    offsets = .{0};
    vk.vkCmdBindVertexBuffers.?(commandBuffer, 0, 1, &vertexBuffers[0], &offsets[0]);
    vk.vkCmdDraw.?(commandBuffer, @intCast(state.vkState.settingsMenuUx.lines.verticeCount), 1, 0, 0);
}
