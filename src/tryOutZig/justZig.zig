const std = @import("std");
const expect = @import("std").testing.expect;
// zig stuff i want to try
//  - connect to twitch chat with zig
//      - twitch IRC: older and harder to pass but i can connect anonymously with justinfanxxxx
//          - read more
//      - have to undstand how to use websocket with zig
//      - be able to get one chat message from my twich chat
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
    direction: f32,
    speed: f32,
};

const Positions: type = struct {
    x: [100000]f32,
    y: [100000]f32,
    direction: [100_000]f32,
    speed: [100_000]f32,
};

const PositionsVec: type = struct {
    x: [12500]@Vector(8, f32),
    y: [12500]@Vector(8, f32),
    direction: [12500]@Vector(8, f32),
    speed: [12500]@Vector(8, f32),
};

const Citizen: type = struct {
    position: Position,
    moveTo: ?Position,
    moveSpeed: f16,
};

pub fn main() !void {
    std.debug.print("start justZig!\n", .{});
    const dataAmount: usize = 100_000;
    var data1: [dataAmount]Position = undefined;
    for (&data1, 0..) |*data, i| {
        data.* = .{ .x = 0, .y = @as(f32, @floatFromInt(i)), .direction = @as(f32, @floatFromInt(i)), .speed = @mod(@as(f32, @floatFromInt(i)), 4.0) + 1.0 };
    }
    var data2: Positions = .{ .x = undefined, .y = undefined, .direction = undefined, .speed = undefined };
    for (0..dataAmount) |i| {
        data2.x[i] = 0;
        data2.y[i] = 0;
        data2.direction[i] = 0.1 * @as(f32, @floatFromInt(i));
        data2.speed[i] = @mod(@as(f32, @floatFromInt(i)), 4.0) + 1.0;
    }
    arrayOfStructNoVector(&data1);
    arrayOfSturctsToVector(&data1);
    structOfArrayWithoutVector();
    structOfArraysToVector(&data2);
    structOfVectorArrays();
}

fn arrayOfSturctsToVector(positions: []Position) void {
    const start = std.time.microTimestamp();

    for (0..100) |_| {
        for (0..12500) |j| {
            const index = j * vectorLength;
            var directionVector: @Vector(vectorLength, f32) = undefined;
            var speedVector: @Vector(vectorLength, f32) = undefined;
            var posVectorX: @Vector(vectorLength, f32) = undefined;
            var posVectorY: @Vector(vectorLength, f32) = undefined;
            for (0..8) |k| {
                directionVector[k] = positions[index + k].direction;
                speedVector[k] = positions[index + k].speed;
                posVectorX[k] = positions[index + k].x;
                posVectorY[k] = positions[index + k].y;
            }

            posVectorX += std.math.sin(directionVector) * speedVector;
            posVectorY += std.math.cos(directionVector) * speedVector;
            for (0..vectorLength) |i| {
                positions[index + i].x = posVectorX[i];
                positions[index + i].y = posVectorY[i];
            }
        }
    }

    const end = std.time.microTimestamp();
    std.debug.print("time arrayOfSturctsToVector: {} microseconds\n", .{end - start});
}

fn structOfArrayWithoutVector() void {
    var data2: Positions = .{ .x = undefined, .y = undefined, .direction = undefined, .speed = undefined };
    for (0..100_000) |i| {
        data2.x[i] = 0;
        data2.y[i] = 0;
        data2.direction[i] = 0.1 * @as(f32, @floatFromInt(i));
        data2.speed[i] = @mod(@as(f32, @floatFromInt(i)), 4.0) + 1.0;
    }

    const start = std.time.microTimestamp();
    for (0..100) |_| {
        for (0..100_000) |i| {
            data2.x[i] += std.math.sin(data2.direction[i]) * data2.speed[i];
            data2.y[i] += std.math.cos(data2.direction[i]) * data2.speed[i];
        }
    }
    const end = std.time.microTimestamp();
    std.debug.print("time structOfArrayWithoutVector: {} microseconds\n", .{end - start});
}

const vectorLength = 8;
fn structOfVectorArrays() void {
    var data2: PositionsVec = .{ .x = undefined, .y = undefined, .direction = undefined, .speed = undefined };
    for (0..12500) |i| {
        data2.x[i] = @splat(0);
        data2.y[i] = @splat(0);
        data2.direction[i] = std.simd.iota(f32, 8);
        data2.speed[i] = @splat(2);
    }
    const start = std.time.microTimestamp();

    for (0..100) |_| {
        for (0..12500) |j| {
            data2.x[j] += std.math.sin(data2.direction[j]) * data2.speed[j];
            data2.y[j] += std.math.cos(data2.direction[j]) * data2.speed[j];
        }
    }

    const end = std.time.microTimestamp();
    std.debug.print("time structOfVectorArrays: {} microseconds\n", .{end - start});
}

fn structOfArraysToVector(positions: *Positions) void {
    const start = std.time.microTimestamp();

    for (0..100) |_| {
        const max: usize = positions.x.len / vectorLength;
        for (0..max) |j| {
            const index = j * vectorLength;
            const directionVector: @Vector(vectorLength, f32) = positions.direction[index..][0..vectorLength].*;
            const speedVector: @Vector(vectorLength, f32) = positions.speed[index..][0..vectorLength].*;
            var posVectorX: @Vector(vectorLength, f32) = positions.x[index..][0..vectorLength].*;
            var posVectorY: @Vector(vectorLength, f32) = positions.y[index..][0..vectorLength].*;
            posVectorX += std.math.sin(directionVector) * speedVector;
            posVectorY += std.math.cos(directionVector) * speedVector;
            for (0..vectorLength) |i| {
                positions.x[index + i] = posVectorX[i];
                positions.y[index + i] = posVectorY[i];
            }
        }
    }

    const end = std.time.microTimestamp();
    std.debug.print("time structOfArraysToVector: {} microseconds\n", .{end - start});
}

fn arrayOfStructNoVector(positions: []Position) void {
    const start = std.time.microTimestamp();
    for (0..100) |_| {
        for (positions) |*pos| {
            movePosition(pos);
        }
    }
    const end = std.time.microTimestamp();
    std.debug.print("time arrayOfStructNoVector: {} microseconds\n", .{end - start});
}

fn movePosition(position: *Position) void {
    position.x += std.math.sin(position.direction) * position.speed;
    position.y += std.math.cos(position.direction) * position.speed;
}

fn movePositionVector(positions: []Position, direction: f32, distance: f32) void {
    positions[0].x += std.math.sin(direction) * distance;
}
