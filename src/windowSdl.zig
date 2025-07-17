const std = @import("std");
const buildin = @import("builtin");
pub const sdl = @cImport({
    @cDefine("VK_NO_PROTOTYPES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

const main = @import("main.zig");
const inputZig = @import("input.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");
const mapZig = @import("map.zig");
const soundMixerZig = @import("soundMixer.zig");
const buildOptionsUxVulkanZig = @import("vulkan/buildOptionsUxVulkan.zig");
const settingsMenuUxVulkanZig = @import("vulkan/settingsMenuVulkan.zig");
const imageZig = @import("image.zig");
const testZig = @import("test.zig");
const saveZig = @import("save.zig");
const chunkAreaZig = @import("chunkArea.zig");
const steamZig = @import("steam.zig");

pub const WindowData = struct {
    window: *sdl.SDL_Window = undefined,
    widthFloat: f32 = 1600,
    heightFloat: f32 = 800,
};

pub var windowData: WindowData = .{};

pub fn initWindowSdl() !void {
    _ = sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO);
    const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE;
    windowData.window = try (sdl.SDL_CreateWindow("The Population Must Grow", @intFromFloat(windowData.widthFloat), @intFromFloat(windowData.heightFloat), flags) orelse error.createWindow);
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

pub fn toggleFullscreen() bool {
    const flags = sdl.SDL_GetWindowFlags(windowData.window);
    if ((flags & sdl.SDL_WINDOW_FULLSCREEN) == 0) {
        _ = sdl.SDL_SetWindowFullscreen(windowData.window, true);
        return true;
    } else {
        _ = sdl.SDL_SetWindowFullscreen(windowData.window, false);
        return false;
    }
}

pub fn handleEvents(state: *main.GameState) !void {
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
            if (try settingsMenuUxVulkanZig.mouseUp(state, .{ .x = event.motion.x, .y = event.motion.y })) {
                return;
            }
        }
        if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (try buildOptionsUxVulkanZig.mouseClick(state, .{ .x = event.motion.x, .y = event.motion.y })) {
                return;
            } else if (try settingsMenuUxVulkanZig.mouseDown(state, .{ .x = event.motion.x, .y = event.motion.y })) {
                return;
            } else {
                if (event.button.button == 1) {
                    state.mouseInfo.leftButtonPressedTimeMs = std.time.milliTimestamp();
                } else {
                    state.mouseInfo.rightButtonPressedTimeMs = std.time.milliTimestamp();
                }
            }
        }

        if (state.buildMode == mapZig.BUILD_MODE_DRAG_RECTANGLE) try handleBuildModeRectangle(&event, state);
        if (state.buildMode == mapZig.BUILD_MODE_DRAW) try handleBuildModeDraw(&event, state);
        if (event.type == sdl.SDL_EVENT_MOUSE_MOTION) {
            state.mouseInfo.currentPos = .{ .x = event.motion.x, .y = event.motion.y };
            try buildOptionsUxVulkanZig.mouseMove(state);
            try settingsMenuUxVulkanZig.mouseMove(state);
            if (state.mouseInfo.rightButtonPressedTimeMs) |_| {
                state.camera.position.x -= event.motion.xrel / state.camera.zoom;
                state.camera.position.y -= event.motion.yrel / state.camera.zoom;
            }
            main.limitCameraArea(state);
        } else if (event.type == sdl.SDL_EVENT_MOUSE_WHEEL) {
            if (event.wheel.y > 0) {
                main.setZoom(state.camera.zoom / 0.8, state, true);
            } else {
                main.setZoom(state.camera.zoom / 1.2, state, true);
            }
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
            if (event.button.button == 1) {
                state.mouseInfo.leftButtonMapDown = null;
                state.mouseInfo.leftButtonPressedTimeMs = null;
            } else {
                state.mouseInfo.rightButtonWindowDown = null;
                state.mouseInfo.rightButtonPressedTimeMs = null;
            }
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (state.buildMode == mapZig.BUILD_MODE_SINGLE and event.button.button == 1) {
                const position = mapZig.mapPositionToTileMiddlePosition(mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera));
                _ = try mapZig.placeHouse(position, state, true, true, 0);
            }
        } else if (event.type == sdl.SDL_EVENT_KEY_UP) {
            if (event.key.scancode == sdl.SDL_SCANCODE_LEFT or event.key.scancode == sdl.SDL_SCANCODE_A) {
                state.keyboardInfo.cameraMoveX = 0;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_RIGHT or event.key.scancode == sdl.SDL_SCANCODE_D) {
                state.keyboardInfo.cameraMoveX = 0;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_UP or event.key.scancode == sdl.SDL_SCANCODE_W) {
                state.keyboardInfo.cameraMoveY = 0;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_DOWN or event.key.scancode == sdl.SDL_SCANCODE_S) {
                state.keyboardInfo.cameraMoveY = 0;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_ESCAPE) {
                state.vkState.settingsMenuUx.menuOpen = !state.vkState.settingsMenuUx.menuOpen;
                try settingsMenuUxVulkanZig.setupVertices(state);
            } else if (event.key.scancode == sdl.SDL_SCANCODE_F1) {
                state.vkState.font.displayPerformance = !state.vkState.font.displayPerformance;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_F12) {
                var count: u32 = 0;
                for (state.threadData) |thread| {
                    for (thread.chunkAreaKeys.items) |chunkAreaKey| {
                        if (state.chunkAreas.getPtr(chunkAreaKey)) |chunkArea| {
                            if (chunkArea.chunks) |chunks| {
                                for (chunks) |*chunk| {
                                    for (chunk.citizens.items) |*citizen| {
                                        if (main.Citizen.isCitizenWorking(citizen)) {
                                            std.debug.print("{}\n\n{}\n", .{ citizen, chunk });
                                            count += 1;
                                            if (count > 5) {
                                                return;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else if (event.key.scancode == sdl.SDL_SCANCODE_LCTRL) {
                state.keyboardInfo.ctrHold = false;
            } else {
                try inputZig.executeActionByKeybind(event.key.scancode, state);
            }
            if (buildin.mode == .Debug) try debugKeyBinds(state, event.key.scancode);
        } else if (event.type == sdl.SDL_EVENT_KEY_DOWN) {
            if (event.key.scancode == sdl.SDL_SCANCODE_LEFT or event.key.scancode == sdl.SDL_SCANCODE_A) {
                state.keyboardInfo.cameraMoveX = -10;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_RIGHT or event.key.scancode == sdl.SDL_SCANCODE_D) {
                state.keyboardInfo.cameraMoveX = 10;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_UP or event.key.scancode == sdl.SDL_SCANCODE_W) {
                state.keyboardInfo.cameraMoveY = -10;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_DOWN or event.key.scancode == sdl.SDL_SCANCODE_S) {
                state.keyboardInfo.cameraMoveY = 10;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_LCTRL) {
                state.keyboardInfo.ctrHold = true;
            }
        } else if (event.type == sdl.SDL_EVENT_QUIT) {
            std.debug.print("clicked window X \n", .{});
            state.gameEnd = true;
        }
    }
}

fn debugKeyBinds(state: *main.GameState, scancode: c_uint) !void {
    if (scancode == sdl.SDL_SCANCODE_F2) {
        if (state.testData == null) {
            state.testData = testZig.createTestData(state.allocator);
            state.testData.?.fpsLimiter = true;
            state.testData.?.skipSaveAndLoad = false;
        }
        state.testData.?.forceSingleCore = true;
    } else if (scancode == sdl.SDL_SCANCODE_F3) {
        if (state.testData == null) {
            state.testData = testZig.createTestData(state.allocator);
            state.testData.?.fpsLimiter = true;
            state.testData.?.skipSaveAndLoad = false;
        }
        state.testData.?.forceSingleCore = false;
    } else if (scancode == sdl.SDL_SCANCODE_F5) {
        if (state.usedThreadsCount < state.maxThreadCount) {
            try main.changeUsedThreadCount(state.usedThreadsCount + 1, state);
            state.autoBalanceThreadCount = false;
            std.debug.print("threadCount increased to {d}\n", .{state.usedThreadsCount});
        }
    } else if (scancode == sdl.SDL_SCANCODE_F6) {
        if (state.usedThreadsCount > 1) {
            try main.changeUsedThreadCount(state.usedThreadsCount - 1, state);
            state.autoBalanceThreadCount = false;
            std.debug.print("threadCount decreased to {d}\n", .{state.usedThreadsCount});
        }
    } else if (scancode == sdl.SDL_SCANCODE_F8) {
        if (state.testData == null) {
            state.testData = testZig.createTestData(state.allocator);
            state.testData.?.fpsLimiter = true;
            state.testData.?.skipSaveAndLoad = false;
            try testZig.setupTestInputsXAreas(&state.testData.?);
        }
    } else if (scancode == sdl.SDL_SCANCODE_F9) {
        std.debug.print("stop game end remove frame limiter\n", .{});
        state.actualGameSpeed = 0;
        state.desiredGameSpeed = 0;
        state.testData = testZig.createTestData(state.allocator);
        state.testData.?.fpsLimiter = false;
    } else if (scancode == sdl.SDL_SCANCODE_F10) {
        try main.deleteSaveAndRestart(state);
    } else if (scancode == sdl.SDL_SCANCODE_F11) {
        std.debug.print("thread performance\n", .{});
        for (state.threadData, 0..) |threadData, index| {
            if (threadData.measureData.performancePerTickedCitizens) |performance| {
                std.debug.print("    {} {} {}\n", .{ index, performance, threadData.measureData.lastMeasureTime });
            }
        }
    } else if (scancode == sdl.SDL_SCANCODE_F12) {
        for (state.threadData) |thread| {
            for (thread.chunkAreaKeys.items) |chunkAreaKey| {
                if (state.chunkAreas.getPtr(chunkAreaKey)) |chunkArea| {
                    if (chunkArea.chunks) |chunks| {
                        for (chunks) |*chunk| {
                            for (chunk.citizens.items) |*citizen| {
                                if (citizen.nextThinkingAction != .idle) {
                                    std.debug.print("{}\n\n{}\n", .{ citizen, chunk });
                                    return;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn handleBuildModeDraw(event: *sdl.SDL_Event, state: *main.GameState) !void {
    if (state.buildMode != mapZig.BUILD_MODE_DRAW) return;
    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN or (event.type == sdl.SDL_EVENT_MOUSE_MOTION) and state.mouseInfo.leftButtonMapDown != null) {
        if (state.mouseInfo.leftButtonPressedTimeMs != null) {
            state.mouseInfo.leftButtonMapDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
            _ = try mapZig.placePath(mapZig.mapPositionToTileMiddlePosition(state.mouseInfo.leftButtonMapDown.?), state);
        }
    }
}

fn handleBuildModeRectangle(event: *sdl.SDL_Event, state: *main.GameState) !void {
    if (state.buildMode != mapZig.BUILD_MODE_DRAG_RECTANGLE) return;

    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
        if (event.button.button != 1) {
            if (std.time.milliTimestamp() - state.mouseInfo.rightButtonPressedTimeMs.? < 175) {
                if (state.mouseInfo.rightButtonWindowDown != null and
                    main.calculateDistance(.{ .x = event.button.x, .y = event.button.y }, state.mouseInfo.rightButtonWindowDown.?) < 5)
                {
                    state.mouseInfo.leftButtonMapDown = null;
                    state.copyAreaRectangle = null;
                    state.rectangles[0] = null;
                }
            }
            return;
        }
        if (state.mouseInfo.leftButtonMapDown != null) {
            const mapMouseUp = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
            const topLeft: main.Position = .{
                .x = @min(mapMouseUp.x, state.mouseInfo.leftButtonMapDown.?.x),
                .y = @min(mapMouseUp.y, state.mouseInfo.leftButtonMapDown.?.y),
            };
            const bottomRight: main.Position = .{
                .x = @max(mapMouseUp.x, state.mouseInfo.leftButtonMapDown.?.x),
                .y = @max(mapMouseUp.y, state.mouseInfo.leftButtonMapDown.?.y),
            };

            const tileXy = mapZig.mapPositionToTileXy(topLeft);
            const tileXyBottomRight = mapZig.mapPositionToTileXyBottomRight(bottomRight);
            var tileRectangle: mapZig.MapTileRectangle = .{
                .topLeftTileXY = tileXy,
                .columnCount = @intCast(tileXyBottomRight.tileX - tileXy.tileX),
                .rowCount = @intCast(tileXyBottomRight.tileY - tileXy.tileY),
            };
            if (state.currentBuildType == mapZig.BUILD_TYPE_BIG_HOUSE) {
                const adjustColumns = @mod(tileRectangle.columnCount, 2);
                const adjustRows = @mod(tileRectangle.rowCount, 2);
                if (mapMouseUp.x < state.mouseInfo.leftButtonMapDown.?.x) {
                    tileRectangle.topLeftTileXY.tileX = tileRectangle.topLeftTileXY.tileX - @as(i32, @intCast(adjustColumns));
                }
                tileRectangle.rowCount += adjustRows;
                if (mapMouseUp.y < state.mouseInfo.leftButtonMapDown.?.y) {
                    tileRectangle.topLeftTileXY.tileY = tileRectangle.topLeftTileXY.tileY - @as(i32, @intCast(adjustRows));
                }
                tileRectangle.columnCount += adjustColumns;
            }

            if (state.currentBuildType == mapZig.BUILD_TYPE_COPY_PASTE) {
                if (state.copyAreaRectangle != null) return;
                state.copyAreaRectangle = tileRectangle;
                return;
            }

            try handleRectangleAreaAction(tileRectangle, state);
        }
        state.mouseInfo.leftButtonMapDown = null;
        state.rectangles[0] = null;
    } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
        if (state.currentBuildType == mapZig.BUILD_TYPE_COPY_PASTE and state.copyAreaRectangle != null) {
            if (event.button.button != 1) {
                state.mouseInfo.rightButtonWindowDown = .{ .x = event.motion.x, .y = event.motion.y };
                return;
            }
            var mapTargetTopLeft = mouseWindowPositionToGameMapPoisition(event.button.x, event.button.y, state.camera);
            if (state.keyboardInfo.ctrHold) {
                main.alignPasteRectangleOfCopyPaste(&mapTargetTopLeft, state);
            }
            try mapZig.copyFromTo(
                state.copyAreaRectangle.?.topLeftTileXY,
                mapZig.mapPositionToTileXy(mapTargetTopLeft),
                state.copyAreaRectangle.?.columnCount,
                state.copyAreaRectangle.?.rowCount,
                state,
            );
        } else {
            if (event.button.button == 1) {
                state.mouseInfo.leftButtonMapDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
            } else {
                state.mouseInfo.rightButtonWindowDown = .{ .x = event.motion.x, .y = event.motion.y };
            }
        }
    }
}

pub fn handleRectangleAreaAction(mapTileRectangle: mapZig.MapTileRectangle, state: *main.GameState) !void {
    var chunk: *mapZig.MapChunk = undefined;
    var currentChunkXY: ?mapZig.ChunkXY = null;
    for (0..mapTileRectangle.columnCount) |x| {
        for (0..mapTileRectangle.rowCount) |y| {
            const position: main.Position = mapZig.mapTileXyToTileMiddlePosition(.{
                .tileX = mapTileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(x)),
                .tileY = mapTileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(y)),
            });
            const loopChunk = mapZig.getChunkXyForPosition(position);
            if (currentChunkXY == null or loopChunk.chunkX != currentChunkXY.?.chunkX or loopChunk.chunkY != currentChunkXY.?.chunkY) {
                currentChunkXY = loopChunk;
                chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(currentChunkXY.?, 0, false, state);
            }
            if (state.currentBuildType == mapZig.BUILD_TYPE_DEMOLISH) {
                try mapZig.demolishAnythingOnPosition(position, mapTileRectangle, state);
                continue;
            }

            if (state.currentBuildType == mapZig.BUILD_TYPE_HOUSE) {
                _ = try mapZig.placeHouse(position, state, true, false, 0);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_BIG_HOUSE) {
                const bigHousePosition: main.Position = .{ .x = position.x + mapZig.GameMap.TILE_SIZE / 2, .y = position.y + mapZig.GameMap.TILE_SIZE / 2 };
                _ = try mapZig.placeBigHouse(bigHousePosition, state, true, false, 0);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_POTATO_FARM) {
                const newPotatoField: mapZig.PotatoField = .{
                    .position = position,
                };
                _ = try mapZig.placePotatoField(newPotatoField, state);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_TREE_FARM) {
                const newTree: mapZig.MapTree = .{
                    .position = position,
                    .regrow = true,
                    .imageIndex = imageZig.IMAGE_GREEN_RECTANGLE,
                };
                _ = try mapZig.placeTree(newTree, state);
            }
        }
    }
    try mapZig.unidleAffectedChunkAreas(mapTileRectangle, state);
    if (state.currentBuildType == mapZig.BUILD_TYPE_DEMOLISH) {
        try main.pathfindingZig.changePathingDataRectangle(mapTileRectangle, mapZig.PathingType.slow, 0, state);
    }
}

pub fn mouseWindowPositionToGameMapPoisition(x: f32, y: f32, camera: main.Camera) main.Position {
    var width: u32 = 0;
    var height: u32 = 0;
    getWindowSize(&width, &height);
    const widthFloatWindow = @as(f64, @floatFromInt(width));
    const heightFloatWindow = @as(f64, @floatFromInt(height));

    const scaleToPixelX = windowData.widthFloat / widthFloatWindow;
    const scaleToPixelY = windowData.heightFloat / heightFloatWindow;

    return main.Position{
        .x = (x - widthFloatWindow / 2) * scaleToPixelX / camera.zoom + camera.position.x,
        .y = (y - heightFloatWindow / 2) * scaleToPixelY / camera.zoom + camera.position.y,
    };
}

pub fn mouseWindowPositionToVulkanSurfacePoisition(x: f32, y: f32) main.PositionF32 {
    var width: u32 = 0;
    var height: u32 = 0;
    getWindowSize(&width, &height);
    const widthFloat = @as(f32, @floatFromInt(width));
    const heightFloat = @as(f32, @floatFromInt(height));

    return main.PositionF32{
        .x = x / widthFloat * 2 - 1,
        .y = y / heightFloat * 2 - 1,
    };
}
