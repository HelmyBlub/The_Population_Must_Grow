const std = @import("std");
const expect = @import("std").testing.expect;
// learn more zig
// zig build-exe src/tryOutZig/justZig.zig
// zig stuff i want to try
//   - vectors
//      - try use vectors with data similar to chatSim data
//   - debugging
//   - multi thread
//      - is debugging different multi threaded?
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
    x: [100_000]f32,
    y: [100_000]f32,
    direction: [100_000]f32,
    speed: [100_000]f32,
};

const Citizen: type = struct {
    position: Position,
    moveTo: ?Position,
    moveSpeed: f16,
};

pub fn main() !void {
    std.debug.print("start justZig!\n", .{});
    const dataAmount: usize = 100_000;
    var dataArray: [dataAmount]Position = undefined;
    for (&dataArray, 0..) |*data, i| {
        data.* = .{ .x = 0, .y = @as(f32, @floatFromInt(i)), .direction = @as(f32, @floatFromInt(i)), .speed = @mod(@as(f32, @floatFromInt(i)), 4.0) + 1.0 };
    }
    var data2: Positions = .{ .x = undefined, .y = undefined, .direction = undefined, .speed = undefined };
    for (0..dataAmount) |i| {
        data2.x[i] = 0;
        data2.y[i] = 0;
        data2.direction[i] = 0.1 * @as(f32, @floatFromInt(i));
        data2.speed[i] = @mod(@as(f32, @floatFromInt(i)), 4.0) + 1.0;
    }
    move(&dataArray);
    moveWithVectors(&data2);
    //    first();
}

const vectorLength = 8;
fn moveWithVectors(positions: *Positions) void {
    const start = std.time.microTimestamp();

    for (0..100) |_| {
        const max: usize = positions.x.len / vectorLength;
        for (0..max) |j| {
            const index = j * vectorLength;
            const directionVector: @Vector(vectorLength, f32) = positions.direction[index..][0..vectorLength].*;
            const speedVector: @Vector(vectorLength, f32) = positions.speed[index..][0..vectorLength].*;
            var posVectorX: @Vector(vectorLength, f32) = positions.x[index..][0..vectorLength].*;
            var posVectorY: @Vector(vectorLength, f32) = positions.y[index..][0..vectorLength].*;
            //            posVectorX += std.math.sin(@as(@Vector(vectorLength, f32), @splat(1))) * @as(@Vector(vectorLength, f32), @splat(2));
            posVectorX += std.math.sin(directionVector) * speedVector;
            posVectorY += std.math.cos(directionVector) * speedVector;
            for (0..vectorLength) |i| {
                positions.x[index + i] = posVectorX[i];
                positions.y[index + i] = posVectorY[i];
            }
        }
        //const oi = 2;
        //std.debug.print("vector data: {d}, {d}, {d}, {d}\n", .{ positions.x[oi], positions.y[oi], positions.direction[oi], positions.speed[oi] });
    }

    const end = std.time.microTimestamp();
    std.debug.print("vector time: {} microseconds\n", .{end - start});
}

fn move(positions: []Position) void {
    const start = std.time.microTimestamp();
    for (0..100) |_| {
        for (positions) |*pos| {
            movePosition(pos);
        }
    }
    const end = std.time.microTimestamp();
    std.debug.print("time: {} microseconds\n", .{end - start});
}

fn movePosition(position: *Position) void {
    position.x += std.math.sin(position.direction) * position.speed;
    position.y += std.math.cos(position.direction) * position.speed;
}

fn movePositionVector(positions: []Position, direction: f32, distance: f32) void {
    positions[0].x += std.math.sin(direction) * distance;
}
