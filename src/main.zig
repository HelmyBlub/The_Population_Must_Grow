const std = @import("std");
// continue:
// try printing FPS to screen

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
    if (texture == null) {
        std.debug.print("SDL_CreateTextureFromSurface Error: {s}\n", .{sdl.SDL_GetError()});
        return;
    }
    sdl.SDL_DestroySurface(testImage);
    defer sdl.SDL_DestroyTexture(texture);

    var event: sdl.SDL_Event = undefined;
    var running = true;
    var somevalue: u16 = 0;
    var frames: u16 = 0;
    while (running) {
        frames += 1;
        somevalue = (somevalue + 1) % 1000;
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                running = false;
            } else if (event.type == sdl.SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    sdl.SDLK_UP => {
                        std.debug.print("key up\n", .{});
                    },
                    sdl.SDLK_DOWN => {
                        std.debug.print("key down\n", .{});
                    },
                    else => {
                        std.debug.print("other key {}\n", .{event.key.key});
                    },
                }
            } else if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN) {
                switch (event.button.button) {
                    1 => {
                        std.debug.print("left mouse {d} {d}\n", .{ event.button.x, event.button.y });
                    },
                    3 => {
                        std.debug.print("right mouse {d} {d}\n", .{ event.button.x, event.button.y });
                    },
                    else => {
                        std.debug.print("mouse input {}\n", .{event.button.button});
                    },
                }
            }
        }

        // Clear screen (set background to green)
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        _ = sdl.SDL_RenderClear(renderer);

        // Draw image
        const stretchRect: [1]sdl.SDL_FRect = .{.{
            .x = @as(f32, @floatFromInt(somevalue)) / 2.0,
            .y = 50,
            .w = window_w / 5,
            .h = window_h / 5,
        }};
        const point: [1]sdl.SDL_FPoint = .{.{ .x = 0, .y = 0 }};
        _ = sdl.SDL_RenderTexture(renderer, texture, null, &stretchRect);
        _ = sdl.SDL_RenderTextureRotated(
            renderer,
            texture,
            null,
            &stretchRect,
            @as(f64, @floatFromInt(somevalue)) / 2.0,
            &point,
            sdl.SDL_FLIP_NONE,
        );
        // Present frame
        var buffer: [20]u8 = undefined;
        const temp = try std.fmt.bufPrint(&buffer, "{}", .{frames});

        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = sdl.SDL_RenderDebugText(renderer, 50, 50, @ptrCast(temp));
        if (!sdl.SDL_RenderPresent(renderer)) {
            std.debug.print("render present Error: {s}\n", .{sdl.SDL_GetError()});
            running = false;
        }
        //sdl.SDL_Delay(5);
    }
}
