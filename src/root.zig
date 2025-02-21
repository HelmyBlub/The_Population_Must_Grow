const std = @import("std");

const ChatSimState = struct {
    citizens: [10000]Citizen,
};
const ChatSimMap: type = struct {
    tileSize: u8,
    length: u16,
};

const Position: type = struct {
    x: f32,
    y: f32,
};

const Citizen: type = struct {
    position: Position,
    moveTo: ?Position,
    moveSpeed: f16,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, {s}!\n", .{"world"});
    first();
}

fn first() void {
    var state: ChatSimState = .{
        .citizens = undefined,
    };

    for (&state.citizens) |*citizen| {
        citizen.* = createCitizen();
    }
    std.debug.print("First citizen: {}\n", .{state.citizens[0]});
    for (0..10) |_| {
        const start = std.time.microTimestamp();
        for (0..600) |_| {
            citizensMove(&state);
        }
        std.debug.print("First citizen: {}\n", .{state.citizens[0]});
        const end = std.time.microTimestamp();
        std.debug.print("for time: {} microseconds\n", .{end - start});
    }
}

fn createCitizen() Citizen {
    return Citizen{
        .position = .{ .x = 0, .y = 0 },
        .moveTo = null,
        .moveSpeed = 2,
    };
}

fn citizensMove(state: *ChatSimState) void {
    for (&state.citizens) |*citizen| {
        citizenMove(citizen);
    }
}

fn citizenMove(citizen: *Citizen) void {
    if (citizen.moveTo == null) {
        const rand = std.crypto.random;
        citizen.moveTo = .{ .x = rand.float(f32) * 100 - 50, .y = rand.float(f32) * 100 - 50 };
    } else {
        const direction: f32 = calculateDirection(citizen.position, citizen.moveTo.?);
        citizen.position.x += std.math.sin(direction) * citizen.moveSpeed;
        citizen.position.y += std.math.cos(direction) * citizen.moveSpeed;
    }
}

fn calculateDirection(startPos: Position, targetPos: Position) f32 {
    var direction: f32 = 0;
    const yDiff = (startPos.y - targetPos.y);
    const xDiff = (startPos.x - targetPos.x);

    if (xDiff >= 0) {
        if (xDiff == 0) return 0;
        direction = -std.math.pi + std.math.atan(yDiff / xDiff);
    } else if (yDiff < 0) {
        direction = -std.math.atan(xDiff / yDiff) + std.math.pi / 2.0;
    } else {
        if (yDiff == 0) return 0;
        direction = -std.math.atan(xDiff / yDiff) - std.math.pi / 2.0;
    }
    return direction;
}
