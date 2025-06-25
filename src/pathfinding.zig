const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");
const fontVulkanZig = @import("vulkan/fontVulkan.zig");
const chunkAreaZig = @import("chunkArea.zig");

const PATHFINDING_DEBUG = false;

pub const PathfindingTempData = struct {
    openSet: std.ArrayList(Node),
    cameFrom: std.HashMap(*ChunkGraphRectangle, *ChunkGraphRectangle, ChunkGraphRectangleContext, 80),
    gScore: std.AutoHashMap(*ChunkGraphRectangle, i32),
    neighbors: std.ArrayList(*ChunkGraphRectangle),
    tempUsizeList: std.ArrayList(usize),
    tempUsizeList2: std.ArrayList(usize),
};

pub const ChunkGraphRectangle = struct {
    index: usize,
    chunkXY: mapZig.ChunkXY,
    tileRectangle: mapZig.MapTileRectangle,
    connectionIndexes: std.ArrayList(GraphConnection),
};

pub const GraphConnection = struct {
    index: usize,
    chunkXY: mapZig.ChunkXY,
};

pub const PathfindingChunkData = struct {
    graphRectangles: std.ArrayList(ChunkGraphRectangle),
    pathingData: [mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]?usize,
};

const ChunkGraphRectangleContext = struct {
    pub fn eql(self: @This(), a: *ChunkGraphRectangle, b: *ChunkGraphRectangle) bool {
        _ = self;
        return a == b;
    }

    // A simple hash function based on FNV-1a.
    pub fn hash(self: @This(), key: *ChunkGraphRectangle) u64 {
        _ = self;
        var h: u64 = 1469598103934665603;
        h ^= @intCast(key.index);
        h *%= 1099511628211;
        return h;
    }
};

// A struct representing a node in the A* search.
const Node = struct {
    rectangle: *ChunkGraphRectangle,
    cost: i32, // g(x): cost from start to this node.
    priority: i32, // f(x) = g(x) + h(x) (with h() as the heuristic).
};

pub fn changePathingDataRectangle(rectangle: mapZig.MapTileRectangle, pathingType: mapZig.PathingType, threadIndex: usize, state: *main.GameState) !void {
    if (pathingType == mapZig.PathingType.blocking) {
        const chunkXYRectangles = getChunksOfRectangle(rectangle);

        for (chunkXYRectangles) |optChunkXYRectangle| {
            if (optChunkXYRectangle) |chunkXYRectangle| {
                const chunkXY = mapZig.getChunkXyForTileXy(chunkXYRectangle.topLeftTileXY);
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, threadIndex, state);
                if (PATHFINDING_DEBUG) std.debug.print("start change graph\n", .{});
                if (PATHFINDING_DEBUG) std.debug.print("    placed blocking rectangle: {}\n", .{chunkXYRectangle});
                const pathingIndexForGraphRectangleIndexes = try getPathingIndexesForUniqueGraphRectanglesOfRectangle(chunkXYRectangle, chunk, threadIndex, state);
                for (pathingIndexForGraphRectangleIndexes) |pathingIndex| {
                    if (chunk.pathingData.pathingData[pathingIndex]) |graphIndex| {
                        const graphTileRectangle = chunk.pathingData.graphRectangles.items[graphIndex].tileRectangle;
                        const rectangleLimitedToGraphRectangle: mapZig.MapTileRectangle = getOverlappingRectangle(chunkXYRectangle, graphTileRectangle);
                        for (0..rectangleLimitedToGraphRectangle.columnCount) |x| {
                            for (0..rectangleLimitedToGraphRectangle.rowCount) |y| {
                                const pathingIndexOverlapping = getPathingIndexForTileXY(.{
                                    .tileX = rectangleLimitedToGraphRectangle.topLeftTileXY.tileX + @as(i32, @intCast(x)),
                                    .tileY = rectangleLimitedToGraphRectangle.topLeftTileXY.tileY + @as(i32, @intCast(y)),
                                });
                                chunk.pathingData.pathingData[pathingIndexOverlapping] = null;
                            }
                        }

                        try splitGraphRectangle(rectangleLimitedToGraphRectangle, graphIndex, chunk, threadIndex, state);
                    }
                }
            }
        }
    } else {
        if (PATHFINDING_DEBUG) std.debug.print("delete rectangle {}\n", .{rectangle});
        const startChunkX = @divFloor(rectangle.topLeftTileXY.tileX, mapZig.GameMap.CHUNK_LENGTH);
        const startChunkY = @divFloor(rectangle.topLeftTileXY.tileY, mapZig.GameMap.CHUNK_LENGTH);
        var maxChunkX = @divFloor(rectangle.columnCount - 1, mapZig.GameMap.CHUNK_LENGTH) + 1;
        if (@mod(rectangle.topLeftTileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(@as(i32, @intCast(rectangle.columnCount)), mapZig.GameMap.CHUNK_LENGTH) > mapZig.GameMap.CHUNK_LENGTH) {
            maxChunkX += 1;
        }
        var maxChunkY = @divFloor(rectangle.rowCount - 1, mapZig.GameMap.CHUNK_LENGTH) + 1;
        if (@mod(rectangle.topLeftTileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) + @mod(@as(i32, @intCast(rectangle.rowCount)), mapZig.GameMap.CHUNK_LENGTH) > mapZig.GameMap.CHUNK_LENGTH) {
            maxChunkY += 1;
        }
        for (0..maxChunkX) |chunkAddX| {
            for (0..maxChunkY) |chunkAddY| {
                const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(.{
                    .chunkX = startChunkX + @as(i32, @intCast(chunkAddX)),
                    .chunkY = startChunkY + @as(i32, @intCast(chunkAddY)),
                }, threadIndex, state);
                if (chunk.buildings.items.len == 0 and chunk.bigBuildings.items.len == 0 and chunk.blockingTiles.items.len == 0) {
                    try clearChunkGraph(chunk, threadIndex, state);
                } else {
                    const chunkTileRectangle: mapZig.MapTileRectangle = .{
                        .topLeftTileXY = .{ .tileX = mapZig.GameMap.CHUNK_LENGTH * chunk.chunkXY.chunkX, .tileY = mapZig.GameMap.CHUNK_LENGTH * chunk.chunkXY.chunkY },
                        .columnCount = mapZig.GameMap.CHUNK_LENGTH,
                        .rowCount = mapZig.GameMap.CHUNK_LENGTH,
                    };
                    const overlappingRectangle = getOverlappingRectangle(rectangle, chunkTileRectangle);
                    try checkForPathingBlockRemovalsInChunk(chunk, overlappingRectangle, threadIndex, state);
                }
            }
        }
    }
}

fn checkForPathingBlockRemovalsInChunk(chunk: *mapZig.MapChunk, rectangle: mapZig.MapTileRectangle, threadIndex: usize, state: *main.GameState) !void {
    // check each tile if blocking and if it should not block anymore
    if (PATHFINDING_DEBUG) std.debug.print("checkForPathingBlockRemovalsInChunk {}\n", .{rectangle});
    for (0..rectangle.columnCount) |x| {
        rowLoop: for (0..rectangle.rowCount) |y| {
            const tileXY: mapZig.TileXY = .{
                .tileX = rectangle.topLeftTileXY.tileX + @as(i32, @intCast(x)),
                .tileY = rectangle.topLeftTileXY.tileY + @as(i32, @intCast(y)),
            };
            const pathingIndex = getPathingIndexForTileXY(tileXY);
            if (chunk.pathingData.pathingData[pathingIndex] != null) continue;
            if (try mapZig.getBuildingOnPosition(mapZig.mapTileXyToTileMiddlePosition(tileXY), threadIndex, state) != null) {
                continue;
            } else if (chunk.blockingTiles.items.len > 0) {
                for (chunk.blockingTiles.items) |blockingTile| {
                    if (blockingTile.tileX == tileXY.tileX and blockingTile.tileY == tileXY.tileY) {
                        continue :rowLoop;
                    }
                }
            }
            // change tile to not blocking
            var newGraphRectangle: ChunkGraphRectangle = .{
                .tileRectangle = .{ .topLeftTileXY = tileXY, .columnCount = 1, .rowCount = 1 },
                .index = chunk.pathingData.graphRectangles.items.len,
                .connectionIndexes = std.ArrayList(GraphConnection).init(state.allocator),
                .chunkXY = chunk.chunkXY,
            };
            chunk.pathingData.pathingData[pathingIndex] = newGraphRectangle.index;

            //check neighbors
            const neighborTileXYs = [_]mapZig.TileXY{
                .{ .tileX = tileXY.tileX - 1, .tileY = tileXY.tileY },
                .{ .tileX = tileXY.tileX + 1, .tileY = tileXY.tileY },
                .{ .tileX = tileXY.tileX, .tileY = tileXY.tileY - 1 },
                .{ .tileX = tileXY.tileX, .tileY = tileXY.tileY + 1 },
            };
            var neighborChunk = chunk;
            for (neighborTileXYs) |neighborTileXY| {
                const chunkXY = mapZig.getChunkXyForTileXy(neighborTileXY);
                if (chunkXY.chunkX != neighborChunk.chunkXY.chunkX or chunkXY.chunkY != neighborChunk.chunkXY.chunkY) {
                    neighborChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, threadIndex, state);
                }
                const neighborPathingIndex = getPathingIndexForTileXY(neighborTileXY);
                if (neighborChunk.pathingData.pathingData[neighborPathingIndex]) |neighborGraphIndex| {
                    const neighborGraphRectangle = &neighborChunk.pathingData.graphRectangles.items[neighborGraphIndex];
                    try newGraphRectangle.connectionIndexes.append(.{ .index = neighborGraphIndex, .chunkXY = neighborChunk.chunkXY });
                    try neighborGraphRectangle.connectionIndexes.append(.{ .index = newGraphRectangle.index, .chunkXY = chunk.chunkXY });
                }
            }
            try chunk.pathingData.graphRectangles.append(newGraphRectangle);
            var continueMergeCheck = true;
            while (continueMergeCheck) {
                if (chunk.pathingData.pathingData[pathingIndex]) |anotherMergeCheckGraphIndex| {
                    continueMergeCheck = try checkForGraphMergeAndDoIt(anotherMergeCheckGraphIndex, chunk, threadIndex, state);
                }
            }
        }
    }
}

fn clearChunkGraph(chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !void {
    if (chunk.buildings.items.len > 0 or chunk.bigBuildings.items.len > 0) return;
    if (PATHFINDING_DEBUG) std.debug.print("clear chunk graph {}\n", .{chunk.chunkXY});

    const newGraphRectangleIndex: usize = 0;
    {
        var currentDeleteIndex: usize = 0;
        const graphRectangle = &chunk.pathingData.graphRectangles.items[newGraphRectangleIndex];
        while (graphRectangle.connectionIndexes.items.len > currentDeleteIndex) {
            const deleteChunkXY = graphRectangle.connectionIndexes.items[currentDeleteIndex].chunkXY;
            if (deleteChunkXY.chunkX == chunk.chunkXY.chunkX and deleteChunkXY.chunkY == chunk.chunkXY.chunkY) {
                _ = graphRectangle.connectionIndexes.swapRemove(currentDeleteIndex);
            } else {
                currentDeleteIndex += 1;
            }
        }
        graphRectangle.tileRectangle = .{
            .topLeftTileXY = .{ .tileX = chunk.chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH, .tileY = chunk.chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH },
            .columnCount = mapZig.GameMap.CHUNK_LENGTH,
            .rowCount = mapZig.GameMap.CHUNK_LENGTH,
        };
    }

    for (1..chunk.pathingData.graphRectangles.items.len) |graphIndex| {
        const graphRectangle = &chunk.pathingData.graphRectangles.items[graphIndex];
        for (graphRectangle.connectionIndexes.items) |conData| {
            if (conData.chunkXY.chunkX == chunk.chunkXY.chunkX and conData.chunkXY.chunkY == chunk.chunkXY.chunkY) continue;
            const newGraphRectangle = &chunk.pathingData.graphRectangles.items[newGraphRectangleIndex];
            const otherChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(conData.chunkXY, threadIndex, state);
            const otherGraphRectangle = &otherChunk.pathingData.graphRectangles.items[conData.index];
            if (try appendConnectionWithCheck(newGraphRectangle, conData)) {
                _ = try appendConnectionWithCheck(otherGraphRectangle, .{ .index = newGraphRectangleIndex, .chunkXY = chunk.chunkXY });
            }
        }
    }

    while (chunk.pathingData.graphRectangles.items.len > 1) {
        const toRemoveGraphRectangle = chunk.pathingData.graphRectangles.items[1];
        try swapRemoveGraphIndex(.{ .chunkXY = chunk.chunkXY, .index = 1 }, threadIndex, state);
        toRemoveGraphRectangle.connectionIndexes.deinit();
    }

    const newGraphRectangle = &chunk.pathingData.graphRectangles.items[newGraphRectangleIndex];
    try setPaththingDataRectangle(newGraphRectangle.tileRectangle, newGraphRectangleIndex, threadIndex, state);
}

/// does not check if overlapping
fn getOverlappingRectangle(rect1: mapZig.MapTileRectangle, rect2: mapZig.MapTileRectangle) mapZig.MapTileRectangle {
    const left = @max(rect1.topLeftTileXY.tileX, rect2.topLeftTileXY.tileX);
    const top = @max(rect1.topLeftTileXY.tileY, rect2.topLeftTileXY.tileY);
    const right = @min(rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount)), rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount)));
    const bottom = @min(rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount)), rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount)));
    return mapZig.MapTileRectangle{
        .topLeftTileXY = .{
            .tileX = @max(rect1.topLeftTileXY.tileX, rect2.topLeftTileXY.tileX),
            .tileY = @max(rect1.topLeftTileXY.tileY, rect2.topLeftTileXY.tileY),
        },
        .columnCount = @intCast(right - left),
        .rowCount = @intCast(bottom - top),
    };
}

fn getPathingIndexesForUniqueGraphRectanglesOfRectangle(rectangle: mapZig.MapTileRectangle, chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) ![]usize {
    state.threadData[threadIndex].pathfindingTempData.tempUsizeList.clearRetainingCapacity();
    state.threadData[threadIndex].pathfindingTempData.tempUsizeList2.clearRetainingCapacity();

    var graphRecIndexes = &state.threadData[threadIndex].pathfindingTempData.tempUsizeList;
    var result = &state.threadData[threadIndex].pathfindingTempData.tempUsizeList2;
    for (0..rectangle.columnCount) |x| {
        for (0..rectangle.rowCount) |y| {
            const pathingIndex = getPathingIndexForTileXY(.{
                .tileX = rectangle.topLeftTileXY.tileX + @as(i32, @intCast(x)),
                .tileY = rectangle.topLeftTileXY.tileY + @as(i32, @intCast(y)),
            });
            const optGraphIndex = chunk.pathingData.pathingData[pathingIndex];
            if (optGraphIndex) |graphIndex| {
                var exists = false;
                for (graphRecIndexes.items) |item| {
                    if (item == graphIndex) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    try result.append(pathingIndex);
                    try graphRecIndexes.append(graphIndex);
                }
            }
        }
    }
    return result.items;
}

fn getChunksOfRectangle(rectangle: mapZig.MapTileRectangle) [4]?mapZig.MapTileRectangle {
    var chunkXYRectangles = [_]?mapZig.MapTileRectangle{ null, null, null, null };
    var xColumnCut: u32 = @as(u32, @intCast(@mod(rectangle.topLeftTileXY.tileX, mapZig.GameMap.CHUNK_LENGTH))) + rectangle.columnCount;
    if (xColumnCut > mapZig.GameMap.CHUNK_LENGTH) {
        xColumnCut = @mod(xColumnCut, mapZig.GameMap.CHUNK_LENGTH);
    } else {
        xColumnCut = 0;
    }
    var yRowCut: u32 = @as(u32, @intCast(@mod(rectangle.topLeftTileXY.tileY, mapZig.GameMap.CHUNK_LENGTH))) + rectangle.rowCount;
    if (yRowCut > mapZig.GameMap.CHUNK_LENGTH) {
        yRowCut = @mod(yRowCut, mapZig.GameMap.CHUNK_LENGTH);
    } else {
        yRowCut = 0;
    }
    chunkXYRectangles[0] = rectangle;
    if (xColumnCut == 0) {
        if (yRowCut > 0) {
            chunkXYRectangles[0].?.rowCount -= yRowCut;
        }
    } else {
        if (yRowCut == 0) {
            chunkXYRectangles[0].?.columnCount -= xColumnCut;
        } else {
            chunkXYRectangles[0].?.columnCount -= xColumnCut;
            chunkXYRectangles[0].?.rowCount -= yRowCut;
        }
    }
    if (xColumnCut > 0) {
        chunkXYRectangles[1] = mapZig.MapTileRectangle{
            .topLeftTileXY = .{
                .tileX = chunkXYRectangles[0].?.topLeftTileXY.tileX + @as(i32, @intCast(xColumnCut)),
                .tileY = chunkXYRectangles[0].?.topLeftTileXY.tileY,
            },
            .columnCount = xColumnCut,
            .rowCount = chunkXYRectangles[0].?.rowCount,
        };
    }
    if (yRowCut > 0) {
        chunkXYRectangles[2] = mapZig.MapTileRectangle{
            .topLeftTileXY = .{
                .tileX = chunkXYRectangles[0].?.topLeftTileXY.tileX,
                .tileY = chunkXYRectangles[0].?.topLeftTileXY.tileY + @as(i32, @intCast(yRowCut)),
            },
            .columnCount = chunkXYRectangles[0].?.columnCount,
            .rowCount = yRowCut,
        };
    }
    if (xColumnCut > 0 and yRowCut > 0) {
        chunkXYRectangles[3] = mapZig.MapTileRectangle{
            .topLeftTileXY = .{
                .tileX = chunkXYRectangles[0].?.topLeftTileXY.tileX + @as(i32, @intCast(xColumnCut)),
                .tileY = chunkXYRectangles[0].?.topLeftTileXY.tileY + @as(i32, @intCast(yRowCut)),
            },
            .columnCount = xColumnCut,
            .rowCount = yRowCut,
        };
    }
    return chunkXYRectangles;
}

fn splitGraphRectangle(rectangle: mapZig.MapTileRectangle, graphIndex: usize, chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !void {
    var graphRectangleForUpdateIndex: usize = 0;
    var graphRectangleForUpdateIndexes = [_]?usize{ null, null, null, null };
    const toSplitGraphRectangle = chunk.pathingData.graphRectangles.items[graphIndex];
    if (PATHFINDING_DEBUG) {
        std.debug.print("    graph rect to change: ", .{});
        printGraphData(&toSplitGraphRectangle);
    }
    const directions = [_]mapZig.TileXY{
        .{ .tileX = -1, .tileY = @as(i32, @intCast(rectangle.rowCount)) - 1 },
        .{ .tileX = 0, .tileY = -1 },
        .{ .tileX = @intCast(rectangle.columnCount), .tileY = 0 },
        .{ .tileX = @as(i32, @intCast(rectangle.columnCount)) - 1, .tileY = @intCast(rectangle.rowCount) },
    };
    if (PATHFINDING_DEBUG) {
        std.debug.print("    Adjacent tile rectangles to check if new graph rectangles need to be created: \n", .{});
    }
    var newTileRetangles = [_]?mapZig.MapTileRectangle{ null, null, null, null };
    for (directions, 0..) |direction, i| {
        const adjacentTile: mapZig.TileXY = .{
            .tileX = rectangle.topLeftTileXY.tileX + direction.tileX,
            .tileY = rectangle.topLeftTileXY.tileY + direction.tileY,
        };
        if (toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileX <= adjacentTile.tileX and adjacentTile.tileX <= toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(toSplitGraphRectangle.tileRectangle.columnCount)) - 1 //
        and toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileY <= adjacentTile.tileY and adjacentTile.tileY <= toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(toSplitGraphRectangle.tileRectangle.rowCount)) - 1) {
            newTileRetangles[i] = createAjdacentTileRectangle(adjacentTile, i, toSplitGraphRectangle);
            if (PATHFINDING_DEBUG) std.debug.print("        added tile rectangle: {}\n", .{newTileRetangles[i].?});
        }
    }
    // create new rectangles
    var originalReplaced = false;
    var tileRectangleIndexToGraphRectangleIndex = [_]?usize{ null, null, null, null };
    for (newTileRetangles, 0..) |optTileRectangle, i| {
        if (optTileRectangle) |tileRectangle| {
            if (PATHFINDING_DEBUG) {
                std.debug.print("   Create graph rec from tile rec or replace old one: {} \n", .{tileRectangle});
            }
            var newGraphRectangle: ChunkGraphRectangle = .{
                .tileRectangle = tileRectangle,
                .index = chunk.pathingData.graphRectangles.items.len,
                .chunkXY = chunk.chunkXY,
                .connectionIndexes = std.ArrayList(GraphConnection).init(state.allocator),
            };
            // connections from newest to previous
            for (0..i) |connectToIndex| {
                if (i > 1 and i - 2 == connectToIndex) continue; // do not connect diagonals
                if (tileRectangleIndexToGraphRectangleIndex[connectToIndex]) |connectToGraphIndex| {
                    try newGraphRectangle.connectionIndexes.append(.{ .index = connectToGraphIndex, .chunkXY = chunk.chunkXY });
                    if (PATHFINDING_DEBUG) {
                        std.debug.print("       added connection {} to rec {}. ", .{ newGraphRectangle.index, connectToGraphIndex });
                        printGraphData(&newGraphRectangle);
                    }
                }
            }

            if (originalReplaced) {
                try chunk.pathingData.graphRectangles.append(newGraphRectangle);
                if (PATHFINDING_DEBUG) std.debug.print("        new rec {}, {}\n", .{ newGraphRectangle.index, newGraphRectangle.tileRectangle });
            } else {
                originalReplaced = true;
                newGraphRectangle.index = toSplitGraphRectangle.index;
                chunk.pathingData.graphRectangles.items[toSplitGraphRectangle.index] = newGraphRectangle;
                if (PATHFINDING_DEBUG) std.debug.print("        replaced rec {} with {}\n", .{ newGraphRectangle.index, newGraphRectangle.tileRectangle });
            }
            try setPaththingDataRectangle(tileRectangle, newGraphRectangle.index, threadIndex, state);
            graphRectangleForUpdateIndexes[graphRectangleForUpdateIndex] = newGraphRectangle.index;
            tileRectangleIndexToGraphRectangleIndex[i] = newGraphRectangle.index;
            graphRectangleForUpdateIndex += 1;
            // connections from previous to newest
            for (0..i) |connectToIndex| {
                if (i > 1 and i - 2 == connectToIndex) continue; // do not connect diagonals
                if (tileRectangleIndexToGraphRectangleIndex[connectToIndex]) |connectToGraphIndex| {
                    const previousNewGraphRectangle = &chunk.pathingData.graphRectangles.items[connectToGraphIndex];
                    try previousNewGraphRectangle.connectionIndexes.append(.{ .index = newGraphRectangle.index, .chunkXY = chunk.chunkXY });
                    if (PATHFINDING_DEBUG) {
                        std.debug.print("       added connection {} to rec {}. ", .{ newGraphRectangle.index, previousNewGraphRectangle.index });
                        printGraphData(&newGraphRectangle);
                    }
                }
            }
        }
    }
    // correct connections
    for (toSplitGraphRectangle.connectionIndexes.items) |conData| {
        if (PATHFINDING_DEBUG) std.debug.print("    checking rec {} conIndex {}\n", .{ toSplitGraphRectangle.index, conData });
        const connectedChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(conData.chunkXY, threadIndex, state);
        const connectionGraphRectanglePtr = &connectedChunk.pathingData.graphRectangles.items[conData.index];
        const rect1 = connectionGraphRectanglePtr.tileRectangle;
        var removeOldRequired = true;
        for (graphRectangleForUpdateIndexes) |optIndex| {
            if (optIndex) |index| {
                if (index == conData.index and conData.chunkXY.chunkX == chunk.chunkXY.chunkX and conData.chunkXY.chunkY == chunk.chunkXY.chunkY) continue;
                const newGraphRectanglePtr = &chunk.pathingData.graphRectangles.items[index];
                const rect2 = newGraphRectanglePtr.tileRectangle;
                if (areRectanglesTouchingOnEdge(rect1, rect2)) {
                    {
                        if (toSplitGraphRectangle.index == index) removeOldRequired = false;
                        _ = try appendConnectionWithCheck(newGraphRectanglePtr, .{ .index = connectionGraphRectanglePtr.index, .chunkXY = connectionGraphRectanglePtr.chunkXY });
                        _ = try appendConnectionWithCheck(connectionGraphRectanglePtr, .{ .index = newGraphRectanglePtr.index, .chunkXY = newGraphRectanglePtr.chunkXY });
                    }
                }
            }
        }
        if (removeOldRequired) {
            for (0..connectionGraphRectanglePtr.connectionIndexes.items.len) |conIndexIndex| {
                const temp = connectionGraphRectanglePtr.connectionIndexes.items[conIndexIndex];
                if (temp.index == toSplitGraphRectangle.index and temp.chunkXY.chunkX == toSplitGraphRectangle.chunkXY.chunkX and temp.chunkXY.chunkY == toSplitGraphRectangle.chunkXY.chunkY) {
                    _ = connectionGraphRectanglePtr.connectionIndexes.swapRemove(conIndexIndex);
                    if (PATHFINDING_DEBUG) {
                        std.debug.print("       removed connection {} from rec {}. ", .{ conIndexIndex, connectionGraphRectanglePtr.index });
                        printGraphData(connectionGraphRectanglePtr);
                    }
                    break;
                }
            }
        }
    }
    if (!originalReplaced) {
        try swapRemoveGraphIndex(.{ .index = toSplitGraphRectangle.index, .chunkXY = toSplitGraphRectangle.chunkXY }, threadIndex, state);
    }
    for (newTileRetangles) |optTileRectangle| {
        if (optTileRectangle) |tileRectangle| {
            if (PATHFINDING_DEBUG) {
                std.debug.print("   Check Merge: {} \n", .{tileRectangle});
            }
            const pathingDataTileIndex = getPathingIndexForTileXY(tileRectangle.topLeftTileXY);
            var continueMergeCheck = true;
            while (continueMergeCheck) {
                if (chunk.pathingData.pathingData[pathingDataTileIndex]) |anotherMergeCheckGraphIndex| {
                    continueMergeCheck = try checkForGraphMergeAndDoIt(anotherMergeCheckGraphIndex, chunk, threadIndex, state);
                }
            }
        }
    }
    toSplitGraphRectangle.connectionIndexes.deinit();
}

pub fn areRectanglesTouchingOnEdge(rect1: mapZig.MapTileRectangle, rect2: mapZig.MapTileRectangle) bool {
    if (rect1.topLeftTileXY.tileX <= rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount)) and rect2.topLeftTileXY.tileX <= rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount)) and
        rect1.topLeftTileXY.tileY <= rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount)) and rect2.topLeftTileXY.tileY <= rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount)))
    {
        if (rect1.topLeftTileXY.tileX < rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount)) and rect2.topLeftTileXY.tileX < rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount)) or
            rect1.topLeftTileXY.tileY < rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount)) and rect2.topLeftTileXY.tileY < rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount)))
        {
            return true;
        }
    }
    return false;
}

/// returns true if something merged
fn checkForGraphMergeAndDoIt(graphRectForMergeCheckIndex: usize, chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !bool {
    const graphRectForMergeCheck = chunk.pathingData.graphRectangles.items[graphRectForMergeCheckIndex];
    if (try checkMergeGraphRectangles(graphRectForMergeCheck.tileRectangle, chunk, threadIndex, state)) |mergeIndex| {
        const mergedToGraphRectangle = &chunk.pathingData.graphRectangles.items[mergeIndex];
        if (PATHFINDING_DEBUG) {
            std.debug.print("       merged rec {} with {}\n", .{ mergeIndex, graphRectForMergeCheck.index });
        }
        for (graphRectForMergeCheck.connectionIndexes.items) |conData| {
            if (mergeIndex == conData.index and conData.chunkXY.chunkX == chunk.chunkXY.chunkX and conData.chunkXY.chunkY == chunk.chunkXY.chunkY) continue;
            const conChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(conData.chunkXY, threadIndex, state);
            const connectionGraphRectangle = &conChunk.pathingData.graphRectangles.items[conData.index];
            for (connectionGraphRectangle.connectionIndexes.items, 0..) |mergedToCon, mergeToIndexIndex| {
                if (mergedToCon.index == graphRectForMergeCheck.index and mergedToCon.chunkXY.chunkX == graphRectForMergeCheck.chunkXY.chunkX and mergedToCon.chunkXY.chunkY == graphRectForMergeCheck.chunkXY.chunkY) {
                    if (!connectionsIndexesContains(connectionGraphRectangle.connectionIndexes.items, .{ .index = mergeIndex, .chunkXY = chunk.chunkXY })) {
                        connectionGraphRectangle.connectionIndexes.items[mergeToIndexIndex] = .{ .index = mergeIndex, .chunkXY = chunk.chunkXY };
                        if (PATHFINDING_DEBUG) {
                            std.debug.print("           updated connection in rec {} from {} to {}. ", .{ connectionGraphRectangle.index, mergedToCon, mergeIndex });
                            printGraphData(connectionGraphRectangle);
                        }
                    } else {
                        _ = connectionGraphRectangle.connectionIndexes.swapRemove(mergeToIndexIndex);
                        if (PATHFINDING_DEBUG) {
                            std.debug.print("           removed connection {} from rec {}. ", .{ mergedToCon, connectionGraphRectangle.index });
                            printGraphData(connectionGraphRectangle);
                        }
                    }
                    _ = try appendConnectionWithCheck(mergedToGraphRectangle, conData);
                    break;
                }
            }
        }
        try swapRemoveGraphIndex(.{ .index = graphRectForMergeCheck.index, .chunkXY = chunk.chunkXY }, threadIndex, state);
        graphRectForMergeCheck.connectionIndexes.deinit();
        return true;
    }
    return false;
}

/// returns true if appended
fn appendConnectionWithCheck(addConnectionbToGraph: *ChunkGraphRectangle, newConIndex: GraphConnection) !bool {
    if (!connectionsIndexesContains(addConnectionbToGraph.connectionIndexes.items, newConIndex)) {
        try addConnectionbToGraph.connectionIndexes.append(newConIndex);
        if (PATHFINDING_DEBUG) {
            std.debug.print("   added connection {} to rec {}.", .{ newConIndex, addConnectionbToGraph.index });
            printGraphData(addConnectionbToGraph);
        }
        return true;
    }
    return false;
}

fn printGraphData(graphRectangle: *const ChunkGraphRectangle) void {
    std.debug.print("rec(id: {}_{}, topLeft: {}|{}, c:{}, r:{}, connections:{any})\n", .{
        graphRectangle.index,
        graphRectangle.chunkXY,
        graphRectangle.tileRectangle.topLeftTileXY.tileX,
        graphRectangle.tileRectangle.topLeftTileXY.tileY,
        graphRectangle.tileRectangle.columnCount,
        graphRectangle.tileRectangle.rowCount,
        graphRectangle.connectionIndexes.items,
    });
}

fn connectionsIndexesContains(connections: []GraphConnection, check: GraphConnection) bool {
    for (connections) |con| {
        if (con.index == check.index and con.chunkXY.chunkX == check.chunkXY.chunkX and con.chunkXY.chunkY == check.chunkXY.chunkY) {
            return true;
        }
    }
    return false;
}

/// returns merge graph rectangle index
fn checkMergeGraphRectangles(tileRectangle: mapZig.MapTileRectangle, chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !?usize {
    //do right merge check
    if (@mod(tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(tileRectangle.columnCount)), mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
        const optRightGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(tileRectangle.columnCount)), .tileY = tileRectangle.topLeftTileXY.tileY })];
        if (optRightGraphRectangleIndex) |rightRectangleIndex| {
            const rightRectangle = &chunk.pathingData.graphRectangles.items[rightRectangleIndex];
            if (rightRectangle.tileRectangle.topLeftTileXY.tileY == tileRectangle.topLeftTileXY.tileY and rightRectangle.tileRectangle.rowCount == tileRectangle.rowCount) {
                // can be merged
                rightRectangle.tileRectangle.columnCount += @as(u32, @intCast(rightRectangle.tileRectangle.topLeftTileXY.tileX - tileRectangle.topLeftTileXY.tileX));
                rightRectangle.tileRectangle.topLeftTileXY.tileX = tileRectangle.topLeftTileXY.tileX;
                try setPaththingDataRectangle(tileRectangle, rightRectangle.index, threadIndex, state);
                if (PATHFINDING_DEBUG) std.debug.print("    merge right {}, {}, mergedWith: {}\n", .{ rightRectangle.tileRectangle, rightRectangle.index, tileRectangle });
                return rightRectangle.index;
            }
        }
    }
    //do down merge check
    if (@mod(tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(tileRectangle.rowCount)), mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
        const optDownGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX, .tileY = tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(tileRectangle.rowCount)) })];
        if (optDownGraphRectangleIndex) |downRectangleIndex| {
            const downRectangle = &chunk.pathingData.graphRectangles.items[downRectangleIndex];
            if (downRectangle.tileRectangle.topLeftTileXY.tileX == tileRectangle.topLeftTileXY.tileX and downRectangle.tileRectangle.columnCount == tileRectangle.columnCount) {
                // can be merged
                downRectangle.tileRectangle.rowCount += @as(u32, @intCast(downRectangle.tileRectangle.topLeftTileXY.tileY - tileRectangle.topLeftTileXY.tileY));
                downRectangle.tileRectangle.topLeftTileXY.tileY = tileRectangle.topLeftTileXY.tileY;
                try setPaththingDataRectangle(tileRectangle, downRectangle.index, threadIndex, state);
                if (PATHFINDING_DEBUG) std.debug.print("    merge down {}, {}\n", .{ downRectangle.tileRectangle, downRectangle.index });
                return downRectangle.index;
            }
        }
    }
    //do left merge check
    if (@mod(tileRectangle.topLeftTileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
        const optLeftGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX - 1, .tileY = tileRectangle.topLeftTileXY.tileY })];
        if (optLeftGraphRectangleIndex) |leftRectangleIndex| {
            const leftRectangle = &chunk.pathingData.graphRectangles.items[leftRectangleIndex];
            if (leftRectangle.tileRectangle.topLeftTileXY.tileY == tileRectangle.topLeftTileXY.tileY and leftRectangle.tileRectangle.rowCount == tileRectangle.rowCount) {
                // can be merged
                leftRectangle.tileRectangle.columnCount += tileRectangle.columnCount;
                try setPaththingDataRectangle(tileRectangle, leftRectangle.index, threadIndex, state);
                if (PATHFINDING_DEBUG) std.debug.print("    merge left {}, {}\n", .{ leftRectangle.tileRectangle, leftRectangle.index });
                return leftRectangle.index;
            }
        }
    }
    //do up merge check
    if (@mod(tileRectangle.topLeftTileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
        const optUpGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX, .tileY = tileRectangle.topLeftTileXY.tileY - 1 })];
        if (optUpGraphRectangleIndex) |upRectangleIndex| {
            const upRectangle = &chunk.pathingData.graphRectangles.items[upRectangleIndex];
            if (upRectangle.tileRectangle.topLeftTileXY.tileX == tileRectangle.topLeftTileXY.tileX and upRectangle.tileRectangle.columnCount == tileRectangle.columnCount) {
                // can be merged
                upRectangle.tileRectangle.rowCount += tileRectangle.rowCount;
                try setPaththingDataRectangle(tileRectangle, upRectangle.index, threadIndex, state);
                if (PATHFINDING_DEBUG) std.debug.print("    merge up {}, {}\n", .{ upRectangle.tileRectangle, upRectangle.index });
                return upRectangleIndex;
            }
        }
    }
    return null;
}

fn swapRemoveGraphIndex(toRemoveGraph: GraphConnection, threadIndex: usize, state: *main.GameState) !void {
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(toRemoveGraph.chunkXY, threadIndex, state);
    const removedGraph = chunk.pathingData.graphRectangles.swapRemove(toRemoveGraph.index);
    if (PATHFINDING_DEBUG) {
        std.debug.print("   swap remove {}. ", .{toRemoveGraph});
        printGraphData(&removedGraph);
    }
    const oldIndex = chunk.pathingData.graphRectangles.items.len;
    // remove existing connections to removedGraph
    for (removedGraph.connectionIndexes.items) |removedConData| {
        const connectedChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(removedConData.chunkXY, threadIndex, state);
        const connectedGraph = if (oldIndex == removedConData.index and removedConData.chunkXY.chunkX == toRemoveGraph.chunkXY.chunkX and removedConData.chunkXY.chunkY == toRemoveGraph.chunkXY.chunkY) &connectedChunk.pathingData.graphRectangles.items[toRemoveGraph.index] else &connectedChunk.pathingData.graphRectangles.items[removedConData.index];
        for (connectedGraph.connectionIndexes.items, 0..) |checkConData, i| {
            if (checkConData.index == toRemoveGraph.index and checkConData.chunkXY.chunkX == toRemoveGraph.chunkXY.chunkX and checkConData.chunkXY.chunkY == toRemoveGraph.chunkXY.chunkY) {
                _ = connectedGraph.connectionIndexes.swapRemove(i);
                if (PATHFINDING_DEBUG) {
                    std.debug.print("       removed connection {} from rec {}. ", .{ checkConData, removedConData });
                    printGraphData(connectedGraph);
                }
                break;
            }
        }
    }

    // change indexes of newAtIndex
    if (toRemoveGraph.index >= oldIndex) return;
    try graphRectangleConnectionMovedUpdate(oldIndex, toRemoveGraph.index, chunk, threadIndex, state);
    try setPaththingDataRectangle(chunk.pathingData.graphRectangles.items[toRemoveGraph.index].tileRectangle, toRemoveGraph.index, threadIndex, state);
}

pub fn graphRectangleConnectionMovedUpdate(oldIndex: usize, newIndex: usize, chunk: *mapZig.MapChunk, threadIndex: usize, state: *main.GameState) !void {
    if (oldIndex <= newIndex) return;
    const newAtIndex = &chunk.pathingData.graphRectangles.items[newIndex];
    if (PATHFINDING_DEBUG) {
        std.debug.print("   changed index rec {} -> {}. ", .{ newAtIndex.index, newIndex });
        printGraphData(newAtIndex);
    }
    newAtIndex.index = newIndex;
    for (newAtIndex.connectionIndexes.items) |newAtConData| {
        const connectedChunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(newAtConData.chunkXY, threadIndex, state);
        const connectedGraph = &connectedChunk.pathingData.graphRectangles.items[newAtConData.index];
        for (connectedGraph.connectionIndexes.items, 0..) |checkConData, i| {
            if (oldIndex == checkConData.index and newAtIndex.chunkXY.chunkX == checkConData.chunkXY.chunkX and newAtIndex.chunkXY.chunkY == checkConData.chunkXY.chunkY) {
                connectedGraph.connectionIndexes.items[i].index = newIndex;
                if (PATHFINDING_DEBUG) {
                    std.debug.print("       updated connection in rec {} from {} to {} . ", .{ connectedGraph.index, oldIndex, newIndex });
                    printGraphData(connectedGraph);
                }
                break;
            }
        }
    }
}

/// assumes to be only in one chunk
fn setPaththingDataRectangle(rectangle: mapZig.MapTileRectangle, newIndex: ?usize, threadIndex: usize, state: *main.GameState) !void {
    const chunkXY = mapZig.getChunkXyForTileXy(rectangle.topLeftTileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, threadIndex, state);
    for (0..rectangle.columnCount) |x| {
        for (0..rectangle.rowCount) |y| {
            chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = rectangle.topLeftTileXY.tileX + @as(i32, @intCast(x)), .tileY = rectangle.topLeftTileXY.tileY + @as(i32, @intCast(y)) })] = newIndex;
        }
    }
}

fn createAjdacentTileRectangle(adjacentTile: mapZig.TileXY, i: usize, graphRectangle: ChunkGraphRectangle) mapZig.MapTileRectangle {
    var newRecTopLeft: ?mapZig.TileXY = null;
    var newRecTopRight: ?mapZig.TileXY = null;
    var newRecBottomLeft: ?mapZig.TileXY = null;
    var newRecBottomRight: ?mapZig.TileXY = null;
    switch (i) {
        0 => {
            newRecBottomRight = adjacentTile;
        },
        1 => {
            newRecBottomLeft = adjacentTile;
        },
        2 => {
            newRecTopLeft = adjacentTile;
        },
        3 => {
            newRecTopRight = adjacentTile;
        },
        else => {
            unreachable;
        },
    }
    for (0..3) |j| {
        switch (@mod(i + j, 4)) {
            0 => {
                newRecBottomLeft = .{
                    .tileX = if (newRecTopLeft) |left| left.tileX else graphRectangle.tileRectangle.topLeftTileXY.tileX,
                    .tileY = newRecBottomRight.?.tileY,
                };
            },
            1 => {
                newRecTopLeft = .{
                    .tileX = newRecBottomLeft.?.tileX,
                    .tileY = if (newRecTopRight) |top| top.tileY else graphRectangle.tileRectangle.topLeftTileXY.tileY,
                };
            },
            2 => {
                newRecTopRight = .{
                    .tileX = if (newRecBottomRight) |right| right.tileX else graphRectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(graphRectangle.tileRectangle.columnCount)) - 1,
                    .tileY = newRecTopLeft.?.tileY,
                };
            },
            3 => {
                newRecBottomRight = .{
                    .tileX = newRecTopRight.?.tileX,
                    .tileY = if (newRecBottomLeft) |bottom| bottom.tileY else graphRectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(graphRectangle.tileRectangle.rowCount)) - 1,
                };
            },
            else => {
                unreachable;
            },
        }
    }

    return .{
        .topLeftTileXY = newRecTopLeft.?,
        .columnCount = @as(u32, @intCast(newRecBottomRight.?.tileX - newRecTopLeft.?.tileX + 1)),
        .rowCount = @as(u32, @intCast(newRecBottomRight.?.tileY - newRecTopLeft.?.tileY + 1)),
    };
}

pub fn createPathfindingData(allocator: std.mem.Allocator) !PathfindingTempData {
    return PathfindingTempData{
        .openSet = std.ArrayList(Node).init(allocator),
        .cameFrom = std.HashMap(*ChunkGraphRectangle, *ChunkGraphRectangle, ChunkGraphRectangleContext, 80).init(allocator),
        .gScore = std.AutoHashMap(*ChunkGraphRectangle, i32).init(allocator),
        .neighbors = std.ArrayList(*ChunkGraphRectangle).init(allocator),
        .tempUsizeList = std.ArrayList(usize).init(allocator),
        .tempUsizeList2 = std.ArrayList(usize).init(allocator),
    };
}

pub fn destoryChunkData(pathingData: *PathfindingChunkData) void {
    for (pathingData.graphRectangles.items) |graphRectangle| {
        graphRectangle.connectionIndexes.deinit();
    }
    pathingData.graphRectangles.deinit();
}

pub fn destroyPathfindingData(data: *PathfindingTempData) void {
    data.cameFrom.deinit();
    data.gScore.deinit();
    data.openSet.deinit();
    data.neighbors.deinit();
    data.tempUsizeList.deinit();
    data.tempUsizeList2.deinit();
}

fn heuristic(a: *ChunkGraphRectangle, b: *ChunkGraphRectangle) i32 {
    return @as(i32, @intCast(@abs(a.tileRectangle.topLeftTileXY.tileX - b.tileRectangle.topLeftTileXY.tileX) + @abs(a.tileRectangle.topLeftTileXY.tileY - b.tileRectangle.topLeftTileXY.tileY)));
}

fn reconstructPath(
    cameFrom: *std.HashMap(*ChunkGraphRectangle, *ChunkGraphRectangle, ChunkGraphRectangleContext, 80),
    goalRectangle: *ChunkGraphRectangle,
    goalTile: mapZig.TileXY,
    citizen: *main.Citizen,
) !void {
    var current = goalRectangle;
    var lastRectangleCrossingPosition = mapZig.mapTileXyToTileMiddlePosition(goalTile);
    try citizen.moveTo.append(lastRectangleCrossingPosition);
    while (true) {
        if (cameFrom.get(current)) |parent| {
            var rectangleCrossingPosition: main.Position = .{ .x = 0, .y = 0 };
            if (current.tileRectangle.topLeftTileXY.tileX <= parent.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(parent.tileRectangle.columnCount)) - 1 and parent.tileRectangle.topLeftTileXY.tileX <= current.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(current.tileRectangle.columnCount)) - 1) {
                if (current.tileRectangle.topLeftTileXY.tileY < parent.tileRectangle.topLeftTileXY.tileY) {
                    rectangleCrossingPosition.y = @floatFromInt(parent.tileRectangle.topLeftTileXY.tileY * mapZig.GameMap.TILE_SIZE);
                } else {
                    rectangleCrossingPosition.y = @floatFromInt(current.tileRectangle.topLeftTileXY.tileY * mapZig.GameMap.TILE_SIZE);
                }
                const leftOverlapTile: i32 = @max(current.tileRectangle.topLeftTileXY.tileX, parent.tileRectangle.topLeftTileXY.tileX);
                const rightOverlapTile: i32 = @min(current.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(current.tileRectangle.columnCount)) - 1, parent.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(parent.tileRectangle.columnCount)) - 1);
                const leftOverlapPos: f32 = @floatFromInt(leftOverlapTile * mapZig.GameMap.TILE_SIZE);
                const rightOverlapPos: f32 = @floatFromInt(rightOverlapTile * mapZig.GameMap.TILE_SIZE);
                if (leftOverlapPos > lastRectangleCrossingPosition.x) {
                    rectangleCrossingPosition.x = leftOverlapPos;
                } else if (rightOverlapPos < lastRectangleCrossingPosition.x) {
                    rectangleCrossingPosition.x = rightOverlapPos;
                } else {
                    rectangleCrossingPosition.x = lastRectangleCrossingPosition.x;
                }
            } else {
                if (current.tileRectangle.topLeftTileXY.tileX < parent.tileRectangle.topLeftTileXY.tileX) {
                    rectangleCrossingPosition.x = @floatFromInt(parent.tileRectangle.topLeftTileXY.tileX * mapZig.GameMap.TILE_SIZE);
                } else {
                    rectangleCrossingPosition.x = @floatFromInt(current.tileRectangle.topLeftTileXY.tileX * mapZig.GameMap.TILE_SIZE);
                }
                const topOverlapTile: i32 = @max(current.tileRectangle.topLeftTileXY.tileY, parent.tileRectangle.topLeftTileXY.tileY);
                const bottomOverlapTile: i32 = @min(current.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(current.tileRectangle.rowCount)) - 1, parent.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(parent.tileRectangle.rowCount)) - 1);
                const topOverlapPos: f32 = @floatFromInt(topOverlapTile * mapZig.GameMap.TILE_SIZE);
                const bottomOverlapPos: f32 = @floatFromInt(bottomOverlapTile * mapZig.GameMap.TILE_SIZE);
                if (topOverlapPos > lastRectangleCrossingPosition.y) {
                    rectangleCrossingPosition.y = topOverlapPos;
                } else if (bottomOverlapPos < lastRectangleCrossingPosition.y) {
                    rectangleCrossingPosition.y = bottomOverlapPos;
                } else {
                    rectangleCrossingPosition.y = lastRectangleCrossingPosition.y;
                }
            }
            current = parent;
            lastRectangleCrossingPosition = rectangleCrossingPosition;
            try citizen.moveTo.append(rectangleCrossingPosition);
        } else {
            break;
        }
    }
}

// returns false if no path found
pub fn pathfindAStar(
    goalTile: mapZig.TileXY,
    citizen: *main.Citizen,
    threadIndex: usize,
    state: *main.GameState,
) !bool {
    const startTile = mapZig.mapPositionToTileXy(citizen.position);
    if (startTile.tileX == goalTile.tileX and startTile.tileY == goalTile.tileY) {
        try citizen.moveTo.append(mapZig.mapTileXyToTilePosition(goalTile));
        return true;
    }
    if (try isTilePathBlocking(goalTile, threadIndex, state)) {
        if (PATHFINDING_DEBUG) std.debug.print("goal on blocking tile {}\n", .{goalTile});
        return false;
    }
    var openSet = &state.threadData[threadIndex].pathfindingTempData.openSet;
    openSet.clearRetainingCapacity();
    var cameFrom = &state.threadData[threadIndex].pathfindingTempData.cameFrom;
    cameFrom.clearRetainingCapacity();
    var gScore = &state.threadData[threadIndex].pathfindingTempData.gScore;
    gScore.clearRetainingCapacity();
    var neighbors = &state.threadData[threadIndex].pathfindingTempData.neighbors;
    var startRecData = try getChunkGraphRectangleIndexForTileXY(startTile, threadIndex, state);
    if (startRecData == null) {
        if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY - 1 }, threadIndex, state)) |topOfStart| {
            startRecData = topOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY + 1 }, threadIndex, state)) |bottomOfStart| {
            startRecData = bottomOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX - 1, .tileY = startTile.tileY }, threadIndex, state)) |leftOfStart| {
            startRecData = leftOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX + 1, .tileY = startTile.tileY }, threadIndex, state)) |rightOfStart| {
            startRecData = rightOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY - 2 }, threadIndex, state)) |top2OfStart| {
            startRecData = top2OfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX - 2, .tileY = startTile.tileY }, threadIndex, state)) |left2OfStart| {
            startRecData = left2OfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY + 2 }, threadIndex, state)) |bottom2OfStart| {
            startRecData = bottom2OfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX + 2, .tileY = startTile.tileY }, threadIndex, state)) |right2OfStart| {
            startRecData = right2OfStart;
        } else {
            if (PATHFINDING_DEBUG) std.debug.print("stuck on blocking tile", .{});
            return false;
        }
    }
    const startChunk = try mapZig.getChunkByChunkXYWithRequestForLoad(startRecData.?.chunkXY, threadIndex, state);
    if (startChunk == null) return false;
    const start = &startChunk.?.pathingData.graphRectangles.items[startRecData.?.index];
    const goalRecData = (try getChunkGraphRectangleIndexForTileXY(goalTile, threadIndex, state)).?;
    const goalChunk = try mapZig.getChunkByChunkXYWithRequestForLoad(goalRecData.chunkXY, threadIndex, state);
    if (goalChunk == null) return false;
    const goal = &goalChunk.?.pathingData.graphRectangles.items[goalRecData.index];

    try gScore.put(start, 0);
    const startNode = Node{
        .rectangle = start,
        .cost = 0,
        .priority = heuristic(start, goal),
    };
    try openSet.append(startNode);
    const maxSearchDistance = (main.Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE + mapZig.GameMap.CHUNK_LENGTH * 2) * mapZig.GameMap.TILE_SIZE;

    var counter: usize = 0;
    while (openSet.items.len > 0) {
        counter += 1;
        var currentIndex: usize = 0;
        var current = openSet.items[0];
        for (openSet.items, 0..) |node, i| {
            if (node.priority < current.priority) {
                current = node;
                currentIndex = i;
            }
        }

        if (cameFrom.ctx.eql(current.rectangle, goal)) {
            try reconstructPath(cameFrom, current.rectangle, goalTile, citizen);
            state.pathfindTestValue = state.pathfindTestValue * 0.99 + @as(f32, @floatFromInt(counter)) * 0.01;
            return true;
        }

        _ = openSet.swapRemove(currentIndex);

        neighbors.clearRetainingCapacity();
        var conChunk: ?*mapZig.MapChunk = null;
        for (current.rectangle.connectionIndexes.items) |conData| {
            if (conChunk == null or conChunk.?.chunkXY.chunkX != conData.chunkXY.chunkX or conChunk.?.chunkXY.chunkY != conData.chunkXY.chunkY) {
                conChunk = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(conData.chunkXY, state);
                if (conChunk == null) continue;
            }
            if (conChunk.?.pathingData.graphRectangles.items.len <= conData.index) {
                std.debug.print("beforePathfinding crash: {}, {}", .{ current.rectangle.tileRectangle, current.rectangle.index });
            }
            const neighborGraph = &conChunk.?.pathingData.graphRectangles.items[conData.index];
            const neighborMiddle = mapZig.getTileRectangleMiddlePosition(neighborGraph.tileRectangle);
            const citizenDistancePos = citizen.homePosition;
            if (@abs(neighborMiddle.x - citizenDistancePos.x) < maxSearchDistance and @abs(neighborMiddle.y - citizenDistancePos.y) < maxSearchDistance) {
                try neighbors.append(neighborGraph);
            }
        }

        for (neighbors.items) |neighbor| {
            const tentativeGScore = current.cost + 1;
            if (gScore.get(neighbor) == null or tentativeGScore < gScore.get(neighbor).?) {
                try cameFrom.put(neighbor, current.rectangle);
                try gScore.put(neighbor, tentativeGScore);
                const fScore = tentativeGScore + heuristic(neighbor, goal);
                var found = false;
                for (openSet.items) |*node| {
                    if (cameFrom.ctx.eql(node.rectangle, neighbor)) {
                        if (fScore < node.priority) {
                            node.cost = tentativeGScore;
                            node.priority = fScore;
                        }
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try openSet.append(Node{
                        .rectangle = neighbor,
                        .cost = tentativeGScore,
                        .priority = fScore,
                    });
                }
            }
        }
    }
    if (PATHFINDING_DEBUG) std.debug.print("pathfindings found no available path", .{});
    state.pathfindTestValue = state.pathfindTestValue * 0.99 + @as(f32, @floatFromInt(counter)) * 0.01;
    return false;
}

pub fn getRandomClosePathingPosition(citizen: *main.Citizen, threadIndex: usize, state: *main.GameState) !?main.Position {
    const optChunk = try mapZig.getChunkByPositionWithoutCreateOrLoad(citizen.position, state);
    if (optChunk == null) {
        return null;
    }
    const chunk = optChunk.?;
    var result: ?main.Position = null;
    const citizenPosTileXy = mapZig.mapPositionToTileXy(citizen.position);
    if (chunk.pathingData.pathingData[getPathingIndexForTileXY(citizenPosTileXy)]) |graphIndex| {
        var currentRectangle = &chunk.pathingData.graphRectangles.items[graphIndex];
        const rand = &state.random;
        for (0..2) |_| {
            if (currentRectangle.connectionIndexes.items.len == 0) break;
            const randomConnectionIndex: usize = @intFromFloat(rand.random().float(f32) * @as(f32, @floatFromInt(currentRectangle.connectionIndexes.items.len)));
            const randomCon = currentRectangle.connectionIndexes.items[randomConnectionIndex];
            const optConChunk = (try mapZig.getChunkByChunkXYWithoutCreateOrLoad(randomCon.chunkXY, state));
            if (optConChunk) |conChunk| currentRectangle = &conChunk.pathingData.graphRectangles.items[randomCon.index];
        }
        const randomReachableGraphTopLeftPos = mapZig.mapTileXyToTileMiddlePosition(currentRectangle.tileRectangle.topLeftTileXY);
        const homePos: main.Position = citizen.homePosition;
        const finalRandomPosition = main.Position{
            .x = randomReachableGraphTopLeftPos.x + @as(f64, @floatFromInt((currentRectangle.tileRectangle.columnCount - 1) * mapZig.GameMap.TILE_SIZE)) * rand.random().float(f64),
            .y = randomReachableGraphTopLeftPos.y + @as(f64, @floatFromInt((currentRectangle.tileRectangle.rowCount - 1) * mapZig.GameMap.TILE_SIZE)) * rand.random().float(f64),
        };
        const distanceHomeRandomPosition = main.calculateDistance(finalRandomPosition, homePos);
        if (distanceHomeRandomPosition < main.Citizen.MAX_SQUARE_TILE_SEARCH_DISTANCE * mapZig.GameMap.TILE_SIZE * 0.4 or main.calculateDistance(homePos, citizen.position) > distanceHomeRandomPosition) {
            result = finalRandomPosition;
        }
    } else {
        if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY - 1 }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY - 1 });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY + 1 }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY + 1 });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX - 1, .tileY = citizenPosTileXy.tileY }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX - 1, .tileY = citizenPosTileXy.tileY });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX + 1, .tileY = citizenPosTileXy.tileY }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX + 1, .tileY = citizenPosTileXy.tileY });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY - 2 }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY - 2 });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX - 2, .tileY = citizenPosTileXy.tileY }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX - 2, .tileY = citizenPosTileXy.tileY });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY + 2 }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX, .tileY = citizenPosTileXy.tileY + 2 });
        } else if (!try isTilePathBlocking(.{ .tileX = citizenPosTileXy.tileX + 2, .tileY = citizenPosTileXy.tileY }, threadIndex, state)) {
            result = mapZig.mapTileXyToTileMiddlePosition(.{ .tileX = citizenPosTileXy.tileX + 2, .tileY = citizenPosTileXy.tileY });
        }
    }
    return result;
}

pub fn paintDebugPathfindingVisualization(state: *main.GameState) !void {
    if (!PATHFINDING_DEBUG) return;
    const recVertCount = 8;
    const graphRectangleColor = [_]f32{ 1, 0, 0 };
    const connectionRectangleColor = [_]f32{ 0, 0, 1 };
    const visibleChunks = mapZig.getTopLeftVisibleChunkXY(state);

    mainLoop: for (0..visibleChunks.rows + 2) |row| {
        for (0..visibleChunks.columns + 2) |column| {
            const chunkXY: mapZig.ChunkXY = .{ .chunkX = @as(i32, @intCast(row)) + visibleChunks.left, .chunkY = @as(i32, @intCast(column)) + visibleChunks.top };
            const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, 0, state);
            for (chunk.pathingData.graphRectangles.items) |rectangle| {
                const topLeftVulkan = mapZig.mapTileXyToVulkanSurfacePosition(rectangle.tileRectangle.topLeftTileXY, state.camera);
                const bottomRightVulkan = mapZig.mapTileXyToVulkanSurfacePosition(.{
                    .tileX = rectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(rectangle.tileRectangle.columnCount)),
                    .tileY = rectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(rectangle.tileRectangle.rowCount)),
                }, state.camera);
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount] = .{ .pos = .{ topLeftVulkan.x, topLeftVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 1] = .{ .pos = .{ bottomRightVulkan.x, topLeftVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 2] = .{ .pos = .{ bottomRightVulkan.x, topLeftVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 3] = .{ .pos = .{ bottomRightVulkan.x, bottomRightVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 4] = .{ .pos = .{ bottomRightVulkan.x, bottomRightVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 5] = .{ .pos = .{ topLeftVulkan.x, bottomRightVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 6] = .{ .pos = .{ topLeftVulkan.x, bottomRightVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 7] = .{ .pos = .{ topLeftVulkan.x, topLeftVulkan.y }, .color = graphRectangleColor };
                state.vkState.rectangle.verticeCount += recVertCount;
                for (rectangle.connectionIndexes.items) |conData| {
                    if (try mapZig.getChunkByChunkXYWithoutCreateOrLoad(conData.chunkXY, state)) |conChunk| {
                        if (state.vkState.rectangle.verticeCount + 6 >= rectangleVulkanZig.VkRectangle.MAX_VERTICES) break :mainLoop;
                        if (conChunk.pathingData.graphRectangles.items.len <= conData.index) {
                            std.debug.print("beforeCrash: {}, {}, {}, {}, {}\n", .{ rectangle.tileRectangle, rectangle.index, rectangle.chunkXY, conData.chunkXY, rectangle.connectionIndexes.items.len });
                            continue;
                        }
                        const conRect = conChunk.pathingData.graphRectangles.items[conData.index].tileRectangle;
                        var rectTileXy: mapZig.TileXY = rectangle.tileRectangle.topLeftTileXY;
                        var conTileXy: mapZig.TileXY = conRect.topLeftTileXY;
                        if (rectangle.tileRectangle.topLeftTileXY.tileY < conRect.topLeftTileXY.tileY + @as(i32, @intCast(conRect.rowCount)) and conRect.topLeftTileXY.tileY < rectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(rectangle.tileRectangle.rowCount)) and
                            rectangle.tileRectangle.topLeftTileXY.tileX <= conRect.topLeftTileXY.tileX + @as(i32, @intCast(conRect.columnCount)) and conRect.topLeftTileXY.tileX <= rectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(rectangle.tileRectangle.columnCount)))
                        {
                            const maxTop = @max(rectangle.tileRectangle.topLeftTileXY.tileY, conRect.topLeftTileXY.tileY);
                            const minBottom = @min(rectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(rectangle.tileRectangle.rowCount)), conRect.topLeftTileXY.tileY + @as(i32, @intCast(conRect.rowCount)));
                            const middleY = @divFloor(maxTop + minBottom, 2);
                            rectTileXy.tileY = middleY;
                            conTileXy.tileY = middleY;
                            if (rectTileXy.tileX < conTileXy.tileX) {
                                rectTileXy.tileX = conTileXy.tileX - 1;
                            } else {
                                conTileXy.tileX = rectTileXy.tileX - 1;
                            }
                        } else if (rectangle.tileRectangle.topLeftTileXY.tileX < conRect.topLeftTileXY.tileX + @as(i32, @intCast(conRect.columnCount)) and conRect.topLeftTileXY.tileX < rectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(rectangle.tileRectangle.columnCount)) and
                            rectangle.tileRectangle.topLeftTileXY.tileY <= conRect.topLeftTileXY.tileY + @as(i32, @intCast(conRect.rowCount)) and conRect.topLeftTileXY.tileY <= rectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(rectangle.tileRectangle.rowCount)))
                        {
                            const maxLeft = @max(rectangle.tileRectangle.topLeftTileXY.tileX, conRect.topLeftTileXY.tileX);
                            const minRight = @min(rectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(rectangle.tileRectangle.columnCount)), conRect.topLeftTileXY.tileX + @as(i32, @intCast(conRect.columnCount)));
                            const middleX = @divFloor(maxLeft + minRight, 2);
                            rectTileXy.tileX = middleX;
                            conTileXy.tileX = middleX;
                            if (rectTileXy.tileY < conTileXy.tileY) {
                                rectTileXy.tileY = conTileXy.tileY - 1;
                            } else {
                                conTileXy.tileY = rectTileXy.tileY - 1;
                            }
                        }

                        const conArrowEndVulkan = mapZig.mapTileXyMiddleToVulkanSurfacePosition(conTileXy, state.camera);
                        const arrowStartVulkan = mapZig.mapTileXyMiddleToVulkanSurfacePosition(rectTileXy, state.camera);
                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = connectionRectangleColor };
                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 1] = .{ .pos = .{ arrowStartVulkan.x, arrowStartVulkan.y }, .color = connectionRectangleColor };

                        const direction = main.calculateDirection(arrowStartVulkan, conArrowEndVulkan) + std.math.pi;

                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 2] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = .{ 0, 0, 0 } };
                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 3] = .{ .pos = .{ conArrowEndVulkan.x + @cos(direction + 0.3) * 0.05, conArrowEndVulkan.y + @sin(direction + 0.3) * 0.05 }, .color = .{ 0, 0, 0 } };
                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 4] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = .{ 0, 0, 0 } };
                        state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 5] = .{ .pos = .{ conArrowEndVulkan.x + @cos(direction - 0.3) * 0.05, conArrowEndVulkan.y + @sin(direction - 0.3) * 0.05 }, .color = .{ 0, 0, 0 } };
                        state.vkState.rectangle.verticeCount += 6;
                    }
                }
                if (state.vkState.rectangle.verticeCount + recVertCount >= rectangleVulkanZig.VkRectangle.MAX_VERTICES) break :mainLoop;
            }
        }
    }
}

pub fn paintDebugPathfindingVisualizationFont(state: *main.GameState) !void {
    if (!PATHFINDING_DEBUG) return;
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForPosition(state.camera.position, 0, state);
    for (chunk.pathingData.pathingData, 0..) |optGraphIndex, i| {
        if (optGraphIndex) |graphIndex| {
            const mapPosition = getMapPositionForPathingIndex(chunk, i);
            const vulkanPosition = mapZig.mapPositionToVulkanSurfacePoisition(mapPosition.x, mapPosition.y, state.camera);
            _ = try fontVulkanZig.paintNumber(@as(u32, @intCast(graphIndex)), vulkanPosition, 16, &state.vkState.font.vkFont);
        }
    }
}

fn isTilePathBlocking(tileXY: mapZig.TileXY, threadIndex: usize, state: *main.GameState) !bool {
    return try getChunkGraphRectangleIndexForTileXY(tileXY, threadIndex, state) == null;
}

fn getChunkGraphRectangleIndexForTileXY(tileXY: mapZig.TileXY, threadIndex: usize, state: *main.GameState) !?GraphConnection {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkByChunkXYWithRequestForLoad(chunkXY, threadIndex, state);
    if (chunk == null) return null;
    const pathingDataIndex = getPathingIndexForTileXY(tileXY);
    const optIndex = chunk.?.pathingData.pathingData[pathingDataIndex];
    if (optIndex) |index| {
        return .{ .index = index, .chunkXY = chunkXY };
    } else {
        return null;
    }
}

pub fn getPathingIndexForTileXY(tileXY: mapZig.TileXY) usize {
    return @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
}

fn getMapPositionForPathingIndex(chunk: *mapZig.MapChunk, pathingIndex: usize) main.Position {
    return .{
        .x = @floatFromInt(chunk.chunkXY.chunkX * mapZig.GameMap.CHUNK_SIZE + @as(i32, @intCast(@mod(pathingIndex, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.TILE_SIZE))),
        .y = @floatFromInt(chunk.chunkXY.chunkY * mapZig.GameMap.CHUNK_SIZE + @as(i32, @intCast(@divFloor(pathingIndex, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.TILE_SIZE))),
    };
}

pub fn checkIsPositionReachableMovementAreaBiggerThan(position: main.Position, threadIndex: usize, limit: u32, state: *main.GameState) !bool {
    const visitedGraphRecList = &state.threadData[threadIndex].pathfindingTempData.neighbors;
    const toVisitGraphRecList = &state.threadData[threadIndex].pathfindingTempData.openSet;
    visitedGraphRecList.clearRetainingCapacity();
    toVisitGraphRecList.clearRetainingCapacity();

    const optChunk = try mapZig.getChunkByPositionWithoutCreateOrLoad(position, state);
    if (optChunk) |chunk| {
        var reachableAreaSize: u32 = 0;
        const tileXY = mapZig.mapPositionToTileXy(position);
        const pathingDataIndex = getPathingIndexForTileXY(tileXY);
        const optGraphIndex = chunk.pathingData.pathingData[pathingDataIndex];
        if (optGraphIndex) |graphIndex| {
            try toVisitGraphRecList.append(.{ .cost = 0, .priority = 0, .rectangle = &chunk.pathingData.graphRectangles.items[graphIndex] });
            while (toVisitGraphRecList.items.len > 0) {
                const current = toVisitGraphRecList.swapRemove(0).rectangle;
                reachableAreaSize += current.tileRectangle.columnCount * current.tileRectangle.rowCount;
                if (reachableAreaSize >= limit) return true;
                try visitedGraphRecList.append(current);
                neighborLoop: for (current.connectionIndexes.items) |neighbor| {
                    for (visitedGraphRecList.items) |visited| {
                        if (visited.index == neighbor.index and visited.chunkXY.chunkX == neighbor.chunkXY.chunkX and visited.chunkXY.chunkY == neighbor.chunkXY.chunkY) {
                            continue :neighborLoop;
                        }
                    }
                    const optNeighborChunk = try mapZig.getChunkByChunkXYWithoutCreateOrLoad(neighbor.chunkXY, state);
                    if (optNeighborChunk) |neighborChunk| {
                        try toVisitGraphRecList.append(.{ .cost = 0, .priority = 0, .rectangle = &neighborChunk.pathingData.graphRectangles.items[neighbor.index] });
                    }
                }
            }
        }
    }
    return false;
}
