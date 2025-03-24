const std = @import("std");
const main = @import("main.zig");
const Position = main.Position;

pub const Citizen: type = struct {
    position: Position,
    moveTo: ?Position,
    moveSpeed: f16,

    pub fn createCitizen() Citizen {
        return Citizen{
            .position = .{ .x = 0, .y = 0 },
            .moveTo = null,
            .moveSpeed = 0.1,
        };
    }

    pub fn citizensMove(state: *main.ChatSimState) void {
        for (state.citizens.items) |*citizen| {
            citizenMove(citizen);
        }
    }

    pub fn citizenMove(citizen: *Citizen) void {
        if (citizen.moveTo == null) {
            const rand = std.crypto.random;
            citizen.moveTo = .{ .x = rand.float(f32) * 400.0 - 200.0, .y = rand.float(f32) * 400.0 - 200.0 };
        } else {
            if (@abs(citizen.position.x - citizen.moveTo.?.x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.?.y) < citizen.moveSpeed) {
                citizen.moveTo = null;
                return;
            }
            const direction: f32 = main.calculateDirection(citizen.position, citizen.moveTo.?);
            citizen.position.x += std.math.cos(direction) * citizen.moveSpeed;
            citizen.position.y += std.math.sin(direction) * citizen.moveSpeed;
        }
    }

    pub fn randomlyPlace(state: *main.ChatSimState) void {
        const rand = std.crypto.random;
        for (state.citizens.items) |*citizen| {
            citizen.position.x = rand.float(f32) * 400.0 - 200.0;
            citizen.position.y = rand.float(f32) * 400.0 - 200.0;
        }
    }
};
