const std = @import("std");
const main = @import("main.zig");
const Position = main.Position;

pub const Citizen: type = struct {
    position: Position,
    moveTo: ?Position = null,
    moveSpeed: f16,
    buildingIndex: ?usize = null,
    treeIndex: ?usize = null,
    hasWood: bool = false,

    pub fn createCitizen() Citizen {
        return Citizen{
            .position = .{ .x = 0, .y = 0 },
            .moveSpeed = 0.5,
        };
    }

    pub fn citizensMove(state: *main.ChatSimState) !void {
        var spawnCounter: u32 = 0;
        for (state.citizens.items) |*citizen| {
            const result = try citizenMove(citizen, state);
            if (result) spawnCounter += 1;
        }
        for (0..spawnCounter) |_| {
            const newCitizen = main.Citizen.createCitizen();
            try state.citizens.append(newCitizen);
        }
    }

    pub fn citizenMove(citizen: *Citizen, state: *main.ChatSimState) !bool {
        if (citizen.buildingIndex != null) {
            var chunk = state.chunks.get("0_0").?;
            if (citizen.treeIndex == null and citizen.hasWood == false) {
                findFastestTreeAndMoveTo(citizen, state);
            } else if (citizen.treeIndex != null and citizen.hasWood == false) {
                if (@abs(citizen.position.x - citizen.moveTo.?.x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.?.y) < citizen.moveSpeed) {
                    citizen.hasWood = true;
                    var tree = &chunk.trees.items[citizen.treeIndex.?];
                    tree.grow = 0;
                    tree.citizenOnTheWay = false;
                    citizen.treeIndex = null;
                    const targetBuilding = chunk.buildings.items[citizen.buildingIndex.?];
                    citizen.moveTo = .{ .x = targetBuilding.position.x, .y = targetBuilding.position.y };
                    return false;
                }
            } else if (citizen.treeIndex == null and citizen.hasWood == true) {
                if (@abs(citizen.position.x - citizen.moveTo.?.x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.?.y) < citizen.moveSpeed) {
                    citizen.hasWood = false;
                    citizen.treeIndex = null;
                    var building: *main.Building = &chunk.buildings.items[citizen.buildingIndex.?];
                    building.inConstruction = false;
                    citizen.buildingIndex = null;
                    citizen.moveTo = null;
                    if (building.type == main.BUILDING_TYPE_HOUSE) {
                        return true;
                    } else if (building.type == main.BUILDING_TYPE_TREE_FARM) {
                        //try to place around the house
                        for (0..5) |i| {
                            for (0..5) |j| {
                                const position: main.Position = .{
                                    .x = building.position.x + (@as(f32, @floatFromInt(i)) - 2) * 20,
                                    .y = building.position.y + (@as(f32, @floatFromInt(j)) - 2) * 20,
                                };
                                if (main.mapIsTilePositionFree(position, state) == false) continue;
                                const newTree: main.MapTree = .{
                                    .position = position,
                                    .grow = 0,
                                };
                                try chunk.trees.append(newTree);
                            }
                        }
                        try state.chunks.put("0_0", chunk);
                        return false;
                    }
                }
            }
        } else if (citizen.moveTo == null) {
            const rand = std.crypto.random;
            citizen.moveTo = .{ .x = rand.float(f32) * 400.0 - 200.0, .y = rand.float(f32) * 400.0 - 200.0 };
        } else {
            if (@abs(citizen.position.x - citizen.moveTo.?.x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.?.y) < citizen.moveSpeed) {
                citizen.moveTo = null;
                return false;
            }
        }
        const direction: f32 = main.calculateDirection(citizen.position, citizen.moveTo.?);
        citizen.position.x += std.math.cos(direction) * citizen.moveSpeed;
        citizen.position.y += std.math.sin(direction) * citizen.moveSpeed;
        return false;
    }

    pub fn randomlyPlace(state: *main.ChatSimState) void {
        const rand = std.crypto.random;
        for (state.citizens.items) |*citizen| {
            citizen.position.x = rand.float(f32) * 400.0 - 200.0;
            citizen.position.y = rand.float(f32) * 400.0 - 200.0;
        }
    }
};

fn findFastestTreeAndMoveTo(citizen: *Citizen, state: *main.ChatSimState) void {
    const chunk = state.chunks.getPtr("0_0").?;
    const targetPosition: main.Position = chunk.buildings.items[citizen.buildingIndex.?].position;
    var closestTree: ?*main.MapTree = null;
    var closestTreeIndex: usize = 0;
    var fastestDistance: f32 = 0;
    for (chunk.trees.items, 0..) |*tree, i| {
        if (tree.grow < 1 or tree.citizenOnTheWay) continue;
        const tempDistance: f32 = main.calculateDistance(citizen.position, tree.position) + main.calculateDistance(tree.position, targetPosition);
        if (closestTree == null or fastestDistance > tempDistance) {
            closestTree = tree;
            closestTreeIndex = i;
            fastestDistance = tempDistance;
        }
    }
    if (closestTree != null) {
        citizen.treeIndex = closestTreeIndex;
        closestTree.?.citizenOnTheWay = true;
        citizen.moveTo = .{ .x = closestTree.?.position.x, .y = closestTree.?.position.y };
    }
}
