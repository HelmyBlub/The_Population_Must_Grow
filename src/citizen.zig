const std = @import("std");
const main = @import("main.zig");
const Position = main.Position;
const mapZig = @import("map.zig");

pub const Citizen: type = struct {
    position: Position,
    moveTo: std.ArrayList(main.Position),
    executingUntil: ?u32 = null,
    moveSpeed: f16,
    idle: bool = true,
    buildingPosition: ?main.Position = null,
    treePosition: ?main.Position = null,
    farmPosition: ?main.Position = null,
    potatoPosition: ?main.Position = null,
    hasWood: bool = false,
    homePosition: ?Position = null,
    foodLevel: f32 = 1,
    deadUntil: ?u32 = null,
    pathSearchFailedTimeMs: ?u32 = null,
    pub const MAX_SQUARE_TILE_SEARCH_DISTANCE = 50;
    pub const FAILED_PATH_SEARCH_WAIT_TIME_MS = 1000;

    pub fn createCitizen(allocator: std.mem.Allocator) Citizen {
        return Citizen{
            .position = .{ .x = 0, .y = 0 },
            .moveSpeed = 2.0,
            .moveTo = std.ArrayList(main.Position).init(allocator),
        };
    }

    pub fn destroyCitizens(chunk: *mapZig.MapChunk) void {
        for (chunk.citizens.items) |*citizen| {
            citizen.moveTo.deinit();
        }
    }

    pub fn citizensTick(chunk: *mapZig.MapChunk, state: *main.ChatSimState) !void {
        for (0..chunk.citizens.items.len) |i| {
            const citizen: *Citizen = &chunk.citizens.items[i];
            if (citizen.deadUntil) |deadUntil| {
                if (state.gameTimeMs > deadUntil) {
                    citizen.deadUntil = null;
                    citizen.foodLevel = 1;
                }
            } else {
                try foodTick(citizen, state);
                try citizenMove(citizen, state);
            }
        }
    }

    pub fn moveToPosition(self: *Citizen, target: main.Position, state: *main.ChatSimState) !void {
        // _ = state;
        // try self.moveTo.append(target);
        const start = mapZig.mapPositionToTileXy(self.position);
        const goal = mapZig.mapPositionToTileXy(target);
        const foundPath = try main.pathfindingZig.pathfindAStar(start, goal, self, state);
        if (!foundPath) {
            self.pathSearchFailedTimeMs = state.gameTimeMs;
        }
    }

    pub fn citizenMove(citizen: *Citizen, state: *main.ChatSimState) !void {
        if (citizen.pathSearchFailedTimeMs) |failedSearchTime| {
            if (failedSearchTime + Citizen.FAILED_PATH_SEARCH_WAIT_TIME_MS < state.gameTimeMs) {
                citizen.pathSearchFailedTimeMs = null;
            } else {
                return;
            }
        }
        if (citizen.potatoPosition) |potatoPosition| {
            if (citizen.moveTo.items.len == 0 and (citizen.executingUntil == null or citizen.executingUntil.? <= state.gameTimeMs)) {
                if (try mapZig.getPotatoFieldOnPosition(potatoPosition, state)) |farmTile| {
                    if (main.calculateDistance(farmTile.position, citizen.position) <= citizen.moveSpeed) {
                        if (citizen.executingUntil == null) {
                            if (farmTile.grow >= 1) {
                                farmTile.grow = 0;
                                farmTile.citizenOnTheWay -= 1;
                                citizen.executingUntil = state.gameTimeMs + 1000;
                            }
                        } else if (citizen.executingUntil.? <= state.gameTimeMs) {
                            citizen.potatoPosition = null;
                            citizen.foodLevel += 0.5;
                            citizen.executingUntil = null;
                        }
                    } else {
                        try citizen.moveToPosition(.{ .x = farmTile.position.x, .y = farmTile.position.y }, state);
                    }
                } else {
                    citizen.potatoPosition = null;
                }
            }
        } else if (citizen.farmPosition) |farmPosition| {
            if (citizen.moveTo.items.len == 0 and (citizen.executingUntil == null or citizen.executingUntil.? <= state.gameTimeMs)) {
                if (try mapZig.getPotatoFieldOnPosition(farmPosition, state)) |farmTile| {
                    if (main.calculateDistance(farmTile.position, citizen.position) <= citizen.moveSpeed) {
                        if (citizen.executingUntil == null) {
                            if (try mapZig.canBuildOrWaitForTreeCutdown(farmPosition, state)) {
                                farmTile.planted = true;
                                citizen.executingUntil = state.gameTimeMs + 1000;
                            }
                        } else if (citizen.executingUntil.? <= state.gameTimeMs) {
                            citizen.executingUntil = null;
                            citizen.farmPosition = null;
                            citizen.idle = true;
                        }
                    } else {
                        try citizen.moveToPosition(.{ .x = farmTile.position.x, .y = farmTile.position.y }, state);
                    }
                } else {
                    citizen.farmPosition = null;
                    citizen.idle = true;
                }
            }
        } else if (citizen.buildingPosition) |buildingPosition| {
            if (citizen.moveTo.items.len == 0 and (citizen.executingUntil == null or citizen.executingUntil.? <= state.gameTimeMs)) {
                if (citizen.treePosition == null and citizen.hasWood == false) {
                    try findAndSetFastestTree(citizen, buildingPosition, state);
                    if (citizen.treePosition == null and try mapZig.getBuildingOnPosition(buildingPosition, state) == null) {
                        citizen.hasWood = false;
                        citizen.treePosition = null;
                        citizen.buildingPosition = null;
                        citizen.moveTo.clearAndFree();
                        citizen.idle = true;
                    }
                } else if (citizen.treePosition != null and citizen.hasWood == false) {
                    const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(citizen.treePosition.?, state);
                    if (main.calculateDistance(citizen.treePosition.?, citizen.position) < mapZig.GameMap.TILE_SIZE) {
                        for (chunk.trees.items, 0..) |*tree, i| {
                            if (main.calculateDistance(citizen.treePosition.?, tree.position) < mapZig.GameMap.TILE_SIZE) {
                                if (citizen.executingUntil == null) {
                                    citizen.executingUntil = state.gameTimeMs + 1000;
                                    return;
                                } else if (citizen.executingUntil.? <= state.gameTimeMs) {
                                    citizen.executingUntil = null;
                                    citizen.hasWood = true;
                                    tree.grow = 0;
                                    tree.citizenOnTheWay = false;
                                    citizen.treePosition = null;
                                    try citizen.moveToPosition(buildingPosition, state);
                                    if (!tree.regrow) {
                                        _ = chunk.trees.swapRemove(i);
                                    }
                                    return;
                                }
                            }
                        }
                        citizen.treePosition = null;
                    } else {
                        try citizen.moveToPosition(citizen.treePosition.?, state);
                    }
                } else if (citizen.treePosition == null and citizen.hasWood == true) {
                    if (try mapZig.getBuildingOnPosition(buildingPosition, state)) |building| {
                        if (building.inConstruction == false) {
                            citizen.hasWood = false;
                            citizen.treePosition = null;
                            citizen.buildingPosition = null;
                            citizen.moveTo.clearAndFree();
                            citizen.idle = true;
                            return;
                        }
                        if (main.calculateDistance(citizen.position, buildingPosition) < mapZig.GameMap.TILE_SIZE) {
                            if (citizen.executingUntil == null) {
                                citizen.executingUntil = state.gameTimeMs + 1000;
                            } else if (citizen.executingUntil.? <= state.gameTimeMs) {
                                if (try mapZig.canBuildOrWaitForTreeCutdown(buildingPosition, state)) {
                                    citizen.executingUntil = null;
                                    citizen.hasWood = false;
                                    citizen.treePosition = null;
                                    citizen.buildingPosition = null;
                                    citizen.moveTo.clearAndFree();
                                    citizen.idle = true;
                                    building.woodRequired -= 1;
                                    if (building.type == mapZig.BUILDING_TYPE_HOUSE) {
                                        building.inConstruction = false;
                                        const buildRectangle = mapZig.get1x1RectangleFromPosition(building.position);
                                        try main.pathfindingZig.changePathingDataRectangle(buildRectangle, mapZig.PathingType.blocking, state);
                                        var newCitizen = main.Citizen.createCitizen(state.allocator);
                                        newCitizen.position = buildingPosition;
                                        newCitizen.homePosition = newCitizen.position;
                                        try mapZig.placeCitizen(newCitizen, state);
                                        building.citizensSpawned += 1;
                                        return;
                                    } else if (building.type == mapZig.BUILDING_TYPE_BIG_HOUSE) {
                                        if (building.woodRequired == 0) {
                                            building.inConstruction = false;
                                            const buildRectangle = mapZig.getBigBuildingRectangle(building.position);
                                            try main.pathfindingZig.changePathingDataRectangle(buildRectangle, mapZig.PathingType.blocking, state);
                                            while (building.citizensSpawned < 8) {
                                                var newCitizen = main.Citizen.createCitizen(state.allocator);
                                                newCitizen.position = buildingPosition;
                                                newCitizen.homePosition = newCitizen.position;
                                                try mapZig.placeCitizen(newCitizen, state);
                                                building.citizensSpawned += 1;
                                            }
                                            return;
                                        }
                                    }
                                }
                            }
                        } else {
                            try citizen.moveToPosition(buildingPosition, state);
                        }
                    } else {
                        citizen.hasWood = false;
                        citizen.treePosition = null;
                        citizen.buildingPosition = null;
                        citizen.moveTo.clearAndFree();
                        citizen.idle = true;
                    }
                }
            }
        } else if (citizen.treePosition != null) {
            if (citizen.moveTo.items.len == 0 and (citizen.executingUntil == null or citizen.executingUntil.? <= state.gameTimeMs)) {
                if (try mapZig.getTreeOnPosition(citizen.treePosition.?, state)) |tree| {
                    if (main.calculateDistance(citizen.position, tree.position) < mapZig.GameMap.TILE_SIZE) {
                        if (citizen.executingUntil == null) {
                            citizen.executingUntil = state.gameTimeMs + 1000;
                            tree.planted = true;
                        } else if (citizen.executingUntil.? <= state.gameTimeMs) {
                            citizen.executingUntil = null;
                            citizen.treePosition = null;
                            citizen.idle = true;
                        }
                    } else {
                        try citizen.moveToPosition(tree.position, state);
                    }
                } else {
                    citizen.treePosition = null;
                    citizen.idle = true;
                }
            }
        } else if (citizen.moveTo.items.len == 0) {
            try setRandomMoveTo(citizen, state);
        } else {
            if (@abs(citizen.position.x - citizen.moveTo.getLast().x) < citizen.moveSpeed and @abs(citizen.position.y - citizen.moveTo.getLast().y) < citizen.moveSpeed) {
                _ = citizen.moveTo.pop();
                return;
            }
        }
        if (citizen.moveTo.items.len > 0) {
            const moveTo = citizen.moveTo.getLast();
            const direction: f32 = main.calculateDirection(citizen.position, moveTo);
            citizen.position.x += std.math.cos(direction) * citizen.moveSpeed;
            citizen.position.y += std.math.sin(direction) * citizen.moveSpeed;
            if (@abs(citizen.position.x - moveTo.x) < citizen.moveSpeed and @abs(citizen.position.y - moveTo.y) < citizen.moveSpeed) {
                _ = citizen.moveTo.pop();
            }
        }
    }

    pub fn randomlyPlace(chunk: *mapZig.MapChunk) void {
        const rand = std.crypto.random;
        for (chunk.citizens.items) |*citizen| {
            citizen.position.x = rand.float(f32) * 400.0 - 200.0;
            citizen.position.y = rand.float(f32) * 400.0 - 200.0;
        }
    }

    pub fn findClosestFreeCitizen(targetPosition: main.Position, state: *main.ChatSimState) !?*Citizen {
        var closestCitizen: ?*Citizen = null;
        var shortestDistance: f32 = 0;

        var topLeftChunk = mapZig.getChunkXyForPosition(targetPosition);
        var iteration: u8 = 0;
        const maxIterations: u8 = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
        while (closestCitizen == null and iteration < maxIterations) {
            const loops = iteration * 2 + 1;
            for (0..loops) |x| {
                for (0..loops) |y| {
                    if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                    const chunkXY: mapZig.ChunkXY = .{
                        .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                        .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                    };
                    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
                    for (chunk.citizens.items) |*citizen| {
                        if (!citizen.idle) continue;
                        const tempDistance: f32 = main.calculateDistance(targetPosition, citizen.position);
                        if (closestCitizen == null or shortestDistance > tempDistance) {
                            closestCitizen = citizen;
                            shortestDistance = tempDistance;
                        }
                    }
                }
            }
            iteration += 1;
            topLeftChunk.chunkX -= 1;
            topLeftChunk.chunkY -= 1;
        }
        return closestCitizen;
    }
};

fn foodTick(citizen: *Citizen, state: *main.ChatSimState) !void {
    const hungryBefore = !(citizen.foodLevel > 0.5);
    citizen.foodLevel -= 1.0 / 60.0 / 60.0;
    if (citizen.foodLevel > 0.5 or citizen.potatoPosition != null or citizen.executingUntil != null or (hungryBefore and citizen.moveTo.items.len > 0)) return;
    if (try findClosestFreePotato(citizen.position, state)) |potato| {
        potato.citizenOnTheWay += 1;
        citizen.potatoPosition = potato.position;
        citizen.moveTo.clearAndFree();
    } else if (citizen.foodLevel <= 0) {
        citizen.deadUntil = state.gameTimeMs + 60_000;
        if (citizen.homePosition) |pos| citizen.position = pos;
        std.debug.print("citizen starved to death\n", .{});
    }
}

pub fn findClosestFreePotato(targetPosition: main.Position, state: *main.ChatSimState) !?*mapZig.PotatoField {
    var shortestDistance: f32 = 0;
    var resultPotatoField: ?*mapZig.PotatoField = null;
    var topLeftChunk = mapZig.getChunkXyForPosition(targetPosition);
    var iteration: u8 = 0;
    const maxIterations: u8 = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
    while (resultPotatoField == null and iteration < maxIterations) {
        const loops = iteration * 2 + 1;
        for (0..loops) |x| {
            for (0..loops) |y| {
                if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                const chunkXY: mapZig.ChunkXY = .{
                    .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                    .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                };
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
                for (chunk.potatoFields.items) |*potatoField| {
                    if (!potatoField.planted or potatoField.citizenOnTheWay >= 2) continue;
                    if (potatoField.citizenOnTheWay > 0 and potatoField.grow < 1) continue;
                    const tempDistance: f32 = main.calculateDistance(targetPosition, potatoField.position) + (1.0 - potatoField.grow + @as(f32, @floatFromInt(potatoField.citizenOnTheWay))) * 40.0;
                    if (resultPotatoField == null or shortestDistance > tempDistance) {
                        shortestDistance = tempDistance;
                        resultPotatoField = potatoField;
                    }
                }
            }
        }
        iteration += 1;
        topLeftChunk.chunkX -= 1;
        topLeftChunk.chunkY -= 1;
    }

    return resultPotatoField;
}

fn findAndSetFastestTree(citizen: *Citizen, targetPosition: Position, state: *main.ChatSimState) !void {
    var closestTree: ?*mapZig.MapTree = null;
    var fastestDistance: f32 = 0;
    var topLeftChunk = mapZig.getChunkXyForPosition(citizen.position);
    var iteration: u8 = 0;
    const maxIterations: u8 = @divFloor(Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE, mapZig.GameMap.CHUNK_LENGTH);
    while (closestTree == null and iteration < maxIterations) {
        const loops = iteration * 2 + 1;
        for (0..loops) |x| {
            for (0..loops) |y| {
                if (x != 0 and x != loops - 1 and y != 0 and y != loops - 1) continue;
                const chunkXY: mapZig.ChunkXY = .{
                    .chunkX = topLeftChunk.chunkX + @as(i32, @intCast(x)),
                    .chunkY = topLeftChunk.chunkY + @as(i32, @intCast(y)),
                };
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
                for (chunk.trees.items) |*tree| {
                    if (tree.grow < 1 or tree.citizenOnTheWay) continue;
                    const tempDistance: f32 = main.calculateDistance(citizen.position, tree.position) + main.calculateDistance(tree.position, targetPosition);
                    if (closestTree == null or fastestDistance > tempDistance) {
                        closestTree = tree;
                        fastestDistance = tempDistance;
                    }
                }
            }
        }
        iteration += 1;
        topLeftChunk.chunkX -= 1;
        topLeftChunk.chunkY -= 1;
    }
    if (closestTree != null) {
        citizen.treePosition = closestTree.?.position;
        closestTree.?.citizenOnTheWay = true;
    } else {
        try setRandomMoveTo(citizen, state);
    }
}

fn setRandomMoveTo(citizen: *Citizen, state: *main.ChatSimState) !void {
    const randomPos = try main.pathfindingZig.getRandomClosePathingPosition(citizen, state);
    try citizen.moveToPosition(randomPos, state);
}
