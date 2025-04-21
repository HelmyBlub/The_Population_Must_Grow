const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");

pub const PathfindingData = struct {
    openSet: std.ArrayList(Node),
    cameFrom: std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80),
    gScore: std.AutoHashMap(mapZig.TileXY, i32),
};

pub const PathfindingChunkData = struct {
    pathingData: [mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]mapZig.PathingType = [_]mapZig.PathingType{mapZig.PathingType.slow} ** (mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH),
};

const TileXyContext = struct {
    pub fn eql(self: @This(), a: mapZig.TileXY, b: mapZig.TileXY) bool {
        _ = self;
        return a.tileX == b.tileX and a.tileY == b.tileY;
    }

    // A simple hash function based on FNV-1a.
    pub fn hash(self: @This(), key: mapZig.TileXY) u64 {
        _ = self;
        var h: u64 = 1469598103934665603;
        h ^= @bitCast(@as(i64, @intCast(key.tileX)));
        h *%= 1099511628211;
        h ^= @bitCast(@as(i64, @intCast(key.tileY)));
        h *%= 1099511628211;
        return h;
    }
};

// A struct representing a node in the A* search.
const Node = struct {
    pos: mapZig.TileXY,
    cost: i32, // g(x): cost from start to this node.
    priority: i32, // f(x) = g(x) + h(x) (with h() as the heuristic).
};

pub fn createChunkData(chunkXY: mapZig.ChunkXY, allocator: std.mem.Allocator, state: *main.ChatSimState) !PathfindingChunkData {
    _ = chunkXY;
    _ = state;
    _ = allocator;
    return PathfindingChunkData{};
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
        .cameFrom = std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80).init(allocator),
        .gScore = std.AutoHashMap(mapZig.TileXY, i32).init(allocator),
    };
}

pub fn destoryChunkData(pathingData: *PathfindingChunkData) void {
    _ = pathingData;
}

pub fn destoryPathfindingData(data: *PathfindingData) void {
    data.cameFrom.deinit();
    data.gScore.deinit();
    data.openSet.deinit();
}

// The Manhattan distance is a common heuristic for grids.
pub fn heuristic(a: mapZig.TileXY, b: mapZig.TileXY) i32 {
    return @as(i32, @intCast(@abs(a.tileX - b.tileX) + @abs(a.tileY - b.tileY)));
}

// Reconstruct the path by walking back through the cameFrom map.
// The cameFrom map maps a coordinate to the coordinate from which it was reached.
pub fn reconstructPath(
    cameFrom: *std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80),
    goal: mapZig.TileXY,
    citizen: *main.Citizen,
) !void {
    var current = goal;
    try citizen.moveTo.append(mapZig.mapTileXyToTileMiddlePosition(current));
    // Walk back until no parent is found.
    while (true) {
        if (cameFrom.get(current)) |parent| {
            current = parent;
            // Prepend the parent at the beginning.
            try citizen.moveTo.append(mapZig.mapTileXyToTileMiddlePosition(current));
        } else {
            break;
        }
    }
}

// The A* implementation.
// Returns an optional slice of Coordinates representing the path from start to goal.
pub fn pathfindAStar(
    start: mapZig.TileXY,
    goal: mapZig.TileXY,
    citizen: *main.Citizen,
    state: *main.ChatSimState,
) !void {
    if (try isTilePathBlocking(goal.tileX, state)) {
        return;
    }
    // openSet holds nodes we still need to examine.
    var openSet = &state.pathfindingData.openSet;
    openSet.clearRetainingCapacity();
    // cameFrom records how we reached each coordinate.
    var cameFrom = &state.pathfindingData.cameFrom;
    cameFrom.clearRetainingCapacity();
    // gScore map: best cost from start to a given coordinate.
    var gScore = &state.pathfindingData.gScore;
    gScore.clearRetainingCapacity();

    // Set the start node score.
    try gScore.put(start, 0);
    const startNode = Node{
        .pos = start,
        .cost = 0,
        .priority = heuristic(start, goal),
    };
    try openSet.append(startNode);

    while (openSet.items.len > 0) {
        // Find the node in openSet with the lowest priority (f-score).
        var currentIndex: usize = 0;
        var current = openSet.items[0];
        for (openSet.items, 0..) |node, i| {
            if (node.priority < current.priority) {
                current = node;
                currentIndex = i;
            }
        }

        // If we reached the goal, reconstruct and return the path.

        if (cameFrom.ctx.eql(current.pos, goal)) {
            try reconstructPath(cameFrom, current.pos, citizen);
            return;
        }

        // Remove the current node from openSet.
        _ = openSet.swapRemove(currentIndex);

        // Expand each neighbor of the current node.
        const neighbors: [4]mapZig.TileXY = .{
            .{ .tileX = current.pos.tileX, .tileY = current.pos.tileY + 1 },
            .{ .tileX = current.pos.tileX, .tileY = current.pos.tileY - 1 },
            .{ .tileX = current.pos.tileX + 1, .tileY = current.pos.tileY },
            .{ .tileX = current.pos.tileX - 1, .tileY = current.pos.tileY },
        };
        for (neighbors) |neighbor| {
            // Skip neighbors if the tile is blocked.
            if (try isTilePathBlocking(.{ .tileX = neighbor.tileX, .tileY = neighbor.tileY }, state)) continue;
            // Assume a cost of 1 per move.
            const tentativeGScore = current.cost + 1;
            if (gScore.get(neighbor) == null or tentativeGScore < gScore.get(neighbor).?) {
                // Record the best path to this neighbor.
                try cameFrom.put(neighbor, current.pos);
                try gScore.put(neighbor, tentativeGScore);
                const fScore = tentativeGScore + heuristic(neighbor, goal);
                var found = false;
                // If the neighbor is already in openSet, update its cost if the new fScore is lower.
                for (openSet.items) |*node| {
                    if (cameFrom.ctx.eql(node.pos, neighbor)) {
                        if (fScore < node.priority) {
                            node.cost = tentativeGScore;
                            node.priority = fScore;
                        }
                        found = true;
                        break;
                    }
                }
                // If not in openSet, add it.
                if (!found) {
                    try openSet.append(Node{
                        .pos = neighbor,
                        .cost = tentativeGScore,
                        .priority = fScore,
                    });
                }
            }
        }
    }
}

pub fn paintDebugPathfindingVisualization(state: *main.ChatSimState) !void {
    _ = state;
}

fn isTilePathBlocking(tileXY: mapZig.TileXY, state: *main.ChatSimState) !bool {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
    const pathingDataIndex = @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
    return chunk.pathingData.pathingData[pathingDataIndex] == mapZig.PathingType.blocking;
}

fn changePathingData(tileXY: mapZig.TileXY, pathingType: mapZig.PathingType, state: *main.ChatSimState) !void {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY, state);
    const pathingDataIndex = @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
    chunk.pathingData.pathingData[pathingDataIndex] = pathingType;
}
