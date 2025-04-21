const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");
const rectangleVulkanZig = @import("vulkan/rectangleVulkan.zig");

const PATHFINDING_DEBUG = true;

pub const PathfindingData = struct {
    openSet: std.ArrayList(Node),
    cameFrom: std.HashMap(*ChunkGraphRectangle, *ChunkGraphRectangle, ChunkGraphRectangleContext, 80),
    gScore: std.AutoHashMap(*ChunkGraphRectangle, i32),
    neighbors: std.ArrayList(*ChunkGraphRectangle),
    graphRectangles: std.ArrayList(ChunkGraphRectangle),
};

pub const ChunkGraphRectangle = struct {
    index: usize,
    tileRectangle: mapZig.MapTileRectangle,
    connectionIndexes: std.ArrayList(usize),
};

pub const PathfindingChunkData = struct {
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

pub fn createChunkData(chunkXY: mapZig.ChunkXY, allocator: std.mem.Allocator, state: *main.ChatSimState) !PathfindingChunkData {
    const chunkGraphRectangle: ChunkGraphRectangle = .{
        .index = state.pathfindingData.graphRectangles.items.len,
        .connectionIndexes = std.ArrayList(usize).init(allocator),
        .tileRectangle = .{
            .topLeftTileXY = .{
                .tileX = chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
                .tileY = chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
            },
            .columnCount = mapZig.GameMap.CHUNK_LENGTH,
            .rowCount = mapZig.GameMap.CHUNK_LENGTH,
        },
    };
    try state.pathfindingData.graphRectangles.append(chunkGraphRectangle);
    var result: PathfindingChunkData = .{ .pathingData = undefined };
    for (0..result.pathingData.len) |i| {
        result.pathingData[i] = chunkGraphRectangle.index;
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
            const neighborGraphRectangleIndex = neighborChunk.pathingData.pathingData[0].?;
            try state.pathfindingData.graphRectangles.items[neighborGraphRectangleIndex].connectionIndexes.append(chunkGraphRectangle.index);
            try state.pathfindingData.graphRectangles.items[chunkGraphRectangle.index].connectionIndexes.append(neighborGraphRectangleIndex);
        }
    }

    return result;
}

pub fn changePathingDataRectangle(rectangle: mapZig.MapTileRectangle, pathingType: mapZig.PathingType, state: *main.ChatSimState) !void {
    if (pathingType == mapZig.PathingType.blocking) {
        const chunkXY = mapZig.getChunkXyForTileXy(rectangle.topLeftTileXY);
        const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
        const topLeftPathingIndex = getPathingIndexForTileXY(rectangle.topLeftTileXY);
        const optGraphRectangleIndex = chunk.pathingData.pathingData[topLeftPathingIndex];
        if (optGraphRectangleIndex) |graphRectangleIndex| {
            if (PATHFINDING_DEBUG) std.debug.print("start change graph\n", .{});
            if (PATHFINDING_DEBUG) std.debug.print("    placed blocking rectangle: {}\n", .{rectangle});
            chunk.pathingData.pathingData[topLeftPathingIndex] = null;
            var graphRectangleForUpdateIndex: usize = 0;
            var graphRectangleForUpdateIndexes = [_]?usize{ null, null, null, null };
            const toSplitGraphRectangle = state.pathfindingData.graphRectangles.items[graphRectangleIndex];
            if (PATHFINDING_DEBUG) {
                std.debug.print("    graph rect to change: ", .{});
                printGraphData(&toSplitGraphRectangle);
            }
            const directions = [_]mapZig.TileXY{
                .{ .tileX = -1, .tileY = 0 },
                .{ .tileX = 0, .tileY = -1 },
                .{ .tileX = 1, .tileY = 0 },
                .{ .tileX = 0, .tileY = 1 },
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
                if (toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileX <= adjacentTile.tileX and adjacentTile.tileX <= toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(toSplitGraphRectangle.tileRectangle.columnCount)) - 1 and toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileY <= adjacentTile.tileY and adjacentTile.tileY <= toSplitGraphRectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(toSplitGraphRectangle.tileRectangle.rowCount)) - 1) {
                    newTileRetangles[i] = createAjdacentTileRectangle(adjacentTile, i, toSplitGraphRectangle);
                    if (PATHFINDING_DEBUG) std.debug.print("        added tile rectangle: {}\n", .{newTileRetangles[i].?});
                }
            }
            // check merges
            var lastMergedTileRectanlge: ?mapZig.MapTileRectangle = null;
            for (newTileRetangles, 0..) |optTileRectangle, i| {
                if (optTileRectangle) |tileRectangle| {
                    if (try checkMergeGraphRectangles(tileRectangle, i, chunk, state)) |mergeIndex| {
                        lastMergedTileRectanlge = tileRectangle;
                        newTileRetangles[i] = null;
                        graphRectangleForUpdateIndexes[graphRectangleForUpdateIndex] = mergeIndex;
                        graphRectangleForUpdateIndex += 1;
                    }
                }
            }
            // create new rectangles which could not merge
            var originalReplaced = false;
            var tileRectangleIndexToGraphRectangleIndex = [_]?usize{ null, null, null, null };
            for (newTileRetangles, 0..) |optTileRectangle, i| {
                if (optTileRectangle) |tileRectangle| {
                    if (PATHFINDING_DEBUG) {
                        std.debug.print("   Create graph rec from tile rec or replace old one: {} \n", .{tileRectangle});
                    }
                    var newGraphRectangle: ChunkGraphRectangle = .{
                        .tileRectangle = tileRectangle,
                        .index = state.pathfindingData.graphRectangles.items.len,
                        .connectionIndexes = std.ArrayList(usize).init(state.allocator),
                    };
                    // connections from newest to previous
                    for (0..i) |connectToIndex| {
                        if (i > 1 and i - 2 == connectToIndex) continue; // do not connect diagonals
                        if (tileRectangleIndexToGraphRectangleIndex[connectToIndex]) |connectToGraphIndex| {
                            try newGraphRectangle.connectionIndexes.append(connectToGraphIndex);
                            if (PATHFINDING_DEBUG) {
                                std.debug.print("       added connection {} to rec {}. ", .{ newGraphRectangle.index, connectToGraphIndex });
                                printGraphData(&newGraphRectangle);
                            }
                        }
                    }

                    if (originalReplaced) {
                        try state.pathfindingData.graphRectangles.append(newGraphRectangle);
                        if (PATHFINDING_DEBUG) std.debug.print("        new rec {}, {}\n", .{ newGraphRectangle.index, newGraphRectangle.tileRectangle });
                    } else {
                        originalReplaced = true;
                        newGraphRectangle.index = toSplitGraphRectangle.index;
                        state.pathfindingData.graphRectangles.items[toSplitGraphRectangle.index] = newGraphRectangle;
                        if (PATHFINDING_DEBUG) std.debug.print("        replaced rec {} with {}\n", .{ newGraphRectangle.index, newGraphRectangle.tileRectangle });
                    }
                    try setPaththingDataRectangle(tileRectangle, newGraphRectangle.index, state);
                    graphRectangleForUpdateIndexes[graphRectangleForUpdateIndex] = newGraphRectangle.index;
                    tileRectangleIndexToGraphRectangleIndex[i] = newGraphRectangle.index;
                    graphRectangleForUpdateIndex += 1;
                    // connections from previous to newest
                    for (0..i) |connectToIndex| {
                        if (i > 1 and i - 2 == connectToIndex) continue; // do not connect diagonals
                        if (tileRectangleIndexToGraphRectangleIndex[connectToIndex]) |connectToGraphIndex| {
                            const previousNewGraphRectangle = &state.pathfindingData.graphRectangles.items[connectToGraphIndex];
                            try previousNewGraphRectangle.connectionIndexes.append(newGraphRectangle.index);
                            if (PATHFINDING_DEBUG) {
                                std.debug.print("       added connection {} to rec {}. ", .{ newGraphRectangle.index, previousNewGraphRectangle.index });
                                printGraphData(&newGraphRectangle);
                            }
                        }
                    }
                }
            }
            // correct connetions
            for (toSplitGraphRectangle.connectionIndexes.items) |conIndex| {
                if (PATHFINDING_DEBUG) std.debug.print("    checking rec {} conIndex {}\n", .{ toSplitGraphRectangle.index, conIndex });
                const connectionGraphRectanglePtr = &state.pathfindingData.graphRectangles.items[conIndex];
                const rect1 = connectionGraphRectanglePtr.tileRectangle;
                var connectionGraphReplacedOld = false;
                for (graphRectangleForUpdateIndexes) |optIndex| {
                    if (optIndex) |index| {
                        if (index == conIndex) continue;
                        const newGraphRectanglePtr = &state.pathfindingData.graphRectangles.items[index];
                        const rect2 = newGraphRectanglePtr.tileRectangle;
                        if (rect1.topLeftTileXY.tileX <= rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount)) and rect2.topLeftTileXY.tileX <= rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount)) and
                            rect1.topLeftTileXY.tileY <= rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount)) and rect2.topLeftTileXY.tileY <= rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount)))
                        {
                            if (rect1.topLeftTileXY.tileX < rect2.topLeftTileXY.tileX + @as(i32, @intCast(rect2.columnCount)) and rect2.topLeftTileXY.tileX <= rect1.topLeftTileXY.tileX + @as(i32, @intCast(rect1.columnCount)) or
                                rect1.topLeftTileXY.tileY <= rect2.topLeftTileXY.tileY + @as(i32, @intCast(rect2.rowCount)) and rect2.topLeftTileXY.tileY <= rect1.topLeftTileXY.tileY + @as(i32, @intCast(rect1.rowCount)))
                            {
                                var replacedNew = false;
                                if (!connectionGraphReplacedOld) {
                                    for (0..connectionGraphRectanglePtr.connectionIndexes.items.len) |conIndexIndex| {
                                        if (connectionGraphRectanglePtr.connectionIndexes.items[conIndexIndex] == toSplitGraphRectangle.index) {
                                            connectionGraphReplacedOld = true;
                                            if (connectionsIndexesContains(connectionGraphRectanglePtr.connectionIndexes.items, toSplitGraphRectangle.index)) {
                                                if (toSplitGraphRectangle.index != newGraphRectanglePtr.index) {
                                                    _ = connectionGraphRectanglePtr.connectionIndexes.swapRemove(conIndexIndex);
                                                    if (PATHFINDING_DEBUG) {
                                                        std.debug.print("       removed connection {} in rec {}. ", .{ toSplitGraphRectangle.index, connectionGraphRectanglePtr.index });
                                                        printGraphData(connectionGraphRectanglePtr);
                                                    }
                                                }
                                            } else {
                                                replacedNew = true;
                                                connectionGraphRectanglePtr.connectionIndexes.items[conIndexIndex] = newGraphRectanglePtr.index;
                                                if (PATHFINDING_DEBUG) {
                                                    std.debug.print("       update connection in rec {} from {} to {}. ", .{ connectionGraphRectanglePtr.index, toSplitGraphRectangle.index, newGraphRectanglePtr.index });
                                                    printGraphData(connectionGraphRectanglePtr);
                                                }
                                            }
                                            break;
                                        }
                                    }
                                }
                                _ = try appendConnectionWithCheck(newGraphRectanglePtr, connectionGraphRectanglePtr.index);
                                if (!replacedNew) {
                                    _ = try appendConnectionWithCheck(connectionGraphRectanglePtr, newGraphRectanglePtr.index);
                                }
                            }
                        }
                    }
                }
                if (!connectionGraphReplacedOld) {
                    for (0..connectionGraphRectanglePtr.connectionIndexes.items.len) |conIndexIndex| {
                        if (connectionGraphRectanglePtr.connectionIndexes.items[conIndexIndex] == toSplitGraphRectangle.index) {
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
                try swapRemoveGraphIndex(toSplitGraphRectangle.index, state);

                if (lastMergedTileRectanlge) |tileRec| {
                    if (chunk.pathingData.pathingData[getPathingIndexForTileXY(tileRec.topLeftTileXY)]) |anotherMergeCheckGraphIndex| {
                        _ = try checkForGraphMergeAndDoIt(anotherMergeCheckGraphIndex, chunk, state);
                    }
                }
            }
            toSplitGraphRectangle.connectionIndexes.deinit();
        }
    } else {
        //TODO
    }
}

/// returns true if something merged
fn checkForGraphMergeAndDoIt(graphRectForMergeCheckIndex: usize, chunk: *mapZig.MapChunk, state: *main.ChatSimState) !bool {
    const graphRectForMergeCheck = state.pathfindingData.graphRectangles.items[graphRectForMergeCheckIndex];
    if (try checkMergeGraphRectangles(graphRectForMergeCheck.tileRectangle, 5, chunk, state)) |mergeIndex| {
        const mergedToGraphRectangle = &state.pathfindingData.graphRectangles.items[mergeIndex];
        if (PATHFINDING_DEBUG) {
            std.debug.print("   merged rec {} with {}\n", .{ mergeIndex, graphRectForMergeCheck.index });
        }
        for (graphRectForMergeCheck.connectionIndexes.items) |conIndex| {
            if (mergeIndex == conIndex) continue;
            const connectionGraphRectangle = &state.pathfindingData.graphRectangles.items[conIndex];
            for (connectionGraphRectangle.connectionIndexes.items, 0..) |mergedToConIndex, mergeToIndexIndex| {
                if (mergedToConIndex == graphRectForMergeCheck.index) {
                    if (!connectionsIndexesContains(connectionGraphRectangle.connectionIndexes.items, mergeIndex)) {
                        connectionGraphRectangle.connectionIndexes.items[mergeToIndexIndex] = mergeIndex;
                        if (PATHFINDING_DEBUG) {
                            std.debug.print("       updated connection in rec {} from {} to {}. ", .{ connectionGraphRectangle.index, mergedToConIndex, mergeIndex });
                            printGraphData(connectionGraphRectangle);
                        }
                    } else {
                        _ = connectionGraphRectangle.connectionIndexes.swapRemove(mergeToIndexIndex);
                        if (PATHFINDING_DEBUG) {
                            std.debug.print("       removed connection {} from rec {}. ", .{ mergedToConIndex, connectionGraphRectangle.index });
                            printGraphData(connectionGraphRectangle);
                        }
                    }
                    _ = try appendConnectionWithCheck(mergedToGraphRectangle, conIndex);
                    break;
                }
            }
        }
        try swapRemoveGraphIndex(graphRectForMergeCheck.index, state);
        graphRectForMergeCheck.connectionIndexes.deinit();
        return true;
    }
    return false;
}

/// returns true if appended
fn appendConnectionWithCheck(addConnectionbToGraph: *ChunkGraphRectangle, newConIndex: usize) !bool {
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

fn printGraphData(addConnectionbToGraph: *const ChunkGraphRectangle) void {
    std.debug.print("rec(id: {}, topLeft: {}|{}, c:{}, r:{}, connections:{any})\n", .{
        addConnectionbToGraph.index,
        addConnectionbToGraph.tileRectangle.topLeftTileXY.tileX,
        addConnectionbToGraph.tileRectangle.topLeftTileXY.tileY,
        addConnectionbToGraph.tileRectangle.columnCount,
        addConnectionbToGraph.tileRectangle.rowCount,
        addConnectionbToGraph.connectionIndexes.items,
    });
}

fn connectionsIndexesContains(indexes: []usize, checkIndex: usize) bool {
    for (indexes) |index| {
        if (index == checkIndex) {
            return true;
        }
    }
    return false;
}

/// returns merge graph rectangle index
fn checkMergeGraphRectangles(tileRectangle: mapZig.MapTileRectangle, skipDirectionIndex: usize, chunk: *mapZig.MapChunk, state: *main.ChatSimState) !?usize {
    if (skipDirectionIndex != 0) {
        //do right merge check
        if (@mod(tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(tileRectangle.columnCount)), mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
            const optRightGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(tileRectangle.columnCount)), .tileY = tileRectangle.topLeftTileXY.tileY })];
            if (optRightGraphRectangleIndex) |rightRectangleIndex| {
                const rightRectangle = &state.pathfindingData.graphRectangles.items[rightRectangleIndex];
                if (rightRectangle.tileRectangle.topLeftTileXY.tileY == tileRectangle.topLeftTileXY.tileY and rightRectangle.tileRectangle.rowCount == tileRectangle.rowCount) {
                    // can be merged
                    rightRectangle.tileRectangle.columnCount += @as(u32, @intCast(rightRectangle.tileRectangle.topLeftTileXY.tileX - tileRectangle.topLeftTileXY.tileX));
                    rightRectangle.tileRectangle.topLeftTileXY.tileX = tileRectangle.topLeftTileXY.tileX;
                    try setPaththingDataRectangle(tileRectangle, rightRectangle.index, state);
                    if (PATHFINDING_DEBUG) std.debug.print("    merge right {}, {}, mergedWith: {}\n", .{ rightRectangle.tileRectangle, rightRectangle.index, tileRectangle });
                    return rightRectangle.index;
                }
            }
        }
    }
    if (skipDirectionIndex != 1) {
        //do down merge check
        if (@mod(tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(tileRectangle.rowCount)), mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
            const optDownGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX, .tileY = tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(tileRectangle.rowCount)) })];
            if (optDownGraphRectangleIndex) |downRectangleIndex| {
                const downRectangle = &state.pathfindingData.graphRectangles.items[downRectangleIndex];
                if (downRectangle.tileRectangle.topLeftTileXY.tileX == tileRectangle.topLeftTileXY.tileX and downRectangle.tileRectangle.columnCount == tileRectangle.columnCount) {
                    // can be merged
                    downRectangle.tileRectangle.rowCount += @as(u32, @intCast(downRectangle.tileRectangle.topLeftTileXY.tileY - tileRectangle.topLeftTileXY.tileY));
                    downRectangle.tileRectangle.topLeftTileXY.tileY = tileRectangle.topLeftTileXY.tileY;
                    try setPaththingDataRectangle(tileRectangle, downRectangle.index, state);
                    if (PATHFINDING_DEBUG) std.debug.print("    merge down {}, {}\n", .{ downRectangle.tileRectangle, downRectangle.index });
                    return downRectangle.index;
                }
            }
        }
    }
    if (skipDirectionIndex != 2) {
        //do left merge check
        if (@mod(tileRectangle.topLeftTileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
            const optLeftGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX - 1, .tileY = tileRectangle.topLeftTileXY.tileY })];
            if (optLeftGraphRectangleIndex) |leftRectangleIndex| {
                const leftRectangle = &state.pathfindingData.graphRectangles.items[leftRectangleIndex];
                if (leftRectangle.tileRectangle.topLeftTileXY.tileY == tileRectangle.topLeftTileXY.tileY and leftRectangle.tileRectangle.rowCount == tileRectangle.rowCount) {
                    // can be merged
                    leftRectangle.tileRectangle.columnCount += tileRectangle.columnCount;
                    try setPaththingDataRectangle(tileRectangle, leftRectangle.index, state);
                    if (PATHFINDING_DEBUG) std.debug.print("    merge left {}, {}\n", .{ leftRectangle.tileRectangle, leftRectangle.index });
                    return leftRectangle.index;
                }
            }
        }
    }
    if (skipDirectionIndex != 3) {
        //do up merge check
        if (@mod(tileRectangle.topLeftTileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) != 0) { //don't merge with other chunk
            const optUpGraphRectangleIndex = chunk.pathingData.pathingData[getPathingIndexForTileXY(.{ .tileX = tileRectangle.topLeftTileXY.tileX, .tileY = tileRectangle.topLeftTileXY.tileY - 1 })];
            if (optUpGraphRectangleIndex) |upRectangleIndex| {
                const upRectangle = &state.pathfindingData.graphRectangles.items[upRectangleIndex];
                if (upRectangle.tileRectangle.topLeftTileXY.tileX == tileRectangle.topLeftTileXY.tileX and upRectangle.tileRectangle.columnCount == tileRectangle.columnCount) {
                    // can be merged
                    upRectangle.tileRectangle.rowCount += tileRectangle.rowCount;
                    try setPaththingDataRectangle(tileRectangle, upRectangle.index, state);
                    if (PATHFINDING_DEBUG) std.debug.print("    merge up {}, {}\n", .{ upRectangle.tileRectangle, upRectangle.index });
                    return upRectangleIndex;
                }
            }
        }
    }
    return null;
}

fn swapRemoveGraphIndex(graphIndex: usize, state: *main.ChatSimState) !void {
    const removedGraph = state.pathfindingData.graphRectangles.swapRemove(graphIndex);
    if (PATHFINDING_DEBUG) {
        std.debug.print("   swap remove {}. ", .{graphIndex});
        printGraphData(&removedGraph);
    }
    const oldIndex = state.pathfindingData.graphRectangles.items.len;
    // remove existing connections to removedGraph
    for (removedGraph.connectionIndexes.items) |conIndex| {
        const connectedGraph = if (conIndex != oldIndex) &state.pathfindingData.graphRectangles.items[conIndex] else &state.pathfindingData.graphRectangles.items[graphIndex];
        for (connectedGraph.connectionIndexes.items, 0..) |checkIndex, i| {
            if (checkIndex == graphIndex) {
                _ = connectedGraph.connectionIndexes.swapRemove(i);
                if (PATHFINDING_DEBUG) {
                    std.debug.print("       removed connection {} from rec {}. ", .{ checkIndex, connectedGraph.index });
                    printGraphData(connectedGraph);
                }
                break;
            }
        }
    }

    // change indexes of newAtIndex
    if (graphIndex >= oldIndex) return;
    const newAtIndex = &state.pathfindingData.graphRectangles.items[graphIndex];
    if (PATHFINDING_DEBUG) {
        std.debug.print("   changed index rec {} -> {}. ", .{ newAtIndex.index, graphIndex });
        printGraphData(newAtIndex);
    }
    newAtIndex.index = graphIndex;
    for (newAtIndex.connectionIndexes.items) |conIndex| {
        const connectedGraph = &state.pathfindingData.graphRectangles.items[conIndex];
        for (connectedGraph.connectionIndexes.items, 0..) |checkIndex, i| {
            if (checkIndex == oldIndex) {
                connectedGraph.connectionIndexes.items[i] = graphIndex;
                if (PATHFINDING_DEBUG) {
                    std.debug.print("       updated connection in rec {} from {} to {}. ", .{ connectedGraph.index, oldIndex, graphIndex });
                    printGraphData(connectedGraph);
                }

                break;
            }
        }
    }
    try setPaththingDataRectangle(newAtIndex.tileRectangle, graphIndex, state);
}

/// assumes to be only in one chunk
fn setPaththingDataRectangle(rectangle: mapZig.MapTileRectangle, newIndex: ?usize, state: *main.ChatSimState) !void {
    const chunkXY = mapZig.getChunkXyForTileXy(rectangle.topLeftTileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
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

pub fn createPathfindingData(allocator: std.mem.Allocator) !PathfindingData {
    return PathfindingData{
        .openSet = std.ArrayList(Node).init(allocator),
        .cameFrom = std.HashMap(*ChunkGraphRectangle, *ChunkGraphRectangle, ChunkGraphRectangleContext, 80).init(allocator),
        .gScore = std.AutoHashMap(*ChunkGraphRectangle, i32).init(allocator),
        .graphRectangles = std.ArrayList(ChunkGraphRectangle).init(allocator),
        .neighbors = std.ArrayList(*ChunkGraphRectangle).init(allocator),
    };
}

pub fn destoryChunkData(pathingData: *PathfindingChunkData) void {
    _ = pathingData;
}

pub fn destoryPathfindingData(data: *PathfindingData) void {
    data.cameFrom.deinit();
    data.gScore.deinit();
    data.openSet.deinit();
    data.neighbors.deinit();
    for (data.graphRectangles.items) |graphRectangle| {
        graphRectangle.connectionIndexes.deinit();
    }
    data.graphRectangles.deinit();
}

pub fn heuristic(a: *ChunkGraphRectangle, b: *ChunkGraphRectangle) i32 {
    return @as(i32, @intCast(@abs(a.tileRectangle.topLeftTileXY.tileX - b.tileRectangle.topLeftTileXY.tileX) + @abs(a.tileRectangle.topLeftTileXY.tileY - b.tileRectangle.topLeftTileXY.tileY)));
}

pub fn reconstructPath(
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

pub fn pathfindAStar(
    startTile: mapZig.TileXY,
    goalTile: mapZig.TileXY,
    citizen: *main.Citizen,
    state: *main.ChatSimState,
) !void {
    if (try isTilePathBlocking(goalTile, state)) {
        if (PATHFINDING_DEBUG) std.debug.print("goal on blocking tile {}\n", .{goalTile});
        return;
    }
    var openSet = &state.pathfindingData.openSet;
    openSet.clearRetainingCapacity();
    var cameFrom = &state.pathfindingData.cameFrom;
    cameFrom.clearRetainingCapacity();
    var gScore = &state.pathfindingData.gScore;
    gScore.clearRetainingCapacity();
    var neighbors = &state.pathfindingData.neighbors;
    var startRecIndex = try getChunkGraphRectangleIndexForTileXY(startTile, state);
    if (startRecIndex == null) {
        if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY - 1 }, state)) |topOfStart| {
            startRecIndex = topOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX, .tileY = startTile.tileY + 1 }, state)) |bottomOfStart| {
            startRecIndex = bottomOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX - 1, .tileY = startTile.tileY }, state)) |leftOfStart| {
            startRecIndex = leftOfStart;
        } else if (try getChunkGraphRectangleIndexForTileXY(.{ .tileX = startTile.tileX + 1, .tileY = startTile.tileY }, state)) |rightOfStart| {
            startRecIndex = rightOfStart;
        } else {
            if (PATHFINDING_DEBUG) std.debug.print("stuck on blocking tile", .{});
            return;
        }
    }
    const start = &state.pathfindingData.graphRectangles.items[startRecIndex.?];
    const goalRecIndex = (try getChunkGraphRectangleIndexForTileXY(goalTile, state)).?;
    const goal = &state.pathfindingData.graphRectangles.items[goalRecIndex];

    try gScore.put(start, 0);
    const startNode = Node{
        .rectangle = start,
        .cost = 0,
        .priority = heuristic(start, goal),
    };
    try openSet.append(startNode);

    while (openSet.items.len > 0) {
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
            return;
        }

        _ = openSet.swapRemove(currentIndex);

        neighbors.clearRetainingCapacity();
        for (current.rectangle.connectionIndexes.items) |conIndex| {
            if (state.pathfindingData.graphRectangles.items.len <= conIndex) {
                if (PATHFINDING_DEBUG) std.debug.print("beforePathfinding crash: {}, {}", .{ current.rectangle.tileRectangle, current.rectangle.index });
            }
            try neighbors.append(&state.pathfindingData.graphRectangles.items[conIndex]);
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
}

pub fn paintDebugPathfindingVisualization(state: *main.ChatSimState) void {
    if (!PATHFINDING_DEBUG) return;
    const recVertCount = 8;
    const graphRectangleColor = [_]f32{ 1, 0, 0 };
    const connectionRectangleColor = [_]f32{ 0, 0, 1 };
    for (state.pathfindingData.graphRectangles.items) |rectangle| {
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
        for (rectangle.connectionIndexes.items) |conIndex| {
            if (state.vkState.rectangle.verticeCount + 6 >= rectangleVulkanZig.VkRectangle.MAX_VERTICES) break;
            if (state.pathfindingData.graphRectangles.items.len <= conIndex) {
                std.debug.print("beforeCrash: {}, {}\n", .{ rectangle.tileRectangle, rectangle.index });
            }
            const conRect = state.pathfindingData.graphRectangles.items[conIndex];
            var conTileXy: mapZig.TileXY = .{
                .tileX = conRect.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(@divFloor(conRect.tileRectangle.columnCount + 1, 2))),
                .tileY = conRect.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(@divFloor(conRect.tileRectangle.rowCount + 1, 2))),
            };
            var rectTileXy: mapZig.TileXY = .{
                .tileX = rectangle.tileRectangle.topLeftTileXY.tileX + @as(i32, @intCast(@divFloor(rectangle.tileRectangle.columnCount + 1, 2))),
                .tileY = rectangle.tileRectangle.topLeftTileXY.tileY + @as(i32, @intCast(@divFloor(rectangle.tileRectangle.rowCount + 1, 2))),
            };
            const recOffsetX = @divFloor(@as(i32, @intCast(rectangle.tileRectangle.columnCount)), 3);
            const conOffsetX = @divFloor(@as(i32, @intCast(conRect.tileRectangle.columnCount)), 3);
            if (conRect.tileRectangle.topLeftTileXY.tileX > rectangle.tileRectangle.topLeftTileXY.tileX) {
                conTileXy.tileX -= conOffsetX;
                rectTileXy.tileX += recOffsetX;
            } else if (conRect.tileRectangle.topLeftTileXY.tileX < rectangle.tileRectangle.topLeftTileXY.tileX) {
                conTileXy.tileX += conOffsetX;
                rectTileXy.tileX -= recOffsetX;
            }
            const recOffsetY = @divFloor(@as(i32, @intCast(rectangle.tileRectangle.rowCount)), 3);
            const conOffsetY = @divFloor(@as(i32, @intCast(conRect.tileRectangle.rowCount)), 3);
            if (conRect.tileRectangle.topLeftTileXY.tileY > rectangle.tileRectangle.topLeftTileXY.tileY) {
                conTileXy.tileY -= conOffsetY;
                rectTileXy.tileY += recOffsetY;
            } else if (conRect.tileRectangle.topLeftTileXY.tileY < rectangle.tileRectangle.topLeftTileXY.tileY) {
                conTileXy.tileY += conOffsetY;
                rectTileXy.tileY -= recOffsetY;
            }
            const conArrowEndVulkan = mapZig.mapTileXyToVulkanSurfacePosition(conTileXy, state.camera);
            const arrowStartVulkan = mapZig.mapTileXyToVulkanSurfacePosition(rectTileXy, state.camera);
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = connectionRectangleColor };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 1] = .{ .pos = .{ arrowStartVulkan.x, arrowStartVulkan.y }, .color = connectionRectangleColor };

            const direction = main.calculateDirection(arrowStartVulkan, conArrowEndVulkan) + std.math.pi;

            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 2] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = .{ 0, 0, 0 } };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 3] = .{ .pos = .{ conArrowEndVulkan.x + @cos(direction + 0.3) * 0.05, conArrowEndVulkan.y + @sin(direction + 0.3) * 0.05 }, .color = .{ 0, 0, 0 } };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 4] = .{ .pos = .{ conArrowEndVulkan.x, conArrowEndVulkan.y }, .color = .{ 0, 0, 0 } };
            state.vkState.rectangle.vertices[state.vkState.rectangle.verticeCount + 5] = .{ .pos = .{ conArrowEndVulkan.x + @cos(direction - 0.3) * 0.05, conArrowEndVulkan.y + @sin(direction - 0.3) * 0.05 }, .color = .{ 0, 0, 0 } };
            state.vkState.rectangle.verticeCount += 6;
        }
        if (state.vkState.rectangle.verticeCount + recVertCount >= rectangleVulkanZig.VkRectangle.MAX_VERTICES) break;
    }
}

fn isTilePathBlocking(tileXY: mapZig.TileXY, state: *main.ChatSimState) !bool {
    return try getChunkGraphRectangleIndexForTileXY(tileXY, state) == null;
}

fn getChunkGraphRectangleIndexForTileXY(tileXY: mapZig.TileXY, state: *main.ChatSimState) !?usize {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
    const pathingDataIndex = getPathingIndexForTileXY(tileXY);
    return chunk.pathingData.pathingData[pathingDataIndex];
}

fn getPathingIndexForTileXY(tileXY: mapZig.TileXY) usize {
    return @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
}
