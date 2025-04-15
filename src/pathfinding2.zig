const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");

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
    for (0..rectangle.columnCount) |column| {
        for (0..rectangle.rowCount) |row| {
            try changePathingData(.{
                .tileX = rectangle.topLeftTileXY.tileX + @as(i32, @intCast(column)),
                .tileY = rectangle.topLeftTileXY.tileY + @as(i32, @intCast(row)),
            }, pathingType, state);
        }
    }
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
        return;
    }
    var openSet = &state.pathfindingData.openSet;
    openSet.clearRetainingCapacity();
    var cameFrom = &state.pathfindingData.cameFrom;
    cameFrom.clearRetainingCapacity();
    var gScore = &state.pathfindingData.gScore;
    gScore.clearRetainingCapacity();
    var neighbors = &state.pathfindingData.neighbors;
    const startRecIndex = try getChunkGraphRectangleIndexForTileXY(startTile, state);
    if (startRecIndex == null) return;
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

fn changePathingData(tileXY: mapZig.TileXY, pathingType: mapZig.PathingType, state: *main.ChatSimState) !void {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
    const pathingDataIndex = @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
    //TODO
    _ = pathingType;
    _ = chunk;
    _ = pathingDataIndex;
}
