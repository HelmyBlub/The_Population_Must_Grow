const std = @import("std");
const main = @import("main.zig");

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const PaintInfo: type = struct {
    window: *sdl.SDL_Window,
    window_w: u16,
    window_h: u16,
    renderer: *sdl.SDL_Renderer,
    texture: [*c]sdl.SDL_Texture,
};

pub fn paintInit() !PaintInfo {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init Error: {s}\n", .{sdl.SDL_GetError()});
        return error.ERROR_SDL_INIT;
    }

    const window_w = 640;
    const window_h = 480;

    if (!sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_VSYNC, "1")) {
        std.debug.print("SDL_SetHint Error: {s}\n", .{sdl.SDL_GetError()});
        return error.ERROR_SDL_HINT;
    }
    const window: *sdl.SDL_Window, const renderer: *sdl.SDL_Renderer = create_window_and_renderer: {
        var window: ?*sdl.SDL_Window = null;
        var renderer: ?*sdl.SDL_Renderer = null;
        if (!sdl.SDL_CreateWindowAndRenderer("ChatSim", window_w, window_h, 0, &window, &renderer)) {
            std.debug.print("SDL_createWindowAndRendere Error: {s}\n", .{sdl.SDL_GetError()});
            return error.ERROR_SDL_CREATE_WINDOW;
        }
        errdefer comptime unreachable;

        break :create_window_and_renderer .{ window.?, renderer.? };
    };
    const img_path = "src/test.bmp";
    const testImage = sdl.SDL_LoadBMP(img_path);
    if (testImage == null) {
        std.debug.print("SDL_LoadBMP Error: {s}\n", .{sdl.SDL_GetError()});
        return error.ERROR_SDL_LOAD_BMP;
    }

    const texture = sdl.SDL_CreateTextureFromSurface(renderer, testImage);
    if (texture == null) {
        std.debug.print("SDL_CreateTextureFromSurface Error: {s}\n", .{sdl.SDL_GetError()});
        return error.Failure;
    }
    if (!sdl.SDL_SetTextureScaleMode(texture, sdl.SDL_SCALEMODE_LINEAR)) {
        std.debug.print("SDL_SetTextureScaleMode Error: {s}\n", .{sdl.SDL_GetError()});
    }
    var scaleMode: u32 = 0;
    _ = sdl.SDL_GetTextureScaleMode(texture, &scaleMode);
    std.debug.print("scaleMode: {}\n", .{scaleMode});
    sdl.SDL_DestroySurface(testImage);
    return PaintInfo{
        .renderer = renderer,
        .window = window,
        .window_w = window_w,
        .window_h = window_h,
        .texture = texture,
    };
}

pub fn paintDestroy(state: main.ChatSimState) void {
    sdl.SDL_Quit();
    sdl.SDL_DestroyRenderer(state.paintInfo.renderer);
    sdl.SDL_DestroyWindow(state.paintInfo.window);
    sdl.SDL_DestroyTexture(state.paintInfo.texture);
}

pub fn paint(state: *main.ChatSimState) !void {
    const paintInfo = state.paintInfo;
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        if (event.type == sdl.SDL_EVENT_QUIT) {
            state.gameEnd = true;
        }
    }
    // Clear screen (set background to green)
    _ = sdl.SDL_SetRenderDrawColor(paintInfo.renderer, 0, 255, 0, 255);
    _ = sdl.SDL_RenderClear(paintInfo.renderer);
    // Draw image
    const centerOffsetX: f32 = @as(f32, @floatFromInt(state.paintInfo.window_w)) / 2.0;
    const centerOffsetY: f32 = @as(f32, @floatFromInt(state.paintInfo.window_h)) / 2.0;
    for (state.citizens.items) |*citizen| {
        const stretchRect: [1]sdl.SDL_FRect = .{.{
            .x = citizen.position.x + centerOffsetX,
            .y = citizen.position.y + centerOffsetY,
            .w = 50.0,
            .h = 50.0,
        }};
        const point: [1]sdl.SDL_FPoint = .{.{ .x = 20, .y = 20 }};
        _ = sdl.SDL_RenderTextureRotated(
            paintInfo.renderer,
            paintInfo.texture,
            null,
            &stretchRect,
            @as(f64, @floatFromInt(state.gameTimeMs)) / 20.0,
            &point,
            sdl.SDL_FLIP_NONE,
        );
    }
    // Present frame
    if (!sdl.SDL_RenderPresent(paintInfo.renderer)) {
        std.debug.print("render present Error: {s}\n", .{sdl.SDL_GetError()});
        state.gameEnd = true;
    }
}
