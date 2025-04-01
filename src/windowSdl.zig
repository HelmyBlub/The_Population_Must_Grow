const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
const main = @import("main.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");

const WindowData = struct {
    window: *sdl.SDL_Window = undefined,
    widthFloat: f32 = 1600,
    heightFloat: f32 = 800,
};
pub var windowData: WindowData = .{};

pub fn initWindowSdl() !void {
    _ = sdl.SDL_Init(sdl.SDL_INIT_VIDEO);
    const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE;
    windowData.window = try (sdl.SDL_CreateWindow("ChatSim", @intFromFloat(windowData.widthFloat), @intFromFloat(windowData.heightFloat), flags) orelse error.createWindow);
    _ = sdl.SDL_ShowWindow(windowData.window);
}

pub fn destroyWindowSdl() void {
    sdl.SDL_DestroyWindow(windowData.window);
    sdl.SDL_Quit();
}

pub fn getSurfaceForVulkan(instance: sdl.VkInstance) sdl.VkSurfaceKHR {
    var surface: sdl.VkSurfaceKHR = undefined;
    _ = sdl.SDL_Vulkan_CreateSurface(windowData.window, instance, null, &surface);
    return surface;
}

pub fn getWindowSize(width: *u32, height: *u32) void {
    var w: c_int = undefined;
    var h: c_int = undefined;
    _ = sdl.SDL_GetWindowSize(windowData.window, &w, &h);
    width.* = @intCast(w);
    height.* = @intCast(h);
}

pub fn handleEvents(state: *main.ChatSimState) !void {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        if (event.type == sdl.SDL_EVENT_MOUSE_MOTION) {
            state.currentMouse = .{ .x = event.motion.x, .y = event.motion.y };
        } else if (event.type == sdl.SDL_EVENT_MOUSE_WHEEL) {
            if (event.wheel.y > 0) {
                state.camera.zoom *= 1.2;
                if (state.camera.zoom > 10) {
                    state.camera.zoom = 10;
                }
            } else {
                state.camera.zoom /= 1.2;
                if (state.camera.zoom < 0.1) {
                    state.camera.zoom = 0.1;
                }
            }
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
            if (state.buildMode == main.BUILDING_MODE_DRAG_RECTANGLE and state.mouseDown != null) {
                const mouseUp = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
                const topLeft: main.Position = .{
                    .x = @min(mouseUp.x, state.mouseDown.?.x),
                    .y = @min(mouseUp.y, state.mouseDown.?.y),
                };
                const tileSizeFloat: f32 = @floatFromInt(main.ChatSimState.TILE_SIZE);
                const width: usize = @intFromFloat(@ceil(@abs(state.mouseDown.?.x - mouseUp.x) / tileSizeFloat));
                const height: usize = @intFromFloat(@ceil(@abs(state.mouseDown.?.y - mouseUp.y) / tileSizeFloat));
                var chunk = state.chunks.get("0_0").?;
                for (0..width) |x| {
                    for (0..height) |y| {
                        const position: main.Position = main.mapPositionToTilePosition(.{ .x = topLeft.x + @as(f32, @floatFromInt(x)) * tileSizeFloat, .y = topLeft.y + @as(f32, @floatFromInt(y)) * tileSizeFloat });
                        if (main.mapIsTilePositionFree(position, state) == false) continue;
                        for (state.citizens.items) |*citizen| {
                            if (citizen.buildingIndex != null) continue;
                            citizen.buildingIndex = chunk.buildings.items.len;
                            const newBuilding: main.Building = .{
                                .position = position,
                                .type = state.currentBuildingType,
                            };
                            try chunk.buildings.append(newBuilding);
                            try state.chunks.put("0_0", chunk);
                            break;
                        }
                    }
                }
            }
            state.mouseDown = null;
            state.rectangle = null;
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (state.buildMode == main.BUILDING_MODE_SINGLE) {
                const position = main.mapPositionToTilePosition(mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera));
                if (main.mapIsTilePositionFree(position, state) == false) return;
                var chunk = state.chunks.get("0_0").?;
                for (state.citizens.items) |*citizen| {
                    if (citizen.buildingIndex != null) continue;
                    citizen.buildingIndex = chunk.buildings.items.len;
                    const newBuilding: main.Building = .{
                        .position = position,
                        .type = state.currentBuildingType,
                    };
                    try chunk.buildings.append(newBuilding);
                    try state.chunks.put("0_0", chunk);
                    break;
                }
            } else if (state.buildMode == main.BUILDING_MODE_DRAG_RECTANGLE) {
                state.mouseDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
            }
        } else if (event.type == sdl.SDL_EVENT_KEY_UP) {
            if (event.key.scancode == sdl.SDL_SCANCODE_LEFT or event.key.scancode == sdl.SDL_SCANCODE_A) {
                state.camera.position.x -= 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_RIGHT or event.key.scancode == sdl.SDL_SCANCODE_D) {
                state.camera.position.x += 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_UP or event.key.scancode == sdl.SDL_SCANCODE_W) {
                state.camera.position.y -= 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_DOWN or event.key.scancode == sdl.SDL_SCANCODE_S) {
                state.camera.position.y += 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_1) {
                state.currentBuildingType = main.BUILDING_TYPE_HOUSE;
                state.buildMode = main.BUILDING_MODE_SINGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_2) {
                state.currentBuildingType = main.BUILDING_TYPE_TREE_FARM;
                state.buildMode = main.BUILDING_MODE_SINGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_3) {
                state.currentBuildingType = main.BUILDING_TYPE_HOUSE;
                state.buildMode = main.BUILDING_MODE_DRAG_RECTANGLE;
            }
        } else if (event.type == sdl.SDL_EVENT_QUIT) {
            std.debug.print("clicked window X \n", .{});
            state.gameEnd = true;
        }
    }
}

pub fn mouseWindowPositionToGameMapPoisition(x: f32, y: f32, camera: main.Camera) main.Position {
    var width: u32 = 0;
    var height: u32 = 0;
    getWindowSize(&width, &height);
    const widthFloat = @as(f32, @floatFromInt(width));
    const heightFloat = @as(f32, @floatFromInt(height));

    return main.Position{
        .x = (x - widthFloat / 2) / camera.zoom + camera.position.x,
        .y = (y - heightFloat / 2) / camera.zoom + camera.position.y,
    };
}

pub fn mouseWindowPositionToVulkanSurfacePoisition(x: f32, y: f32) main.Position {
    var width: u32 = 0;
    var height: u32 = 0;
    getWindowSize(&width, &height);
    const widthFloat = @as(f32, @floatFromInt(width));
    const heightFloat = @as(f32, @floatFromInt(height));

    return main.Position{
        .x = x / widthFloat * 2 - 1,
        .y = y / heightFloat * 2 - 1,
    };
}

pub fn gameMapPositionToVulkanSurfacePoisition(x: f32, y: f32, camera: main.Camera) main.Position {
    var width: u32 = 0;
    var height: u32 = 0;
    getWindowSize(&width, &height);
    const widthFloat = @as(f32, @floatFromInt(width));
    const heightFloat = @as(f32, @floatFromInt(height));

    return main.Position{
        .x = ((x - camera.position.x) * camera.zoom + widthFloat / 2) / widthFloat * 2 - 1,
        .y = ((y - camera.position.y) * camera.zoom + heightFloat / 2) / heightFloat * 2 - 1,
    };
}
