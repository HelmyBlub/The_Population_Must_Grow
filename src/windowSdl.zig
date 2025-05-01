const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
const minimp3 = @cImport({
    @cInclude("minimp3_ex.h");
});
const main = @import("main.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");
const mapZig = @import("map.zig");

pub const WindowData = struct {
    window: *sdl.SDL_Window = undefined,
    widthFloat: f32 = 1600,
    heightFloat: f32 = 800,
};

const SoundFile = struct {
    data: [*]u8,
    len: u32,
    isMp3: bool,
};

pub const SoundData = struct {
    stream: ?*sdl.SDL_AudioStream,
    sounds: []SoundFile,
};

pub var windowData: WindowData = .{};
pub var soundData: SoundData = undefined;

pub fn initWindowSdl(allocator: std.mem.Allocator) !void {
    _ = sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO);
    const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE;
    windowData.window = try (sdl.SDL_CreateWindow("ChatSim", @intFromFloat(windowData.widthFloat), @intFromFloat(windowData.heightFloat), flags) orelse error.createWindow);
    _ = sdl.SDL_ShowWindow(windowData.window);
    try initSounds(allocator);
}

pub fn destroyWindowSdl(allocator: std.mem.Allocator) void {
    sdl.SDL_DestroyWindow(windowData.window);
    destorySounds(allocator);
    sdl.SDL_Quit();
}

fn initSounds(allocator: std.mem.Allocator) !void {
    var desired_spec = sdl.SDL_AudioSpec{
        .format = sdl.SDL_AUDIO_S16,
        .freq = 48000,
        .channels = 1,
    };

    const stream = sdl.SDL_OpenAudioDeviceStream(sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired_spec, null, null);
    if (stream == null) {
        std.debug.print("Failed to create audio stream: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    const device = sdl.SDL_GetAudioStreamDevice(stream);
    if (device == 0) {
        std.debug.print("Failed to open audio device: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    if (!sdl.SDL_ResumeAudioDevice(device)) {
        std.debug.print("Failed to resume audio device: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    const sounds = try allocator.alloc(SoundFile, 2);
    sounds[0] = try loadSoundFile("sounds/441617__danielajq__38-arbol-cayendo.wav", allocator);
    sounds[1] = try loadSoundFile("sounds/553254__t-man95__axe-cutting-wood_chop_1.mp3", allocator);
    soundData = .{
        .stream = stream,
        .sounds = sounds,
    };
}

pub fn playSound(soundIndex: usize) void {
    _ = sdl.SDL_PutAudioStreamData(soundData.stream, soundData.sounds[soundIndex].data, @intCast(soundData.sounds[soundIndex].len));
}

///support wav and mp3
fn loadSoundFile(path: []const u8, allocator: std.mem.Allocator) !SoundFile {
    var audio_buf: [*]u8 = undefined;
    var audio_len: u32 = 0;
    if (std.mem.endsWith(u8, path, ".wav")) {
        var spec: sdl.SDL_AudioSpec = undefined;
        if (!sdl.SDL_LoadWAV(@ptrCast(path), &spec, @ptrCast(&audio_buf), &audio_len)) {
            return error.loadWav;
        }

        return .{ .data = audio_buf, .len = audio_len, .isMp3 = false };
        // defer sdl.SDL_free(audio_buf);
    } else if (std.mem.endsWith(u8, path, ".mp3")) {
        var mp3 = minimp3.mp3dec_ex_t{};
        if (minimp3.mp3dec_ex_open(&mp3, path.ptr, minimp3.MP3D_SEEK_TO_SAMPLE) != 0) {
            return error.openMp3;
        }
        defer minimp3.mp3dec_ex_close(&mp3);
        // Allocate your own buffer for the decoded samples
        const total_samples = mp3.samples; // number of samples (not bytes)
        const sample_count: usize = @intCast(total_samples);
        const decoded = try allocator.alloc(i16, sample_count);

        // Read all samples
        const samples_read = minimp3.mp3dec_ex_read(&mp3, decoded.ptr, sample_count);
        audio_buf = @ptrCast(decoded.ptr);
        audio_len = @intCast(samples_read * @sizeOf(i16));
        return .{ .data = audio_buf, .len = audio_len, .isMp3 = true };
    } else {
        return error.unknwonSoundFileType;
    }
}

fn destorySounds(allocator: std.mem.Allocator) void {
    sdl.SDL_DestroyAudioStream(soundData.stream);
    for (soundData.sounds) |sound| {
        if (sound.isMp3) {
            // allocator.free(sound.data);
        } else {
            sdl.SDL_free(sound.data);
        }
    }
    allocator.free(soundData.sounds);
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
        if (state.buildMode == mapZig.BUILD_MODE_DRAG_RECTANGLE) try handleBuildModeRectangle(&event, state);
        if (state.buildMode == mapZig.BUILD_MODE_DRAW) try handleBuildModeDraw(&event, state);
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
            state.mapMouseDown = null;
        } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
            if (state.buildMode == mapZig.BUILD_MODE_SINGLE) {
                const position = mapZig.mapPositionToTileMiddlePosition(mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera));
                const newBuilding: mapZig.Building = .{
                    .position = position,
                    .type = state.currentBuildType,
                };
                _ = try mapZig.placeBuilding(newBuilding, state, true);
            }
        } else if (event.type == sdl.SDL_EVENT_KEY_UP) {
            var buildModeChanged = false;
            if (event.key.scancode == sdl.SDL_SCANCODE_LEFT or event.key.scancode == sdl.SDL_SCANCODE_A) {
                state.camera.position.x -= 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_RIGHT or event.key.scancode == sdl.SDL_SCANCODE_D) {
                state.camera.position.x += 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_UP or event.key.scancode == sdl.SDL_SCANCODE_W) {
                state.camera.position.y -= 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_DOWN or event.key.scancode == sdl.SDL_SCANCODE_S) {
                state.camera.position.y += 100 / state.camera.zoom;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_KP_PLUS) {
                state.gameSpeed *= 2;
                if (state.gameSpeed > 64) state.gameSpeed = 64;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_KP_MINUS) {
                state.gameSpeed /= 2;
                if (state.gameSpeed < 0.0625) state.gameSpeed = 0.0625;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_1) {
                state.currentBuildType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_SINGLE;
                buildModeChanged = true;
                playSound(0);
            } else if (event.key.scancode == sdl.SDL_SCANCODE_2) {
                state.currentBuildType = mapZig.BUILD_TYPE_TREE_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
                playSound(1);
            } else if (event.key.scancode == sdl.SDL_SCANCODE_3) {
                state.currentBuildType = mapZig.BUILD_TYPE_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_4) {
                state.currentBuildType = mapZig.BUILD_TYPE_POTATO_FARM;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_5) {
                state.currentBuildType = mapZig.BUILD_TYPE_COPY_PASTE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_6) {
                state.currentBuildType = mapZig.BUILD_TYPE_BIG_HOUSE;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_7) {
                state.currentBuildType = mapZig.BUILD_TYPE_PATHES;
                state.buildMode = mapZig.BUILD_MODE_DRAW;
                buildModeChanged = true;
            } else if (event.key.scancode == sdl.SDL_SCANCODE_9) {
                state.currentBuildType = mapZig.BUILD_TYPE_DEMOLISH;
                state.buildMode = mapZig.BUILD_MODE_DRAG_RECTANGLE;
                buildModeChanged = true;
            }
            if (buildModeChanged) {
                state.copyAreaRectangle = null;
                state.mapMouseDown = null;
                state.rectangles[0] = null;
            }
        } else if (event.type == sdl.SDL_EVENT_QUIT) {
            std.debug.print("clicked window X \n", .{});
            state.gameEnd = true;
        }
    }
}

fn handleBuildModeDraw(event: *sdl.SDL_Event, state: *main.ChatSimState) !void {
    if (state.buildMode != mapZig.BUILD_MODE_DRAW) return;
    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN or (event.type == sdl.SDL_EVENT_MOUSE_MOTION) and state.mapMouseDown != null) {
        state.mapMouseDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
        _ = try mapZig.placePath(mapZig.mapPositionToTileMiddlePosition(state.mapMouseDown.?), state);
    }
}

fn handleBuildModeRectangle(event: *sdl.SDL_Event, state: *main.ChatSimState) !void {
    if (state.buildMode != mapZig.BUILD_MODE_DRAG_RECTANGLE) return;

    if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
        if (event.button.button != 1) {
            state.mapMouseDown = null;
            state.copyAreaRectangle = null;
            state.rectangles[0] = null;
            return;
        }
        if (state.mapMouseDown != null) {
            const mapMouseUp = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
            const topLeft: main.Position = .{
                .x = @min(mapMouseUp.x, state.mapMouseDown.?.x),
                .y = @min(mapMouseUp.y, state.mapMouseDown.?.y),
            };
            const bottomRight: main.Position = .{
                .x = @max(mapMouseUp.x, state.mapMouseDown.?.x),
                .y = @max(mapMouseUp.y, state.mapMouseDown.?.y),
            };
            const tileXy = mapZig.mapPositionToTileXy(topLeft);
            const tileXyBottomRight = mapZig.mapPositionToTileXyBottomRight(bottomRight);
            const tileRectangle: mapZig.MapTileRectangle = .{
                .topLeftTileXY = tileXy,
                .columnCount = @intCast(tileXyBottomRight.tileX - tileXy.tileX),
                .rowCount = @intCast(tileXyBottomRight.tileY - tileXy.tileY),
            };
            if (state.currentBuildType == mapZig.BUILD_TYPE_COPY_PASTE) {
                if (state.copyAreaRectangle != null) return;
                state.copyAreaRectangle = tileRectangle;
                return;
            }

            try handleRectangleAreaAction(tileRectangle, state);
        }
        state.mapMouseDown = null;
        state.rectangles[0] = null;
    } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
        if (state.currentBuildType == mapZig.BUILD_TYPE_COPY_PASTE and state.copyAreaRectangle != null) {
            if (event.button.button != 1) return;
            const mapTargetTopLeft = mouseWindowPositionToGameMapPoisition(event.button.x, event.button.y, state.camera);
            try mapZig.copyFromTo(
                state.copyAreaRectangle.?.topLeftTileXY,
                mapZig.mapPositionToTileXy(mapTargetTopLeft),
                state.copyAreaRectangle.?.columnCount,
                state.copyAreaRectangle.?.rowCount,
                state,
            );
        } else {
            state.mapMouseDown = mouseWindowPositionToGameMapPoisition(event.motion.x, event.motion.y, state.camera);
        }
    }
}

fn handleRectangleAreaAction(mapTileRectangle: mapZig.MapTileRectangle, state: *main.ChatSimState) !void {
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
                chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(currentChunkXY.?, state);
            }
            if (state.currentBuildType == mapZig.BUILD_TYPE_DEMOLISH) {
                try mapZig.demolishAnythingOnPosition(position, mapTileRectangle, state);
                continue;
            }

            if (state.currentBuildType == mapZig.BUILD_TYPE_HOUSE) {
                const newBuilding: mapZig.Building = .{
                    .position = position,
                    .type = mapZig.BUILDING_TYPE_HOUSE,
                };
                _ = try mapZig.placeBuilding(newBuilding, state, true);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_BIG_HOUSE) {
                const newBuilding: mapZig.Building = .{
                    .position = .{ .x = position.x + mapZig.GameMap.TILE_SIZE / 2, .y = position.y + mapZig.GameMap.TILE_SIZE / 2 },
                    .type = mapZig.BUILDING_TYPE_BIG_HOUSE,
                    .woodRequired = 16,
                };
                _ = try mapZig.placeBuilding(newBuilding, state, true);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_POTATO_FARM) {
                const newPotatoField: mapZig.PotatoField = .{
                    .position = position,
                    .planted = false,
                };
                _ = try mapZig.placePotatoField(newPotatoField, state);
            } else if (state.currentBuildType == mapZig.BUILD_TYPE_TREE_FARM) {
                const newTree: mapZig.MapTree = .{
                    .position = position,
                    .planted = false,
                    .regrow = true,
                };
                _ = try mapZig.placeTree(newTree, state);
            }
        }
    }
    if (state.currentBuildType == mapZig.BUILD_TYPE_DEMOLISH) {
        try main.pathfindingZig.changePathingDataRectangle(mapTileRectangle, mapZig.PathingType.slow, state);
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
