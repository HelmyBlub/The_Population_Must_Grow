const std = @import("std");
const main = @import("main.zig");
const Position = main.Position;

pub const Citizen: type = struct {
    position: Position,
    moveTo: ?Position = null,
    moveSpeed: f16,
    idle: bool = true,
    buildingIndex: ?usize = null,
    treeIndex: ?usize = null,
    farmIndex: ?usize = null,
    potatoIndex: ?usize = null,
    hasWood: bool = false,
    homePosition: ?Position = null,
    foodLevel: f32 = 1,
    deadUntil: ?u32 = null,

    pub fn createCitizen() Citizen {
        return Citizen{
            .position = .{ .x = 0, .y = 0 },
            .moveSpeed = 2.0,
        };
    }

    pub fn citizensTick(state: *main.ChatSimState) !void {
        for (0..state.citizens.items.len) |i| {
            const citizen: *Citizen = &state.citizens.items[i];
            if (citizen.deadUntil) |deadUntil| {
                if (state.gameTimeMs > deadUntil) {
                    citizen.deadUntil = null;
                    citizen.foodLevel = 1;
                }
            } else {
                foodTick(citizen, state);
                try citizenMove(citizen, state);
            }
        }
    }

    pub fn citizenMove(citizen: *Citizen, state: *main.ChatSimState) !void {
        if (citizen.potatoIndex) |potatoIndex| {
            if (citizen.moveTo == null) {
                var chunk = state.chunks.getPtr("0_0").?;
                const farmTile = &chunk.potatoFields.items[potatoIndex];
                if (main.calculateDistance(farmTile.position, citizen.position) <= citizen.moveSpeed) {
                    if (farmTile.grow >= 1) {
                        farmTile.grow = 0;
                        farmTile.citizenOnTheWay -= 1;
                        citizen.potatoIndex = null;
                        citizen.foodLevel += 0.5;
                    }
                } else {
                    citizen.moveTo = .{ .x = farmTile.position.x, .y = farmTile.position.y };
                }
            }
        } else if (citizen.farmIndex) |farmIndex| {
            if (citizen.moveTo == null) {
                var chunk = state.chunks.getPtr("0_0").?;
                const farmTile = &chunk.potatoFields.items[farmIndex];
                if (main.calculateDistance(farmTile.position, citizen.position) <= citizen.moveSpeed) {
                    farmTile.planted = true;
                    citizen.farmIndex = null;
                    citizen.idle = true;
                } else {
                    citizen.moveTo = .{ .x = farmTile.position.x, .y = farmTile.position.y };
                }
            }
        } else if (citizen.buildingIndex != null) {
            var chunk = state.chunks.getPtr("0_0").?;
            if (citizen.moveTo == null) {
                if (citizen.treeIndex == null and citizen.hasWood == false) {
                    findFastestTreeAndMoveTo(citizen, state);
                } else if (citizen.treeIndex != null and citizen.hasWood == false) {
                    citizen.hasWood = true;
                    var tree = &chunk.trees.items[citizen.treeIndex.?];
                    tree.grow = 0;
                    tree.citizenOnTheWay = false;
                    citizen.treeIndex = null;
                    const targetBuilding = chunk.buildings.items[citizen.buildingIndex.?];
                    citizen.moveTo = .{ .x = targetBuilding.position.x, .y = targetBuilding.position.y };
                    return;
                } else if (citizen.treeIndex == null and citizen.hasWood == true) {
                    citizen.hasWood = false;
                    citizen.treeIndex = null;
                    var building: *main.Building = &chunk.buildings.items[citizen.buildingIndex.?];
                    building.inConstruction = false;
                    citizen.buildingIndex = null;
                    citizen.moveTo = null;
                    citizen.idle = true;
                    if (building.type == main.BUILDING_TYPE_HOUSE) {
                        var newCitizen = main.Citizen.createCitizen();
                        newCitizen.position = citizen.position;
                        newCitizen.homePosition = newCitizen.position;
                        try state.citizens.append(newCitizen);
                        return;
                    } else if (building.type == main.BUILDING_TYPE_TREE_FARM) {
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
                        return;
                    }
                }
            }
        } else if (citizen.moveTo == null) {
            const rand = std.crypto.random;
            citizen.moveTo = .{
                .x = rand.float(f32) * 400.0 - 200.0,
                .y = rand.float(f32) * 400.0 - 200.0,
            };
            if (citizen.homePosition) |pos| {
                citizen.moveTo.?.x += pos.x;
                citizen.moveTo.?.y += pos.y;
            }
        } else {
            if (@abs(citizen.position.x - citizen.moveTo.?.x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.?.y) < citizen.moveSpeed) {
                citizen.moveTo = null;
                return;
            }
        }
        if (citizen.moveTo) |moveTo| {
            const direction: f32 = main.calculateDirection(citizen.position, moveTo);
            citizen.position.x += std.math.cos(direction) * citizen.moveSpeed;
            citizen.position.y += std.math.sin(direction) * citizen.moveSpeed;
            if (@abs(citizen.position.x - moveTo.x) < citizen.moveSpeed and @abs(citizen.position.y - moveTo.y) < citizen.moveSpeed) {
                citizen.moveTo = null;
            }
        }
    }

    pub fn randomlyPlace(state: *main.ChatSimState) void {
        const rand = std.crypto.random;
        for (state.citizens.items) |*citizen| {
            citizen.position.x = rand.float(f32) * 400.0 - 200.0;
            citizen.position.y = rand.float(f32) * 400.0 - 200.0;
        }
    }

    pub fn findClosestFreeCitizen(targetPosition: main.Position, state: *main.ChatSimState) ?*Citizen {
        var closestCitizen: ?*Citizen = null;
        var shortestDistance: f32 = 0;
        for (state.citizens.items) |*citizen| {
            if (!citizen.idle) continue;
            const tempDistance: f32 = main.calculateDistance(targetPosition, citizen.position);
            if (closestCitizen == null or shortestDistance > tempDistance) {
                closestCitizen = citizen;
                shortestDistance = tempDistance;
            }
        }
        return closestCitizen;
    }
};

fn foodTick(citizen: *Citizen, state: *main.ChatSimState) void {
    citizen.foodLevel -= 1.0 / 60.0 / 60.0;
    if (citizen.foodLevel > 0.5 or citizen.potatoIndex != null) return;
    const chunk = state.chunks.getPtr("0_0").?;
    if (findClosestFreePotato(citizen.position, state)) |potatoIndex| {
        const potato = &chunk.potatoFields.items[potatoIndex];
        potato.citizenOnTheWay += 1;
        citizen.potatoIndex = potatoIndex;
        citizen.moveTo = null;
    } else if (citizen.foodLevel <= 0) {
        citizen.deadUntil = state.gameTimeMs + 60_000;
        if (citizen.homePosition) |pos| citizen.position = pos;
        std.debug.print("citizen starved to death\n", .{});
    }
}

pub fn findClosestFreePotato(targetPosition: main.Position, state: *main.ChatSimState) ?usize {
    var shortestDistance: f32 = 0;
    var index: ?usize = null;
    const chunk = state.chunks.getPtr("0_0").?;
    for (chunk.potatoFields.items, 0..) |*potatoField, i| {
        if (!potatoField.planted or potatoField.citizenOnTheWay >= 2) continue;
        if (potatoField.citizenOnTheWay > 0 and potatoField.grow < 1) continue;
        const tempDistance: f32 = main.calculateDistance(targetPosition, potatoField.position) + (1.0 - potatoField.grow + @as(f32, @floatFromInt(potatoField.citizenOnTheWay))) * 40.0;
        if (index == null or shortestDistance > tempDistance) {
            shortestDistance = tempDistance;
            index = i;
        }
    }
    return index;
}

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
