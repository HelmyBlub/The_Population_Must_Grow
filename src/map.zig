const std = @import("std");
const main = @import("main.zig");
const windowSdlZig = @import("windowSdl.zig");

pub const GameMap = struct {
    chunks: std.HashMap(u64, MapChunk, U64HashMapContext, 30),
    activeChunkKeys: std.ArrayList(u64),
    pub const CHUNK_LENGTH: u8 = 8;
    pub const TILE_SIZE: u16 = 20;
    pub const CHUNK_SIZE: u16 = GameMap.CHUNK_LENGTH * GameMap.TILE_SIZE;
    pub const MAX_CHUNKS_ROWS_COLUMNS: u32 = 10_000;
};

const U64HashMapContext = struct {
    pub fn hash(self: @This(), s: u64) u64 {
        _ = self;
        return s;
    }
    pub fn eql(self: @This(), a: u64, b: u64) bool {
        _ = self;
        return a == b;
    }
};

pub const MapChunk = struct {
    chunkX: i32,
    chunkY: i32,
    trees: std.ArrayList(MapTree),
    buildings: std.ArrayList(Building),
    potatoFields: std.ArrayList(PotatoField),
};

pub const MapTree = struct {
    position: main.Position,
    citizenOnTheWay: bool = false,
    ///  values from 0 to 1
    grow: f32 = 0,
};

pub const Building = struct {
    type: u8,
    position: main.Position,
    inConstruction: bool = true,
};

pub const PotatoField = struct {
    position: main.Position,
    citizenOnTheWay: u8 = 0,
    planted: bool = false,
    ///  values from 0 to 1
    grow: f32 = 0,
};

pub const ChunkXY = struct {
    chunkX: i32,
    chunkY: i32,
};

const VisibleChunksData = struct {
    top: i32,
    left: i32,
    rows: usize,
    columns: usize,
};

pub const BUILDING_MODE_SINGLE = 0;
pub const BUILDING_MODE_DRAG_RECTANGLE = 1;
pub const BUILDING_TYPE_HOUSE = 0;
pub const BUILDING_TYPE_TREE_FARM = 1;
pub const BUILDING_TYPE_POTATO_FARM = 2;

pub fn createMap(allocator: std.mem.Allocator) !GameMap {
    var map: GameMap = .{
        .chunks = std.HashMap(u64, MapChunk, U64HashMapContext, 30).init(allocator),
        .activeChunkKeys = std.ArrayList(u64).init(allocator),
    };
    const spawnChunk = try createSpawnChunk(allocator);
    const key = getKeyForChunkXY(spawnChunk.chunkX, spawnChunk.chunkY);
    try map.chunks.put(key, spawnChunk);
    return map;
}

pub fn getTopLeftVisibleChunkXY(state: *main.ChatSimState) VisibleChunksData {
    const camera = state.camera;
    const mapVisibleTopLeft: main.Position = .{
        .x = camera.position.x - windowSdlZig.windowData.widthFloat / 2 / camera.zoom - 10,
        .y = camera.position.y - windowSdlZig.windowData.heightFloat / 2 / camera.zoom - 10,
    };
    const chunkXY = getChunkXyForPosition(mapVisibleTopLeft);

    return VisibleChunksData{
        .left = chunkXY.chunkX,
        .top = chunkXY.chunkY,
        .columns = @intFromFloat(windowSdlZig.windowData.widthFloat / camera.zoom / GameMap.CHUNK_SIZE + 2),
        .rows = @intFromFloat(windowSdlZig.windowData.heightFloat / camera.zoom / GameMap.CHUNK_SIZE + 2),
    };
}

pub fn getChunkAndCreateIfNotExistsForChunkXY(chunkX: i32, chunkY: i32, state: *main.ChatSimState) !*MapChunk {
    const key = getKeyForChunkXY(chunkX, chunkY);
    if (!state.map.chunks.contains(key)) {
        try createAndPushChunkForChunkXY(chunkX, chunkY, state);
    }
    return state.map.chunks.getPtr(key).?;
}

pub fn getChunkAndCreateIfNotExistsForPosition(position: main.Position, state: *main.ChatSimState) !*MapChunk {
    const chunkXY = getChunkXyForPosition(position);
    return getChunkAndCreateIfNotExistsForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
}

pub fn mapIsTilePositionFree(pos: main.Position, state: *main.ChatSimState) !bool {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(pos, state);
    for (chunk.buildings.items) |building| {
        if (main.calculateDistance(pos, building.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    for (chunk.trees.items) |tree| {
        if (main.calculateDistance(pos, tree.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    for (chunk.potatoFields.items) |field| {
        if (main.calculateDistance(pos, field.position) < GameMap.TILE_SIZE) {
            return false;
        }
    }
    return true;
}

pub fn placeTree(tree: MapTree, state: *main.ChatSimState) !void {
    if (!try mapIsTilePositionFree(tree.position, state)) return;
    const chunk = try getChunkAndCreateIfNotExistsForPosition(tree.position, state);
    try chunk.trees.append(tree);
}

pub fn getTreeOnPosition(position: main.Position, state: *main.ChatSimState) !?*MapTree {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.trees.items) |*tree| {
        if (main.calculateDistance(position, tree.position) < GameMap.TILE_SIZE) {
            return tree;
        }
    }
    return null;
}

pub fn getBuildingOnPosition(position: main.Position, state: *main.ChatSimState) !?*Building {
    const chunk = try getChunkAndCreateIfNotExistsForPosition(position, state);
    for (chunk.buildings.items) |*building| {
        if (main.calculateDistance(position, building.position) < GameMap.TILE_SIZE) {
            return building;
        }
    }
    return null;
}

pub fn getKeyForPosition(position: main.Position) !u64 {
    const chunkXY = getChunkXyForPosition(position);
    return getKeyForChunkXY(chunkXY.chunkX, chunkXY.chunkY);
}

pub fn getKeyForChunkXY(chunkX: i32, chunkY: i32) u64 {
    return @intCast(chunkX * GameMap.MAX_CHUNKS_ROWS_COLUMNS + chunkY + GameMap.MAX_CHUNKS_ROWS_COLUMNS * GameMap.MAX_CHUNKS_ROWS_COLUMNS);
}

pub fn getChunkXyForPosition(position: main.Position) ChunkXY {
    return .{
        .chunkX = @intFromFloat(@floor(position.x / GameMap.CHUNK_SIZE)),
        .chunkY = @intFromFloat(@floor(position.y / GameMap.CHUNK_SIZE)),
    };
}

fn createAndPushChunkForChunkXY(chunkX: i32, chunkY: i32, state: *main.ChatSimState) !void {
    const newChunk = try createChunk(chunkX, chunkY, state.allocator);
    const key = getKeyForChunkXY(chunkX, chunkY);
    try state.map.chunks.put(key, newChunk);
}

fn createAndPushChunkForPosition(position: main.Position, state: *main.ChatSimState) !void {
    const chunkXY = getChunkXyForPosition(position);
    try createAndPushChunkForChunkXY(chunkXY.chunkX, chunkXY.chunkY, state);
}

fn createChunk(chunkX: i32, chunkY: i32, allocator: std.mem.Allocator) !MapChunk {
    var mapChunk: MapChunk = .{
        .chunkX = chunkX,
        .chunkY = chunkY,
        .buildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
    };

    for (0..GameMap.CHUNK_LENGTH) |x| {
        for (0..GameMap.CHUNK_LENGTH) |y| {
            const random = fixedRandom(
                @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(chunkX * GameMap.CHUNK_LENGTH)),
                @as(f32, @floatFromInt(y)) + @as(f32, @floatFromInt(chunkY * GameMap.CHUNK_LENGTH)),
                0.0,
            );
            if (random < 0.1) {
                const tree = MapTree{
                    .position = .{
                        .x = @floatFromInt((chunkX * GameMap.CHUNK_LENGTH + @as(i32, @intCast(x))) * GameMap.TILE_SIZE),
                        .y = @floatFromInt((chunkY * GameMap.CHUNK_LENGTH + @as(i32, @intCast(y))) * GameMap.TILE_SIZE),
                    },
                    .grow = 1.0,
                };
                try mapChunk.trees.append(tree);
            }
        }
    }
    return mapChunk;
}

fn createSpawnChunk(allocator: std.mem.Allocator) !MapChunk {
    var spawnChunk: MapChunk = .{
        .chunkX = 0,
        .chunkY = 0,
        .buildings = std.ArrayList(Building).init(allocator),
        .trees = std.ArrayList(MapTree).init(allocator),
        .potatoFields = std.ArrayList(PotatoField).init(allocator),
    };
    try spawnChunk.buildings.append(.{ .position = .{ .x = 0, .y = 0 }, .inConstruction = false, .type = BUILDING_TYPE_HOUSE });
    try spawnChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE, .y = 0 }, .grow = 1 });
    try spawnChunk.trees.append(.{ .position = .{ .x = GameMap.TILE_SIZE, .y = GameMap.TILE_SIZE }, .grow = 1 });
    return spawnChunk;
}

fn fixedRandom(x: f32, y: f32, seed: f32) f32 {
    return @mod((@sin((x * 112.01716 + y * 718.233 + seed * 1234.1234) * 437057.545323) * 1000000.0), 256) / 256.0;
}
