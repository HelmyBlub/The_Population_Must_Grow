// continue trying out openGL by somehow connecting x11 and gl libs
// build with:
// zig build-exe src/x11.zig -lX11 -lGL -lc

const std = @import("std");
const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});
const gl = @cImport({
    @cInclude("GL/gl.h");
    @cInclude("GL/glx.h");
});

var display: ?*x11.Display = null;
var window: x11.Window = undefined;
var glContext: gl.GLXContext = undefined;

// Initialize X11 Window & OpenGL Context
fn initWindow() !void {
    display = x11.XOpenDisplay(null);
    if (display == null) {
        @panic("Failed to open X11 display");
    }
    const screen = x11.XDefaultScreen(display);
    const root = x11.XRootWindow(display, screen);

    window = x11.XCreateSimpleWindow(display, root, 0, 0, 800, 600, 1, 0, x11.XWhitePixel(display, screen));
    _ = x11.XMapWindow(display, window);
    _ = x11.XStoreName(display, window, "Zig X11 Game");

    // Create OpenGL context
    std.debug.print("4\n", .{});

    const gc = x11.XDefaultGC(display, screen);
    var counter: u32 = 0;

    while (true) {
        counter += 1;
        var buffer: [20]u8 = undefined;
        const formatted_str = try std.fmt.bufPrint(&buffer, "{}", .{counter});
        const temp: []u8 = try std.fmt.bufPrint(&buffer, "123", .{});
        _ = x11.XPending(display);
        _ = x11.XDrawString(display, window, gc, 60, 100, @ptrCast(&temp), @intCast(temp.len));
        std.debug.print("{}, {s}\n", .{ counter, formatted_str });
        std.time.sleep(1000000000);
    }

    glContext = gl.glXCreateContext(@ptrCast(display), @ptrCast(x11.XDefaultVisual(display, screen)), null, 1);
    _ = gl.glXMakeCurrent(@ptrCast(display), window, glContext);
    std.debug.print("5\n", .{});
}

// Handle keyboard input (move player)
fn handleInput(event: x11.XEvent) void {
    if (event.type == x11.KeyPress) {
        const key = x11.XLookupKeysym(@ptrCast(@constCast(&event.xkey)), 0);
        if (key == 'q') {
            std.debug.print("Quitting...\n", .{});
            _ = x11.XCloseDisplay(display);
            std.process.exit(0);
        }
    }
}

// Render Scene (Triangle & Lines)
fn render() void {
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    // Draw a red triangle
    gl.glBegin(gl.GL_TRIANGLES);
    gl.glColor3f(1.0, 0.0, 0.0);
    gl.glVertex2f(-0.5, -0.5);
    gl.glVertex2f(0.5, -0.5);
    gl.glVertex2f(0.0, 0.5);
    gl.glEnd();

    // Draw a blue line
    gl.glBegin(gl.GL_LINES);
    gl.glColor3f(0.0, 0.0, 1.0);
    gl.glVertex2f(-0.5, 0.0);
    gl.glVertex2f(0.5, 0.0);
    gl.glEnd();

    gl.glXSwapBuffers(@ptrCast(display), window);
}

// Game Loop
fn runGame() void {
    var event: x11.XEvent = undefined;
    std.debug.print("8\n", .{});
    while (true) {
        while (x11.XPending(display) > 0) {
            _ = x11.XNextEvent(display, &event);
            handleInput(event);
        }
        render();
        std.debug.print("9\n", .{});
    }
}

// Entry Point
pub fn main() !void {
    try initWindow();
    std.debug.print("7\n", .{});
    runGame();
}
