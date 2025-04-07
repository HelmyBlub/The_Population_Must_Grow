const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
const main = @import("main.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");
const mapZig = @import("map.zig");

pub const WindowData = struct {
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
            if (state.buildMode == mapZig.BUILD_MODE_DRAG_RECTANGLE and state.mouseDown != null) {
                const mouseUp = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
                const topLeft: main.Position = .{
                    .x = @min(mouseUp.x, state.mouseDown.?.x),
                    .y = @min(mouseUp.y, state.mouseDown.?.y),
                };
                const tileSizeFloat: f32 = @floatFromInt(mapZig.GameMap.TILE_SIZE);
                const width: usize = @intFromFloat(@ceil(@abs(state.mouseDown.?.x - mouseUp.x) / tileSizeFloat));
                const height: usize = @intFromFloat(@ceil(@abs(state.mouseDown.?.y - mouseUp.y) / tileSizeFloat));
                var currentChunkXY: mapZig.ChunkXY = undefined;
                if (state.currentBuildingType == mapZig.BUILD_TYPE_COPY_PASTE) {
                    if (event.button.button == 1) {
                        if (state.copyAreaRectangle != null) return;
                        const position = mapZig.mapPositionToTilePosition(topLeft);
                        state.copyAreaRectangle = .{
                            .pos = position,
                            .height = @floatFromInt(height * mapZig.GameMap.TILE_SIZE),
                            .width = @floatFromInt(width * mapZig.GameMap.TILE_SIZE),
                        };
                    } else {
                        state.mouseDown = null;
                        state.copyAreaRectangle = null;
                        state.rectangles[0] = null;
                    }
                    return;
                }
                var chunk: *mapZig.MapChunk = undefined;
                for (0..width) |x| {
                    for (0..height) |y| {
                        const position: main.Position = mapZig.mapPositionToTileMiddlePosition(.{ .x = topLeft.x + @as(f32, @floatFromInt(x)) * tileSizeFloat, .y = topLeft.y + @as(f32, @floatFromInt(y)) * tileSizeFloat });
                        const loopChunk = mapZig.getChunkXyForPosition(position);
                        if (loopChunk.chunkX != currentChunkXY.chunkX or loopChunk.chunkY != currentChunkXY.chunkY) {
                            currentChunkXY = loopChunk;
                            chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(currentChunkXY.chunkX, currentChunkXY.chunkY, state);
                        }
                        if (state.currentBuildingType == mapZig.BUILD_TYPE_DEMOLISH) {
                            try mapZig.demolishAnythingOnPosition(position, state);
                            continue;
                        }

                        const freeCitizen = try main.Citizen.findClosestFreeCitizen(position, state);
                        if (freeCitizen) |citizen| {
                            if (state.currentBuildingType == mapZig.BUILD_TYPE_HOUSE) {
                                if (citizen.buildingPosition != null) continue;
                                const newBuilding: mapZig.Building = .{
                                    .position = position,
                                    .type = state.currentBuildingType,
                                };
                                if (try mapZig.placeBuilding(newBuilding, state)) {
                                    citizen.buildingPosition = position;
                                    citizen.idle = false;
                                    citizen.moveTo = null;
                                }
                            } else if (state.currentBuildingType == mapZig.BUILD_TYPE_POTATO_FARM) {
                                if (citizen.farmPosition != null) continue;
                                const newPotatoField: mapZig.PotatoField = .{
                                    .position = position,
                                    .planted = false,
                                };
                                if (try mapZig.placePotatoField(newPotatoField, state)) {
                                    citizen.farmPosition = position;
                                    citizen.idle = false;
                                    citizen.moveTo = null;
                                }
                            } else if (state.currentBuildingType == mapZig.BUILD_TYPE_TREE_FARM) {
                                if (citizen.treePosition != null) continue;
                                const newTree: mapZig.MapTree = .{
                                    .position = position,
                                    .planted = false,
                                    .regrow = true,
                                };
                                if (try mapZig.placeTree(newTree, state)) {
                                    citizen.treePosition = position;
                                    citizen.idle = false;
                                    citizen.moveTo = null;
                                }
                            }
                        }
                    }
                }
            }
            state.mouseDown = null;
            state.rectangles[0] = null;
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (state.buildMode == mapZig.BUILD_MODE_SINGLE) {
                const position = mapZig.mapPositionToTileMiddlePosition(mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera));
                const freeCitizen = try main.Citizen.findClosestFreeCitizen(position, state);
                if (freeCitizen) |citizen| {
                    if (citizen.buildingPosition != null) continue;
                    const newBuilding: mapZig.Building = .{
                        .position = position,
                        .type = state.currentBuildingType,
                    };
                    if (try mapZig.placeBuilding(newBuilding, state)) {
                        citizen.buildingPosition = position;
                        citizen.idle = false;
                        citizen.moveTo = null;
                    }
                }
            } else if (state.buildMode == mapZig.BUILD_MODE_DRAG_RECTANGLE) {
                if (state.currentBuildingType == mapZig.BUILD_TYPE_COPY_PASTE and state.copyAreaRectangle != null) {
                    if (event.button.button != 1) return;
                    const mapTargetTopLeft = mouseWindowPositionToGameMapPoisition(event.button.x, event.button.y, state.camera);
                    const targetTopLeftTileMiddle = mapZig.mapPositionToTileMiddlePosition(mapTargetTopLeft);
                    for (0..@intFromFloat(state.copyAreaRectangle.?.width / mapZig.GameMap.TILE_SIZE)) |x| {
                        for (0..@intFromFloat(state.copyAreaRectangle.?.height / mapZig.GameMap.TILE_SIZE)) |y| {
                            const sourcePosition: main.Position = .{
                                .x = state.copyAreaRectangle.?.pos.x + @as(f32, @floatFromInt(x * mapZig.GameMap.TILE_SIZE)) + mapZig.GameMap.TILE_SIZE / 2,
                                .y = state.copyAreaRectangle.?.pos.y + @as(f32, @floatFromInt(y * mapZig.GameMap.TILE_SIZE)) + mapZig.GameMap.TILE_SIZE / 2,
                            };
                            const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(sourcePosition, state);
                            const targetPosition: main.Position = .{
                                .x = targetTopLeftTileMiddle.x + @as(f32, @floatFromInt(x * mapZig.GameMap.TILE_SIZE)),
                                .y = targetTopLeftTileMiddle.y + @as(f32, @floatFromInt(y * mapZig.GameMap.TILE_SIZE)),
                            };
                            const freeCitizen = try main.Citizen.findClosestFreeCitizen(targetPosition, state);
                            if (freeCitizen == null) continue;
                            for (chunk.buildings.items) |building| {
                                if (main.calculateDistance(sourcePosition, building.position) < mapZig.GameMap.TILE_SIZE) {
                                    const newBuilding: mapZig.Building = .{
                                        .position = targetPosition,
                                        .inConstruction = true,
                                        .type = building.type,
                                    };
                                    if (try mapZig.placeBuilding(newBuilding, state)) {
                                        freeCitizen.?.buildingPosition = newBuilding.position;
                                        freeCitizen.?.idle = false;
                                        freeCitizen.?.moveTo = null;
                                    }
                                    continue;
                                }
                            }
                            for (chunk.trees.items) |tree| {
                                if (main.calculateDistance(sourcePosition, tree.position) < mapZig.GameMap.TILE_SIZE and tree.regrow) {
                                    const newTree: mapZig.MapTree = .{
                                        .position = targetPosition,
                                        .regrow = true,
                                        .planted = false,
                                    };
                                    if (try mapZig.placeTree(newTree, state)) {
                                        freeCitizen.?.treePosition = newTree.position;
                                        freeCitizen.?.idle = false;
                                        freeCitizen.?.moveTo = null;
                                    }
                                    continue;
                                }
                            }
                            for (chunk.potatoFields.items) |potatoField| {
                                if (main.calculateDistance(sourcePosition, potatoField.position) < mapZig.GameMap.TILE_SIZE) {
                                    const newPotatoField: mapZig.PotatoField = .{
                                        .position = targetPosition,
                                        .planted = false,
                                    };
                                    if (try mapZig.placePotatoField(newPotatoField, state)) {
                                        freeCitizen.?.farmPosition = newPotatoField.position;
                                        freeCitizen.?.idle = false;
                                        freeCitizen.?.moveTo = null;
                                    }
                                    continue;
                                }
                            }
                        }
                    }
                } else {
                    state.mouseDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
                }
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
                state.currentBuildingType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_SINGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_2) {
                state.currentBuildingType = mapZig.BUILD_TYPE_TREE_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_3) {
                state.currentBuildingType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_4) {
                state.currentBuildingType = mapZig.BUILD_TYPE_POTATO_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_5) {
                state.currentBuildingType = mapZig.BUILD_TYPE_COPY_PASTE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_9) {
                state.currentBuildingType = mapZig.BUILD_TYPE_DEMOLISH;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
            }
            if (state.copyAreaRectangle != null and state.currentBuildingType != mapZig.BUILD_TYPE_COPY_PASTE) {
                state.copyAreaRectangle = null;
                state.mouseDown = null;
                state.rectangles[0] = null;
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
