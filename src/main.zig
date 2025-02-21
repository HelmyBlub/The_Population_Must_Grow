const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub fn main() !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init Error: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_Quit();

    const window_w = 640;
    const window_h = 480;
    if (!sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_VSYNC, "1")) {
        std.debug.print("SDL_SetHint Error: {s}\n", .{sdl.SDL_GetError()});
        return;
    }

    const window: *sdl.SDL_Window, const renderer: *sdl.SDL_Renderer = create_window_and_renderer: {
        var window: ?*sdl.SDL_Window = null;
        var renderer: ?*sdl.SDL_Renderer = null;
        if (!sdl.SDL_CreateWindowAndRenderer("ChatSim", window_w, window_h, 0, &window, &renderer)) {
            std.debug.print("SDL_createWindowAndRendere Error: {s}\n", .{sdl.SDL_GetError()});
            return;
        }
        errdefer comptime unreachable;

        break :create_window_and_renderer .{ window.?, renderer.? };
    };
    defer sdl.SDL_DestroyRenderer(renderer);
    defer sdl.SDL_DestroyWindow(window);

    const img_path = "src/test.bmp";
    const testImage = sdl.SDL_LoadBMP(img_path);
    if (testImage == null) {
        std.debug.print("SDL_LoadBMP Error: {s}\n", .{sdl.SDL_GetError()});
        return;
    }

    const texture = sdl.SDL_CreateTextureFromSurface(renderer, testImage);
    //sdl.SDL_FreeSurface(testImage);
    if (texture == null) {
        std.debug.print("SDL_CreateTextureFromSurface Error: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyTexture(texture);

    var event: sdl.SDL_Event = undefined;
    var running = true;
    while (running) {
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                running = false;
            }
        }

        // Clear screen (set background to green)
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        _ = sdl.SDL_RenderClear(renderer);

        // Draw image
        _ = sdl.SDL_RenderTexture(renderer, texture, null, null);

        // Present frame
        if (!sdl.SDL_RenderPresent(renderer)) {
            std.debug.print("render present Error: {s}\n", .{sdl.SDL_GetError()});
            running = false;
        }
    }
}
