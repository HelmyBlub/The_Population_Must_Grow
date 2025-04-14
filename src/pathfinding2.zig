const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");

pub const PathfindingData = struct {
    openSet: std.ArrayList(Node),
    cameFrom: std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80),
    gScore: std.AutoHashMap(mapZig.TileXY, i32),
    graphRectangles: std.ArrayList(ChunkGraphRectangle),
};

pub const ChunkGraphRectangle = struct {
    tileRectangle: mapZig.MapTileRectangle,
    connections: std.ArrayList(*ChunkGraphRectangle),
};

pub const PathfindingChunkData = struct {
    pathingData: [mapZig.GameMap.CHUNK_LENGTH * mapZig.GameMap.CHUNK_LENGTH]*ChunkGraphRectangle,
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
    const chunkGraphRectangle: ChunkGraphRectangle = .{
        .connections = std.ArrayList(*ChunkGraphRectangle).init(allocator),
        .tileRectangle = .{
            .topLeftTileXY = .{
                .tileX = chunkXY.chunkX * mapZig.GameMap.CHUNK_LENGTH,
                .tileY = chunkXY.chunkY * mapZig.GameMap.CHUNK_LENGTH,
            },
            .columnCount = mapZig.GameMap.CHUNK_LENGTH,
            .rowCount = mapZig.GameMap.CHUNK_LENGTH,
        },
    };
    state.pathfindingData.graphRectangles.append(chunkGraphRectangle);
    const result: PathfindingChunkData = .{};
    for (0..result.pathingData.len) |i| {
        result.pathingData[i] = state.pathfindingData.graphRectangles.getLast();
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
        .cameFrom = std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80).init(allocator),
        .gScore = std.AutoHashMap(mapZig.TileXY, i32).init(allocator),
        .graphRectangles = std.ArrayList(ChunkGraphRectangle).init(allocator),
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

pub fn heuristic(a: mapZig.TileXY, b: mapZig.TileXY) i32 {
    return @as(i32, @intCast(@abs(a.tileX - b.tileX) + @abs(a.tileY - b.tileY)));
}

pub fn reconstructPath(
    cameFrom: *std.HashMap(mapZig.TileXY, mapZig.TileXY, TileXyContext, 80),
    start: mapZig.TileXY,
    citizen: *main.Citizen,
) !void {
    var current = start;
    try citizen.moveTo.append(mapZig.mapTileXyToTileMiddlePosition(current));
    while (true) {
        if (cameFrom.get(current)) |parent| {
            current = parent;
            try citizen.moveTo.append(mapZig.mapTileXyToTileMiddlePosition(current));
        } else {
            break;
        }
    }
}

pub fn pathfindAStar(
    start: mapZig.TileXY,
    goal: mapZig.TileXY,
    citizen: *main.Citizen,
    state: *main.ChatSimState,
) !void {
    _ = state;
    _ = start;
    try citizen.moveTo.append(mapZig.mapTileXyToTileMiddlePosition(goal));
    return;
}

pub fn oldPathfindAStar(
    start: mapZig.TileXY,
    goal: mapZig.TileXY,
    citizen: *main.Citizen,
    state: *main.ChatSimState,
) !void {
    if (try isTilePathBlocking(.{ .tileX = goal.tileX, .tileY = goal.tileY }, state)) {
        return;
    }
    var openSet = &state.pathfindingData.openSet;
    openSet.clearRetainingCapacity();
    var cameFrom = &state.pathfindingData.cameFrom;
    cameFrom.clearRetainingCapacity();
    var gScore = &state.pathfindingData.gScore;
    gScore.clearRetainingCapacity();

    try gScore.put(start, 0);
    const startNode = Node{
        .pos = start,
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

        if (cameFrom.ctx.eql(current.pos, goal)) {
            try reconstructPath(cameFrom, current.pos, citizen);
            return;
        }

        _ = openSet.swapRemove(currentIndex);

        const neighbors: [4]mapZig.TileXY = .{
            .{ .tileX = current.pos.tileX, .tileY = current.pos.tileY + 1 },
            .{ .tileX = current.pos.tileX, .tileY = current.pos.tileY - 1 },
            .{ .tileX = current.pos.tileX + 1, .tileY = current.pos.tileY },
            .{ .tileX = current.pos.tileX - 1, .tileY = current.pos.tileY },
        };
        for (neighbors) |neighbor| {
            if (try isTilePathBlocking(.{ .tileX = neighbor.tileX, .tileY = neighbor.tileY }, state)) continue;
            const tentativeGScore = current.cost + 1;
            if (gScore.get(neighbor) == null or tentativeGScore < gScore.get(neighbor).?) {
                try cameFrom.put(neighbor, current.pos);
                try gScore.put(neighbor, tentativeGScore);
                const fScore = tentativeGScore + heuristic(neighbor, goal);
                var found = false;
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

fn isTilePathBlocking(tileXY: mapZig.TileXY, state: *main.ChatSimState) !bool {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
    const pathingDataIndex = @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
    return chunk.pathingData.pathingData[pathingDataIndex] == mapZig.PathingType.blocking;
}

fn changePathingData(tileXY: mapZig.TileXY, pathingType: mapZig.PathingType, state: *main.ChatSimState) !void {
    const chunkXY = mapZig.getChunkXyForTileXy(tileXY);
    const chunk = try mapZig.getChunkAndCreateIfNotExistsForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
    const pathingDataIndex = @as(usize, @intCast(@mod(tileXY.tileX, mapZig.GameMap.CHUNK_LENGTH) + @mod(tileXY.tileY, mapZig.GameMap.CHUNK_LENGTH) * mapZig.GameMap.CHUNK_LENGTH));
    chunk.pathingData.pathingData[pathingDataIndex] = pathingType;
}
