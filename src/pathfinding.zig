const std = @import("std");
const mapZig = @import("map.zig");
const main = @import("main.zig");

const TileXyContext = struct {
    pub fn eql(a: mapZig.TileXY, b: mapZig.TileXY) bool {
        return a.tileX == b.tileX and a.tileY == b.tileY;
    }

    // A simple hash function based on FNV-1a.
    pub fn hash(self: mapZig.TileXY) u64 {
        var h: u64 = 1469598103934665603;
        h ^= @intCast(self.tileX);
        h *= 1099511628211;
        h ^= @intCast(self.tileY);
        h *= 1099511628211;
        return h;
    }
};

// A struct representing a node in the A* search.
const Node = struct {
    pos: mapZig.TileXY,
    cost: i32, // g(x): cost from start to this node.
    priority: i32, // f(x) = g(x) + h(x) (with h() as the heuristic).
};

// The Manhattan distance is a common heuristic for grids.
pub fn heuristic(a: mapZig.TileXY, b: mapZig.TileXY) i32 {
    return std.math.abs(a.tileX - b.tileX) + std.math.abs(a.tileY - b.tileY);
}

// Get the four cardinal neighbors.
pub fn getNeighbors(pos: mapZig.TileXY) []mapZig.TileXY {
    var neighbors: [4]mapZig.TileXY = .{
        .{ .x = pos.tileX, .y = pos.tileY + 1 },
        .{ .x = pos.tileX, .y = pos.tileY - 1 },
        .{ .x = pos.tileX + 1, .y = pos.tileY },
        .{ .x = pos.tileX - 1, .y = pos.tileY },
    };
    return neighbors[0..];
}

// Reconstruct the path by walking back through the cameFrom map.
// The cameFrom map maps a coordinate to the coordinate from which it was reached.
pub fn reconstructPath(
    cameFrom: *std.AutoHashMap(mapZig.TileXY, mapZig.TileXY),
    current: mapZig.TileXY,
    allocator: *std.mem.Allocator,
) ![]mapZig.TileXY {
    var path = std.ArrayList(mapZig.TileXY).init(allocator);
    try path.append(current);
    // Walk back until no parent is found.
    while (true) {
        if (cameFrom.get(current)) |parent| {
            current = parent.*;
            // Prepend the parent at the beginning.
            try path.prepend(current);
        } else {
            break;
        }
    }
    return path.toOwnedSlice();
}

// The A* implementation.
// Returns an optional slice of Coordinates representing the path from start to goal.
pub fn pathfindAStar(
    allocator: std.mem.Allocator,
    start: mapZig.TileXY,
    goal: mapZig.TileXY,
    state: *main.ChatSimState,
) !?[]mapZig.TileXY {
    // openSet holds nodes we still need to examine.
    var openSet = std.ArrayList(Node).init(allocator);
    // cameFrom records how we reached each coordinate.
    var cameFrom = std.HashMap(u64, mapZig.TileXY, TileXyContext, 80);
    // gScore map: best cost from start to a given coordinate.
    var gScore = std.AutoHashMap(mapZig.TileXY, i32).init(allocator);

    defer openSet.deinit();
    defer cameFrom.deinit();
    defer gScore.deinit();

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
        if (mapZig.TileXY.eq(current.pos, goal)) {
            return reconstructPath(&cameFrom, current.pos, allocator);
        }

        // Remove the current node from openSet.
        openSet.items.swapRemove(currentIndex);

        // Expand each neighbor of the current node.
        const neighbors = getNeighbors(current.pos);
        for (neighbors) |neighbor| {
            // Skip neighbors if the tile is blocked.
            if (mapZig.isTilePathBlocking(.{ .tileX = neighbor.x, .tileY = neighbor.y }, state)) continue;
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
                    if (TileXyContext.eql(node.pos, neighbor)) {
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
    // If we've exhausted the search space, return null (no path found).
    return null;
}
