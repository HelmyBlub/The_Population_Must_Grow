const std = @import("std");
const main = @import("main.zig");
const mapZig = @import("map.zig");
const imageZig = @import("image.zig");
const pathfindingZig = @import("pathfinding.zig");

const SAVE_EMPTY = 0;
const SAVE_PATH = 1;
const SAVE_TREE = 2;
const SAVE_TREE_AND_PATH = 3;
const SAVE_TREE_AND_BUILD_ORDER_BUILDING = 4;
const SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING = 5;
const SAVE_TREE_AND_BUILD_ORDER_POTATO = 6;
const SAVE_TREE_REGROW = 7;
const SAVE_TREE_BUILD_ORDER = 8;
const SAVE_TREE_GROWING = 9;
const SAVE_POTATO = 10;
const SAVE_POTATO_GROWING = 11;
const SAVE_POTATO_BUILD_ORDER = 12;
const SAVE_BUILDING = 13;
const SAVE_BUILDING_BUILD_ORDER = 14;
const SAVE_BIG_BUILDING = 15;
const SAVE_BIG_BUILDING_BUILD_ORDER = 16;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_1 = 17;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_2 = 18;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_3 = 19;
const SAVE_BIG_BUILDING_BUILD_ORDER_CITIZEN_4 = 20;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE = 21;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_1 = 22;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_2 = 23;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_3 = 24;
const SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE_CITIZEN_4 = 25;

fn getSavePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const game_name = "NumberGoUp";
    const save_folder = "saves";

    const base_dir = try std.fs.getAppDataDir(allocator, game_name);
    defer allocator.free(base_dir);

    const directory_path = try std.fs.path.join(allocator, &.{ base_dir, save_folder });
    defer allocator.free(directory_path);
    try std.fs.cwd().makePath(directory_path);

    const full_path = try std.fs.path.join(allocator, &.{ directory_path, filename });
    return full_path;
}

fn getFileNameForAreaXy(areaXY: main.ChunkAreaXY, allocator: std.mem.Allocator) ![]const u8 {
    // Format the filename: region_x_y.dat
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const writer = buf.writer();
    try writer.print("region_{d}_{d}.dat", .{ areaXY.areaX, areaXY.areaY });

    return getSavePath(allocator, buf.items);
}

pub fn saveChunkAreaToFile(chunkArea: *main.ChunkArea, state: *main.ChatSimState) !void {
    const filepath = try getFileNameForAreaXy(chunkArea.areaXY, state.allocator);
    defer state.allocator.free(filepath);
    const file = try std.fs.cwd().createFile(filepath, .{ .truncate = true });
    defer file.close();
    const writer = file.writer();
    var writeValues: [main.ChunkArea.SIZE * main.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;
    for (0..writeValues.len) |index| {
        writeValues[index] = SAVE_EMPTY;
    }

    for (0..main.ChunkArea.SIZE) |areaChunkX| {
        for (0..main.ChunkArea.SIZE) |areaChunkY| {
            const chunkXY: mapZig.ChunkXY = .{
                .chunkX = (@as(i32, @intCast(areaChunkX)) + chunkArea.areaXY.areaX * main.ChunkArea.SIZE),
                .chunkY = (@as(i32, @intCast(areaChunkY)) + chunkArea.areaXY.areaY * main.ChunkArea.SIZE),
            };
            const writeValueChunkXyIndex: usize = (areaChunkX * main.ChunkArea.SIZE + areaChunkY) * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH;
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
            for (chunk.trees.items) |tree| {
                const writeValueIndex: usize = writeValueChunkXyIndex + positionToWriteIndexTilePart(tree.position);
                var writeValue: u8 = SAVE_TREE;
                if (tree.regrow) {
                    if (tree.growStartTimeMs == null and !tree.fullyGrown) {
                        writeValue = SAVE_TREE_BUILD_ORDER;
                    } else if (tree.growStartTimeMs != null) {
                        writeValue = SAVE_TREE_GROWING;
                    } else {
                        writeValue = SAVE_TREE_REGROW;
                    }
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.pathes.items) |path| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(path);
                var writeValue: u8 = SAVE_PATH;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_PATH;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.potatoFields.items) |potatoField| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(potatoField.position);
                var writeValue: u8 = SAVE_POTATO;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_POTATO;
                } else if (potatoField.growStartTimeMs != null) {
                    writeValue = SAVE_POTATO_GROWING;
                } else if (!potatoField.fullyGrown) {
                    writeValue = SAVE_POTATO_BUILD_ORDER;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.buildings.items) |building| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(building.position);
                var writeValue: u8 = SAVE_BUILDING;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_BUILDING;
                } else if (building.inConstruction) {
                    writeValue = SAVE_BUILDING_BUILD_ORDER;
                }
                writeValues[writeValueIndex] = writeValue;
            }
            for (chunk.bigBuildings.items) |bigBuilding| {
                const writeValueIndex = writeValueChunkXyIndex + positionToWriteIndexTilePart(bigBuilding.position);
                var writeValue: u8 = SAVE_BIG_BUILDING;
                if (writeValues[writeValueIndex] == SAVE_TREE) {
                    writeValue = SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING;
                } else if (bigBuilding.inConstruction) {
                    if (bigBuilding.woodRequired <= 8) {
                        writeValue = SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE;
                    } else {
                        writeValue = SAVE_BIG_BUILDING_BUILD_ORDER;
                    }
                }
                writeValues[writeValueIndex] = writeValue;
            }
        }
    }
    try writer.writeAll(&writeValues);
}

fn positionToWriteIndexTilePart(position: main.Position) usize {
    const tileXY = mapZig.mapPositionToTileXy(position);
    const tileUsizeX: usize = @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH));
    const tileUsizeY: usize = @intCast(@mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH));
    return tileUsizeX * mapZig.GameMap.CHUNK_LENGTH + tileUsizeY;
}

pub fn loadChunkAreaFromFile(areaXY: main.ChunkAreaXY, state: *main.ChatSimState) !void {
    const path = try getFileNameForAreaXy(areaXY, state.allocator);
    defer state.allocator.free(path);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader();
    var readValues: [main.ChunkArea.SIZE * main.ChunkArea.SIZE * mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]u8 = undefined;
    _ = try reader.readAll(&readValues);

    var currentChunkXY: mapZig.ChunkXY = .{ .chunkX = 0, .chunkY = 0 };
    var currentKey: u64 = 0;
    var currenChunk: ?mapZig.MapChunk = null;
    for (readValues, 0..) |value, index| {
        const tileXYIndex = @mod(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
        if (tileXYIndex == 0) {
            const chunkInAreaIndex = @divFloor(index, mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH);
            if (currenChunk) |chunk| {
                if (state.map.chunks.contains(currentKey)) {
                    const oldChunk = state.map.chunks.getPtr(currentKey).?;
                    disconnectPathingBetweenChunkAreas(oldChunk, state);
                    mapZig.destroyChunk(oldChunk);
                }
                try state.map.chunks.put(currentKey, chunk);
            }
            currentChunkXY = .{
                .chunkX = areaXY.areaX * main.ChunkArea.SIZE + @as(i32, @intCast(@divFloor(chunkInAreaIndex, main.ChunkArea.SIZE))),
                .chunkY = areaXY.areaY * main.ChunkArea.SIZE + @as(i32, @intCast(@mod(chunkInAreaIndex, main.ChunkArea.SIZE))),
            };
            currentKey = mapZig.getKeyForChunkXY(currentChunkXY);
            currenChunk = try mapZig.createEmptyChunk(currentChunkXY, state);
            var pathfindChunkData: pathfindingZig.PathfindingChunkData = .{
                .pathingData = undefined,
                .graphRectangles = std.ArrayList(pathfindingZig.ChunkGraphRectangle).init(state.allocator),
            };
            for (0..pathfindChunkData.pathingData.len) |i| {
                pathfindChunkData.pathingData[i] = null;
            }
            currenChunk.?.pathingData = pathfindChunkData;
        }

        const position: main.Position = mapZig.mapTileXyToTileMiddlePosition(.{
            .tileX = @as(i32, @intCast(@divFloor(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
            .tileY = @as(i32, @intCast(@mod(tileXYIndex, mapZig.GameMap.CHUNK_LENGTH))) + currentChunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
        });

        if (currenChunk) |*chunk| {
            switch (value) {
                SAVE_PATH => {
                    try chunk.pathes.append(position);
                },
                SAVE_TREE => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_AND_PATH => {
                    try chunk.pathes.append(position);
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_REGROW => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                        .regrow = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_GROWING => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .growStartTimeMs = state.gameTimeMs,
                        .regrow = true,
                    };
                    const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .tree = chunk.trees.items.len }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
                    try chunk.queue.append(queueItem);
                    try chunk.trees.append(newTree);
                },
                SAVE_TREE_BUILD_ORDER => {
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .regrow = true,
                        .imageIndex = imageZig.IMAGE_GREEN_RECTANGLE,
                    };
                    try chunk.trees.append(newTree);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_POTATO => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.potatoFields.append(newPotato);
                },
                SAVE_TREE_AND_BUILD_ORDER_POTATO => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                    };
                    try chunk.potatoFields.append(newPotato);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_POTATO_GROWING => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                        .growStartTimeMs = state.gameTimeMs,
                    };
                    const queueItem = mapZig.ChunkQueueItem{ .itemData = .{ .potatoField = chunk.potatoFields.items.len }, .executeTime = state.gameTimeMs + mapZig.GROW_TIME_MS };
                    try chunk.queue.append(queueItem);
                    try chunk.potatoFields.append(newPotato);
                },
                SAVE_POTATO_BUILD_ORDER => {
                    const newPotato: mapZig.PotatoField = .{
                        .position = position,
                    };
                    try chunk.potatoFields.append(newPotato);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                        .inConstruction = false,
                        .citizensSpawned = 1,
                        .woodRequired = 0,
                        .imageIndex = imageZig.IMAGE_HOUSE,
                    };
                    var newCitizen = main.Citizen.createCitizen(position, state.allocator);
                    newCitizen.position = position;
                    newCitizen.foodLevel += @as(f32, @floatFromInt(@mod(index, 100))) / 100.0 + 0.5; //should not all want to eat at the same time
                    try chunk.citizens.append(newCitizen);
                    try chunk.buildings.append(newBuilding);
                },
                SAVE_BUILDING_BUILD_ORDER => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                    };
                    try chunk.buildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                },
                SAVE_TREE_AND_BUILD_ORDER_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .house,
                        .position = position,
                    };
                    try chunk.buildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = 1 });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_BIG_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .inConstruction = false,
                        .citizensSpawned = 8,
                        .woodRequired = 0,
                        .imageIndex = imageZig.IMAGE_BIG_HOUSE,
                    };
                    for (0..8) |_| {
                        var newCitizen = main.Citizen.createCitizen(position, state.allocator);
                        newCitizen.position = position;
                        newCitizen.foodLevel += @as(f32, @floatFromInt(@mod(index, 100))) / 100.0 + 0.5; //should not all want to eat at the same time
                        try chunk.citizens.append(newCitizen);
                    }
                    try chunk.bigBuildings.append(newBuilding);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                },
                SAVE_TREE_AND_BUILD_ORDER_BIG_BUILDING => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                    const newTree: mapZig.MapTree = .{
                        .position = position,
                        .fullyGrown = true,
                    };
                    try chunk.trees.append(newTree);
                },
                SAVE_BIG_BUILDING_BUILD_ORDER_HALVE_DONE => {
                    const newBuilding: mapZig.Building = .{
                        .type = .bigHouse,
                        .position = .{ .x = position.x - mapZig.GameMap.TILE_SIZE / 2, .y = position.y - mapZig.GameMap.TILE_SIZE / 2 },
                        .woodRequired = mapZig.Building.BIG_HOUSE_WOOD / 2,
                    };
                    try chunk.bigBuildings.append(newBuilding);
                    try chunk.buildOrders.append(.{ .position = position, .materialCount = newBuilding.woodRequired });
                },

                else => {
                    //missing implementation or nothing to do
                },
            }
        }
    }
    if (currenChunk) |chunk| {
        if (state.map.chunks.contains(currentKey)) {
            const oldChunk = state.map.chunks.getPtr(currentKey).?;
            disconnectPathingBetweenChunkAreas(oldChunk, state);
            mapZig.destroyChunk(oldChunk);
        }
        try state.map.chunks.put(currentKey, chunk);
    }
    try setupPathingForLoadedChunkArea(areaXY, state);
}

fn setupPathingForLoadedChunkArea(areaXY: main.ChunkAreaXY, state: *main.ChatSimState) !void {
    // var chunkArea: main.ChunkArea = .{
    //     .areaXY = areaXY,
    //     .activeChunkKeys = std.ArrayList(main.ChunkAreaActiveKey).init(state.allocator),
    //     .currentChunkKeyIndex = 0,
    // };
    for (0..main.ChunkArea.SIZE) |x| {
        for (0..main.ChunkArea.SIZE) |y| {
            const chunkXY: mapZig.ChunkXY = .{
                .chunkX = @as(i32, @intCast(x)) + areaXY.areaX * main.ChunkArea.SIZE,
                .chunkY = @as(i32, @intCast(y)) + areaXY.areaY * main.ChunkArea.SIZE,
            };
            const chunkKey = mapZig.getKeyForChunkXY(chunkXY);
            const chunk = state.map.chunks.getPtr(chunkKey).?;
            if (chunk.buildings.items.len == 0 and chunk.bigBuildings.items.len == 0) {
                const chunkGraphRectangle: pathfindingZig.ChunkGraphRectangle = .{
                    .index = 0,
                    .chunkKey = chunkKey,
                    .connectionIndexes = std.ArrayList(pathfindingZig.GraphConnection).init(state.allocator),
                    .tileRectangle = .{
                        .topLeftTileXY = .{
                            .tileX = chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
                            .tileY = chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
                        },
                        .columnCount = mapZig.GameMap.CHUNK_LENGTH,
                        .rowCount = mapZig.GameMap.CHUNK_LENGTH,
                    },
                };
                try chunk.pathingData.graphRectangles.append(chunkGraphRectangle);
                const neighbors = [_]mapZig.ChunkXY{
                    .{ .chunkX = chunkXY.chunkX - 1, .chunkY = chunkXY.chunkY },
                    .{ .chunkX = chunkXY.chunkX + 1, .chunkY = chunkXY.chunkY },
                    .{ .chunkX = chunkXY.chunkX, .chunkY = chunkXY.chunkY - 1 },
                    .{ .chunkX = chunkXY.chunkX, .chunkY = chunkXY.chunkY + 1 },
                };
                for (neighbors) |neighbor| {
                    const key = mapZig.getKeyForChunkXY(neighbor);
                    if (state.map.chunks.getPtr(key)) |neighborChunk| {
                        for (neighborChunk.pathingData.graphRectangles.items) |*neighborGraphRectangle| {
                            if (pathfindingZig.areRectanglesTouchingOnEdge(chunkGraphRectangle.tileRectangle, neighborGraphRectangle.tileRectangle)) {
                                try neighborGraphRectangle.connectionIndexes.append(.{ .index = chunkGraphRectangle.index, .chunkKey = chunkKey });
                                try chunk.pathingData.graphRectangles.items[0].connectionIndexes.append(.{ .index = neighborGraphRectangle.index, .chunkKey = key });
                            }
                        }
                    }
                }
                for (0..chunk.pathingData.pathingData.len) |i| {
                    chunk.pathingData.pathingData[i] = chunkGraphRectangle.index;
                }
            } else {
                // case need to determine pathingGraphRectangles as blocking tiles exist
                try setupInitialGraphRectanglesForChunkUnconnected(chunk, chunkKey, state);
                try connectNewGraphRectangles(chunk, chunkKey, state);
            }
        }
    }
}

fn connectNewGraphRectangles(chunk: *mapZig.MapChunk, chunkKey: u64, state: *main.ChatSimState) !void {
    const chunkXY = chunk.chunkXY;
    for (chunk.pathingData.graphRectangles.items, 0..) |*graphRectangle1, index1| {
        for ((index1 + 1)..chunk.pathingData.graphRectangles.items.len) |index2| {
            const graphRectangle2 = &chunk.pathingData.graphRectangles.items[index2];
            if (pathfindingZig.areRectanglesTouchingOnEdge(graphRectangle1.tileRectangle, graphRectangle2.tileRectangle)) {
                try graphRectangle1.connectionIndexes.append(.{ .index = index2, .chunkKey = chunkKey });
                try graphRectangle2.connectionIndexes.append(.{ .index = index1, .chunkKey = chunkKey });
            }
        }
    }
    const neighbors = [_]mapZig.ChunkXY{
        .{ .chunkX = chunkXY.chunkX - 1, .chunkY = chunkXY.chunkY },
        .{ .chunkX = chunkXY.chunkX + 1, .chunkY = chunkXY.chunkY },
        .{ .chunkX = chunkXY.chunkX, .chunkY = chunkXY.chunkY - 1 },
        .{ .chunkX = chunkXY.chunkX, .chunkY = chunkXY.chunkY + 1 },
    };
    for (neighbors) |neighbor| {
        const key = mapZig.getKeyForChunkXY(neighbor);
        if (state.map.chunks.getPtr(key)) |neighborChunk| {
            for (chunk.pathingData.graphRectangles.items, 0..) |*graphRectangle, index1| {
                for (neighborChunk.pathingData.graphRectangles.items) |*neighborGraphRectangle| {
                    if (pathfindingZig.areRectanglesTouchingOnEdge(graphRectangle.tileRectangle, neighborGraphRectangle.tileRectangle)) {
                        try neighborGraphRectangle.connectionIndexes.append(.{ .index = graphRectangle.index, .chunkKey = chunkKey });
                        try chunk.pathingData.graphRectangles.items[index1].connectionIndexes.append(.{ .index = neighborGraphRectangle.index, .chunkKey = key });
                    }
                }
            }
        }
    }
}

fn setupInitialGraphRectanglesForChunkUnconnected(chunk: *mapZig.MapChunk, chunkKey: u64, state: *main.ChatSimState) !void {
    var blockingTiles: [mapZig.GameMap.CHUNK_LENGTH][mapZig.GameMap.CHUNK_LENGTH]bool = undefined;
    for (0..blockingTiles.len) |indexX| {
        for (0..blockingTiles.len) |indexY| {
            blockingTiles[indexX][indexY] = false;
        }
    }
    for (chunk.buildings.items) |building| {
        const tileXY = mapZig.mapPositionToTileXy(building.position);
        const indexX: usize = @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH));
        const indexY: usize = @intCast(@mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH));
        blockingTiles[indexX][indexY] = true;
    }
    for (chunk.bigBuildings.items) |bigBuilding| {
        const tileXY = mapZig.mapPositionToTileXy(bigBuilding.position);
        const indexX: usize = @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH));
        const indexY: usize = @intCast(@mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH));
        blockingTiles[indexX][indexY] = true;
        if (indexX > 0 and indexY > 0) {
            blockingTiles[indexX - 1][indexY] = true;
            blockingTiles[indexX][indexY - 1] = true;
            blockingTiles[indexX - 1][indexY - 1] = true;
        } else if (indexX > 0) {
            blockingTiles[indexX - 1][indexY] = true;
            try pathfindingZig.changePathingDataRectangle(.{
                .topLeftTileXY = .{ .tileX = tileXY.tileX - 1, .tileY = tileXY.tileY - 1 },
                .columnCount = 2,
                .rowCount = 1,
            }, .blocking, 0, state);
        } else if (indexY > 0) {
            blockingTiles[indexX][indexY - 1] = true;
            try pathfindingZig.changePathingDataRectangle(.{
                .topLeftTileXY = .{ .tileX = tileXY.tileX - 1, .tileY = tileXY.tileY - 1 },
                .columnCount = 1,
                .rowCount = 2,
            }, .blocking, 0, state);
        } else {
            try pathfindingZig.changePathingDataRectangle(.{
                .topLeftTileXY = .{ .tileX = tileXY.tileX - 1, .tileY = tileXY.tileY - 1 },
                .columnCount = 2,
                .rowCount = 2,
            }, .blocking, 0, state);
        }
    }
    var usedTiles: [mapZig.GameMap.CHUNK_LENGTH][mapZig.GameMap.CHUNK_LENGTH]bool = undefined;
    for (0..blockingTiles.len) |indexX| {
        for (0..blockingTiles.len) |indexY| {
            usedTiles[indexX][indexY] = false;
        }
    }
    for (0..blockingTiles.len) |indexX| {
        for (0..blockingTiles.len) |indexY| {
            if (usedTiles[indexX][indexY] or blockingTiles[indexX][indexY]) continue;
            var width: u8 = 1;
            var height: u8 = 1;
            while (indexX + width < blockingTiles.len and !usedTiles[indexX + width][indexY] and !blockingTiles[indexX + width][indexY]) {
                width += 1;
            }
            heightLoop: while (indexY + height < blockingTiles.len) {
                for (indexX..(indexX + width)) |checkXIndex| {
                    if (usedTiles[checkXIndex][indexY + height] or blockingTiles[checkXIndex][indexY + height]) {
                        break :heightLoop;
                    }
                }
                height += 1;
            }
            const chunkGraphRectangle: pathfindingZig.ChunkGraphRectangle = .{
                .index = chunk.pathingData.graphRectangles.items.len,
                .chunkKey = chunkKey,
                .connectionIndexes = std.ArrayList(pathfindingZig.GraphConnection).init(state.allocator),
                .tileRectangle = .{
                    .topLeftTileXY = .{
                        .tileX = @as(i32, @intCast(indexX)) + chunk.chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
                        .tileY = @as(i32, @intCast(indexY)) + chunk.chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
                    },
                    .columnCount = width,
                    .rowCount = height,
                },
            };
            try chunk.pathingData.graphRectangles.append(chunkGraphRectangle);
            for (indexX..(indexX + width)) |updateX| {
                for (indexY..(indexY + height)) |updateY| {
                    usedTiles[updateX][updateY] = true;
                    const pathingIndex = pathfindingZig.getPathingIndexForTileXY(.{
                        .tileX = chunk.chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH + @as(i32, @intCast(updateX)),
                        .tileY = chunk.chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH + @as(i32, @intCast(updateY)),
                    });
                    chunk.pathingData.pathingData[pathingIndex] = chunkGraphRectangle.index;
                }
            }
        }
    }
}

fn disconnectPathingBetweenChunkAreas(chunk: *mapZig.MapChunk, state: *main.ChatSimState) void {
    const chunkAreaXPos = @mod(chunk.chunkXY.chunkX, main.ChunkArea.SIZE);
    const chunkAreaYPos = @mod(chunk.chunkXY.chunkY, main.ChunkArea.SIZE);
    const chunkKey = mapZig.getKeyForChunkXY(chunk.chunkXY);
    if (chunkAreaXPos == 0 or chunkAreaXPos == main.ChunkArea.SIZE - 1 or chunkAreaYPos == 0 or chunkAreaYPos == main.ChunkArea.SIZE - 1) {
        var checkLeftKey: ?u64 = if (chunkAreaXPos == 0) mapZig.getKeyForChunkXY(.{ .chunkX = chunk.chunkXY.chunkX - 1, .chunkY = chunk.chunkXY.chunkY }) else null;
        var checkRightKey: ?u64 = if (chunkAreaXPos == main.ChunkArea.SIZE - 1) mapZig.getKeyForChunkXY(.{ .chunkX = chunk.chunkXY.chunkX + 1, .chunkY = chunk.chunkXY.chunkY }) else null;
        var checkTopKey: ?u64 = if (chunkAreaYPos == 0) mapZig.getKeyForChunkXY(.{ .chunkX = chunk.chunkXY.chunkX, .chunkY = chunk.chunkXY.chunkY - 1 }) else null;
        var checkBottomKey: ?u64 = if (chunkAreaYPos == main.ChunkArea.SIZE - 1) mapZig.getKeyForChunkXY(.{ .chunkX = chunk.chunkXY.chunkX, .chunkY = chunk.chunkXY.chunkY + 1 }) else null;

        var chunkLeft: ?*mapZig.MapChunk = undefined;
        if (checkLeftKey) |key| {
            chunkLeft = state.map.chunks.getPtr(key);
            if (chunkLeft == null) checkLeftKey = null;
        }
        var chunkRight: ?*mapZig.MapChunk = undefined;
        if (checkRightKey) |key| {
            chunkRight = state.map.chunks.getPtr(key);
            if (chunkRight == null) checkRightKey = null;
        }
        var chunkTop: ?*mapZig.MapChunk = undefined;
        if (checkTopKey) |key| {
            chunkTop = state.map.chunks.getPtr(key);
            if (chunkTop == null) checkTopKey = null;
        }
        var chunkBottom: ?*mapZig.MapChunk = undefined;
        if (checkBottomKey) |key| {
            chunkBottom = state.map.chunks.getPtr(key);
            if (chunkBottom == null) checkBottomKey = null;
        }

        for (chunk.pathingData.graphRectangles.items, 0..) |graphRectangle, graphRectangleIndex| {
            for (graphRectangle.connectionIndexes.items) |graphConnection| {
                if (checkLeftKey) |key| {
                    if (graphConnection.chunkKey == key) {
                        const adjacentGraphRectangle = &chunkLeft.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkKey == chunkKey and adjacentGraphConnection.index == graphRectangleIndex) {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                pathfindingZig.graphRectangleConnectionMovedUpdate(chunkLeft.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkLeft.?, state);
                                break;
                            }
                        }
                    }
                }
                if (checkRightKey) |key| {
                    if (graphConnection.chunkKey == key) {
                        const adjacentGraphRectangle = &chunkRight.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkKey == chunkKey and adjacentGraphConnection.index == graphRectangleIndex) {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                pathfindingZig.graphRectangleConnectionMovedUpdate(chunkRight.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkRight.?, state);
                                break;
                            }
                        }
                    }
                }
                if (checkTopKey) |key| {
                    if (graphConnection.chunkKey == key) {
                        const adjacentGraphRectangle = &chunkTop.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkKey == chunkKey and adjacentGraphConnection.index == graphRectangleIndex) {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                pathfindingZig.graphRectangleConnectionMovedUpdate(chunkTop.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkTop.?, state);
                                break;
                            }
                        }
                    }
                }
                if (checkBottomKey) |key| {
                    if (graphConnection.chunkKey == key) {
                        const adjacentGraphRectangle = &chunkBottom.?.pathingData.graphRectangles.items[graphConnection.index];
                        for (adjacentGraphRectangle.connectionIndexes.items, 0..) |adjacentGraphConnection, adjacentGraphConnectionIndex| {
                            if (adjacentGraphConnection.chunkKey == chunkKey and adjacentGraphConnection.index == graphRectangleIndex) {
                                _ = adjacentGraphRectangle.connectionIndexes.swapRemove(adjacentGraphConnectionIndex);
                                pathfindingZig.graphRectangleConnectionMovedUpdate(chunkBottom.?.pathingData.graphRectangles.items.len, graphConnection.index, chunkBottom.?, state);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}
